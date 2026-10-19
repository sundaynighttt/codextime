import Foundation
import Testing
@testable import CodexUsageMonitor

@Test func providerOrderAndUnknownPercentRemainExplicit() {
    #expect(ProviderID.allCases == [.codex, .grok, .claude])
    for percent in [Double.nan, .infinity, -.infinity, -1, 101] {
        let window = ProviderUsageWindow(id: "unknown", label: "한도", remainingPercent: percent)
        #expect(window.remainingPercent == nil)
        #expect(window.displayRemainingPercent == nil)
    }
    let unknown = ProviderUsageWindow(id: "missing", label: "한도", remainingPercent: nil)
    #expect(unknown.displayRemainingPercent == nil)
    let valid = ProviderUsageWindow(id: "valid", label: "한도", remainingPercent: 99.9)
    #expect(valid.displayRemainingPercent == 99)
}

@Test func compactPercentUsesMostRestrictedValidWindow() {
    let snapshot = ProviderUsageSnapshot(provider: .codex, windows: [
        ProviderUsageWindow(id: "short", label: "단기", remainingPercent: 93),
        ProviderUsageWindow(id: "weekly", label: "주간", remainingPercent: 0),
        ProviderUsageWindow(id: "unknown", label: "미확인", remainingPercent: nil)
    ])
    #expect(snapshot.displayWindow?.id == "weekly")
    #expect(snapshot.displayRemainingPercent == 0)
    #expect(ProviderUsageSnapshot(provider: .grok, windows: []).displayRemainingPercent == nil)
}

@Test func modelSpecificLimitsDoNotReduceTheSharedUsageSummary() {
    let modelWindow = ProviderUsageWindow(
        id: "sonnet", label: "Sonnet 주간 한도", remainingPercent: 0, countsTowardSummary: false
    )
    let shared = ProviderUsageSnapshot(provider: .claude, windows: [
        ProviderUsageWindow(id: "short", label: "단기", remainingPercent: 80),
        ProviderUsageWindow(id: "weekly", label: "주간", remainingPercent: 50),
        modelWindow
    ])
    #expect(shared.displayRemainingPercent == 50)
    #expect(modelWindow.displayRemainingPercent == 0)
    #expect(ProviderUsageSnapshot(provider: .claude, windows: [modelWindow]).displayRemainingPercent == nil)
    let depletedShared = ProviderUsageSnapshot(provider: .claude, windows: [
        ProviderUsageWindow(id: "short", label: "단기", remainingPercent: 80),
        ProviderUsageWindow(id: "weekly", label: "주간", remainingPercent: 0),
        modelWindow
    ])
    #expect(depletedShared.displayRemainingPercent == 0)
}

@Test func malformedDurationAndResetRemainUnknown() {
    let window = ProviderUsageWindow(
        id: "malformed", label: "한도", remainingPercent: 12,
        resetDate: Date(timeIntervalSince1970: .infinity), durationMinutes: -1
    )
    #expect(window.resetDate == nil)
    #expect(window.durationMinutes == nil)
}

@Test func staleStateRequiresSuccessAndDetectsFailureOrAge() {
    let timestamp = Date(timeIntervalSince1970: 1_000)
    var state = ProviderUsageState(id: .codex)
    #expect(!state.isStale(now: timestamp.addingTimeInterval(5_000)))
    state.lastSuccess = timestamp
    #expect(!state.isStale(now: timestamp.addingTimeInterval(1_200)))
    #expect(state.isStale(now: timestamp.addingTimeInterval(1_201)))
    state.failure = .queryFailed
    #expect(state.isStale(now: timestamp))
}

