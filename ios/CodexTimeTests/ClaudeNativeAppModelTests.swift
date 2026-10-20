import XCTest
@testable import CodexTime

@MainActor
final class ClaudeNativeAppModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFreshCacheLoadsWithoutRepeatingUsageRequest() async {
        let cached = reading(at: now.addingTimeInterval(-120))
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        let requests = await client.fetchCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertTrue(model.isConnected)
        XCTAssertFalse(model.requiresSignIn)
    }

    func testStaleCacheReplacesBothWindowsAtRealObservationTime() async {
        let cached = reading(at: now.addingTimeInterval(-601))
        let fresh = reading(at: now, fiveHourUsed: 32, sevenDayUsed: 68)
        let client = ClaudeAppClientStub(authenticated: true, snapshot: fresh)
        var reloads = 0
        let model = makeModel(client, cached: cached, reloadWidgets: { reloads += 1 })
        await model.load()
        let requests = await client.fetchCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.snapshot, fresh)
        XCTAssertEqual(model.snapshot?.fiveHour.remainingPercent, 68)
        XCTAssertEqual(model.snapshot?.sevenDay.remainingPercent, 32)
        XCTAssertEqual(reloads, 1)
    }

    func testDisconnectedCacheRequiresSignInWithoutUsageRequest() async {
        let cached = reading(at: now.addingTimeInterval(-120))
        let client = ClaudeAppClientStub(authenticated: false, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        let requests = await client.fetchCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertFalse(model.isConnected)
        XCTAssertTrue(model.requiresSignIn)
    }

    func testDemoDoesNotReadAuthenticationOrStartLoginOrUsage() async {
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: reading(at: now), isDemo: { true })
        await model.load()
        model.beginSignIn()
        model.completeSignIn(pastedCode: "synthetic-code")
        await model.refresh()
        await Task.yield()
        let counts = await client.counts()
        XCTAssertEqual(counts.authentication, 0)
        XCTAssertEqual(counts.authorization, 0)
        XCTAssertEqual(counts.completion, 0)
        XCTAssertEqual(counts.usage, 0)
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.canBeginSignIn)
        XCTAssertFalse(model.canCompleteSignIn)
    }

    func testDemoEnteringDuringFetchDiscardsLateResult() async throws {
        let demo = ClaudeAppDemoFlag()
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        await client.setFetchBlocked(true)
        var reloads = 0
        let model = makeModel(client, isDemo: { demo.value }, reloadWidgets: { reloads += 1 })
        let loading = Task { await model.load() }
        try await waitUntil { await client.fetchCount == 1 }
        demo.value = true
        await model.synchronizeDemoState()
        await client.finishFetch()
        await loading.value
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(reloads, 0)
    }

    func testFetchFailureKeepsBothWindowsAndBacksOffAutomaticRetry() async {
        let cached = reading(at: now.addingTimeInterval(-601))
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        await client.setFetchFailure(.network)
        let model = makeModel(client, cached: cached)
        await model.load()
        await model.refreshIfNeeded()
        let requests = await client.fetchCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertEqual(model.snapshot?.updatedAt, cached.updatedAt)
        XCTAssertEqual(model.error, .network)
        XCTAssertTrue(model.isConnected)
    }

    func testExpiredLoginKeepsLastValueButRequestsReconnection() async {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setFetchFailure(.loginExpired)
        await model.refresh()
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertTrue(model.requiresSignIn)
        XCTAssertFalse(model.isConnected)
        XCTAssertEqual(model.error, .loginExpired)
    }

    func testSuccessfulAuthorizationPublishesNewAccountValue() async throws {
        let fresh = reading(at: now, fiveHourUsed: 12, sevenDayUsed: 40)
        let client = ClaudeAppClientStub(authenticated: false, snapshot: fresh)
        var reloads = 0
        let model = makeModel(client, reloadWidgets: { reloads += 1 })
        model.beginSignIn()
        try await waitUntil { model.authorization != nil }
        XCTAssertTrue(model.isAuthenticating)
        XCTAssertTrue(model.canCompleteSignIn)
        XCTAssertFalse(model.canBeginSignIn)
        model.completeSignIn(pastedCode: "synthetic-code")
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.snapshot, fresh)
        XCTAssertNil(model.authorization)
        XCTAssertTrue(model.isConnected)
        XCTAssertFalse(model.isCompletingAuthorization)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertEqual(reloads, 2)
    }

    func testInvalidCallbackPreservesFlowForCorrectedPaste() async throws {
        let client = ClaudeAppClientStub(authenticated: false, snapshot: reading(at: now))
        await client.setCompletionFailure(.invalidCallback)
        let model = makeModel(client)
        model.beginSignIn()
        try await waitUntil { model.authorization != nil }
        let descriptor = model.authorization
        model.completeSignIn(pastedCode: "synthetic-wrong-state")
        try await waitUntil { model.error == .invalidCallback && !model.isCompletingAuthorization }
        XCTAssertEqual(model.authorization, descriptor)
        XCTAssertTrue(model.isAuthenticating)
        XCTAssertTrue(model.canCompleteSignIn)
        XCTAssertFalse(model.isConnected)
        model.completeSignIn(pastedCode: "synthetic-correct-code")
        try await waitUntil { !model.isAuthenticating }
        XCTAssertTrue(model.isConnected)
        XCTAssertNotNil(model.snapshot)
        XCTAssertNil(model.error)
    }

    func testCancelledSignInDiscardsLateAuthorizationDescriptor() async throws {
        let client = ClaudeAppClientStub(authenticated: false, snapshot: reading(at: now))
        await client.setAuthorizationBlocked(true)
        let model = makeModel(client)
        model.beginSignIn()
        try await waitUntil { await client.authorizationCount == 1 }
        await model.cancelSignIn()
        await client.finishAuthorization()
        try await waitUntil { await client.cancelCount >= 1 }
        XCTAssertNil(model.authorization)
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.isAuthenticating)
        let completions = await client.completeCount
        XCTAssertEqual(completions, 0)
    }

    func testCancelledCompletionDoesNotAcceptLateAccountValue() async throws {
        let client = ClaudeAppClientStub(authenticated: false, snapshot: reading(at: now))
        await client.setCompletionBlocked(true)
        var reloads = 0
        let model = makeModel(client, reloadWidgets: { reloads += 1 })
        model.beginSignIn()
        try await waitUntil { model.authorization != nil }
        model.completeSignIn(pastedCode: "synthetic-code")
        try await waitUntil { await client.completeCount == 1 }
        await model.cancelSignIn()
        await client.finishCompletion()
        try await waitUntil { await client.finishedCompletionCount == 1 }
        await Task.yield()
        XCTAssertNil(model.authorization)
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertFalse(model.isCompletingAuthorization)
        XCTAssertEqual(reloads, 1)
    }

    func testCancelledReconnectDoesNotResurrectPreviousAccountValue() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        var reloads = 0
        let model = makeModel(client, cached: cached, reloadWidgets: { reloads += 1 })
        await model.load()
        model.beginSignIn()
        try await waitUntil { model.authorization != nil }
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertEqual(reloads, 1)
        await model.cancelSignIn()
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.canRefresh)
    }

    func testReconnectRequestFailureKeepsOldValueMarkedForSignIn() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setAuthorizationFailure(.network)
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertEqual(model.error, .network)
        XCTAssertTrue(model.requiresSignIn)
        XCTAssertFalse(model.isConnected)
    }

    func testNewCredentialWithFailedFirstUsageDoesNotReusePreviousAccountValue() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setFirstAuthorizedUsageFailure(.usageUnavailable)
        model.beginSignIn()
        try await waitUntil { model.authorization != nil }
        model.completeSignIn(pastedCode: "synthetic-code")
        try await waitUntil { !model.isAuthenticating }
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.isConnected)
        XCTAssertTrue(model.canRefresh)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertEqual(model.error, .usageUnavailable)
    }

    func testDisconnectDuringFetchDiscardsLateValue() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setFetchBlocked(true)
        let refreshing = Task { await model.refresh() }
        try await waitUntil { await client.fetchCount == 1 }
        await model.disconnect()
        await client.finishFetch()
        await refreshing.value
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.isRefreshing)
        let signOuts = await client.signOutCount
        XCTAssertEqual(signOuts, 1)
    }

    func testDisconnectBlocksNewSignInUntilCredentialDeletionCompletes() async throws {
        let client = ClaudeAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: reading(at: now))
        await model.load()
        await client.setSignOutBlocked(true)
        let disconnecting = Task { await model.disconnect() }
        try await waitUntil { await client.signOutCount == 1 }
        XCTAssertTrue(model.isDisconnecting)
        XCTAssertFalse(model.canBeginSignIn)
        model.beginSignIn()
        model.completeSignIn(pastedCode: "synthetic-code")
        let counts = await client.counts()
        XCTAssertEqual(counts.authorization, 0)
        XCTAssertEqual(counts.completion, 0)
        await client.finishSignOut()
        await disconnecting.value
        XCTAssertFalse(model.isDisconnecting)
        XCTAssertTrue(model.canBeginSignIn)
    }

    func testDemoEnteringDuringCompletionDiscardsLateAccountValue() async throws {
        let demo = ClaudeAppDemoFlag()
        let client = ClaudeAppClientStub(authenticated: false, snapshot: reading(at: now))
        await client.setCompletionBlocked(true)
        var reloads = 0
        let model = makeModel(client, isDemo: { demo.value }, reloadWidgets: { reloads += 1 })
        model.beginSignIn()
        try await waitUntil { model.authorization != nil }
        model.completeSignIn(pastedCode: "synthetic-code")
        try await waitUntil { await client.completeCount == 1 }
        demo.value = true
        await model.synchronizeDemoState()
        await client.finishCompletion()
        try await waitUntil { await client.finishedCompletionCount == 1 }
        await Task.yield()
        XCTAssertNil(model.authorization)
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.isCompletingAuthorization)
        XCTAssertFalse(model.canBeginSignIn)
        XCTAssertEqual(reloads, 1)
    }

    private func reading(at date: Date, fiveHourUsed: Double = 24,
                         sevenDayUsed: Double = 56) -> ClaudeNativeUsageSnapshot {
        ClaudeNativeUsageSnapshot(
            fiveHour: ClaudeNativeUsageWindow(usedPercent: fiveHourUsed,
                                              resetAt: now.addingTimeInterval(3_600)),
            sevenDay: ClaudeNativeUsageWindow(usedPercent: sevenDayUsed,
                                              resetAt: now.addingTimeInterval(86_400)),
            updatedAt: date)
    }

    private func makeModel(
        _ client: ClaudeAppClientStub,
        cached: ClaudeNativeUsageSnapshot? = nil,
        isDemo: @escaping @Sendable () -> Bool = { false },
        reloadWidgets: @escaping @MainActor () -> Void = {}
    ) -> ClaudeNativeAppModel {
        let fixedNow = now
        return ClaudeNativeAppModel(client: client, cachedSnapshot: { cached },
                                    isDemoEnabled: isDemo, now: { fixedNow },
                                    reloadWidgets: reloadWidgets)
    }

    private func waitUntil(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Synthetic client did not reach the expected operation")
        throw ClaudeNativeClientError.busy
    }
}

