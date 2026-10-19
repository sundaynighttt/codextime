import XCTest
import UsageSync
@testable import CodexTime

final class CodexTimeTests: XCTestCase {
    func testUsagePayloadMapsRemainingPercentAndReset() throws {
        let data = Data(
            """
            {
              "plan_type": "pro",
              "rate_limit": {
                "allowed": true,
                "limit_reached": false,
                "primary_window": {
                  "used_percent": 27,
                  "reset_after_seconds": 3600,
                  "reset_at": 2000000000
                }
              }
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(UsagePayload.self, from: data)
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let snapshot = try payload.snapshot(now: now)

        XCTAssertEqual(snapshot.remainingPercent, 73)
        XCTAssertEqual(snapshot.resetAt, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(snapshot.updatedAt, now)
        XCTAssertNil(snapshot.lifetimeTokens)
        XCTAssertNil(snapshot.isDemo)
    }

    func testProfilePayloadReadsLifetimeTokens() throws {
        let data = Data(
            """
            {
              "profile": {
                "display_name": "ignored"
              },
              "stats": {
                "lifetime_tokens": 37801098536
              }
            }
            """.utf8
        )

        let payload = try JSONDecoder().decode(ProfilePayload.self, from: data)

        XCTAssertEqual(payload.stats?.lifetimeTokens, 37_801_098_536)
    }

    func testUsageSnapshotDecodesCacheCreatedBeforeLifetimeTokens() throws {
        let data = Data(
            """
            {
              "remainingPercent": 73,
              "resetAt": 2000000000,
              "updatedAt": 1900000000
            }
            """.utf8
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(snapshot.remainingPercent, 73)
        XCTAssertNil(snapshot.lifetimeTokens)
    }

    func testCompactTokenCountUsesKoreanUnits() {
        let locale = Locale(identifier: "ko_KR")

        XCTAssertEqual(UsageFormatter.compactTokenCount(37_801_098_536, locale: locale), "378억")
        XCTAssertEqual(UsageFormatter.compactTokenCount(155_000_000, locale: locale), "1.6억")
        XCTAssertEqual(UsageFormatter.compactTokenCount(9_999, locale: locale), "9,999")
    }

    func testRemainingTimeUsesCompactDayHourFormat() {
        let now = Date(timeIntervalSince1970: 1_000)
        let reset = now.addingTimeInterval(3 * 86_400 + 17 * 3_600 + 30 * 60)

        XCTAssertEqual(UsageFormatter.remainingTime(until: reset, now: now), "3d 17h")
    }

    func testUpdateTimeUsesTwentyFourHourClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3_600))
        let date = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(UsageFormatter.updateTime(date, calendar: calendar), "09:00")
    }

    func testJWTClaimsReadsChatGPTAccountAndExpiration() throws {
        let expiration: TimeInterval = 2_000_000_000
        let token = try fakeJWT(payload: [
            "exp": expiration,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": "account-test",
            ],
        ])

        let claims = try XCTUnwrap(JWTClaims(token: token))
        XCTAssertEqual(claims.chatGPTAccountID, "account-test")
        XCTAssertEqual(claims.expiration, Date(timeIntervalSince1970: expiration))
    }

    func testDeviceCodeResponseAcceptsStringIntervalAndLegacyCodeKey() throws {
        let data = Data(
            """
            {
              "device_auth_id": "device-123",
              "usercode": "ABCD-1234",
              "interval": "5"
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        XCTAssertEqual(response.deviceAuthID, "device-123")
        XCTAssertEqual(response.userCode, "ABCD-1234")
        XCTAssertEqual(response.interval, 5)
    }

    func testDeviceAuthorizationRetriesURLSessionCancellation() {
        XCTAssertTrue(
            DeviceAuthorizationRetryPolicy.shouldRetry(URLError(.cancelled))
        )
    }

    func testDeviceAuthorizationDoesNotRetryUnrelatedErrors() {
        XCTAssertFalse(
            DeviceAuthorizationRetryPolicy.shouldRetry(CodexClientError.invalidResponse)
        )
    }

    func testDemoIsExplicitAndSeparateFromRealCache() {
        let store = SharedUsageStore(suiteName: "codextime-test-\(UUID().uuidString)")
        defer { store.delete() }
        let real = UsageSnapshot(remainingPercent: 42, resetAt: .distantFuture,
                                 updatedAt: .distantPast, lifetimeTokens: nil)
        store.save(real)
        let demo = store.startDemo(now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(demo.isDemo, true)
        XCTAssertEqual(store.load(), demo)
        store.save(demo)
        store.endDemo()
        XCTAssertEqual(store.load(), real)
        XCTAssertFalse(store.isDemoEnabled)
    }

    func testDemoRefreshKeepsSampleValueAndResetTime() throws {
        let store = SharedUsageStore(suiteName: "codextime-test-\(UUID().uuidString)")
        defer { store.delete() }
        let initial = store.startDemo(now: Date(timeIntervalSince1970: 1_000))
        let refreshed = try XCTUnwrap(store.refreshDemo(now: Date(timeIntervalSince1970: 2_000)))
        XCTAssertEqual(refreshed.remainingPercent, initial.remainingPercent)
        XCTAssertEqual(refreshed.resetAt, initial.resetAt)
        XCTAssertEqual(refreshed.updatedAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(refreshed.isDemo, true)
    }

    func testDemoClientDoesNotNeedNetworkAndExitClearsDemo() async throws {
        let store = SharedUsageStore(suiteName: "codextime-test-\(UUID().uuidString)")
        defer { store.delete() }
        _ = store.startDemo()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RejectNetworkProtocol.self]
        let client = CodexAccountClient(session: URLSession(configuration: configuration), usageStore: store)
        let snapshot = try await client.fetchUsage()
        XCTAssertEqual(snapshot.isDemo, true)
        XCTAssertEqual(snapshot.remainingPercent, 73)
        try await client.signOut()
        XCTAssertNil(store.load())
    }

    func testProviderDisplayDistinguishesMissingValueFromZero() {
        let missing = ProviderUsageDisplay(provider: .codex, snapshot: nil)
        XCTAssertEqual(missing.percentText, "—")
        XCTAssertEqual(missing.statusText, "연결 필요")
        let zero = UsageSnapshot(remainingPercent: 0, resetAt: .distantFuture,
                                 updatedAt: .distantPast, lifetimeTokens: nil)
        XCTAssertEqual(ProviderUsageDisplay(provider: .codex, snapshot: zero).percentText, "0%")
    }

    func testUnconnectedProvidersNeverReuseCodexValues() {
        let real = UsageSnapshot(remainingPercent: 42, resetAt: .distantFuture,
                                 updatedAt: .distantPast, lifetimeTokens: nil)
        for snapshot in [real, .demo()] {
            for provider in [PhoneUsageProvider.grok, .claude] {
                let display = ProviderUsageDisplay(provider: provider, snapshot: snapshot)
                XCTAssertEqual(display.percentText, "—")
                XCTAssertEqual(display.statusText, provider == .claude ? "허용 확인" :
                    (snapshot.isDemo == true ? "예시 · 일시 정지" : "iCloud 연결"))
                XCTAssertTrue(display.accessibilityText.contains("잔여량 없음"))
            }
        }
    }

    func testCodexDisplayPreservesRealAndExplicitDemoStates() {
        let real = UsageSnapshot(remainingPercent: 42, resetAt: .distantFuture,
                                 updatedAt: .distantPast, lifetimeTokens: nil)
        XCTAssertEqual(ProviderUsageDisplay(provider: .codex, snapshot: real).percentText, "42%")
        XCTAssertEqual(ProviderUsageDisplay(provider: .codex, snapshot: real).statusText, "연결됨")
        let demo = ProviderUsageDisplay(provider: .codex, snapshot: .demo())
        XCTAssertEqual(demo.statusText, "예시")
        XCTAssertTrue(demo.accessibilityText.contains("예시 데이터"))
    }

    func testGrokUsesOnlyOptedInMatchingCloudResult() {
        let now = Date()
        let reading = SyncedUsage(provider: .grok, remainingPercent: 67,
                                  resetAt: now.addingTimeInterval(3_600), observedAt: now, status: .ready)
        let codex = UsageSnapshot(remainingPercent: 42, resetAt: .distantFuture,
                                  updatedAt: now, lifetimeTokens: nil)
        let disconnected = ProviderUsageDisplay(provider: .grok, snapshot: codex,
                                                cloudReading: reading, cloudEnabled: false, now: now)
        XCTAssertEqual(disconnected.percentText, "—")
        XCTAssertEqual(disconnected.statusText, "iCloud 연결")
        let connected = ProviderUsageDisplay(provider: .grok, snapshot: codex,
                                             cloudReading: reading, cloudEnabled: true, now: now)
        XCTAssertEqual(connected.percentText, "67%")
        XCTAssertEqual(connected.statusText, "Mac에서 동기화")
        XCTAssertTrue(connected.accessibilityText.contains("67퍼센트"))
        XCTAssertEqual(ProviderUsageDisplay(provider: .codex, snapshot: codex,
                                            cloudReading: reading, cloudEnabled: true, now: now).percentText, "42%")
    }

    func testGrokCloudCacheShowsStaleAndNetworkFailureWithoutInventingNewValue() {
        let now = Date()
        let reading = SyncedUsage(provider: .grok, remainingPercent: 0,
                                  resetAt: now.addingTimeInterval(3_600), observedAt: now, status: .ready)
        let stale = ProviderUsageDisplay(provider: .grok, snapshot: nil, cloudReading: reading,
                                         cloudEnabled: true, now: now.addingTimeInterval(1_201))
        XCTAssertEqual(stale.percentText, "0%")
        XCTAssertEqual(stale.statusText, "오래된 정보")
        let networkError = ProviderUsageDisplay(provider: .grok, snapshot: nil, cloudReading: reading,
                                                cloudEnabled: true, cloudHadError: true, now: now)
        XCTAssertEqual(networkError.percentText, "0%")
        XCTAssertEqual(networkError.statusText, "연결 오류 · 캐시")
        let missing = ProviderUsageDisplay(provider: .grok, snapshot: nil,
                                           cloudEnabled: true, cloudHadError: true, now: now)
        XCTAssertEqual(missing.percentText, "—")
        XCTAssertEqual(missing.statusText, "동기화 오류")
    }

    func testGrokNeverShowsBlockedFailedPausedOrOtherProviderNumbers() {
        let now = Date()
        for status in [SyncReadingStatus.disconnected, .paused, .blocked, .failed] {
            let reading = SyncedUsage(provider: .grok, remainingPercent: 67,
                                      resetAt: now.addingTimeInterval(3_600), observedAt: now, status: status)
            XCTAssertEqual(ProviderUsageDisplay(provider: .grok, snapshot: nil, cloudReading: reading,
                                                cloudEnabled: true, now: now).percentText, "—")
        }
        let claude = SyncedUsage(provider: .claude, remainingPercent: 67,
                                 resetAt: now.addingTimeInterval(3_600), observedAt: now, status: .ready)
        XCTAssertEqual(ProviderUsageDisplay(provider: .grok, snapshot: nil, cloudReading: claude,
                                            cloudEnabled: true, now: now).percentText, "—")
    }

    func testClaudeRemainsBlockedEvenWithCloudValueAndCodexDemo() {
        let now = Date()
        let reading = SyncedUsage(provider: .claude, remainingPercent: 67,
                                  resetAt: now.addingTimeInterval(3_600), observedAt: now, status: .ready)
        let display = ProviderUsageDisplay(provider: .claude, snapshot: .demo(), cloudReading: reading,
                                            cloudEnabled: true, now: now)
        XCTAssertEqual(display.percentText, "—")
        XCTAssertEqual(display.statusText, "허용 확인")
        XCTAssertTrue(display.accessibilityText.contains("연결 차단됨"))
    }

    func testDemoNeverRendersRealCloudQuota() {
        let now = Date()
        let reading = SyncedUsage(provider: .grok, remainingPercent: 67,
                                  resetAt: now.addingTimeInterval(3_600), observedAt: now, status: .ready)
        let display = ProviderUsageDisplay(provider: .grok, snapshot: .demo(), cloudReading: reading,
                                            cloudEnabled: true, now: now)
        XCTAssertEqual(display.percentText, "—")
        XCTAssertEqual(display.statusText, "예시 · 일시 정지")
        XCTAssertTrue(display.accessibilityText.contains("일시 정지"))
        XCTAssertFalse(display.accessibilityText.contains("67"))
    }

    @MainActor
    func testDemoPausesCloudRequestsAndExitResumesExistingOptIn() async throws {
        let suiteName = "codextime-demo-cloud-test-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let usageStore = SharedUsageStore(suiteName: suiteName)
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let transport = CountingCloudTransport()
        let sync = UsageCloudSync(preferences: preferences, transport: transport)
        await sync.enable()
        let previousFetches = transport.fetches
        let previousScopeChecks = transport.scopeChecks
        _ = usageStore.startDemo()
        let model = AppModel(usageStore: usageStore, cloudSync: sync)
        await model.refreshCloudIfAllowed()
        XCTAssertEqual(transport.fetches, previousFetches)
        XCTAssertEqual(transport.scopeChecks, previousScopeChecks)
        XCTAssertTrue(UsageSyncCache.isRequestedEnabled(preferences: preferences))
        usageStore.endDemo()
        await model.refreshCloudIfAllowed()
        XCTAssertEqual(transport.fetches, previousFetches + 1)
    }

    func testConfigurationErrorMarksCloudResultAsCachedError() {
        XCTAssertTrue(CloudSyncState.notConfigured.hasCloudReadError)
    }

    func testReleaseKeepsAppIdentity() {
        XCTAssertEqual(CodexConfiguration.appGroupID, "group.com.sundaynighttt.codextime")
        XCTAssertEqual(CodexConfiguration.keychainGroupSuffix, "com.sundaynighttt.codextime.auth")
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.sundaynighttt.codextime.ios")
    }

    private func fakeJWT(payload: [String: Any]) throws -> String {
        let header = try JSONSerialization.data(withJSONObject: ["alg": "none"])
        let payload = try JSONSerialization.data(withJSONObject: payload)
        return [header, payload, Data("signature".utf8)]
            .map { data in
                data.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "=", with: "")
            }
            .joined(separator: ".")
    }
}

private final class RejectNetworkProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTFail("예시 모드는 네트워크를 호출하면 안 됩니다")
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@MainActor
private final class CountingCloudTransport: UsageSyncTransport {
    var scopeChecks = 0
    var fetches = 0
    func accountScope() async throws -> String? {
        scopeChecks += 1
        return "fake-own-account"
    }
    func fetch(expectedScope: String) async throws -> [SyncedUsage] {
        fetches += 1
        return []
    }
    func save(_ readings: [SyncedUsage], expectedScope: String) async throws {}
    func deleteAll(expectedScope: String) async throws {}
}
