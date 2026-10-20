import XCTest
@testable import CodexTime

@MainActor
final class GrokAppModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFreshCacheLoadsWithoutRepeatingUsageRequest() async {
        let cached = reading(at: now.addingTimeInterval(-120))
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        let requests = await client.fetchCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertTrue(model.isConnected)
        XCTAssertFalse(model.requiresSignIn)
    }

    func testStaleCacheRefreshesOnceAndPublishesRealObservationTime() async {
        let cached = reading(at: now.addingTimeInterval(-601))
        let fresh = reading(at: now, used: 32)
        let client = GrokAppClientStub(authenticated: true, snapshot: fresh)
        var reloads = 0
        let model = makeModel(client, cached: cached, reloadWidgets: { reloads += 1 })
        await model.load()
        let requests = await client.fetchCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.snapshot, fresh)
        XCTAssertEqual(reloads, 1)
    }

    func testDisconnectedCacheRequiresSignInWithoutUsageRequest() async {
        let cached = reading(at: now.addingTimeInterval(-120))
        let client = GrokAppClientStub(authenticated: false, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        let requests = await client.fetchCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertFalse(model.isConnected)
        XCTAssertTrue(model.requiresSignIn)
    }

    func testDemoDoesNotReadAuthenticationOrStartLoginOrUsage() async {
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: reading(at: now), isDemo: { true })
        await model.load()
        model.beginSignIn()
        await model.refresh()
        await Task.yield()
        let counts = await client.counts()
        XCTAssertEqual(counts.authentication, 0)
        XCTAssertEqual(counts.authorization, 0)
        XCTAssertEqual(counts.usage, 0)
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.canBeginSignIn)
    }

    func testDemoEnteringDuringFetchDiscardsLateUIResult() async throws {
        let demo = GrokDemoFlag()
        let fresh = reading(at: now)
        let client = GrokAppClientStub(authenticated: true, snapshot: fresh)
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

    func testDisconnectDuringFetchDiscardsLateValue() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
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

    func testCancelledSignInDoesNotAcceptLateCompletion() async throws {
        let client = GrokAppClientStub(authenticated: false, snapshot: reading(at: now))
        await client.setAuthorizationBlocked(true)
        var reloads = 0
        let model = makeModel(client, reloadWidgets: { reloads += 1 })
        model.beginSignIn()
        try await waitUntil { await client.completeCount == 1 }
        XCTAssertNotNil(model.authorization)
        await model.cancelSignIn()
        await client.finishAuthorization()
        try await waitUntil { await client.finishedAuthorizationCount == 1 }
        await Task.yield()
        XCTAssertNil(model.authorization)
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.isAuthenticating)
        XCTAssertEqual(reloads, 1)
        XCTAssertNil(model.connectionFailureStage)
        XCTAssertNil(model.message)
        let cancellations = await client.cancelCount
        XCTAssertGreaterThanOrEqual(cancellations, 1)
    }

    func testFetchFailureKeepsLastValueAndBacksOffAutomaticRetry() async {
        let cached = reading(at: now.addingTimeInterval(-601))
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
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
        XCTAssertNil(model.connectionFailureStage)
        XCTAssertEqual(model.message, GrokClientError.network.errorDescription)
    }

    func testExpiredLoginKeepsOldValueButRequestsReconnection() async {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setFetchFailure(.loginExpired)
        await model.refresh()
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertTrue(model.requiresSignIn)
        XCTAssertFalse(model.isConnected)
        XCTAssertEqual(model.error, .loginExpired)
        XCTAssertNil(model.connectionFailureStage)
    }

    func testCancelledReconnectClearsPreviousAccountValueAndDoesNotClaimConnected() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setAuthorizationBlocked(true)
        model.beginSignIn()
        XCTAssertFalse(model.isConnected)
        try await waitUntil { await client.completeCount == 1 }
        await model.cancelSignIn()
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.canRefresh)
        await client.finishAuthorization()
        try await waitUntil { await client.finishedAuthorizationCount == 1 }
    }

    func testReconnectRequestFailureKeepsOldValueMarkedForSignIn() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setAuthorizationRequestFailure(.network)
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertEqual(model.error, .network)
        XCTAssertTrue(model.requiresSignIn)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.canRefresh)
        XCTAssertEqual(model.connectionFailureStage, .approvalResult)
        XCTAssertTrue(model.message?.hasPrefix("Grok 연결 승인을 마무리하지 못했습니다.") == true)
        XCTAssertTrue(model.message?.contains(GrokClientError.network.errorDescription!) == true)
    }

    func testNewCredentialWithFailedFirstUsageDoesNotReusePreviousAccountValue() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setFirstAuthorizedUsageFailure(.usageUnavailable)
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.isConnected)
        XCTAssertTrue(model.canRefresh)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertEqual(model.error, .usageUnavailable)
        XCTAssertEqual(model.connectionFailureStage, .firstUsage)
        XCTAssertTrue(model.message?.hasPrefix("Grok 인증은 완료됐지만 사용량을 조회하지 못했습니다.") == true)
    }

    func testDisconnectBlocksNewSignInUntilCredentialDeletionCompletes() async throws {
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: reading(at: now))
        await model.load()
        await client.setSignOutBlocked(true)
        let disconnecting = Task { await model.disconnect() }
        try await waitUntil { await client.signOutCount == 1 }
        XCTAssertTrue(model.isDisconnecting)
        XCTAssertFalse(model.canBeginSignIn)
        model.beginSignIn()
        let count = await client.authorizationCount
        XCTAssertEqual(count, 0)
        await client.finishSignOut()
        await disconnecting.value
        XCTAssertFalse(model.isDisconnecting)
        XCTAssertTrue(model.canBeginSignIn)
    }

    func testApprovalPollingFailureDoesNotClaimTheAccountWasConnected() async throws {
        let client = GrokAppClientStub(authenticated: false, snapshot: reading(at: now))
        await client.setApprovalFailure(.network)
        let model = makeModel(client)
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.connectionFailureStage, .approvalResult)
        XCTAssertTrue(model.message?.hasPrefix("Grok 연결 승인을 마무리하지 못했습니다.") == true)
        XCTAssertFalse(model.isConnected)
        XCTAssertFalse(model.canRefresh)
        XCTAssertNil(model.snapshot)
        let signOuts = await client.signOutCount
        XCTAssertEqual(signOuts, 0)
    }

    func testAuthenticatedFirstUsageFailureCanRefreshWithoutAnotherLogin() async throws {
        let fresh = reading(at: now)
        let client = GrokAppClientStub(authenticated: false, snapshot: fresh)
        await client.setFirstAuthorizedUsageFailure(.network)
        let model = makeModel(client)
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.connectionFailureStage, .firstUsage)
        XCTAssertTrue(model.isConnected)
        XCTAssertTrue(model.canRefresh)
        XCTAssertFalse(model.requiresSignIn)
        XCTAssertNil(model.snapshot)
        XCTAssertTrue(model.message?.contains(GrokClientError.network.errorDescription!) == true)
        await model.load()
        await model.refreshIfNeeded()
        let automaticFetches = await client.fetchCount
        XCTAssertEqual(automaticFetches, 0, "A foreground return must retain the first-usage backoff")
        XCTAssertEqual(model.connectionFailureStage, .firstUsage)
        await model.refresh()
        XCTAssertEqual(model.snapshot, fresh)
        XCTAssertNil(model.error)
        XCTAssertNil(model.connectionFailureStage)
        XCTAssertNil(model.message)
        let counts = await client.counts()
        let signOuts = await client.signOutCount
        XCTAssertEqual(counts.authorization, 1)
        XCTAssertEqual(counts.usage, 1)
        XCTAssertEqual(signOuts, 0, "Retrying usage must preserve the authenticated credential")
    }

    func testNewSignInClearsPreviousConnectionFailureStageBeforeSuccessfulCompletion() async throws {
        let fresh = reading(at: now)
        let client = GrokAppClientStub(authenticated: false, snapshot: fresh)
        await client.setApprovalFailure(.network)
        let model = makeModel(client)
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.connectionFailureStage, .approvalResult)
        await client.setApprovalFailure(nil)
        await client.setAuthorizationBlocked(true)
        model.beginSignIn()
        XCTAssertNil(model.connectionFailureStage)
        XCTAssertNil(model.error)
        try await waitUntil { await client.completeCount == 2 }
        await client.finishAuthorization()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.snapshot, fresh)
        XCTAssertTrue(model.isConnected)
        XCTAssertNil(model.connectionFailureStage)
        XCTAssertNil(model.message)
    }

    func testDisconnectClearsTheFirstUsageFailureStage() async throws {
        let client = GrokAppClientStub(authenticated: false, snapshot: reading(at: now))
        await client.setFirstAuthorizedUsageFailure(.network)
        let model = makeModel(client)
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.connectionFailureStage, .firstUsage)
        await model.disconnect()
        XCTAssertNil(model.connectionFailureStage)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isConnected)
        XCTAssertNil(model.snapshot)
    }

    func testEnteringDemoClearsTheFirstUsageFailureStage() async throws {
        let demo = GrokDemoFlag()
        let client = GrokAppClientStub(authenticated: false, snapshot: reading(at: now))
        await client.setFirstAuthorizedUsageFailure(.network)
        let model = makeModel(client, isDemo: { demo.value })
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.connectionFailureStage, .firstUsage)
        demo.value = true
        await model.synchronizeDemoState()
        XCTAssertNil(model.connectionFailureStage)
        XCTAssertNil(model.message)
        XCTAssertFalse(model.isConnected)
        XCTAssertNil(model.snapshot)
    }

    func testFreshSharedCacheClearsFirstUsageFailureOnReturn() async throws {
        let fresh = reading(at: now)
        let cache = GrokSnapshotBox()
        let client = GrokAppClientStub(authenticated: false, snapshot: fresh)
        await client.setFirstAuthorizedUsageFailure(.network)
        let fixedNow = now
        let model = GrokAppModel(client: client, cachedSnapshot: { cache.value },
            isDemoEnabled: { false }, now: { fixedNow }, reloadWidgets: {})
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.connectionFailureStage, .firstUsage)
        cache.value = fresh
        await model.load()
        XCTAssertEqual(model.snapshot, fresh)
        XCTAssertTrue(model.isConnected)
        XCTAssertNil(model.connectionFailureStage)
        XCTAssertNil(model.message)
        let requests = await client.fetchCount
        XCTAssertEqual(requests, 0)
    }

    func testOldSharedCacheDoesNotHideANewApprovalFailure() async throws {
        let cached = reading(at: now.addingTimeInterval(-10))
        let client = GrokAppClientStub(authenticated: true, snapshot: reading(at: now))
        let model = makeModel(client, cached: cached)
        await model.load()
        await client.setAuthorizationRequestFailure(.busy, keepsExistingAuthentication: true)
        model.beginSignIn()
        try await waitUntil { !model.isAuthenticating }
        XCTAssertEqual(model.connectionFailureStage, .approvalResult)
        await model.load()
        XCTAssertEqual(model.snapshot, cached)
        XCTAssertTrue(model.isConnected)
        XCTAssertEqual(model.connectionFailureStage, .approvalResult)
        XCTAssertEqual(model.error, .busy)
        XCTAssertTrue(model.message?.hasPrefix("Grok 연결 승인을 마무리하지 못했습니다.") == true)
    }

    private func reading(at date: Date, used: Double = 24) -> GrokUsageSnapshot {
        GrokUsageSnapshot(usedPercent: used, period: .weekly,
                          resetAt: now.addingTimeInterval(86_400), updatedAt: date)
    }

    private func makeModel(
        _ client: GrokAppClientStub,
        cached: GrokUsageSnapshot? = nil,
        isDemo: @escaping @Sendable () -> Bool = { false },
        reloadWidgets: @escaping @MainActor () -> Void = {}
    ) -> GrokAppModel {
        let fixedNow = now
        return GrokAppModel(client: client, cachedSnapshot: { cached },
                            isDemoEnabled: isDemo, now: { fixedNow }, reloadWidgets: reloadWidgets)
    }

    private func waitUntil(_ predicate: @escaping () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Synthetic client did not reach the expected operation")
        throw GrokClientError.busy
    }
}

