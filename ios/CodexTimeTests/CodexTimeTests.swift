import XCTest
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
