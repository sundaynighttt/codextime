import XCTest
@testable import CodexTime

final class ClaudeNativeUsageDisplayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testStandaloneClaudeDisplaysItsOwnAtomicPair() {
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil, now: now,
            claudeSnapshot: reading())
        XCTAssertEqual(display.claudeLimits.map(\.percentText), ["75%", "90%"])
        XCTAssertEqual(display.statusText, "자동 조회")
        XCTAssertTrue(display.claudeLimits.allSatisfy { $0.confirmationText.hasPrefix("자동 ") })
        XCTAssertTrue(display.accessibilityText.contains("사용률 25%"))
    }

    func testNativePairPrecedesOlderManualAndDoesNotMixSources() {
        let manual = WebUsageReading(provider: .claude, percent: 3, valueKind: .remaining,
            metric: .claudeWeekly, updatedAt: now.addingTimeInterval(-100))
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil,
            webMetricReadings: [.claudeWeekly: manual], now: now, claudeSnapshot: reading())
        XCTAssertEqual(display.claudeLimits.map(\.percentText), ["75%", "90%"])
    }

    func testZeroUsageIsNotMissing() {
        let direct = ClaudeNativeUsageSnapshot(fiveHour: .init(usedPercent: 0, resetAt: nil),
            sevenDay: .init(usedPercent: 100, resetAt: nil), updatedAt: now)
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil, now: now, claudeSnapshot: direct)
        XCTAssertEqual(display.claudeLimits.map(\.percentText), ["0%", "100%"])
    }

    func testOldOrResetPairIsMarkedAsPreviousObservation() {
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil, now: now,
            claudeSnapshot: reading(updatedAt: now.addingTimeInterval(-1_201)))
        XCTAssertEqual(display.statusText, "지난 조회")
        XCTAssertTrue(display.claudeLimits.allSatisfy { $0.confirmationText.hasPrefix("지난 ") })
    }

    func testReconnectKeepsObservationWithoutCallingItFresh() {
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil, now: now,
            claudeSnapshot: reading(), claudeRequiresSignIn: true)
        XCTAssertEqual(display.claudeLimits.map(\.percentText), ["75%", "90%"])
        XCTAssertTrue(display.claudeLimits.allSatisfy { $0.confirmationText == "재연결 필요" })
    }

    func testNewManualSourceAfterFailedConnectionWinsAsOnePair() {
        let manual = WebUsageReading(provider: .claude, percent: 3, valueKind: .remaining,
            metric: .claudeWeekly, updatedAt: now)
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil,
            webMetricReadings: [.claudeWeekly: manual], now: now,
            claudeSnapshot: reading(updatedAt: now.addingTimeInterval(-30)), claudeRequiresSignIn: true)
        XCTAssertEqual(display.claudeLimits.map(\.percentText), ["3%", "—"])
        XCTAssertEqual(display.statusText, "수동 · 주간")
    }

    func testDemoAndOtherProvidersCannotExposeClaudeAccountData() {
        let demo = ProviderUsageDisplay(provider: .claude, snapshot: .demo(now: now), now: now,
            claudeSnapshot: reading(), claudeRequiresSignIn: true)
        XCTAssertEqual(demo.claudeLimits.map(\.percentText), ["—", "—"])
        XCTAssertTrue(demo.claudeLimits.allSatisfy { $0.confirmationText == "예시 없음" })
        let grok = ProviderUsageDisplay(provider: .grok, snapshot: nil, now: now, claudeSnapshot: reading())
        XCTAssertEqual(grok.percentText, "—")
    }

    func testMalformedPairFailsClosed() {
        let direct = ClaudeNativeUsageSnapshot(fiveHour: .init(usedPercent: 101, resetAt: nil),
            sevenDay: .init(usedPercent: 1, resetAt: nil), updatedAt: now)
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil, now: now, claudeSnapshot: direct)
        XCTAssertEqual(display.claudeLimits.map(\.percentText), ["—", "—"])
    }

    private func reading(updatedAt: Date? = nil) -> ClaudeNativeUsageSnapshot {
        .init(fiveHour: .init(usedPercent: 10, resetAt: now.addingTimeInterval(3_600)),
              sevenDay: .init(usedPercent: 25, resetAt: now.addingTimeInterval(86_400)),
              updatedAt: updatedAt ?? now)
    }
}
