import Foundation
import Security
import Testing
@testable import CodexUsageMonitor

private let claudeFixtureNow = Date(timeIntervalSince1970: 1_800_000_000)

@Test func claudeCredentialParserAcceptsOnlyUnexpiredProfileScopedOAuth() throws {
    let data = Data(#"{"claudeAiOauth":{"accessToken":"fixture-access-token","expiresAt":1800003600000,"scopes":["user:profile","user:inference"],"refreshToken":"ignored-fixture-refresh"}}"#.utf8)
    let credential = try ClaudeUsageCredentialParser.parse(data: data, now: claudeFixtureNow)
    #expect(credential.expiresAt == claudeFixtureNow.addingTimeInterval(3_600))
    #expect(!String(describing: credential).contains("fixture-access-token"))
    #expect(!String(reflecting: credential).contains("fixture-access-token"))
    for invalid in [
        #"{"claudeAiOauth":{"accessToken":"fixture","expiresAt":1799999999000,"scopes":["user:profile"]}}"#,
        #"{"claudeAiOauth":{"accessToken":"fixture","expiresAt":true,"scopes":["user:profile"]}}"#,
        #"{"claudeAiOauth":{"accessToken":"fixture\nvalue","expiresAt":1800003600000,"scopes":["user:profile"]}}"#,
        #"{"claudeAiOauth":{"accessToken":"","expiresAt":1800003600000,"scopes":["user:profile"]}}"#,
        #"{"mcpOAuth":{}}"#
    ] {
        #expect(throws: ProviderUsageFailure.authenticationRequired) {
            try ClaudeUsageCredentialParser.parse(data: Data(invalid.utf8), now: claudeFixtureNow)
        }
    }
    #expect(throws: ProviderUsageFailure.unsupported) {
        try ClaudeUsageCredentialParser.parse(data: Data(#"{"claudeAiOauth":{"accessToken":"fixture","expiresAt":1800003600000,"scopes":["user:inference"]}}"#.utf8), now: claudeFixtureNow)
    }
}

@Test func claudeOAuthParserKeepsOnlyWhitelistedQuotaWindows() throws {
    let json = #"{"five_hour":{"utilization":12.5,"resets_at":"2027-01-15T09:00:00.000Z"},"seven_day":{"utilization":100,"resets_at":"2027-01-18T09:00:00Z"},"seven_day_sonnet":{"utilization":0},"seven_day_opus":{"utilization":null},"account":{"email":"fixture@example.invalid"},"extra_usage":{"monthly_limit":500,"used_credits":100},"unexpected_quota":{"utilization":1}}"#
    let snapshot = try ClaudeOAuthUsageParser.parse(data: Data(json.utf8))
    #expect(snapshot.provider == .claude)
    #expect(snapshot.planName == nil)
    #expect(snapshot.windows.map(\.id) == ["five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus"])
    #expect(snapshot.windows.map(\.remainingPercent) == [87.5, 0, 100, nil])
    #expect(snapshot.windows.first?.resetDate != nil)
    #expect(snapshot.displayRemainingPercent == 0)
}

@Test func claudeModelSpecificDepletionDoesNotReplaceSharedQuotaSummary() throws {
    let json = #"{"five_hour":{"utilization":50},"seven_day":{"utilization":25},"seven_day_opus":{"utilization":100}}"#
    let snapshot = try ClaudeOAuthUsageParser.parse(data: Data(json.utf8))
    #expect(snapshot.displayRemainingPercent == 50)
    #expect(snapshot.windows.first(where: { $0.id == "seven_day_opus" })?.remainingPercent == 0)
}

@Test func claudeOAuthUnknownValuesNeverBecomeZeroOrHundred() throws {
    for value in ["null", "true", "-1", "101", "\"50\""] {
        let json = "{\"five_hour\":{\"utilization\":\(value),\"resets_at\":\"invalid-date\"}}"
        let snapshot = try ClaudeOAuthUsageParser.parse(data: Data(json.utf8))
        #expect(snapshot.windows.first?.remainingPercent == nil)
        #expect(snapshot.windows.first?.resetDate == nil)
    }
    #expect(throws: ProviderUsageFailure.invalidResponse) {
        try ClaudeOAuthUsageParser.parse(data: Data(#"{"extra_usage":{"used_credits":0}}"#.utf8))
    }
}

@Test func claudeOAuthClientUsesOnlyUsageEndpointAndApprovedHeaders() async throws {
    let transport = ClaudeFixtureTransport(response: ClaudeUsageHTTPResponse(
        statusCode: 200, data: Data(#"{"five_hour":{"utilization":40}}"#.utf8)))
    let client = ClaudeOAuthUsageProviderClient(credentials: ClaudeFixtureCredentials(), transport: transport,
                                               now: { claudeFixtureNow })
    let result = try await client.fetchUsage()
    #expect(result.displayRemainingPercent == 60)
    let request = try #require(await transport.request)
    #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(request.httpMethod == "GET")
    #expect(request.httpBody == nil)
    #expect(request.timeoutInterval == 8)
    #expect(request.httpShouldHandleCookies == false)
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access-token")
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
}

@Test func claudeOAuthExpiredCredentialsStopBeforeNetworking() async throws {
    let transport = ClaudeFixtureTransport(response: ClaudeUsageHTTPResponse(statusCode: 200, data: Data()))
    let client = ClaudeOAuthUsageProviderClient(
        credentials: ClaudeFixtureCredentials(expiry: claudeFixtureNow.addingTimeInterval(-1)),
        transport: transport, now: { claudeFixtureNow })
    do {
        _ = try await client.fetchUsage()
        Issue.record("Expected expired login to stop before the request")
    } catch { #expect(error as? ProviderUsageFailure == .authenticationRequired) }
    #expect(await transport.request == nil)
}

@Test func claudeOAuthHTTPAndNetworkFailuresNeverExposeResponseBodies() async throws {
    for (status, failure) in [(401, ProviderUsageFailure.authenticationRequired), (403, .authenticationRequired),
                              (429, .queryFailed), (500, .queryFailed), (302, .queryFailed)] {
        let client = ClaudeOAuthUsageProviderClient(credentials: ClaudeFixtureCredentials(),
            transport: ClaudeFixtureTransport(response: ClaudeUsageHTTPResponse(statusCode: status,
                data: Data("fixture-private-body".utf8))), now: { claudeFixtureNow })
        do { _ = try await client.fetchUsage(); Issue.record("Expected a fixed failure") }
        catch { #expect(error as? ProviderUsageFailure == failure) }
    }
    let timedOut = ClaudeOAuthUsageProviderClient(credentials: ClaudeFixtureCredentials(),
        transport: ClaudeFixtureFailingTransport(error: URLError(.timedOut)), now: { claudeFixtureNow })
    do { _ = try await timedOut.fetchUsage(); Issue.record("Expected timeout") }
    catch { #expect(error as? ProviderUsageFailure == .timeout) }
    let failed = ClaudeOAuthUsageProviderClient(credentials: ClaudeFixtureCredentials(),
        transport: ClaudeFixtureFailingTransport(error: NSError(domain: "fixture-private-message", code: 1)),
        now: { claudeFixtureNow })
    do { _ = try await failed.fetchUsage(); Issue.record("Expected sanitized failure") }
    catch { #expect(error as? ProviderUsageFailure == .queryFailed) }
}

@Test func claudeOAuthPermissionDenialBlocksBackgroundReadsUntilExplicitRetry() throws {
    let suite = "codextime-claude-permission-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let state = ClaudeUsageKeychainPermissionState(defaults: defaults)
    #expect(state.failure(for: errSecUserCanceled) == .permissionDenied)
    #expect(throws: ProviderUsageFailure.permissionDenied) { try state.beginAttempt(allowAuthenticationUI: false) }
    try state.beginAttempt(allowAuthenticationUI: true)
    try state.beginAttempt(allowAuthenticationUI: false)
    #expect(defaults.object(forKey: ClaudeUsageKeychainPermissionState.deniedKey) == nil)
    #expect(state.failure(for: errSecInteractionNotAllowed) == .permissionRequired)
    #expect(state.failure(for: errSecItemNotFound) == .authenticationRequired)
}

@Test func claudeOAuthTransportRejectsForeignHostsBeforeNetworking() async throws {
    let request = URLRequest(url: URL(string: "https://example.invalid/api/oauth/usage")!)
    do { _ = try await ClaudeUsageEphemeralTransport().fetch(request); Issue.record("Expected rejected host") }
    catch { #expect(error as? ProviderUsageFailure == .unsupported) }
}

@Test func claudeOAuthRedirectsNeverForwardAuthorization() throws {
    let delegate = ClaudeUsageSessionDelegate()
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: ClaudeOAuthUsageProviderClient.endpoint)
    let response = try #require(HTTPURLResponse(url: ClaudeOAuthUsageProviderClient.endpoint, statusCode: 302,
        httpVersion: nil, headerFields: ["Location": "https://example.invalid/"]))
    var redirected: URLRequest? = URLRequest(url: URL(string: "https://example.invalid/")!)
    delegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                        newRequest: redirected!) { redirected = $0 }
    #expect(redirected == nil)
}

private struct ClaudeFixtureCredentials: ClaudeUsageCredentialSource {
    var expiry = claudeFixtureNow.addingTimeInterval(3_600)
    func loadCredential(now: Date) async throws -> ClaudeUsageCredential {
        ClaudeUsageCredential(accessToken: "fixture-access-token", expiresAt: expiry)
    }
}

private actor ClaudeFixtureTransport: ClaudeUsageTransport {
    let response: ClaudeUsageHTTPResponse
    private(set) var request: URLRequest?
    init(response: ClaudeUsageHTTPResponse) { self.response = response }
    func fetch(_ request: URLRequest) async throws -> ClaudeUsageHTTPResponse {
        self.request = request
        return response
    }
}

private struct ClaudeFixtureFailingTransport: ClaudeUsageTransport {
    let error: any Error
    func fetch(_ request: URLRequest) async throws -> ClaudeUsageHTTPResponse { throw error }
}
