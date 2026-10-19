import Foundation
import Security
import Testing
@testable import CodexUsageMonitor

private let grokFixtureToken = "e30.eyJleHAiOjQxMDI0NDQ4MDB9.fixture-only"
private let grokFixtureCipher = "djEwJF9BisKTPgzMDdKAA2aSJuphM7aorlq4YI3tzyGLwKcykkHeetKMEz5SF0g8n1XI"
private let grokFixtureScope = String(repeating: "a", count: 64)

@Test func grokDecryptsIndependentOpenSSLFixtureWithoutRealCredentials() throws {
    let cipher = try #require(Data(base64Encoded: grokFixtureCipher))
    let decoded = try GrokBotSafeStorage.decrypt(cipher, password: Data("fixture-password".utf8))
    #expect(String(data: decoded, encoding: .utf8) == grokFixtureToken)
    // CBC does not authenticate the password: incorrect keys may yield valid padding.
    let wrongPasswordResult = try? GrokBotSafeStorage.decrypt(
        cipher, password: Data("wrong-fixture-password".utf8)
    )
    #expect(wrongPasswordResult != decoded)
}

@Test func grokReadsOnlyActiveAccessTokenAndIgnoresRefreshAndOtherAccounts() throws {
    let store = try grokStoreFixture(selectedTeam: "djEwzMoPMPos9Yy2tWvomdKJiA==")
    let reader = GrokBotStoredCredentials(
        readStore: { store }, readPassword: { _ in Data("fixture-password".utf8) },
        permission: GrokFixturePermission()
    )
    let authorization = try reader.readAuthorization()
    #expect(authorization.accessToken == grokFixtureToken)
    #expect(authorization.selectedTeamID == 42)
}

@Test func grokRejectsCorruptActiveAccountRatherThanUsingLegacyToken() throws {
    let store = try grokStoreFixture(active: String(repeating: "b", count: 64), legacy: grokFixtureCipher)
    let reader = GrokBotStoredCredentials(
        readStore: { store }, readPassword: { _ in Issue.record("Keychain must not be read"); return Data() },
        permission: GrokFixturePermission()
    )
    #expect(throws: ProviderUsageFailure.authenticationRequired) { try reader.readAuthorization() }
}

@Test func grokRejectsPlaintextAndMismatchedScopeWithoutMigration() {
    #expect(throws: ProviderUsageFailure.unsupported) {
        try GrokBotStoredCredentials.ciphertext("plaintext:v1:fixture-only", expectedScope: nil)
    }
    #expect(throws: ProviderUsageFailure.authenticationRequired) {
        try GrokBotStoredCredentials.ciphertext(
            "scoped:v1:\(grokFixtureScope):\(grokFixtureCipher)", expectedScope: String(repeating: "b", count: 64)
        )
    }
    #expect(throws: ProviderUsageFailure.unsupported) {
        try GrokBotSafeStorage.decrypt(Data("v11fixture-only".utf8), password: Data("fixture-only".utf8))
    }
}

@Test func grokDenialStopsAutomaticReadsAndManualRetryAllowsOnlyOnePrompt() throws {
    let permission = GrokFixturePermission()
    let calls = GrokFixtureCounter()
    let store = try grokStoreFixture()
    let automatic = GrokBotStoredCredentials(
        readStore: { store }, readPassword: { allowUI in
            #expect(!allowUI)
            calls.increment()
            throw ProviderUsageFailure.permissionDenied
        }, permission: permission
    )
    #expect(throws: ProviderUsageFailure.permissionDenied) { try automatic.readAuthorization() }
    #expect(throws: ProviderUsageFailure.permissionDenied) { try automatic.readAuthorization() }
    #expect(calls.count == 1)
    let manual = GrokBotStoredCredentials(
        allowAuthenticationUI: true, readStore: { store }, readPassword: { allowUI in
            #expect(allowUI)
            calls.increment()
            throw ProviderUsageFailure.permissionDenied
        }, permission: permission
    )
    #expect(throws: ProviderUsageFailure.permissionDenied) { try manual.readAuthorization() }
    #expect(throws: ProviderUsageFailure.permissionDenied) { try manual.readAuthorization() }
    #expect(calls.count == 2)
}