@Test @MainActor func everyProviderHasAnUnknownSlotBeforeConnecting() async {
    let store = UsageStore(clients: [], automaticallyStart: false)
    #expect(Set(store.states.keys) == Set(ProviderID.allCases))
    for id in ProviderID.allCases {
        #expect(store.states[id]?.displayRemainingPercent == nil)
        #expect(store.states[id]?.lastSuccess == nil)
    }
    await store.refreshAndWait()
    for id in ProviderID.allCases {
        #expect(store.states[id]?.failure == .notConnected)
        #expect(store.states[id]?.displayRemainingPercent == nil)
        #expect(store.states[id]?.isRefreshing == false)
    }
}

@Test @MainActor func partialSuccessPublishesBeforeOtherProviderCompletes() async throws {
    let codex = FakeUsageProvider(id: .codex, responses: [.success(snapshot(.codex, 93))])
    let grok = FakeUsageProvider(id: .grok, responses: [.failure(.notConnected)], delay: 0.15)
    let claude = FakeUsageProvider(id: .claude, responses: [.failure(.authenticationRequired)])
    let store = UsageStore(clients: [codex, grok, claude], automaticallyStart: false)
    store.refresh()
    try await waitUntil { store.states[.codex]?.lastSuccess != nil }
    #expect(store.states[.codex]?.displayRemainingPercent == 93)
    #expect(store.states[.grok]?.isRefreshing == true)
    #expect(store.isRefreshing)
    await store.refreshAndWait(.grok)
    #expect(store.states[.grok]?.failure == .notConnected)
    #expect(store.states[.claude]?.failure == .authenticationRequired)
    #expect(store.states[.codex]?.failure == nil)
    #expect(!store.isRefreshing)
    #expect(await codex.callCount == 1)
}

@Test @MainActor func repeatedRefreshJoinsTheSameProviderRequest() async {
    let client = FakeUsageProvider(id: .codex, responses: [.success(snapshot(.codex, 77))], delay: 0.05)
    let store = UsageStore(clients: [client], automaticallyStart: false)
    store.refresh(.codex)
    store.refresh(.codex)
    store.refresh(.codex)
    await store.refreshAndWait(.codex)
    #expect(await client.callCount == 1)
    #expect(await client.maximumActive == 1)
    #expect(store.states[.codex]?.displayRemainingPercent == 77)
}

@Test @MainActor func failureRetainsLastSuccessAndMarksItStale() async {
    let first = snapshot(.codex, 61)
    let timestamp = Date(timeIntervalSince1970: 2_000)
    let client = FakeUsageProvider(id: .codex, responses: [.success(first), .failure(.queryFailed), .success(snapshot(.codex, 62))])
    let store = UsageStore(clients: [client], automaticallyStart: false, currentDate: { timestamp })
    await store.refreshAndWait(.codex)
    #expect(store.states[.codex]?.snapshot == first)
    #expect(store.states[.codex]?.lastSuccess == timestamp)
    #expect(store.states[.codex]?.failure == nil)
    await store.refreshAndWait(.codex)
    #expect(store.states[.codex]?.snapshot == first)
    #expect(store.states[.codex]?.lastSuccess == timestamp)
    #expect(store.states[.codex]?.failure == .queryFailed)
    #expect(store.states[.codex]?.isStale(now: timestamp) == true)
    #expect(!store.isRefreshing)
    await store.refreshAndWait(.codex)
    #expect(store.states[.codex]?.failure == nil)
    #expect(store.states[.codex]?.displayRemainingPercent == 62)
    #expect(store.states[.codex]?.isStale(now: timestamp) == false)
}

