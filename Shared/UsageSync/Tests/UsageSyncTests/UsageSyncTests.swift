import XCTest
@testable import UsageSync

@MainActor final class FakeTransport: UsageSyncTransport {
    var scope: String? = "scope-a"
    var values: [SyncedUsage] = []
    var fetchError: Error?
    var saveError: Error?
    var deleteError: Error?
    var scopeError: Error?
    var scopeCalls = 0
    var saved: [[SyncedUsage]] = []
    var deletedScopes: [String] = []
    var holdSave = false
    var holdFetch = false
    var saveStarted = false
    var fetchStarted = false
    var saveContinuation: CheckedContinuation<Void, Never>?
    var fetchContinuation: CheckedContinuation<Void, Never>?

    func accountScope() async throws -> String? {
        scopeCalls += 1
        if let scopeError { throw scopeError }
        return scope
    }
    func fetch(expectedScope: String) async throws -> [SyncedUsage] {
        guard scope == expectedScope else { throw UsageSyncError.accountChanged }
        fetchStarted = true
        if holdFetch { await withCheckedContinuation { fetchContinuation = $0 } }
        if let fetchError { throw fetchError }
        guard scope == expectedScope else { throw UsageSyncError.accountChanged }
        return values
    }
    func save(_ readings: [SyncedUsage], expectedScope: String) async throws {
        guard scope == expectedScope else { throw UsageSyncError.accountChanged }
        saveStarted = true
        if holdSave { await withCheckedContinuation { saveContinuation = $0 } }
        if let saveError { throw saveError }
        guard scope == expectedScope else { throw UsageSyncError.accountChanged }
        // Simulate a server commit that wins the race against cancellation.
        saved.append(readings)
        values = readings
    }
    func deleteAll(expectedScope: String) async throws {
        guard scope == expectedScope else { throw UsageSyncError.accountChanged }
        if let deleteError { throw deleteError }
        deletedScopes.append(expectedScope)
        values = []
    }
}

