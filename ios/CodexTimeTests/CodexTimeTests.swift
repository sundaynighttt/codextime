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
