import Foundation
import Testing
import UsageSync
@testable import CodexUsageMonitor

@Test func cloudSnapshotContainsOnlyVerifiedGrokSummaryAndBlockedClaude() throws {
    let observed = Date(timeIntervalSince1970: 1_000)
    let reset = Date(timeIntervalSince1970: 3_000)
    let grok = ProviderUsageState(id: .grok,
        snapshot: ProviderUsageSnapshot(provider: .grok, windows: [
            ProviderUsageWindow(id: "first", label: "fixture private label", remainingPercent: 75, resetDate: reset),
            ProviderUsageWindow(id: "shared", label: "other fixture", remainingPercent: 40.9, resetDate: reset)
        ], planName: "fixture private plan"), lastSuccess: observed)
    let claude = ProviderUsageState(id: .claude,
        snapshot: ProviderUsageSnapshot(provider: .claude, windows: [
            ProviderUsageWindow(id: "previous", label: "must never be transferred", remainingPercent: 58)
        ]), lastSuccess: observed)
    let readings = MacUsageCloudSnapshot.readings(states: [.grok: grok, .claude: claude],
        enabledProviders: Set(ProviderID.allCases), isGrokVerified: true)
    #expect(readings.count == 2)
    #expect(readings[0].provider == .grok)
    #expect(readings[0].remainingPercent == 40)
    #expect(readings[0].resetAt == reset)
    #expect(readings[0].observedAt == observed)
    #expect(readings[0].status == .ready)
    #expect(readings[1].provider == .claude)
    #expect(readings[1].remainingPercent == nil)
    #expect(readings[1].observedAt == nil)
    #expect(readings[1].status == .blocked)
    let serialized = String(decoding: try JSONEncoder().encode(readings), as: UTF8.self)
    #expect(!serialized.contains("fixture private"))
    #expect(!serialized.contains("must never"))
    #expect(!serialized.contains("codex"))
}

@Test func cloudSnapshotClearsNumbersWhenHiddenUnverifiedDisconnectedOrFailed() {
    let state = ProviderUsageState(id: .grok,
        snapshot: ProviderUsageSnapshot(provider: .grok, windows: [
            ProviderUsageWindow(id: "quota", label: "fixture", remainingPercent: 75)
        ]), lastSuccess: Date(timeIntervalSince1970: 1_000))
    let hidden = MacUsageCloudSnapshot.readings(states: [.grok: state],
        enabledProviders: [.codex, .claude], isGrokVerified: true)[0]
    #expect(hidden.status == .paused)
    #expect(hidden.remainingPercent == nil)
    let unverified = MacUsageCloudSnapshot.readings(states: [.grok: state],
        enabledProviders: Set(ProviderID.allCases), isGrokVerified: false)[0]
    #expect(unverified.status == .disconnected)
    #expect(unverified.remainingPercent == nil)
    let cases: [(ProviderUsageFailure, SyncReadingStatus)] = [
        (.authenticationRequired, .disconnected), (.notConnected, .disconnected),
        (.queryFailed, .failed), (.timeout, .failed), (.unsupported, .blocked)
    ]
    for (failure, expected) in cases {
        var failed = state
        failed.failure = failure
        let reading = MacUsageCloudSnapshot.readings(states: [.grok: failed],
            enabledProviders: Set(ProviderID.allCases), isGrokVerified: true)[0]
        #expect(reading.status == expected)
        #expect(reading.remainingPercent == nil)
        #expect(reading.resetAt == nil)
        #expect(reading.observedAt == nil)
    }
}

@Test @MainActor func cloudPublisherCoalescesClockUpdatesAndFinishesWithLatestPause() async throws {
    let suite = "codextime-cloud-publisher-fixture-\(UUID())"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let transport = CloudPublisherFixtureTransport()
    let cloud = UsageCloudSync(preferences: preferences, transport: transport)
    await cloud.enable()
    let publisher = MacUsageCloudPublisher(sync: cloud)
    defer {
        transport.releaseFirstSave()
        publisher.stopPending()
        cloud.stopReceiving()
    }
    let ready = [SyncedUsage(provider: .grok, remainingPercent: 71, resetAt: nil,
        observedAt: Date(timeIntervalSince1970: 1_000), status: .ready)]
    publisher.enqueue(ready)
    for _ in 0..<1_000 where transport.saves.isEmpty { await Task.yield() }
    try #require(transport.saves.count == 1)
    publisher.enqueue(ready)
    publisher.enqueue(ready)
    let paused = [SyncedUsage(provider: .grok, remainingPercent: nil, resetAt: nil,
        observedAt: nil, status: .paused)]
    publisher.enqueue(paused)
    transport.releaseFirstSave()
    for _ in 0..<1_000 where transport.saves.count < 2 { await Task.yield() }
    #expect(transport.saves.count == 2)
    #expect(transport.saves.last?.first?.status == .paused)
    #expect(transport.saves.last?.first?.remainingPercent == nil)
    publisher.stopPending()
    cloud.stopReceiving()
}

@MainActor private final class CloudPublisherFixtureTransport: UsageSyncTransport {
    var saves: [[SyncedUsage]] = []
    private var firstSave: CheckedContinuation<Void, Never>?
    func accountScope() async throws -> String? { "synthetic-account-scope" }
    func fetch(expectedScope: String) async throws -> [SyncedUsage] { [] }
    func save(_ readings: [SyncedUsage], expectedScope: String) async throws {
        saves.append(readings)
        if saves.count == 1 { await withCheckedContinuation { firstSave = $0 } }
    }
    func deleteAll(expectedScope: String) async throws {}
    func releaseFirstSave() { firstSave?.resume(); firstSave = nil }
}