@MainActor final class UsageSyncTests: XCTestCase {
    private var preferences: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        suite = "UsageSyncTests." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        preferences.removePersistentDomain(forName: suite)
    }
    override func tearDown() async throws {
        preferences.removePersistentDomain(forName: suite)
        preferences = nil
    }

    private func ready(_ percent: Int = 61, observed: Date = Date()) -> SyncedUsage {
        SyncedUsage(provider: .grok, remainingPercent: percent, resetAt: observed.addingTimeInterval(3_600), observedAt: observed, status: .ready)
    }

    func testConfigurationAcceptsOnlyTrueOrExactYESWithExpectedContainer() {
        let container = "iCloud.com.sundaynighttt.codextime"
        XCTAssertTrue(CloudSyncConfiguration.isEnabled(container: container, flag: true))
        XCTAssertTrue(CloudSyncConfiguration.isEnabled(container: container, flag: "YES"))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: container, flag: false))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: container, flag: "NO"))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: container, flag: "yes"))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: container, flag: "true"))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: container, flag: " YES "))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: container, flag: "$(CODEXTIME_CLOUD_SYNC_CONFIGURED)"))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: container, flag: 1))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: container, flag: nil))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: "iCloud.other", flag: true))
        XCTAssertFalse(CloudSyncConfiguration.isEnabled(container: nil, flag: "YES"))
    }

    func testOnlyAllowlistedFieldsAreEncodedAndClaudeIsBlocked() throws {
        let value = SyncedUsage(provider: .claude, remainingPercent: 88, resetAt: Date(), observedAt: Date(), status: .ready)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["provider", "status"])
        XCTAssertEqual(object["status"] as? String, "blocked")
        XCTAssertNil(value.remainingPercent)
        XCTAssertNil(value.resetAt)
        XCTAssertNil(value.observedAt)
        let grokObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ready())) as? [String: Any])
        XCTAssertEqual(Set(grokObject.keys), ["provider", "remainingPercent", "resetAt", "observedAt", "status"])
    }

    func testUnknownPayloadFieldRejected() throws {
        let data = Data(#"{"provider":"grok","status":"ready","remainingPercent":42,"token":"never-allowed"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SyncedUsage.self, from: data))
    }

    func testInvalidPercentAndFutureObservationNeverBecomeReady() {
        XCTAssertEqual(ready(-1).status, .failed)
        XCTAssertEqual(ready(101).status, .failed)
        XCTAssertEqual(ready(observed: Date().addingTimeInterval(301)).status, .failed)
        let invalidDate = SyncedUsage(provider: .grok, remainingPercent: 50, resetAt: nil, observedAt: Date(timeIntervalSince1970: .infinity), status: .ready)
        XCTAssertEqual(invalidDate.status, .failed)
        let paused = SyncedUsage(provider: .grok, remainingPercent: 50, resetAt: Date(), observedAt: Date(), status: .paused)
        XCTAssertNil(paused.remainingPercent)
        XCTAssertNil(paused.observedAt)
    }

    func testStalenessUsesProviderObservation() {
        let now = Date()
        XCTAssertFalse(ready(observed: now.addingTimeInterval(-1_199)).isStale(at: now))
        XCTAssertTrue(ready(observed: now.addingTimeInterval(-1_201)).isStale(at: now))
        XCTAssertTrue(SyncedUsage(provider: .claude, remainingPercent: nil, resetAt: nil, observedAt: nil, status: .blocked).isStale())
    }

    func testInitDoesNotCallCloudKitAndMissingConfigurationFailsClosed() async {
        let transport = FakeTransport()
        let injected = UsageCloudSync(preferences: preferences, transport: transport)
        XCTAssertFalse(injected.isEnabled)
        XCTAssertEqual(transport.scopeCalls, 0)
        let engine = UsageCloudSync(preferences: preferences)
        await engine.enable()
        XCTAssertEqual(engine.state, .notConfigured)
        XCTAssertFalse(engine.isEnabled)
    }

    func testVerifiedScopeRequiredBeforeRestore() async {
        preferences.set(true, forKey: UsageSyncCache.enabledKey)
        UsageSyncCache.store([.grok: ready()], scope: "scope-a", preferences: preferences)
        let transport = FakeTransport()
        transport.fetchError = UsageSyncError.network
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        XCTAssertTrue(engine.readings.isEmpty)
        await engine.refresh()
        XCTAssertEqual(engine.readings[.grok]?.remainingPercent, 61)
        XCTAssertTrue(engine.isEnabled)
        XCTAssertEqual(engine.state, .networkError)
    }

    func testAccountSwitchClearsCacheAndOptIn() async {
        let transport = FakeTransport()
        transport.values = [ready()]
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        XCTAssertEqual(engine.readings[.grok]?.remainingPercent, 61)
        transport.scope = "scope-b"
        await engine.refresh()
        XCTAssertFalse(engine.isEnabled)
        XCTAssertTrue(engine.readings.isEmpty)
        XCTAssertFalse(UsageSyncCache.isRequestedEnabled(preferences: preferences))
        XCTAssertNil(preferences.data(forKey: UsageSyncCache.cacheKey))
        XCTAssertEqual(engine.state, .signedOut)
        // Another refresh cannot automatically opt in the new account.
        await engine.refresh()
        XCTAssertTrue(engine.readings.isEmpty)
        XCTAssertEqual(transport.saved.count, 0)
    }

    func testSignedOutClearsCacheAndNeverRestoresIt() async {
        let transport = FakeTransport()
        transport.values = [ready()]
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        transport.scope = nil
        await engine.refresh()
        XCTAssertFalse(engine.isEnabled)
        XCTAssertTrue(engine.readings.isEmpty)
        XCTAssertNil(preferences.data(forKey: UsageSyncCache.cacheKey))
        transport.scope = "scope-a"
        await engine.refresh()
        XCTAssertFalse(engine.isEnabled)
        XCTAssertTrue(engine.readings.isEmpty)
    }

    func testNetworkFailureKeepsLastObservationAndSafeError() async {
        let transport = FakeTransport()
        transport.values = [ready()]
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        let original = engine.readings
        transport.fetchError = NSError(domain: "secret-provider-response", code: 123, userInfo: [NSLocalizedDescriptionKey: "credential"])
        await engine.refresh()
        XCTAssertEqual(engine.readings, original)
        XCTAssertEqual(engine.state, .networkError)
        XCTAssertFalse(engine.state.message.contains("credential"))
        XCTAssertFalse(engine.state.message.contains("secret-provider-response"))
    }

    func testDisableDeletesOnlyKnownScopeAndClearsLocalImmediately() async {
        let transport = FakeTransport()
        transport.values = [ready()]
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        await engine.disableAndDelete()
        XCTAssertFalse(engine.isEnabled)
        XCTAssertTrue(engine.readings.isEmpty)
        XCTAssertEqual(transport.deletedScopes, ["scope-a"])
        XCTAssertNil(preferences.data(forKey: UsageSyncCache.cacheKey))
        XCTAssertEqual(engine.state, .disabled)
    }

    func testFailedDeleteRemainsPendingAndRetriesWithoutReenabling() async {
        let transport = FakeTransport()
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        transport.deleteError = UsageSyncError.network
        await engine.disableAndDelete()
        XCTAssertEqual(engine.state, .deletionPending)
        XCTAssertFalse(engine.isEnabled)
        XCTAssertEqual(preferences.string(forKey: UsageSyncCache.deletionKey), "scope-a")
        transport.deleteError = nil
        await engine.retryPendingDeletion()
        XCTAssertEqual(engine.state, .disabled)
        XCTAssertFalse(engine.isEnabled)
        XCTAssertNil(preferences.string(forKey: UsageSyncCache.deletionKey))
        XCTAssertEqual(transport.deletedScopes, ["scope-a"])
    }

    func testPendingDeleteCannotTargetAnotherAccount() async {
        let transport = FakeTransport()
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        transport.scope = "scope-b"
        await engine.disableAndDelete()
        XCTAssertEqual(engine.state, .deletionPending)
        XCTAssertTrue(transport.deletedScopes.isEmpty)
        XCTAssertFalse(engine.isEnabled)
        await engine.enable()
        XCTAssertFalse(engine.isEnabled)
        XCTAssertTrue(transport.deletedScopes.isEmpty)
    }

    func testLateFetchCannotRepopulateDisabledCache() async {
        let transport = FakeTransport()
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        transport.values = [ready()]
        transport.holdFetch = true
        let refresh = Task { await engine.refresh() }
        while transport.fetchContinuation == nil { await Task.yield() }
        engine.stopReceiving()
        transport.fetchContinuation?.resume()
        await refresh.value
        XCTAssertTrue(engine.readings.isEmpty)
        XCTAssertNil(preferences.data(forKey: UsageSyncCache.cacheKey))
        XCTAssertFalse(engine.isEnabled)
    }

    func testDeleteWaitsForLateSaveThenWins() async {
        let transport = FakeTransport()
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        transport.holdSave = true
        let publish = Task { await engine.publish([ready()]) }
        while transport.saveContinuation == nil { await Task.yield() }
        let disable = Task { await engine.disableAndDelete() }
        while engine.isEnabled { await Task.yield() }
        XCTAssertTrue(engine.readings.isEmpty)
        transport.saveContinuation?.resume()
        await publish.value
        await disable.value
        XCTAssertEqual(transport.saved.count, 1)
        XCTAssertEqual(transport.deletedScopes, ["scope-a"])
        XCTAssertTrue(transport.values.isEmpty)
        XCTAssertTrue(engine.readings.isEmpty)
        XCTAssertEqual(engine.state, .disabled)
        XCTAssertNil(preferences.data(forKey: UsageSyncCache.cacheKey))
    }


    func testExplicitDeleteAfterLocalStopTargetsVerifiedCurrentAccount() async {
        let transport = FakeTransport()
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        engine.stopReceiving()
        await engine.disableAndDelete()
        XCTAssertEqual(transport.deletedScopes, ["scope-a"])
        XCTAssertEqual(engine.state, .disabled)
        XCTAssertFalse(engine.isEnabled)
    }

    func testExplicitDeleteWhileSignedOutDoesNotClaimDeletion() async {
        let transport = FakeTransport()
        transport.scope = nil
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.disableAndDelete()
        XCTAssertEqual(engine.state, .signedOut)
        XCTAssertTrue(transport.deletedScopes.isEmpty)
    }


    func testAnotherEngineDisablePreventsLateWidgetCacheRestore() async {
        let widgetTransport = FakeTransport()
        let appTransport = FakeTransport()
        let app = UsageCloudSync(preferences: preferences, transport: appTransport)
        await app.enable()
        let widget = UsageCloudSync(preferences: preferences, transport: widgetTransport)
        widgetTransport.values = [ready()]
        widgetTransport.holdFetch = true
        let refresh = Task { await widget.refresh() }
        while widgetTransport.fetchContinuation == nil { await Task.yield() }
        app.stopReceiving()
        widgetTransport.fetchContinuation?.resume()
        await refresh.value
        XCTAssertFalse(widget.isEnabled)
        XCTAssertTrue(widget.readings.isEmpty)
        XCTAssertNil(preferences.data(forKey: UsageSyncCache.cacheKey))
        XCTAssertFalse(UsageSyncCache.isRequestedEnabled(preferences: preferences))
    }

    func testOldWidgetSessionCannotReplaceNewOptInCache() async {
        let appTransport = FakeTransport()
        let widgetTransport = FakeTransport()
        let app = UsageCloudSync(preferences: preferences, transport: appTransport)
        await app.enable()
        let widget = UsageCloudSync(preferences: preferences, transport: widgetTransport)
        widgetTransport.values = [ready(12)]
        widgetTransport.holdFetch = true
        let refresh = Task { await widget.refresh() }
        while widgetTransport.fetchContinuation == nil { await Task.yield() }
        app.stopReceiving()
        appTransport.values = [ready(76)]
        await app.enable()
        widgetTransport.fetchContinuation?.resume()
        await refresh.value
        XCTAssertFalse(widget.isEnabled)
        XCTAssertTrue(widget.readings.isEmpty)
        XCTAssertTrue(app.isEnabled)
        XCTAssertTrue(UsageSyncCache.isRequestedEnabled(preferences: preferences))
        XCTAssertEqual(UsageSyncCache.readings(preferences: preferences, verifiedScope: "scope-a")[.grok]?.remainingPercent, 76)
    }

    func testStopReceivingDoesNotDeleteRemoteRecords() async {
        let transport = FakeTransport()
        let engine = UsageCloudSync(preferences: preferences, transport: transport)
        await engine.enable()
        engine.stopReceiving()
        XCTAssertFalse(engine.isEnabled)
        XCTAssertTrue(engine.readings.isEmpty)
        XCTAssertTrue(transport.deletedScopes.isEmpty)
    }
}
