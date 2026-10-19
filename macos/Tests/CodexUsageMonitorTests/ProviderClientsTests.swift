import Darwin
import Foundation
import Testing
@testable import CodexUsageMonitor

@Test func claudeAuthenticationStatusNeverInventsQuota() throws {
    #expect(throws: ProviderUsageFailure.authenticationRequired) {
        try ClaudeAuthenticationParser.requireSupportedQuotaConnection(data: Data(#"{"loggedIn":false,"authMethod":"none"}"#.utf8))
    }
    #expect(throws: ProviderUsageFailure.unsupported) {
        try ClaudeAuthenticationParser.requireSupportedQuotaConnection(data: Data(#"{"loggedIn":true,"subscriptionType":"max"}"#.utf8))
    }
    #expect(throws: ProviderUsageFailure.invalidResponse) {
        try ClaudeAuthenticationParser.requireSupportedQuotaConnection(data: Data(#"{"loggedIn":1}"#.utf8))
    }
}

@Test func grokParsesOnlyExplicitIncludedCreditUsage() throws {
    let json = #"{"id":2,"result":{"config":{"creditUsagePercent":12.5,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-10-12T00:00:00Z","end":"2026-10-19T00:00:00Z"},"onDemandUsed":{"val":900},"onDemandCap":{"val":1000}},"subscriptionTier":"SuperGrok"}}"#
    let result = try #require(try GrokBillingParser.parse(line: Data(json.utf8)))
    #expect(result.provider == .grok)
    #expect(result.windows.first?.remainingPercent == 87.5)
    #expect(result.windows.first?.durationMinutes == 10_080)
    #expect(result.windows.first?.label == "주간 구독 크레딧")
    #expect(result.planName == "SuperGrok")
}

@Test func grokIncludedQuotaExcludesOnDemandSpend() throws {
    let json = #"{"id":2,"result":{"monthlyLimit":{"val":1000},"usage":{"includedUsed":{"val":200},"onDemandUsed":{"val":100},"totalUsed":{"val":300}},"billingCycle":{"billingPeriodStart":"2026-10-01T00:00:00Z","billingPeriodEnd":"2026-11-01T00:00:00Z"}}}"#
    let result = try #require(try GrokBillingParser.parse(line: Data(json.utf8)))
    #expect(result.windows.first?.remainingPercent == 80)
    #expect(result.windows.first?.label == "월간 포함 크레딧")
}

@Test func grokMissingQuotaDoesNotBecomeZeroOrHundred() throws {
    for json in [
        #"{"id":2,"result":{"config":{"currentPeriod":{"end":"2026-11-01T00:00:00Z"},"onDemandUsed":{"val":1},"onDemandCap":{"val":100},"prepaidBalance":{"val":1000}}}}"#,
        #"{"id":2,"result":{"monthlyLimit":{"val":100},"usage":{"totalUsed":{"val":0}}}}"#,
        #"{"id":2,"result":{"config":{"creditUsagePercent":null}}}"#,
        #"{"id":2,"result":{"config":{"creditUsagePercent":true}}}"#,
        #"{"id":2,"result":{"config":{"creditUsagePercent":-1}}}"#,
        #"{"id":2,"result":{"config":{"creditUsagePercent":101}}}"#
    ] {
        #expect(throws: ProviderUsageFailure.invalidResponse) { try GrokBillingParser.parse(line: Data(json.utf8)) }
    }
    let zero = #"{"id":2,"result":{"config":{"creditUsagePercent":0}}}"#
    #expect(try GrokBillingParser.parse(line: Data(zero.utf8))?.windows.first?.remainingPercent == 100)
}

@Test func grokRPCIgnoresUnrelatedMessagesAndSanitizesErrors() throws {
    #expect(try GrokBillingParser.parse(line: Data(#"{"id":1,"result":{}}"#.utf8)) == nil)
    #expect(throws: ProviderUsageFailure.unsupported) {
        try GrokBillingParser.parse(line: Data(#"{"id":2,"error":{"code":-32601,"message":"private diagnostic"}}"#.utf8))
    }
    #expect(throws: ProviderUsageFailure.authenticationRequired) {
        try GrokBillingParser.parse(line: Data(#"{"id":2,"error":{"code":-32000,"message":"Authentication required to fetch billing data."}}"#.utf8))
    }
    #expect(throws: ProviderUsageFailure.queryFailed) {
        try GrokBillingParser.parse(line: Data(#"{"id":2,"error":{"code":-32001,"message":"private diagnostic"}}"#.utf8))
    }
}

@Test func claudeClientUsesOnlyReadOnlyAuthStatusArguments() async throws {
    let fixture = try ProviderCLIFixture(script: #"""
    [ "$#" -eq 3 ] && [ "$1" = auth ] && [ "$2" = status ] && [ "$3" = --json ] || exit 91
    printf '%s\n' '{"loggedIn":false,"authMethod":"none"}'
    """#)
    defer { fixture.remove() }
    do {
        _ = try await ClaudeUsageProviderClient(explicitPath: fixture.path, timeout: 1).fetchUsage()
        Issue.record("Logged-out CLI must not return quota")
    } catch {
        #expect(error as? ProviderUsageFailure == .authenticationRequired)
    }
}

@Test func grokCLIInitializesBeforeBillingWithoutModelRequest() async throws {
    let fixture = try ProviderCLIFixture(script: #"""
    [ "$#" -eq 2 ] && [ "$1" = agent ] && [ "$2" = stdio ] || exit 91
    IFS= read -r initialize
    case "$initialize" in *'"method":"initialize"'*) ;; *) exit 92 ;; esac
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"1"}}'
    IFS= read -r billing
    case "$billing" in *'"method":"x.ai/billing"'*) ;; *) exit 93 ;; esac
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"config":{"creditUsagePercent":25}}}'
    sleep 30
    """#)
    defer { fixture.remove() }
    let start = Date()
    let result = try await GrokUsageProviderClient(explicitPath: fixture.path, timeout: 1, allowGrokBuildCLI: true).fetchUsage()
    #expect(result.windows.first?.remainingPercent == 75)
    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func providerCLIReadHangTimesOutAndCleansOwnedChild() async throws {
    let fixture = try ProviderCLIFixture(script: #"""
    trap '' TERM
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
    sleep 30
    """#)
    defer { fixture.remove() }
    let start = Date()
    do {
        _ = try await GrokUsageProviderClient(explicitPath: fixture.path, timeout: 0.12, allowGrokBuildCLI: true).fetchUsage()
        Issue.record("Expected bounded timeout")
    } catch {
        #expect(error as? ProviderUsageFailure == .timeout)
    }
    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func providerCLICancellationAwaitsCleanup() async throws {
    let fixture = try ProviderCLIFixture(script: #"""
    sleep 30
    """#)
    defer { fixture.remove() }
    let start = Date()
    let task = Task { try await GrokUsageProviderClient(explicitPath: fixture.path, timeout: 30, allowGrokBuildCLI: true).fetchUsage() }
    try await Task.sleep(for: .milliseconds(80))
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch {
        #expect(error is CancellationError)
    }
    #expect(Date().timeIntervalSince(start) < 2)
}

@Test func grokBuildMeterStaysDisabledWithoutExplicitProductOptIn() async throws {
    // This executable would return malformed output if launched. The disabled
    // product gate must report disconnected before any subprocess is created.
    let fixture = try ProviderCLIFixture(script: "exit 91")
    defer { fixture.remove() }
    do {
        _ = try await GrokUsageProviderClient(explicitPath: fixture.path).fetchUsage()
        Issue.record("Unverified Grok Build meter must remain disconnected")
    } catch { #expect(error as? ProviderUsageFailure == .notConnected) }
}

@Test func grokProductionAndManualFactoriesUseTheCursorWrapperWithoutFetching() throws {
    // Factory construction does not read credentials. Never invoke the real
    // production clients in unit tests, even when a local verification bit exists.
    let automatic = try #require(ProductionUsageProviders.clients.first(where: { $0.id == .grok })
        as? GrokSubscriptionUsageProviderClient)
    let manual = try #require(ProductionUsageProviders.interactiveClient(for: .grok)
        as? GrokSubscriptionUsageProviderClient)
    #expect(automatic.id == .grok)
    #expect(manual.id == .grok)
}

@Test func unverifiedGrokWrapperDoesNotReadCredentialsOrSendRequests() async {
    let reads = GrokSubscriptionFixtureReadCounter()
    let transport = GrokSubscriptionFixtureTransport()
    let client = GrokSubscriptionUsageProviderClient(
        credentials: GrokSubscriptionFixtureCredentials(reads: reads),
        transport: transport,
        requiresVerification: true,
        isVerified: { false }
    )
    await #expect(throws: ProviderUsageFailure.notConnected) { try await client.fetchUsage() }
    #expect(reads.count == 0)
    #expect(await transport.callCount == 0)
}

@Test func grokWrapperUsesOnlyInjectedCredentialsAndQuotaTransport() async throws {
    let reads = GrokSubscriptionFixtureReadCounter()
    let transport = GrokSubscriptionFixtureTransport()
    let timestamp = Date(timeIntervalSince1970: 2_000)
    let credentials = GrokSubscriptionFixtureCredentials(reads: reads)
    let verified = GrokSubscriptionUsageProviderClient(
        credentials: credentials, transport: transport, now: { timestamp },
        requiresVerification: true, isVerified: { true }
    )
    let usage = try await verified.fetchUsage()
    #expect(usage.provider == .grok)
    #expect(usage.displayRemainingPercent == 74)
    #expect(usage.windows.first?.resetDate == Date(timeIntervalSince1970: 3_600))
    #expect(reads.count == 1)
    #expect(await transport.callCount == 1)
    #expect(await transport.usedExpectedRequest)

    let explicitVerification = GrokSubscriptionUsageProviderClient(
        credentials: credentials, transport: transport, now: { timestamp },
        requiresVerification: false, isVerified: { false }
    )
    #expect(try await explicitVerification.fetchUsage() == usage)
    #expect(reads.count == 2)
    #expect(await transport.callCount == 2)
}

@Test func missingProviderCLIsStayUnavailable() async throws {
    let missing = "/nonexistent/codextime-test-\(UUID().uuidString)"
    do {
        _ = try await ClaudeUsageProviderClient(explicitPath: missing).fetchUsage()
        Issue.record("Expected missing Claude CLI")
    } catch { #expect(error as? ProviderUsageFailure == .notInstalled) }
    do {
        _ = try await GrokUsageProviderClient(explicitPath: missing, allowGrokBuildCLI: true).fetchUsage()
        Issue.record("Expected disconnected Grok quota")
    } catch { #expect(error as? ProviderUsageFailure == .notConnected) }
}

private final class GrokSubscriptionFixtureReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}

private struct GrokSubscriptionFixtureCredentials: GrokBotCredentialSource {
    let reads: GrokSubscriptionFixtureReadCounter
    func readAuthorization() throws -> GrokBotAuthorization {
        reads.increment()
        // Synthetic JWT-shaped fixture; no account or credential store is used.
        let payload = Data(#"{"exp":3000}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return GrokBotAuthorization(accessToken: "fixture.\(payload).fixture")
    }
}

private actor GrokSubscriptionFixtureTransport: GrokBotUsageTransport {
    private(set) var callCount = 0
    private(set) var usedExpectedRequest = false
    func send(_ request: URLRequest) async throws -> GrokBotUsageHTTPResponse {
        callCount += 1
        usedExpectedRequest = request.url == GrokBotUsageProviderClient.endpoint
            && request.httpMethod == "POST"
            && request.httpShouldHandleCookies == false
            && request.value(forHTTPHeaderField: "Authorization") != nil
            && request.value(forHTTPHeaderField: "x-cursor-team-id") == nil
        return GrokBotUsageHTTPResponse(statusCode: 200, body: Data(
            #"{"usagePercent":25.5,"nextResetTimestampUtc":"1970-01-01T01:00:00Z"}"#.utf8
        ))
    }
}

@Test func claudeProductionFactoryRequiresConsentWhileManualFactoryStaysInteractive() throws {
    // Construction only: never fetch real production clients in unit tests.
    let automatic = try #require(ProductionUsageProviders.clients.first(where: { $0.id == .claude })
        as? ClaudeSubscriptionUsageProviderClient)
    let manual = try #require(ProductionUsageProviders.interactiveClient(for: .claude)
        as? ClaudeOAuthUsageProviderClient)
    #expect(automatic.id == .claude)
    #expect(manual.id == .claude)
    #expect(ClaudeSubscriptionUsageProviderClient.connectionEnabledKey == "claudeUsageConnectionEnabled")
}

@Test func claudeConsentGateStopsCredentialAndNetworkAccessUntilEnabled() async throws {
    let counters = ClaudeConnectionFixtureCounters()
    let credentials = ClaudeConnectionFixtureCredentials(counters: counters)
    let transport = ClaudeConnectionFixtureTransport(counters: counters)
    let timestamp = Date(timeIntervalSince1970: 2_000)
    let disabled = ClaudeSubscriptionUsageProviderClient(
        credentials: credentials, transport: transport, now: { timestamp }, isConnectionEnabled: { false }
    )
    await #expect(throws: ProviderUsageFailure.notConnected) { try await disabled.fetchUsage() }
    #expect(await counters.reads == 0)
    #expect(await counters.requests == 0)
    let enabled = ClaudeSubscriptionUsageProviderClient(
        credentials: credentials, transport: transport, now: { timestamp }, isConnectionEnabled: { true }
    )
    let usage = try await enabled.fetchUsage()
    #expect(usage.provider == .claude)
    #expect(usage.displayRemainingPercent == 58)
    #expect(await counters.reads == 1)
    #expect(await counters.requests == 1)
}

private actor ClaudeConnectionFixtureCounters {
    private(set) var reads = 0
    private(set) var requests = 0
    func recordRead() { reads += 1 }
    func recordRequest() { requests += 1 }
}

private struct ClaudeConnectionFixtureCredentials: ClaudeUsageCredentialSource {
    let counters: ClaudeConnectionFixtureCounters
    func loadCredential(now: Date) async throws -> ClaudeUsageCredential {
        await counters.recordRead()
        return ClaudeUsageCredential(accessToken: "fixture-only", expiresAt: now.addingTimeInterval(3_600))
    }
}

private struct ClaudeConnectionFixtureTransport: ClaudeUsageTransport {
    let counters: ClaudeConnectionFixtureCounters
    func fetch(_ request: URLRequest) async throws -> ClaudeUsageHTTPResponse {
        await counters.recordRequest()
        return ClaudeUsageHTTPResponse(statusCode: 200, data: Data(
            #"{"five_hour":{"utilization":42},"seven_day":{"utilization":41}}"#.utf8
        ))
    }
}

private struct ProviderCLIFixture {
    let directory: URL
    var path: String { directory.appendingPathComponent("quota-cli").path }

    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codextime-provider-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("quota-cli")
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