@Test @MainActor func timeoutCancelsOwnedWorkAndKeepsDedupUntilCleanupFinishes() async throws {
    let client = FakeUsageProvider(
        id: .grok, responses: [.success(snapshot(.grok, 56))],
        delay: 10, cancellationCleanupDelay: 0.06
    )
    let store = UsageStore(clients: [client], requestTimeout: 0.02, automaticallyStart: false)
    let start = DispatchTime.now().uptimeNanoseconds
    store.refresh(.grok)
    try await waitUntil { await client.cancellationCount == 1 }
    #expect(store.states[.grok]?.isRefreshing == true)
    store.refresh(.grok)
    store.refresh(.grok)
    #expect(await client.callCount == 1)
    await store.refreshAndWait(.grok)
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    #expect(elapsed < 1)
    #expect(store.states[.grok]?.failure == .timeout)
    #expect(store.states[.grok]?.lastSuccess == nil)
    #expect(store.states[.grok]?.displayRemainingPercent == nil)
    #expect(store.states[.grok]?.isRefreshing == false)
    #expect(await client.activeCount == 0)
    await store.refreshAndWait(.grok)
    #expect(await client.callCount == 2)
    #expect(await client.maximumActive == 1)
}

@Test @MainActor func mismatchedProviderDoesNotReplaceLastSuccess() async {
    let first = snapshot(.claude, 48)
    let client = FakeUsageProvider(id: .claude, responses: [
        .success(first), .success(snapshot(.grok, 100))
    ])
    let store = UsageStore(clients: [client], automaticallyStart: false)
    await store.refreshAndWait(.claude)
    let timestamp = store.states[.claude]?.lastSuccess
    await store.refreshAndWait(.claude)
    #expect(store.states[.claude]?.snapshot == first)
    #expect(store.states[.claude]?.lastSuccess == timestamp)
    #expect(store.states[.claude]?.failure == .invalidResponse)
}

@Test @MainActor func unknownQuotaIsSuccessfulWithoutInventingAPercent() async {
    let client = FakeUsageProvider(id: .grok, responses: [.success(ProviderUsageSnapshot(
        provider: .grok,
        windows: [ProviderUsageWindow(id: "short", label: "단기", remainingPercent: nil)]
    ))])
    let store = UsageStore(clients: [client], automaticallyStart: false)
    await store.refreshAndWait(.grok)
    #expect(store.states[.grok]?.lastSuccess != nil)
    #expect(store.states[.grok]?.displayRemainingPercent == nil)
    #expect(store.states[.grok]?.error == nil)
}

@Test @MainActor func rawProviderErrorNeverReachesPublishedState() async {
    let client = FakeUsageProvider(id: .claude, responses: [.rawFailure])
    let store = UsageStore(clients: [client], automaticallyStart: false)
    await store.refreshAndWait(.claude)
    #expect(store.states[.claude]?.failure == .queryFailed)
    #expect(store.states[.claude]?.error == ProviderUsageFailure.queryFailed.errorDescription)
    #expect(store.states[.claude]?.error?.contains("private-fixture-marker") == false)
}

@Test @MainActor func shutdownCancelsAndWaitsBeforeBlockingNewRequests() async throws {
    let client = FakeUsageProvider(
        id: .codex, responses: [.success(snapshot(.codex, 30))],
        delay: 10, cancellationCleanupDelay: 0.03
    )
    let store = UsageStore(clients: [client], automaticallyStart: false)
    store.refresh(.codex)
    try await waitUntil { await client.callCount == 1 }
    await store.shutdown()
    #expect(await client.activeCount == 0)
    #expect(await client.cancellationCount == 1)
    #expect(store.states[.codex]?.failure == nil)
    #expect(!store.isRefreshing)
    store.start()
    store.refresh(.codex)
    await store.refreshAndWait()
    #expect(await client.callCount == 1)
}

