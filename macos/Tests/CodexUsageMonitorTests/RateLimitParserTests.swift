import Foundation
import Testing
@testable import CodexUsageMonitor

@Test func parsesMainAndSparkBuckets() throws {
    let json = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1788283270},"secondary":null,"planType":"pro"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1788283270},"secondary":null,"planType":"pro"},"codex_spark":{"limitId":"codex_spark","limitName":"Spark","primary":{"usedPercent":21,"windowDurationMins":300,"resetsAt":1787721941},"secondary":null,"planType":"pro"}}}}"#

    let parsed = try RateLimitParser.parse(line: Data(json.utf8))
    let report = try #require(parsed)
    #expect(report.main?.remainingPercent == 96)
    #expect(report.buckets.map(\.name) == ["Codex", "Spark"])
}

@Test func ignoresInitializeResponse() throws {
    let json = #"{"id":1,"result":{"userAgent":"Codex Desktop"}}"#
    #expect(try RateLimitParser.parse(line: Data(json.utf8)) == nil)
}

@Test func formatsCountdown() {
    let now = Date(timeIntervalSince1970: 1_000)
    let reset = now.addingTimeInterval((3 * 86_400) + (17 * 3_600))
    #expect(UsageFormatter.remainingTime(until: reset, now: now) == "3d 17h")
}

@Test func formatsCompactTitleWithOptionalResetTime() {
    let now = Date(timeIntervalSince1970: 1_000)
    let reset = now.addingTimeInterval((3 * 86_400) + (17 * 3_600))
    let bucket = UsageBucket(
        id: "codex",
        name: "Codex",
        primary: RateLimitWindow(
            usedPercent: 4,
            windowDurationMins: 10_080,
            resetsAt: Int64(reset.timeIntervalSince1970)
        ),
        secondary: nil,
        planType: "pro"
    )

    #expect(UsageFormatter.compactTitle(for: bucket, now: now) == "Codex 96% (3d 17h)")
    #expect(UsageFormatter.compactTitle(for: bucket, now: now, showResetTime: false) == "Codex 96%")
}

@Test func defaultsToCompactMenuBarTitleAndPreservesUserChoice() throws {
    let suiteName = "com.sundaynighttt.codex-usage-monitor.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    MenuBarPreferences.registerDefaults(in: defaults)
    #expect(defaults.bool(forKey: MenuBarPreferences.showResetTimeKey) == false)

    defaults.set(true, forKey: MenuBarPreferences.showResetTimeKey)
    MenuBarPreferences.registerDefaults(in: defaults)
    #expect(defaults.bool(forKey: MenuBarPreferences.showResetTimeKey) == true)
}

@Test func fetchesLiveCodexUsageWhenEnabled() async throws {
    guard ProcessInfo.processInfo.environment["CODEX_LIVE_TEST"] == "1" else { return }
    let report = try await CodexAppServerClient().fetchRateLimits()
    #expect(report.main != nil)
    #expect((0...100).contains(report.main?.remainingPercent ?? -1))
}