private final class GrokDemoFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false
    var value: Bool {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class GrokSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: GrokUsageSnapshot?
    var value: GrokUsageSnapshot? {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private actor GrokAppClientStub: GrokAccountServicing {
    var authenticationCount = 0
    var authorizationCount = 0
    var completeCount = 0
    var finishedAuthorizationCount = 0
    var fetchCount = 0
    var cancelCount = 0
    var signOutCount = 0
    private var authenticated: Bool
    private let snapshot: GrokUsageSnapshot
    private var fetchFailure: GrokClientError?
    private var authorizationRequestFailure: GrokClientError?
    private var firstAuthorizedUsageFailure: GrokClientError?
    private var approvalFailure: GrokClientError?
    private var preservesAuthenticationOnAuthorizationFailure = false
    private var fetchBlocked = false
    private var authorizationBlocked = false
    private var signOutBlocked = false
    private var fetchContinuation: CheckedContinuation<Void, Never>?
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var signOutContinuation: CheckedContinuation<Void, Never>?

    init(authenticated: Bool, snapshot: GrokUsageSnapshot) {
        self.authenticated = authenticated
        self.snapshot = snapshot
    }
    func isAuthenticated() async -> Bool {
        authenticationCount += 1
        return authenticated
    }
    func requestDeviceAuthorization() async throws -> GrokDeviceAuthorization {
        authorizationCount += 1
        if let authorizationRequestFailure {
            if !preservesAuthenticationOnAuthorizationFailure { authenticated = false }
            throw authorizationRequestFailure
        }
        authenticated = false
        return GrokDeviceAuthorization(deviceCode: "synthetic-device-code", userCode: "TEST-CODE",
                                       verificationURL: URL(string: "https://auth.x.ai/activate")!,
                                       expiresAt: snapshot.updatedAt.addingTimeInterval(900), interval: 5)
    }
    func completeDeviceAuthorization(_ authorization: GrokDeviceAuthorization) async throws -> GrokUsageSnapshot {
        completeCount += 1
        if authorizationBlocked {
            await withCheckedContinuation { authorizationContinuation = $0 }
        }
        finishedAuthorizationCount += 1
        if let approvalFailure { throw approvalFailure }
        authenticated = true
        if let firstAuthorizedUsageFailure { throw firstAuthorizedUsageFailure }
        return snapshot
    }
    func cancelDeviceAuthorization(_ authorization: GrokDeviceAuthorization) async throws {
        cancelCount += 1
    }
    func fetchUsage(force: Bool) async throws -> GrokUsageSnapshot {
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
    func setFetchFailure(_ value: GrokClientError) { fetchFailure = value }
    func setAuthorizationRequestFailure(_ value: GrokClientError, keepsExistingAuthentication: Bool = false) {
        authorizationRequestFailure = value
        preservesAuthenticationOnAuthorizationFailure = keepsExistingAuthentication
    }
    func setSignOutBlocked(_ value: Bool) { signOutBlocked = value }
    func setFirstAuthorizedUsageFailure(_ value: GrokClientError) { firstAuthorizedUsageFailure = value }
    func setApprovalFailure(_ value: GrokClientError?) { approvalFailure = value }
    func finishSignOut() {
        signOutContinuation?.resume()
        signOutContinuation = nil
    }
    func finishFetch() {
        fetchContinuation?.resume()
        fetchContinuation = nil
    }
    func finishAuthorization() {
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }
    func counts() -> (authentication: Int, authorization: Int, usage: Int) {
        (authenticationCount, authorizationCount, fetchCount)
    }
}