@Test @MainActor func manualConnectionSharesDedupAndDoesNotApplyBackgroundTimeout() async {
    let automatic = FakeUsageProvider(id: .grok, responses: [.success(snapshot(.grok, 10))])
    let manual = FakeUsageProvider(id: .grok, responses: [.success(snapshot(.grok, 74))], delay: 0.06)
    let duplicate = FakeUsageProvider(id: .grok, responses: [.success(snapshot(.grok, 1))])
    let store = UsageStore(clients: [automatic], requestTimeout: 0.005, automaticallyStart: false)
    store.connect(.grok, using: manual)
    #expect(store.states[.grok]?.connectionIsPending == true)
    #expect(store.states[.grok]?.isRefreshing == true)
    store.refresh(.grok)
    store.connect(.grok, using: duplicate)
    await store.refreshAndWait(.grok)
    #expect(await manual.callCount == 1)
    #expect(await automatic.callCount == 0)
    #expect(await duplicate.callCount == 0)
    #expect(await manual.cancellationCount == 0)
    #expect(store.states[.grok]?.displayRemainingPercent == 74)
    #expect(store.states[.grok]?.failure == nil)
    #expect(store.states[.grok]?.connectionIsPending == false)
    #expect(!store.isRefreshing)
}

@Test @MainActor func runningAutomaticRequestAlsoBlocksManualConnection() async {
    let automatic = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 20))], delay: 0.03)
    let manual = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 80))])
    let store = UsageStore(clients: [automatic], automaticallyStart: false)
    store.refresh(.claude)
    store.connect(.claude, using: manual)
    #expect(store.states[.claude]?.connectionIsPending == false)
    await store.refreshAndWait(.claude)
    #expect(await automatic.callCount == 1)
    #expect(await manual.callCount == 0)
    #expect(store.states[.claude]?.displayRemainingPercent == 20)
}

@Test @MainActor func manualConnectionSuccessClearsPermissionRequiredAndUpdatesUsage() async {
    let automatic = FakeUsageProvider(id: .claude, responses: [.failure(.permissionRequired)])
    let manual = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 87))])
    let timestamp = Date(timeIntervalSince1970: 3_000)
    let store = UsageStore(clients: [automatic], automaticallyStart: false, currentDate: { timestamp })
    await store.refreshAndWait(.claude)
    #expect(store.states[.claude]?.failure == .permissionRequired)
    #expect(store.states[.claude]?.error == "사용량 조회 권한이 필요합니다. 메뉴에서 연결 권한을 요청해 주세요.")
    store.connect(.claude, using: manual)
    await store.refreshAndWait(.claude)
    #expect(store.states[.claude]?.failure == nil)
    #expect(store.states[.claude]?.lastSuccess == timestamp)
    #expect(store.states[.claude]?.displayRemainingPercent == 87)
    #expect(store.states[.claude]?.connectionIsPending == false)
}

@Test @MainActor func manualPermissionDenialKeepsCachedUsageAndPublishesFixedMessage() async {
    let automatic = FakeUsageProvider(id: .grok, responses: [.success(snapshot(.grok, 63))])
    let manual = FakeUsageProvider(id: .grok, responses: [.failure(.permissionDenied)])
    let timestamp = Date(timeIntervalSince1970: 4_000)
    let store = UsageStore(clients: [automatic], automaticallyStart: false, currentDate: { timestamp })
    await store.refreshAndWait(.grok)
    store.connect(.grok, using: manual)
    await store.refreshAndWait(.grok)
    #expect(store.states[.grok]?.failure == .permissionDenied)
    #expect(store.states[.grok]?.error == "사용자가 사용량 조회 권한 요청을 취소하거나 거부했습니다.")
    #expect(store.states[.grok]?.displayRemainingPercent == 63)
    #expect(store.states[.grok]?.lastSuccess == timestamp)
    #expect(store.states[.grok]?.isStale(now: timestamp) == true)
    #expect(store.states[.grok]?.connectionIsPending == false)
}

@Test @MainActor func manualConnectionRejectsAMismatchedProviderClient() async {
    let manual = FakeUsageProvider(id: .grok, responses: [.success(snapshot(.grok, 40))])
    let store = UsageStore(clients: [], automaticallyStart: false)
    store.connect(.claude, using: manual)
    #expect(await manual.callCount == 0)
    #expect(store.states[.claude]?.failure == .invalidResponse)
    #expect(store.states[.claude]?.connectionIsPending == false)
    #expect(!store.isRefreshing)
}

