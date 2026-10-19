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

    func testClaudeSessionAndWeekPersistIndependentlyWithWeeklySummary() {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let store = WebUsageStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let weekly = reading(.claude, percent: 31, kind: .used, metric: .claudeWeekly,
                             updatedAt: now.addingTimeInterval(-3_601))
        let session = reading(.claude, percent: 64, kind: .used, metric: .claudeSession)
        XCTAssertTrue(store.save(weekly, now: now))
        XCTAssertTrue(store.save(session, now: now))
        XCTAssertEqual(store.load(.claude, now: now), weekly)
        XCTAssertEqual(store.load(.claude, metric: .claudeWeekly, now: now), weekly)
        XCTAssertEqual(store.load(.claude, metric: .claudeSession, now: now), session)
        let restartedStore = WebUsageStore(suiteName: suite)
        XCTAssertEqual(restartedStore.loadAllMetrics(now: now), [.claudeWeekly: weekly, .claudeSession: session])
        XCTAssertEqual(restartedStore.loadAll(now: now)[.claude], weekly)
        XCTAssertTrue(weekly.isStale(at: now))
        XCTAssertFalse(session.isStale(at: now))
    }

    func testLegacySingleSessionLoadsReadOnlyThenMigratesOnAppSave() throws {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let session = reading(.claude, percent: 64, kind: .used, metric: .claudeSession)
        defaults.set(try JSONEncoder().encode(session), forKey: "webUsageReading.v1.claude")
        let store = WebUsageStore(suiteName: suite)
        XCTAssertEqual(store.load(.claude, now: now), session)
        XCTAssertEqual(store.load(.claude, metric: .claudeSession, now: now), session)
        XCTAssertNil(store.load(.claude, metric: .claudeWeekly, now: now))
        XCTAssertNotNil(defaults.data(forKey: "webUsageReading.v1.claude"))
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v2.claude.claudeSession"))
        let weekly = reading(.claude, percent: 31, kind: .used, metric: .claudeWeekly)
        XCTAssertTrue(store.save(weekly, now: now))
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v1.claude"))
        XCTAssertNotNil(defaults.data(forKey: "webUsageReading.v2.claude.claudeSession"))
        XCTAssertEqual(store.loadAllMetrics(now: now), [.claudeWeekly: weekly, .claudeSession: session])
    }

    func testLegacyMigrationDoesNotOverwriteExistingMetricAndKeepsOtherProvider() throws {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WebUsageStore(suiteName: suite)
        let weekly = reading(.claude, percent: 31, kind: .used, metric: .claudeWeekly)
        XCTAssertTrue(store.save(weekly, now: now))
        let oldWeek = reading(.claude, percent: 82, kind: .used, metric: .claudeWeekly,
                              updatedAt: now.addingTimeInterval(-600))
        defaults.set(try JSONEncoder().encode(oldWeek), forKey: "webUsageReading.v1.claude")
        let grok = reading(.grok, percent: 46, kind: .used, metric: .grokWeekly)
        defaults.set(try JSONEncoder().encode(grok), forKey: "webUsageReading.v1.grok")
        XCTAssertEqual(store.load(.claude, now: now), weekly)
        XCTAssertEqual(store.load(.grok, now: now), grok)
        XCTAssertNotNil(defaults.data(forKey: "webUsageReading.v1.claude"))
        XCTAssertNotNil(defaults.data(forKey: "webUsageReading.v1.grok"))
        // Explicit app saves perform migration; widget loads above performed none.
        XCTAssertTrue(store.save(weekly, now: now))
        XCTAssertEqual(store.load(.claude, now: now), weekly)
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v1.claude"))
        XCTAssertNotNil(defaults.data(forKey: "webUsageReading.v1.grok"))
        XCTAssertTrue(store.save(grok, now: now))
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v1.grok"))
    }

    func testWidgetReadsNeverMigrateOrRecreateDisconnectedCache() throws {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let appStore = WebUsageStore(suiteName: suite)
        let widgetStore = WebUsageStore(suiteName: suite)
        let session = reading(.claude, percent: 64, kind: .used, metric: .claudeSession)
        let originalData = try JSONEncoder().encode(session)
        defaults.set(originalData, forKey: "webUsageReading.v1.claude")
        let widgetReading = widgetStore.load(.claude, metric: .claudeSession, now: now)
        XCTAssertEqual(widgetReading, session)
        XCTAssertEqual(widgetStore.loadAllMetrics(now: now), [.claudeSession: session])
        XCTAssertEqual(defaults.data(forKey: "webUsageReading.v1.claude"), originalData)
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v2.claude.claudeSession"))
        appStore.delete(.claude)
        // A previously returned widget value is only a value, with no queued write.
        XCTAssertEqual(widgetReading, session)
        XCTAssertTrue(widgetStore.loadAllMetrics(now: now).isEmpty)
        XCTAssertNil(widgetStore.load(.claude, now: now))
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v1.claude"))
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v2.claude.claudeSession"))
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v2.claude.claudeWeekly"))
    }

    func testDisconnectDeletesAllClaudeMetricsAndLegacyButPreservesGrok() throws {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WebUsageStore(suiteName: suite)
        let weekly = reading(.claude, percent: 31, kind: .used, metric: .claudeWeekly)
        let session = reading(.claude, percent: 64, kind: .used, metric: .claudeSession)
        let grok = reading(.grok, percent: 46, kind: .used, metric: .grokWeekly)
        XCTAssertTrue(store.save(weekly, now: now))
        XCTAssertTrue(store.save(session, now: now))
        XCTAssertTrue(store.save(grok, now: now))
        defaults.set(try JSONEncoder().encode(session), forKey: "webUsageReading.v1.claude")
        store.delete(.claude)
        XCTAssertNil(store.load(.claude, now: now))
        XCTAssertEqual(store.loadAllMetrics(now: now), [.grokWeekly: grok])
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v1.claude"))
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v2.claude.claudeWeekly"))
        XCTAssertNil(defaults.data(forKey: "webUsageReading.v2.claude.claudeSession"))
    }

    func testPerMetricCacheRejectsMismatchedIdentityFutureAndUnsupportedLimit() throws {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WebUsageStore(suiteName: suite)
        let session = reading(.claude, percent: 64, kind: .used, metric: .claudeSession)
        defaults.set(try JSONEncoder().encode(session), forKey: "webUsageReading.v2.claude.claudeWeekly")
        XCTAssertNil(store.load(.claude, metric: .claudeWeekly, now: now))
        XCTAssertNil(store.load(.grok, metric: .claudeSession, now: now))
        let future = reading(.claude, percent: 31, kind: .used, metric: .claudeWeekly,
                             updatedAt: now.addingTimeInterval(1))
        defaults.set(try JSONEncoder().encode(future), forKey: "webUsageReading.v2.claude.claudeWeekly")
        XCTAssertNil(store.load(.claude, metric: .claudeWeekly, now: now))
        let unknown = Data(#"{"provider":"claude","percent":0,"valueKind":"used","metric":"claudeFable","updatedAt":1}"#.utf8)
        defaults.set(unknown, forKey: "webUsageReading.v2.claude.claudeWeekly")
        XCTAssertNil(store.load(.claude, metric: .claudeWeekly, now: now))
        XCTAssertTrue(store.loadAllMetrics(now: now).isEmpty)
    }

    @MainActor
    func testCoordinatorAcceptsBothLimitsKeepsPartialTimestampAndRestarts() {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let store = WebUsageStore(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let coordinator = WebUsageCoordinator(store: store, now: now)
        let weekly = reading(.claude, percent: 31, kind: .used, metric: .claudeWeekly,
                             updatedAt: now.addingTimeInterval(-3_601))
        let session = reading(.claude, percent: 64, kind: .used, metric: .claudeSession)
        coordinator.accept(weekly, now: now)
        coordinator.accept(session, now: now)
        XCTAssertEqual(coordinator.readings[.claude], weekly)
        XCTAssertEqual(coordinator.metricReadings, [.claudeWeekly: weekly, .claudeSession: session])
        let laterSession = reading(.claude, percent: 68, kind: .used, metric: .claudeSession,
                                   updatedAt: now.addingTimeInterval(120))
        coordinator.accept(laterSession, now: now.addingTimeInterval(120))
        XCTAssertEqual(coordinator.metricReadings[.claudeWeekly]?.updatedAt, weekly.updatedAt)
        XCTAssertEqual(coordinator.metricReadings[.claudeSession], laterSession)
        let restarted = WebUsageCoordinator(store: store, now: now.addingTimeInterval(120))
        XCTAssertEqual(restarted.metricReadings, coordinator.metricReadings)
        XCTAssertEqual(restarted.readings[.claude], weekly)
        restarted.disconnect(.claude)
        XCTAssertTrue(restarted.metricReadings.isEmpty)
        XCTAssertTrue(restarted.readings.isEmpty)
        XCTAssertTrue(store.loadAllMetrics(now: now.addingTimeInterval(120)).isEmpty)
    }

    func testAppAndWidgetUseSeparateClaudeLimitLabelsTimesAndDemoIsolation() {
        let weekly = reading(.claude, percent: 31, kind: .used, metric: .claudeWeekly,
                             updatedAt: now.addingTimeInterval(-3_601))
        let session = reading(.claude, percent: 64, kind: .used, metric: .claudeSession)
        let metrics: [WebUsageMetric: WebUsageReading] = [.claudeWeekly: weekly, .claudeSession: session]
        let display = ProviderUsageDisplay(provider: .claude, snapshot: nil,
                                           webReadings: [.claude: session], webMetricReadings: metrics, now: now)
        XCTAssertEqual(display.percentText, "69%")
        XCTAssertEqual(display.claudeLimits.map(\.metric), [.claudeWeekly, .claudeSession])
        XCTAssertEqual(display.claudeLimits.map(\.percentText), ["69%", "36%"])
        XCTAssertTrue(display.claudeLimits[0].confirmationText.hasPrefix("지난 "))
        XCTAssertTrue(display.claudeLimits[1].confirmationText.hasPrefix("확인 "))
        XCTAssertTrue(display.accessibilityText.contains("주간, 잔여율 69%"))
        XCTAssertTrue(display.accessibilityText.contains("세션, 잔여율 36%"))
        // App and widget both render these shared, per-limit labels and times.
        let demo = ProviderUsageDisplay(provider: .claude, snapshot: .demo(now: now),
                                        webReadings: [.claude: weekly], webMetricReadings: metrics, now: now)
        XCTAssertEqual(demo.claudeLimits.map(\.percentText), ["—", "—"])
        XCTAssertTrue(demo.claudeLimits.allSatisfy { $0.confirmationText == "예시 없음" })
        XCTAssertFalse(demo.accessibilityText.contains("69%"))
    }

    func testPerMetricStoredPayloadKeepsOnlyNumericReadingAllowlist() throws {
        let suite = "codextime-web-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = WebUsageStore(suiteName: suite)
        XCTAssertTrue(store.save(reading(.claude, percent: 31, kind: .used, metric: .claudeWeekly), now: now))
        let data = try XCTUnwrap(defaults.data(forKey: "webUsageReading.v2.claude.claudeWeekly"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["provider", "percent", "valueKind", "metric", "updatedAt"])
    }

    private func reading(_ provider: WebUsageProvider, percent: Double,
                         kind: WebUsageValueKind, metric: WebUsageMetric,
                         updatedAt: Date? = nil) -> WebUsageReading {
        WebUsageReading(provider: provider, percent: percent, valueKind: kind,
                        metric: metric, updatedAt: updatedAt ?? now)
    }
}
