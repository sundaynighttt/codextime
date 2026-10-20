import XCTest
@testable import CodexTime

final class GrokUsageDisplayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testNativeMonthlyReadingTakesPrecedenceWithoutRelabelingManualWeek() {
        let manual = WebUsageReading(provider: .grok, percent: 7, valueKind: .remaining,
                                     metric: .grokWeekly, updatedAt: now.addingTimeInterval(-900))
        let direct = reading(used: 42.5, period: .monthly)
        let display = ProviderUsageDisplay(provider: .grok, snapshot: nil,
            webReadings: [.grok: manual], now: now, grokSnapshot: direct)
        XCTAssertEqual(display.percentText, "57.5%")
        XCTAssertEqual(display.statusText, "자동 · 월간")
        XCTAssertTrue(display.accessibilityText.contains("마지막 조회"))
        XCTAssertFalse(display.accessibilityText.contains("주간"))
    }

    func testNativeZeroIsARealReadingAndGrokDoesNotNeedCodexLogin() {
        let display = ProviderUsageDisplay(provider: .grok, snapshot: nil, now: now,
            grokSnapshot: reading(used: 0))
        XCTAssertEqual(display.percentText, "100%")
        XCTAssertEqual(display.statusText, "자동 · 주간")
        XCTAssertNotNil(display.timeText)
    }

    func testOldNativeReadingKeepsValueAndItsObservationTime() {
        let old = reading(used: 80, updatedAt: now.addingTimeInterval(-1_201))
        let display = ProviderUsageDisplay(provider: .grok, snapshot: nil, now: now, grokSnapshot: old)
        XCTAssertEqual(display.percentText, "20%")
        XCTAssertEqual(display.statusText, "지난 조회 · 주간")
        XCTAssertEqual(old.updatedAt, now.addingTimeInterval(-1_201))
    }

    func testExpiredWindowIsNotDisplayedAsFresh() {
        let previous = GrokUsageSnapshot(usedPercent: 80, period: .weekly,
            resetAt: now.addingTimeInterval(-1), updatedAt: now.addingTimeInterval(-30))
        let display = ProviderUsageDisplay(provider: .grok, snapshot: nil, now: now, grokSnapshot: previous)
        XCTAssertEqual(display.statusText, "지난 조회 · 주간")
        XCTAssertEqual(display.percentText, "20%")
    }

    func testReconnectStatePreservesNativeValueAndTime() {
        let value = reading(used: 12)
        let display = ProviderUsageDisplay(provider: .grok, snapshot: nil, now: now,
            grokSnapshot: value, grokRequiresSignIn: true)
        XCTAssertEqual(display.percentText, "88%")
        XCTAssertEqual(display.statusText, "재연결 필요")
        XCTAssertNotNil(display.timeText)
    }

    func testManualFallbackRemainsLabeledManualWhenNativeLoginIsMissing() {
        let manual = WebUsageReading(provider: .grok, percent: 7, valueKind: .remaining,
            metric: .grokWeekly, updatedAt: now)
        let display = ProviderUsageDisplay(provider: .grok, snapshot: nil,
            webReadings: [.grok: manual], now: now, grokRequiresSignIn: true)
        XCTAssertEqual(display.percentText, "7%")
        XCTAssertEqual(display.statusText, "수동 · 주간")
    }

    func testNewManualConfirmationWinsOverDisconnectedNativeAccount() {
        let manual = WebUsageReading(provider: .grok, percent: 7, valueKind: .remaining,
            metric: .grokWeekly, updatedAt: now)
        let display = ProviderUsageDisplay(provider: .grok, snapshot: nil,
            webReadings: [.grok: manual], now: now,
            grokSnapshot: reading(used: 12, updatedAt: now.addingTimeInterval(-30)),
            grokRequiresSignIn: true)
        XCTAssertEqual(display.percentText, "7%")
        XCTAssertEqual(display.statusText, "수동 · 주간")
    }

    func testDemoNeverExposesNativeReadingOrConnectionState() {
        let display = ProviderUsageDisplay(provider: .grok, snapshot: .demo(now: now), now: now,
            grokSnapshot: reading(used: 12), grokRequiresSignIn: true)
        XCTAssertEqual(display.percentText, "—")
        XCTAssertEqual(display.statusText, "예시 없음")
        XCTAssertNil(display.timeText)
    }

    func testInvalidNativeReadingIsNotUsedAndCannotPopulateAnotherProvider() {
        let invalid = GrokUsageSnapshot(usedPercent: 101, period: .weekly, resetAt: nil, updatedAt: now)
        XCTAssertEqual(ProviderUsageDisplay(provider: .grok, snapshot: nil, now: now,
            grokSnapshot: invalid).percentText, "—")
        XCTAssertEqual(ProviderUsageDisplay(provider: .claude, snapshot: nil, now: now,
            grokSnapshot: reading(used: 12)).percentText, "—")
    }

    private func reading(used: Double, period: GrokUsagePeriod = .weekly,
                         updatedAt: Date? = nil) -> GrokUsageSnapshot {
        GrokUsageSnapshot(usedPercent: used, period: period,
            resetAt: now.addingTimeInterval(86_400), updatedAt: updatedAt ?? now)
    }
}