@Test func grokBackgroundPermissionRequiredDoesNotRecordAnExplicitDenial() throws {
    let permission = GrokFixturePermission()
    let store = try grokStoreFixture()
    let reader = GrokBotStoredCredentials(
        readStore: { store }, readPassword: { _ in throw ProviderUsageFailure.permissionRequired },
        permission: permission
    )
    #expect(throws: ProviderUsageFailure.permissionRequired) { try reader.readAuthorization() }
    #expect(!permission.isDenied())
}

@Test func grokMakesExactlyOneApprovedQuotaRequestAndConvertsUsedPercent() async throws {
    let transport = GrokFixtureTransport(status: 200, body: Data(#"{"usagePercent":23.4,"nextResetTimestampUtc":"2026-10-25T12:34:56.123Z","isUnified":true}"#.utf8))
    let client = GrokBotUsageProviderClient(
        credentials: GrokFixtureCredentials(token: grokFixtureToken, teamID: 42), transport: transport,
        now: { Date(timeIntervalSince1970: 1_000) }
    )
    let snapshot = try await client.fetchUsage()
    #expect(snapshot.provider == .grok)
    #expect(snapshot.displayRemainingPercent == 76)
    #expect(snapshot.windows.first?.label == "공유 주간 한도")
    #expect(snapshot.windows.first?.resetDate != nil)
    let request = try #require(await transport.requests.first)
    #expect(await transport.requests.count == 1)
    #expect(request.url?.absoluteString == "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")
    #expect(request.httpMethod == "POST")
    #expect(request.httpBody == Data("{}".utf8))
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(grokFixtureToken)")
    #expect(request.value(forHTTPHeaderField: "x-cursor-team-id") == "42")
    #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    #expect(request.value(forHTTPHeaderField: "x-cursor-checksum") == nil)
    #expect(!request.httpShouldHandleCookies)
}

@Test func grokExpiredOrMalformedTokenNeverReachesTheNetwork() async {
    for token in ["e30.eyJleHAiOjF9.fixture-only", "invalid-fixture", grokFixtureToken + "\n"] {
        let transport = GrokFixtureTransport(status: 200, body: Data())
        let client = GrokBotUsageProviderClient(
            credentials: GrokFixtureCredentials(token: token), transport: transport,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        await #expect(throws: ProviderUsageFailure.authenticationRequired) { try await client.fetchUsage() }
        #expect(await transport.requests.isEmpty)
    }
}

@Test func grokSanitizesHTTPFailureBodiesAndNeverRetriesAuthentication() async {
    for status in [401, 403, 429, 500, 302] {
        let transport = GrokFixtureTransport(status: status, body: Data("private-fixture-marker".utf8))
        let client = GrokBotUsageProviderClient(
            credentials: GrokFixtureCredentials(token: grokFixtureToken), transport: transport,
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        let expected: ProviderUsageFailure = [401, 403].contains(status) ? .authenticationRequired : .queryFailed
        await #expect(throws: expected) { try await client.fetchUsage() }
        #expect(await transport.requests.count == 1)
    }
}

@Test func grokQuotaRejectsMissingOutOfRangeAndPooledPercent() throws {
    for body in [#"{}"#, #"{"usagePercent":-1}"#, #"{"usagePercent":110}"#, #"{"usagePercent":"NaN"}"#] {
        #expect(throws: ProviderUsageFailure.invalidResponse) {
            try GrokBotUsageProviderClient.decodeQuota(Data(body.utf8))
        }
    }
    #expect(throws: ProviderUsageFailure.unsupported) {
        try GrokBotUsageProviderClient.decodeQuota(Data(#"{"usagePercent":12,"usesPooledEnterpriseAllowance":true}"#.utf8))
    }
    let depleted = try GrokBotUsageProviderClient.decodeQuota(Data(#"{"usagePercent":100}"#.utf8))
    #expect(depleted.displayRemainingPercent == 0)
    #expect(depleted.windows.first?.resetDate == nil)
}

@Test func grokTransportRejectsOtherHostsAndMethodsBeforeNetworkAccess() async {
    let transport = GrokBotURLSessionTransport()
    var other = URLRequest(url: URL(string: "https://example.invalid/quota")!)
    other.httpMethod = "POST"
    await #expect(throws: ProviderUsageFailure.queryFailed) { try await transport.send(other) }
    let wrongMethod = URLRequest(url: GrokBotUsageProviderClient.endpoint)
    await #expect(throws: ProviderUsageFailure.queryFailed) { try await transport.send(wrongMethod) }
}

private func grokStoreFixture(active: String = grokFixtureScope, legacy: String? = nil, selectedTeam: String? = nil) throws -> Data {
    var activeRecord: [String: Any] = [
        "cursor-access-token": "scoped:v1:\(grokFixtureScope):\(grokFixtureCipher)",
        "cursor-refresh-token": ["must": "never decode this field"]
    ]
    if let selectedTeam {
        activeRecord["cursor-selected-team-id"] = "scoped:v1:\(grokFixtureScope):\(selectedTeam)"
    }
    let accounts: [String: Any] = [
        "active": active,
        "accounts": [
            grokFixtureScope: activeRecord,
            "unrelated-fixture-account": ["invalid-ignored-fixture": true]
        ]
    ]
    let accountsJSON = try JSONSerialization.data(withJSONObject: accounts)
    var store: [String: Any] = ["version": 1, "cursor-accounts": String(decoding: accountsJSON, as: UTF8.self)]
    if let legacy { store["cursor-access-token"] = legacy }
    return try JSONSerialization.data(withJSONObject: store)
}

private struct GrokFixtureCredentials: GrokBotCredentialSource {
    let token: String
    var teamID: Int? = nil
    func readAuthorization() throws -> GrokBotAuthorization {
        GrokBotAuthorization(accessToken: token, selectedTeamID: teamID)
    }
}

private actor GrokFixtureTransport: GrokBotUsageTransport {
    let status: Int
    let body: Data
    private(set) var requests: [URLRequest] = []
    init(status: Int, body: Data) { self.status = status; self.body = body }
    func send(_ request: URLRequest) async throws -> GrokBotUsageHTTPResponse {
        requests.append(request)
        return GrokBotUsageHTTPResponse(statusCode: status, body: body)
    }
}

private final class GrokFixturePermission: GrokBotPermissionState, @unchecked Sendable {
    private let lock = NSLock()
    private var denied = false
    func isDenied() -> Bool { lock.lock(); defer { lock.unlock() }; return denied }
    func setDenied(_ denied: Bool) { lock.lock(); defer { lock.unlock() }; self.denied = denied }
}

private final class GrokFixtureCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}


@Test func grokAuthorizationDescriptionsAndDumpRedactCredentials() {
    let authorization = GrokBotAuthorization(accessToken: grokFixtureToken, selectedTeamID: 42)
    var mirrorDump = ""
    dump(authorization, to: &mirrorDump)
    for rendered in [String(describing: authorization), String(reflecting: authorization), mirrorDump] {
        #expect(!rendered.contains(grokFixtureToken))
        #expect(!rendered.contains("42"))
        #expect(rendered.contains("redacted"))
    }
}

@Test func grokKeychainNoAccessIsAnExplicitDenial() {
    #expect(GrokBotStoredCredentials.keychainFailure(for: errSecSuccess) == nil)
    for status in [errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem] {
        #expect(GrokBotStoredCredentials.keychainFailure(for: status) == .permissionDenied)
    }
    #expect(GrokBotStoredCredentials.keychainFailure(for: errSecInteractionNotAllowed) == .permissionRequired)
}

@Test @MainActor func grokCredentialReadsDoNotBlockTheMainThread() async throws {
    let client = GrokBotUsageProviderClient(
        credentials: GrokThreadCheckingCredentials(),
        transport: GrokFixtureTransport(status: 200, body: Data(#"{"usagePercent":45}"#.utf8)),
        now: { Date(timeIntervalSince1970: 1_000) }
    )
    #expect(try await client.fetchUsage().displayRemainingPercent == 55)
}

private struct GrokThreadCheckingCredentials: GrokBotCredentialSource {
    func readAuthorization() throws -> GrokBotAuthorization {
        guard !Thread.isMainThread else { throw ProviderUsageFailure.queryFailed }
        return GrokBotAuthorization(accessToken: grokFixtureToken)
    }
}


@Test func grokConnectionStagesOnlyContainFixedValues() {
    let diagnostics = GrokBotConnectionDiagnostics()
    #expect(diagnostics.stage == nil)
    diagnostics.record(.tokenExpired)
    #expect(diagnostics.stage?.rawValue == "token_expired")
    diagnostics.reset()
    #expect(diagnostics.stage == nil)
}

@Test func grokCredentialDiagnosticsSeparateStoreAndKeychainFailures() throws {
    let store = try grokStoreFixture()
    let unavailable = GrokBotConnectionDiagnostics()
    let unavailableReader = GrokBotStoredCredentials(
        readStore: { throw ProviderUsageFailure.queryFailed },
        readPassword: { _ in Issue.record("Keychain must not be read"); return Data() },
        permission: GrokFixturePermission(), diagnostics: unavailable
    )
    #expect(throws: ProviderUsageFailure.authenticationRequired) { try unavailableReader.readAuthorization() }
    #expect(unavailable.stage == .storeUnavailable)
    let malformed = GrokBotConnectionDiagnostics()
    let malformedReader = GrokBotStoredCredentials(
        readStore: { Data("invalid-fixture".utf8) },
        readPassword: { _ in Issue.record("Keychain must not be read"); return Data() },
        permission: GrokFixturePermission(), diagnostics: malformed
    )
    #expect(throws: ProviderUsageFailure.authenticationRequired) { try malformedReader.readAuthorization() }
    #expect(malformed.stage == .storeFormatOrActiveMissing)
    let missing = GrokBotConnectionDiagnostics()
    let missingReader = GrokBotStoredCredentials(
        readStore: { store }, readPassword: { _ in throw GrokBotKeychainReadFailure.itemMissing },
        permission: GrokFixturePermission(), diagnostics: missing
    )
    #expect(throws: ProviderUsageFailure.authenticationRequired) { try missingReader.readAuthorization() }
    #expect(missing.stage == .keychainItemMissing)
}

@Test func grokConnectionDiagnosticsSeparateTokenAndHTTPFailures() async {
    for (token, expected) in [("invalid-fixture", GrokBotConnectionStage.tokenMalformed), ("e30.eyJleHAiOjF9.fixture-only", .tokenExpired)] {
        let diagnostics = GrokBotConnectionDiagnostics()
        let transport = GrokFixtureTransport(status: 200, body: Data())
        let client = GrokBotUsageProviderClient(
            credentials: GrokFixtureCredentials(token: token), transport: transport,
            now: { Date(timeIntervalSince1970: 1_000) }, diagnostics: diagnostics
        )
        await #expect(throws: ProviderUsageFailure.authenticationRequired) { try await client.fetchUsage() }
        #expect(diagnostics.stage == expected)
        #expect(await transport.requests.isEmpty)
    }
    let diagnostics = GrokBotConnectionDiagnostics()
    let client = GrokBotUsageProviderClient(
        credentials: GrokFixtureCredentials(token: grokFixtureToken),
        transport: GrokFixtureTransport(status: 401, body: Data("private-fixture-marker".utf8)),
        now: { Date(timeIntervalSince1970: 1_000) }, diagnostics: diagnostics
    )
    await #expect(throws: ProviderUsageFailure.authenticationRequired) { try await client.fetchUsage() }
    #expect(diagnostics.stage == .httpAuthRejected)
}