private final class ClaudeAppDemoFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false
    var value: Bool {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

/// The deliberately cancellation-insensitive continuations exercise late UI results.
/// Every value is synthetic; this actor never opens a URL or accesses authentication storage.
private actor ClaudeAppClientStub: ClaudeNativeAccountServicing {
    var authenticationCount = 0
    var authorizationCount = 0
    var completeCount = 0
    var finishedCompletionCount = 0
    var fetchCount = 0
    var cancelCount = 0
    var signOutCount = 0
    private var authenticated: Bool
    private let snapshot: ClaudeNativeUsageSnapshot
    private var fetchFailure: ClaudeNativeClientError?
    private var authorizationFailure: ClaudeNativeClientError?
    private var completionFailure: ClaudeNativeClientError?
    private var firstAuthorizedUsageFailure: ClaudeNativeClientError?
    private var fetchBlocked = false
    private var authorizationBlocked = false
    private var completionBlocked = false
    private var signOutBlocked = false
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var completionContinuation: CheckedContinuation<Void, Never>?
    private var signOutContinuation: CheckedContinuation<Void, Never>?

    init(authenticated: Bool, snapshot: ClaudeNativeUsageSnapshot) {
        self.authenticated = authenticated
        self.snapshot = snapshot
    }
    func isAuthenticated() async -> Bool {
        authenticationCount += 1
        return authenticated
    }
    func beginAuthorization() async throws -> ClaudeNativeAuthorization {
        authorizationCount += 1
        authenticated = false
        if authorizationBlocked {
            await withCheckedContinuation { authorizationContinuation = $0 }
        }
        if let authorizationFailure { throw authorizationFailure }
        return ClaudeNativeAuthorization(id: UUID(),
            authorizationURL: URL(string: "https://claude.ai/oauth/authorize")!,
            expiresAt: snapshot.updatedAt.addingTimeInterval(900))
    }
    func completeAuthorization(_ descriptor: ClaudeNativeAuthorization,
                               pastedCode: String) async throws -> ClaudeNativeUsageSnapshot {
        completeCount += 1
        if completionBlocked {
            await withCheckedContinuation { completionContinuation = $0 }
        }
        finishedCompletionCount += 1
        if let failure = completionFailure {
            completionFailure = nil
            throw failure
        }
        authenticated = true
        if let firstAuthorizedUsageFailure { throw firstAuthorizedUsageFailure }
        return snapshot
    }
    func cancelAuthorization(_ descriptor: ClaudeNativeAuthorization) async throws {
        cancelCount += 1
        authenticated = false
    }
    func fetchUsage(force: Bool) async throws -> ClaudeNativeUsageSnapshot {
        fetchCount += 1
        if fetchBlocked { await withCheckedContinuation { fetchContinuation = $0 } }
        if let fetchFailure { throw fetchFailure }
        return snapshot
    }
    func signOut() async throws {
        signOutCount += 1
        if signOutBlocked { await withCheckedContinuation { signOutContinuation = $0 } }
        authenticated = false
    }
    func setFetchBlocked(_ value: Bool) { fetchBlocked = value }
    func setAuthorizationBlocked(_ value: Bool) { authorizationBlocked = value }
    func setCompletionBlocked(_ value: Bool) { completionBlocked = value }
    func setSignOutBlocked(_ value: Bool) { signOutBlocked = value }
    func setFetchFailure(_ value: ClaudeNativeClientError) { fetchFailure = value }
    func setAuthorizationFailure(_ value: ClaudeNativeClientError) { authorizationFailure = value }
    func setCompletionFailure(_ value: ClaudeNativeClientError) { completionFailure = value }
    func setFirstAuthorizedUsageFailure(_ value: ClaudeNativeClientError) { firstAuthorizedUsageFailure = value }
    func finishFetch() { fetchContinuation?.resume(); fetchContinuation = nil }
    func finishAuthorization() { authorizationContinuation?.resume(); authorizationContinuation = nil }
    func finishCompletion() { completionContinuation?.resume(); completionContinuation = nil }
    func finishSignOut() { signOutContinuation?.resume(); signOutContinuation = nil }
    func counts() -> (authentication: Int, authorization: Int, completion: Int, usage: Int) {
        (authenticationCount, authorizationCount, completeCount, fetchCount)
    }
}