@Test @MainActor func shutdownAlsoWaitsForManualConnectionCleanup() async throws {
    let manual = FakeUsageProvider(
        id: .claude, responses: [.success(snapshot(.claude, 45))],
        delay: 10, cancellationCleanupDelay: 0.03
    )
    let store = UsageStore(clients: [], automaticallyStart: false)
    store.connect(.claude, using: manual)
    try await waitUntil { await manual.callCount == 1 }
    await store.shutdown()
    #expect(await manual.activeCount == 0)
    #expect(await manual.cancellationCount == 1)
    #expect(store.states[.claude]?.connectionIsPending == false)
    #expect(store.states[.claude]?.lastSuccess == nil)
    #expect(store.states[.claude]?.failure == nil)
    store.connect(.claude, using: manual)
    #expect(await manual.callCount == 1)
    #expect(!store.isRefreshing)
}

@Test @MainActor func shutdownBeforeManualTaskStartsDoesNotBeginPermissionRequest() async {
    let manual = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 90))])
    let store = UsageStore(clients: [], automaticallyStart: false)
    store.connect(.claude, using: manual)
    await store.shutdown()
    #expect(await manual.callCount == 0)
    #expect(store.states[.claude]?.connectionIsPending == false)
    #expect(store.states[.claude]?.failure == nil)
    #expect(!store.isRefreshing)
}

@Test @MainActor func disabledProvidersSkipAutomaticIndividualAndManualRequests() async {
    let codex = FakeUsageProvider(id: .codex, responses: [.success(snapshot(.codex, 80))])
    let claude = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 58))])
    let manual = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 12))])
    let store = UsageStore(clients: [codex, claude], enabledProviders: [.codex], automaticallyStart: false)
    store.refresh(.claude)
    store.connect(.claude, using: manual)
    await store.refreshAndWait()
    #expect(await codex.callCount == 1)
    #expect(await claude.callCount == 0)
    #expect(await manual.callCount == 0)
    #expect(store.states[.claude]?.lastAttempt == nil)
    #expect(store.states[.claude]?.failure == nil)
    store.setEnabled(true, for: .claude)
    await store.refreshAndWait(.claude)
    #expect(await claude.callCount == 1)
    #expect(store.states[.claude]?.displayRemainingPercent == 58)
}

@Test @MainActor func hidingCancelsOwnedWorkPreservesCacheAndDoesNotPublishCancellation() async throws {
    let client = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 58))],
                                   cancellationCleanupDelay: 0.04)
    let store = UsageStore(clients: [client], automaticallyStart: false)
    await store.refreshAndWait(.claude)
    let previous = store.states[.claude]
    await client.setDelay(10)
    store.refresh(.claude)
    try await waitUntil { await client.callCount == 2 }
    store.setEnabled(false, for: .claude)
    try await waitUntil { await client.cancellationCount == 1 }
    #expect(store.states[.claude]?.isRefreshing == true)
    #expect(!store.isRefreshing)
    store.refresh(.claude)
    await store.refreshAndWait(.claude)
    #expect(await client.callCount == 2)
    #expect(await client.activeCount == 0)
    #expect(store.states[.claude]?.snapshot == previous?.snapshot)
    #expect(store.states[.claude]?.lastSuccess == previous?.lastSuccess)
    #expect(store.states[.claude]?.failure == previous?.failure)
    #expect(store.states[.claude]?.isRefreshing == false)
}

