import XCTest
@testable import CodexTime

final class WebProviderUsageTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testUsedAndRemainingAreExplicitAndPreserveZero() {
        let used = reading(.grok, percent: 52, kind: .used, metric: .grokWeekly)
        XCTAssertEqual(used.usedPercent, 52)
        XCTAssertEqual(used.remainingPercent, 48)
        let remaining = reading(.claude, percent: 0, kind: .remaining, metric: .claudeSession)
        XCTAssertEqual(remaining.remainingPercent, 0)
        XCTAssertEqual(remaining.usedPercent, 100)
        XCTAssertEqual(ProviderUsageDisplay(provider: .claude, snapshot: nil,
                                           webReadings: [.claude: remaining], now: now).percentText, "0%")
    }

    func testRejectsNonfiniteOutOfRangeAndWrongProviderMetric() {
        for percent in [Double.nan, .infinity, -.infinity, -0.1, 100.1] {
            XCTAssertFalse(reading(.grok, percent: percent, kind: .used, metric: .grokWeekly).isValid)
        }
        let mismatch = reading(.grok, percent: 20, kind: .used, metric: .claudeWeekly)
        XCTAssertFalse(mismatch.isValid)
        XCTAssertTrue(mismatch.remainingPercent.isNaN)
    }

    func testProviderDisplayKeepsCodexAndWebSourcesSeparate() {
        let codex = UsageSnapshot(remainingPercent: 42, resetAt: .distantFuture,
                                  updatedAt: now, lifetimeTokens: nil)
        let grok = reading(.grok, percent: 52, kind: .used, metric: .grokWeekly)
        let readings: [WebUsageProvider: WebUsageReading] = [.grok: grok]
        XCTAssertEqual(ProviderUsageDisplay(provider: .codex, snapshot: codex,
                                           webReadings: readings, now: now).percentText, "42%")
        XCTAssertEqual(ProviderUsageDisplay(provider: .grok, snapshot: codex,
                                           webReadings: readings, now: now).percentText, "48%")
        XCTAssertEqual(ProviderUsageDisplay(provider: .claude, snapshot: codex,
                                           webReadings: readings, now: now).percentText, "—")
    }

    func testDemoDoesNotMixActualWebReadings() {
        let actual = reading(.grok, percent: 52, kind: .used, metric: .grokWeekly)
        let display = ProviderUsageDisplay(provider: .grok, snapshot: .demo(now: now),
                                           webReadings: [.grok: actual], now: now)
        XCTAssertEqual(display.percentText, "—")
        XCTAssertEqual(display.statusText, "예시 없음")
        XCTAssertNil(display.timeText)
    }

    func testOldValueStaysExplicitlyManualAndKeepsMetric() {
        let old = reading(.claude, percent: 12.5, kind: .used, metric: .claudeWeekly,
                          updatedAt: now.addingTimeInterval(-3_601))
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil,
                                           webReadings: [.claude: old], now: now)
        XCTAssertEqual(old.remainingPercent, 87.5)
        XCTAssertEqual(display.statusText, "지난 확인 · 주간")
        XCTAssertNotNil(display.timeText)
        XCTAssertTrue(display.accessibilityText.contains("사용률"))
    }

    func testPreviousDayConfirmationIncludesDate() {
        let old = reading(.grok, percent: 52, kind: .used, metric: .grokWeekly,
                          updatedAt: now.addingTimeInterval(-2 * 86_400))
        XCTAssertTrue(old.confirmationTimeText(at: now).contains("/"))
        XCTAssertFalse(old.confirmationTimeText(at: now).isEmpty)
    }

    func testCacheRoundTripAndPerProviderDelete() {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let store = WebUsageStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let grok = reading(.grok, percent: 52, kind: .used, metric: .grokWeekly)
        let claude = reading(.claude, percent: 18, kind: .remaining, metric: .claudeSession)
        XCTAssertTrue(store.save(grok, now: now))
        XCTAssertTrue(store.save(claude, now: now))
        XCTAssertEqual(store.loadAll(now: now), [.grok: grok, .claude: claude])
        store.delete(.grok)
        XCTAssertNil(store.load(.grok, now: now))
        XCTAssertEqual(store.load(.claude, now: now), claude)
    }

    func testCacheRejectsFutureTimestampOnWriteAndRead() throws {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let store = WebUsageStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let future = reading(.claude, percent: 10, kind: .used, metric: .claudeSession,
                             updatedAt: now.addingTimeInterval(1))
        XCTAssertFalse(store.save(future, now: now))
        UserDefaults(suiteName: suite)?.set(try JSONEncoder().encode(future),
                                          forKey: "webUsageReading.v1.claude")
        XCTAssertNil(store.load(.claude, now: now))
    }

    func testCacheRejectsWrongProviderMalformedAndOversizedData() throws {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let store = WebUsageStore(suiteName: suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let wrong = reading(.claude, percent: 10, kind: .used, metric: .claudeWeekly)
        defaults.set(try JSONEncoder().encode(wrong), forKey: "webUsageReading.v1.grok")
        XCTAssertNil(store.load(.grok, now: now))
        defaults.set(Data("invalid".utf8), forKey: "webUsageReading.v1.grok")
        XCTAssertNil(store.load(.grok, now: now))
        defaults.set(Data(repeating: 0, count: 1_025), forKey: "webUsageReading.v1.grok")
        XCTAssertNil(store.load(.grok, now: now))
    }

    @MainActor
    func testCoordinatorRejectsInvalidAndDisconnectClearsOnlyRequestedProvider() {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let store = WebUsageStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let coordinator = WebUsageCoordinator(store: store)
        let grok = reading(.grok, percent: 52, kind: .used, metric: .grokWeekly)
        let claude = reading(.claude, percent: 18, kind: .remaining, metric: .claudeSession)
        coordinator.accept(grok, now: now)
        coordinator.accept(claude, now: now)
        coordinator.accept(reading(.grok, percent: 200, kind: .used, metric: .grokWeekly), now: now)
        XCTAssertEqual(coordinator.readings[.grok], grok)
        coordinator.disconnect(.grok)
        XCTAssertNil(coordinator.readings[.grok])
        XCTAssertNil(store.load(.grok, now: now))
        XCTAssertEqual(coordinator.readings[.claude], claude)
    }

    @MainActor
    func testDisconnectKeepsSameProviderModelOwnedForSheetReopen() {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let store = WebUsageStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let coordinator = WebUsageCoordinator(store: store)
        let sheetModel = coordinator.model(for: .grok)
        let otherModel = coordinator.model(for: .claude)
        coordinator.accept(reading(.grok, percent: 52, kind: .used, metric: .grokWeekly), now: now)

        // Disconnect happens on the model held by the still-presented sheet.
        // Fetching that provider again must not replace its model or lose a reopened session.
        sheetModel.disconnect()
        XCTAssertNil(sheetModel.webView)
        XCTAssertNil(coordinator.readings[.grok])
        XCTAssertNil(store.load(.grok, now: now))
        XCTAssertTrue(coordinator.model(for: .grok) === sheetModel)
        XCTAssertTrue(coordinator.model(for: .claude) === otherModel)
    }

    func testTwoDecimalPercentFromParserRemainsVisible() {
        let value = reading(.claude, percent: 12.34, kind: .used, metric: .claudeSession)
        XCTAssertEqual(value.remainingPercent, 87.66, accuracy: 0.000_001)
        XCTAssertTrue(WebUsageReading.percentText(value.usedPercent).contains("34"))
        XCTAssertTrue(WebUsageReading.percentText(value.remainingPercent).contains("66"))
    }

    private func reading(_ provider: WebUsageProvider, percent: Double,
                         kind: WebUsageValueKind, metric: WebUsageMetric,
                         updatedAt: Date? = nil) -> WebUsageReading {
        WebUsageReading(provider: provider, percent: percent, valueKind: kind,
                        metric: metric, updatedAt: updatedAt ?? now)
    }
}