@Test @MainActor func rapidReenableWaitsForCleanupAndRefreshesOnceWithoutOverlap() async throws {
    let client = FakeUsageProvider(id: .grok, responses: [
        .success(snapshot(.grok, 10)), .success(snapshot(.grok, 54))
    ], delay: 10, cancellationCleanupDelay: 0.06)
    let store = UsageStore(clients: [client], automaticallyStart: false)
    store.refresh(.grok)
    try await waitUntil { await client.callCount == 1 }
    store.setEnabled(false, for: .grok)
    try await waitUntil { await client.cancellationCount == 1 }
    await client.setDelay(0)
    store.setEnabled(true, for: .grok)
    store.setEnabled(true, for: .grok)
    await store.refreshAndWait(.grok)
    #expect(await client.callCount == 2)
    #expect(await client.maximumActive == 1)
    #expect(await client.activeCount == 0)
    #expect(store.states[.grok]?.displayRemainingPercent == 54)
    #expect(store.states[.grok]?.failure == nil)
}

@Test @MainActor func disconnectJoinsCleanupBlocksRacesAndClearsOnlyTargetAccount() async throws {
    let codex = FakeUsageProvider(id: .codex, responses: [.success(snapshot(.codex, 80))])
    let claude = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 58))],
                                  cancellationCleanupDelay: 0.04)
    let manual = FakeUsageProvider(id: .claude, responses: [.success(snapshot(.claude, 1))])
    let store = UsageStore(clients: [codex, claude], enabledProviders: [.codex, .claude], automaticallyStart: false)
    await store.refreshAndWait()
    let previousCodex = store.states[.codex]
    await claude.setDelay(10)
    store.refresh(.claude)
    try await waitUntil { await claude.callCount == 2 }
    let first = Task { @MainActor in await store.disconnect(.claude) }
    let second = Task { @MainActor in await store.disconnect(.claude) }
    try await waitUntil { await claude.cancellationCount == 1 }
    store.refresh(.claude)
    store.connect(.claude, using: manual)
    await first.value
    await second.value
    #expect(await claude.callCount == 2)
    #expect(await claude.activeCount == 0)
    #expect(await manual.callCount == 0)
    #expect(store.states[.claude] == ProviderUsageState(id: .claude))
    #expect(store.states[.codex] == previousCodex)
    #expect(store.enabledProviders == [.codex, .claude])
}

private func snapshot(_ provider: ProviderID, _ percent: Double) -> ProviderUsageSnapshot {
    ProviderUsageSnapshot(provider: provider, windows: [
        ProviderUsageWindow(id: "short", label: "단기 한도", remainingPercent: percent, durationMinutes: 300)
    ])
}

@MainActor
private func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    Issue.record("Provider state did not reach the expected condition")
}

private enum FakeResponse: Sendable {
    case success(ProviderUsageSnapshot)
    case failure(ProviderUsageFailure)
    case rawFailure
}

private struct RawFixtureError: LocalizedError {
    var errorDescription: String? { "private-fixture-marker" }
}

private actor FakeUsageProvider: UsageProviderClient {
    nonisolated let id: ProviderID
    private let responses: [FakeResponse]
    private var delay: TimeInterval
    private let cancellationCleanupDelay: TimeInterval
    private(set) var callCount = 0
    private(set) var activeCount = 0
    private(set) var maximumActive = 0
    private(set) var cancellationCount = 0

    init(
        id: ProviderID,
        responses: [FakeResponse],
        delay: TimeInterval = 0,
        cancellationCleanupDelay: TimeInterval = 0
    ) {
        self.id = id
        self.responses = responses
        self.delay = delay
        self.cancellationCleanupDelay = cancellationCleanupDelay
    }

    func setDelay(_ delay: TimeInterval) { self.delay = delay }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        let response = responses[min(callCount, responses.count - 1)]
        callCount += 1
        activeCount += 1
        maximumActive = max(maximumActive, activeCount)
        defer { activeCount -= 1 }
        do {
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        } catch {
            cancellationCount += 1
            if cancellationCleanupDelay > 0 {
                let cleanupDelay = cancellationCleanupDelay
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + cleanupDelay) {
                        continuation.resume()
                    }
                }
            }
            throw error
        }
        switch response {
        case let .success(snapshot): return snapshot
        case let .failure(error): throw error
        case .rawFailure: throw RawFixtureError()
        }
    }
}
