import XCTest
import Darwin
@testable import CodexTime

/// Every credential and response in this file is synthetic. No live Keychain or network is used.
final class GrokAccountClientTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 2_000_000_000)

    func testBillingPreservesZeroAndDistinguishesWeeklyMonthlyAndUnknown() throws {
        for (wirePeriod, expected) in [
            ("USAGE_PERIOD_TYPE_WEEKLY", GrokUsagePeriod.weekly),
            ("USAGE_PERIOD_TYPE_MONTHLY", .monthly),
            ("UNRECOGNIZED_PERIOD", .unknown)
        ] {
            let snapshot = try GrokAccountClient.parseUsage(
                billingData(percent: 0, period: wirePeriod), now: instant)
            XCTAssertEqual(snapshot.usedPercent, 0)
            XCTAssertEqual(snapshot.remainingPercent, 100)
            XCTAssertEqual(snapshot.period, expected)
            XCTAssertEqual(snapshot.updatedAt, instant)
            XCTAssertEqual(snapshot.resetAt, instant.addingTimeInterval(3_600))
        }
    }

    func testBillingNeverInventsQuotaFromMissingPercentOrMoney() throws {
        for config: [String: Any] in [
            [:], ["creditUsagePercent": NSNull()],
            ["onDemandUsed": ["val": 20], "onDemandCap": ["val": 100]],
            ["prepaidBalance": ["val": 900], "monthlyLimit": ["val": 1_000], "used": ["val": 5]]
        ] {
            let data = try JSONSerialization.data(withJSONObject: ["config": config])
            XCTAssertThrowsError(try GrokAccountClient.parseUsage(data, now: instant)) {
                XCTAssertEqual($0 as? GrokClientError, .usageUnavailable)
            }
        }
    }

    func testBillingRejectsBooleanStringOutOfRangeAndInvalidDates() throws {
        for value: Any in [true, "42", -0.1, 100.1] {
            XCTAssertThrowsError(try GrokAccountClient.parseUsage(billingData(percent: value), now: instant))
        }
        for period: [String: Any] in [
            ["type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "invalid", "end": iso(instant.addingTimeInterval(10))],
            ["type": "USAGE_PERIOD_TYPE_WEEKLY", "start": iso(instant.addingTimeInterval(10)), "end": iso(instant.addingTimeInterval(20))],
            ["type": "USAGE_PERIOD_TYPE_WEEKLY", "start": iso(instant.addingTimeInterval(-10)), "end": iso(instant.addingTimeInterval(-1))],
            ["type": "USAGE_PERIOD_TYPE_WEEKLY", "start": iso(instant.addingTimeInterval(-10)), "end": "invalid"]
        ] {
            let data = try JSONSerialization.data(withJSONObject: [
                "config": ["creditUsagePercent": 42, "currentPeriod": period]
            ])
            XCTAssertThrowsError(try GrokAccountClient.parseUsage(data, now: instant))
        }
    }

    func testSnapshotStalenessDoesNotRelabelAnOldObservationAsFresh() {
        let snapshot = GrokUsageSnapshot(usedPercent: 42, period: .weekly,
                                        resetAt: instant.addingTimeInterval(5_000), updatedAt: instant)
        XCTAssertFalse(snapshot.isStale(at: instant.addingTimeInterval(1_199)))
        XCTAssertTrue(snapshot.isStale(at: instant.addingTimeInterval(1_200)))
        XCTAssertTrue(snapshot.isStale(at: instant.addingTimeInterval(5_000)))
        XCTAssertFalse(snapshot.isValid(at: instant.addingTimeInterval(-1)))
        XCTAssertEqual(snapshot.updatedAt, instant)
    }

    func testDemoStopsBeforeTokenStoreLockAndNetworkAccess() async {
        let stores = GrokTestStores()
        let transport = GrokScriptTransport([])
        let mutex = GrokTestMutex()
        let client = makeClient(stores: stores, transport: transport, mutex: mutex, isDemo: { true })
        let authenticated = await client.isAuthenticated()
        XCTAssertFalse(authenticated)
        do {
            _ = try await client.requestDeviceAuthorization()
            XCTFail("Demo must not start authorization")
        } catch {
            XCTAssertEqual(error as? GrokClientError, .demoMode)
        }
        do {
            _ = try await client.fetchUsage(force: true)
            XCTFail("Demo must not query usage")
        } catch {
            XCTAssertEqual(error as? GrokClientError, .demoMode)
        }
        XCTAssertEqual(stores.counts, GrokTestStoreCounts())
        XCTAssertEqual(mutex.acquisitions, 0)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testDeviceFlowHonorsPendingAndSlowDownAndWritesOnlyAfterApproval() async throws {
        let clock = GrokTestClock(instant)
        let stores = GrokTestStores()
        let transport = GrokScriptTransport([
            .response(200, deviceData()),
            .response(400, json(["error": "authorization_pending"])),
            .response(400, json(["error": "slow_down"])),
            .response(200, tokenData()),
            .response(200, billingData(percent: 42))
        ])
        let client = makeClient(stores: stores, transport: transport, clock: clock)
        let authorization = try await client.requestDeviceAuthorization()
        XCTAssertNil(stores.auth)
        XCTAssertEqual(authorization.verificationURL, URL(string: "https://auth.x.ai/activate"))
        let snapshot = try await client.completeDeviceAuthorization(authorization)
        XCTAssertEqual(clock.delays, [2, 2, 7])
        XCTAssertEqual(snapshot.usedPercent, 42)
        XCTAssertEqual(stores.auth?.connectionID, authorization.connectionID)
        XCTAssertEqual(stores.state?.snapshot, snapshot)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map(\.url), [
            GrokConfiguration.deviceURL, GrokConfiguration.tokenURL,
            GrokConfiguration.tokenURL, GrokConfiguration.tokenURL, GrokConfiguration.billingURL
        ])
        XCTAssertTrue(requests.prefix(4).allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertEqual(requests.last?.httpMethod, "GET")
        XCTAssertEqual(requests.last?.value(forHTTPHeaderField: "X-XAI-Token-Auth"), "xai-grok-cli")
        var form = URLComponents()
        form.percentEncodedQuery = String(data: requests[0].httpBody ?? Data(), encoding: .utf8)
        let fields = Dictionary(uniqueKeysWithValues: (form.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(fields["scope"], "openid offline_access grok-cli:access")
        XCTAssertEqual(fields["client_id"], GrokConfiguration.clientID)
        XCTAssertEqual(fields["referrer"], "codextime")
    }

    func testDeviceDenialAndExpiryNeverSaveTokensOrFetchBilling() async throws {
        for errorCode in ["access_denied", "expired_token"] {
            let stores = GrokTestStores()
            let transport = GrokScriptTransport([
                .response(200, deviceData()), .response(400, json(["error": errorCode]))
            ])
            let client = makeClient(stores: stores, transport: transport, clock: GrokTestClock(instant))
            let authorization = try await client.requestDeviceAuthorization()
            do {
                _ = try await client.completeDeviceAuthorization(authorization)
                XCTFail("Rejected authorization must fail")
            } catch {
                XCTAssertEqual(error as? GrokClientError,
                               errorCode == "access_denied" ? .authorizationDenied : .loginExpired)
            }
            XCTAssertNil(stores.auth)
            XCTAssertNil(stores.state?.snapshot)
            let requests = await transport.recordedRequests()
            XCTAssertEqual(requests.count, 2)
        }
    }

    func testDevicePollingStopsAtDeadlineWithoutAnotherTokenRequest() async throws {
        let stores = GrokTestStores()
        let clock = GrokTestClock(instant)
        let transport = GrokScriptTransport([
            .response(200, deviceData(expiresIn: 3, interval: 2)),
            .response(400, json(["error": "authorization_pending"]))
        ])
        let client = makeClient(stores: stores, transport: transport, clock: clock)
        let authorization = try await client.requestDeviceAuthorization()
        do {
            _ = try await client.completeDeviceAuthorization(authorization)
            XCTFail("Deadline must expire")
        } catch { XCTAssertEqual(error as? GrokClientError, .loginExpired) }
        XCTAssertEqual(clock.delays, [2, 1])
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(stores.auth)
    }

    func testCachedFreshUsageAvoidsNetworkAndExpiredCacheDoesNot() async throws {
        let cached = GrokUsageSnapshot(usedPercent: 0, period: .weekly,
                                      resetAt: instant.addingTimeInterval(3_600),
                                      updatedAt: instant.addingTimeInterval(-599))
        let stores = authenticatedStores(snapshot: cached)
        let transport = GrokScriptTransport([.response(200, billingData(percent: 23))])
        let client = makeClient(stores: stores, transport: transport)
        let first = try await client.fetchUsage()
        XCTAssertEqual(first, cached)
        var requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
        let forced = try await client.fetchUsage(force: true)
        XCTAssertEqual(forced.usedPercent, 23)
        requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testA401RefreshesOnceAndRetriesBillingWithTheNewAccessToken() async throws {
        let stores = authenticatedStores()
        let transport = GrokScriptTransport([
            .response(401, json(["error": "ignored"])),
            .response(200, tokenData(access: "fixture-access-new", refresh: "fixture-refresh-new")),
            .response(200, billingData(percent: 18))
        ])
        let client = makeClient(stores: stores, transport: transport)
        let result = try await client.fetchUsage(force: true)
        XCTAssertEqual(result.usedPercent, 18)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map(\.url),
                       [GrokConfiguration.billingURL, GrokConfiguration.tokenURL, GrokConfiguration.billingURL])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-old")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-new")
        XCTAssertEqual(stores.auth?.refreshToken, "fixture-refresh-new")
        XCTAssertFalse(stores.auth?.refreshUncertain ?? true)
    }

    func testASecond401DoesNotRefreshAgainWithinTheSameFetch() async throws {
        let stores = authenticatedStores()
        let transport = GrokScriptTransport([
            .response(401, json(["error": "ignored"])),
            .response(200, tokenData()),
            .response(401, json(["error": "ignored again"]))
        ])
        let client = makeClient(stores: stores, transport: transport)
        do {
            _ = try await client.fetchUsage(force: true)
            XCTFail("Repeated authentication rejection must stop")
        } catch { XCTAssertEqual(error as? GrokClientError, .loginExpired) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.filter { $0.url == GrokConfiguration.tokenURL }.count, 1)
        XCTAssertEqual(requests.count, 3)
    }

    func testAmbiguousRefreshIsPersistedAndNeverAutomaticallyRetried() async throws {
        let cached = GrokUsageSnapshot(usedPercent: 33, period: .weekly,
                                      resetAt: instant.addingTimeInterval(10_000),
                                      updatedAt: instant.addingTimeInterval(-2_000))
        let stores = authenticatedStores(snapshot: cached, expiresIn: -1)
        let transport = GrokScriptTransport([.failure(.network)])
        let mutex = GrokTestMutex()
        let firstClient = makeClient(stores: stores, transport: transport, mutex: mutex)
        do {
            _ = try await firstClient.fetchUsage(force: true)
            XCTFail("Lost token rotation response must fail")
        } catch { XCTAssertEqual(error as? GrokClientError, .refreshUncertain) }
        XCTAssertTrue(stores.auth?.refreshUncertain ?? false)
        XCTAssertEqual(stores.state?.snapshot, cached)
        let secondClient = makeClient(stores: stores, transport: transport, mutex: mutex)
        do {
            _ = try await secondClient.fetchUsage(force: true)
            XCTFail("Another app/widget client must not reuse uncertain refresh credentials")
        } catch { XCTAssertEqual(error as? GrokClientError, .refreshUncertain) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testDemoEnteredDuringAnAwaitCannotPublishNewUsage() async throws {
        let previous = GrokUsageSnapshot(usedPercent: 19, period: .weekly,
                                        resetAt: instant.addingTimeInterval(3_600),
                                        updatedAt: instant.addingTimeInterval(-2_000))
        let stores = authenticatedStores(snapshot: previous)
        let demo = GrokTestFlag()
        let gate = GrokResponseGate()
        let transport = GrokScriptTransport([.gated(gate)])
        let client = makeClient(stores: stores, transport: transport, isDemo: { demo.value })
        let pending = Task { try await client.fetchUsage(force: true) }
        await gate.waitUntilRequested()
        demo.value = true
        await gate.resolve(.init(statusCode: 200, data: billingData(percent: 88)))
        do {
            _ = try await pending.value
            XCTFail("Demo entry must discard an in-flight real response")
        } catch { XCTAssertEqual(error as? GrokClientError, .demoMode) }
        XCTAssertEqual(stores.state?.snapshot, previous)
    }

    func testCancellingAuthorizationRetiresLateSuccessfulApproval() async throws {
        let stores = GrokTestStores()
        let gate = GrokResponseGate()
        let transport = GrokScriptTransport([.response(200, deviceData()), .gated(gate)])
        let client = makeClient(stores: stores, transport: transport, clock: GrokTestClock(instant))
        let authorization = try await client.requestDeviceAuthorization()
        let completion = Task { try await client.completeDeviceAuthorization(authorization) }
        await gate.waitUntilRequested()
        try await client.cancelDeviceAuthorization(authorization)
        await gate.resolve(.init(statusCode: 200, data: tokenData()))
        do {
            _ = try await completion.value
            XCTFail("Approval from a retired authorization must not be stored")
        } catch { XCTAssertEqual(error as? GrokClientError, .connectionChanged) }
        XCTAssertNil(stores.auth)
        XCTAssertNil(stores.state?.snapshot)
        XCTAssertNotEqual(stores.state?.connectionID, authorization.connectionID)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
    }

    func testOldAuthorizationCannotDisconnectANewerLoginAttempt() async throws {
        let stores = GrokTestStores()
        let transport = GrokScriptTransport([
            .response(200, deviceData()), .response(200, deviceData())
        ])
        let client = makeClient(stores: stores, transport: transport)
        let old = try await client.requestDeviceAuthorization()
        let newer = try await client.requestDeviceAuthorization()
        try await client.cancelDeviceAuthorization(old)
        XCTAssertEqual(stores.state?.connectionID, newer.connectionID)
        XCTAssertNotEqual(old.connectionID, newer.connectionID)
    }

    func testSignOutWaitsForOwnedFetchAndCannotLeaveALateSnapshot() async throws {
        let stores = authenticatedStores()
        let mutex = GrokTestMutex()
        let gate = GrokResponseGate()
        let transport = GrokScriptTransport([.gated(gate)])
        let client = makeClient(stores: stores, transport: transport, mutex: mutex)
        let fetch = Task { try await client.fetchUsage(force: true) }
        await gate.waitUntilRequested()
        let signOut = Task { try await client.signOut() }
        await mutex.waitUntilContended()
        await gate.resolve(.init(statusCode: 200, data: billingData(percent: 88)))
        _ = try? await fetch.value
        try await signOut.value
        XCTAssertNil(stores.auth)
        XCTAssertNil(stores.state?.snapshot)
        let authenticated = await client.isAuthenticated()
        XCTAssertFalse(authenticated)
    }

    func testTwoClientsWithSharedMutexRotateOnlyOnceAndShareFreshCache() async throws {
        let stores = authenticatedStores(expiresIn: -1)
        let mutex = GrokTestMutex()
        let gate = GrokResponseGate()
        let transport = GrokScriptTransport([
            .gated(gate), .response(200, billingData(percent: 27))
        ])
        let first = makeClient(stores: stores, transport: transport, mutex: mutex)
        let second = makeClient(stores: stores, transport: transport, mutex: mutex)
        let firstFetch = Task { try await first.fetchUsage() }
        await gate.waitUntilRequested()
        let secondFetch = Task { try await second.fetchUsage() }
        await mutex.waitUntilContended()
        await gate.resolve(.init(statusCode: 200, data: tokenData()))
        let a = try await firstFetch.value
        let b = try await secondFetch.value
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.usedPercent, 27)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.filter { $0.url == GrokConfiguration.tokenURL }.count, 1)
    }

    func testUsageFailureKeepsPreviousValueAndObservationTime() async throws {
        let previous = GrokUsageSnapshot(usedPercent: 40, period: .weekly,
                                        resetAt: instant.addingTimeInterval(3_600),
                                        updatedAt: instant.addingTimeInterval(-2_000))
        let stores = authenticatedStores(snapshot: previous)
        let transport = GrokScriptTransport([.response(200, json(["config": [:]]))])
        let client = makeClient(stores: stores, transport: transport)
        do {
            _ = try await client.fetchUsage(force: true)
            XCTFail("Missing quota must not be treated as zero")
        } catch { XCTAssertEqual(error as? GrokClientError, .usageUnavailable) }
        XCTAssertEqual(stores.state?.snapshot, previous)
    }

    func testSingleClientJoinsConcurrentUsageWithoutAnotherBillingRequest() async throws {
        let stores = authenticatedStores()
        let gate = GrokResponseGate()
        let demoProbe = GrokTestReadSignal()
        let transport = GrokScriptTransport([.gated(gate)])
        let client = makeClient(stores: stores, transport: transport, isDemo: { demoProbe.read() })
        let first = Task { try await client.fetchUsage(force: true) }
        await gate.waitUntilRequested()
        let baseline = demoProbe.readCount
        let second = Task { try await client.fetchUsage(force: true) }
        await demoProbe.waitForRead(after: baseline)
        await gate.resolve(.init(statusCode: 200, data: billingData(percent: 67)))
        let a = try await first.value
        let b = try await second.value
        XCTAssertEqual(a, b)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testFetchDeadlineDrainsCancellationAndPreservesUncertainRefreshMarker() async throws {
        let stores = authenticatedStores(expiresIn: -1)
        let mutex = GrokTestMutex()
        let transport = GrokScriptTransport([.cancellableDelay(5)])
        let client = makeClient(stores: stores, transport: transport, mutex: mutex, fetchTimeout: 0.02)
        do {
            _ = try await client.fetchUsage(force: true)
            XCTFail("The owned fetch must have a deadline")
        } catch { XCTAssertEqual(error as? GrokClientError, .network) }
        XCTAssertTrue(stores.auth?.refreshUncertain ?? false)
        XCTAssertFalse(mutex.isHeld)
        do {
            _ = try await client.fetchUsage(force: true)
            XCTFail("Timed-out rotation must not be repeated")
        } catch { XCTAssertEqual(error as? GrokClientError, .refreshUncertain) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        try await client.signOut()
        XCTAssertNil(stores.auth)
        XCTAssertFalse(mutex.isHeld)
    }

    func testRealFileLockBlocksIndependentDescriptorsAndRecoversAfterCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("grok-lock-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let mutex = GrokAuthLock(directoryURL: directory)
        let first = try await mutex.acquire()
        let descriptor = Darwin.open(directory.appendingPathComponent("grok-auth.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        if descriptor >= 0 {
            XCTAssertNotEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
            XCTAssertTrue(errno == EWOULDBLOCK || errno == EAGAIN)
            Darwin.close(descriptor)
        }
        let second = Task { try await GrokAuthLock(directoryURL: directory).acquire() }
        await Task.yield()
        second.cancel()
        do {
            let lease = try await second.value
            lease.release()
            XCTFail("A cancelled waiter must not receive ownership")
        } catch { XCTAssertTrue(error is CancellationError) }
        first.release()
        let third = try await mutex.acquire()
        third.release()
    }

    func testFileStorePersistsOnlyNumericSnapshotAndClearsItWithoutChangingGeneration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("grok-store-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GrokUsageStore(directoryURL: directory)
        let id = UUID()
        let snapshot = GrokUsageSnapshot(usedPercent: 21, period: .weekly,
                                         resetAt: instant.addingTimeInterval(3_600), updatedAt: instant)
        try store.writeState(GrokUsageState(connectionID: id, snapshot: snapshot))
        XCTAssertEqual(store.load(now: instant), snapshot)
        let file = directory.appendingPathComponent("grok-direct-usage-v1.json")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["connectionID", "snapshot"])
        let value = try XCTUnwrap(object["snapshot"] as? [String: Any])
        XCTAssertEqual(Set(value.keys), ["usedPercent", "period", "resetAt", "updatedAt"])
        try store.writeState(GrokUsageState(connectionID: id, snapshot: nil))
        XCTAssertNil(store.load(now: instant))
        XCTAssertEqual(try store.readState()?.connectionID, id)
        try Data(repeating: 0, count: 4_097).write(to: file)
        XCTAssertThrowsError(try store.readState())
    }

    private func makeClient(stores: GrokTestStores, transport: GrokScriptTransport,
                            mutex: GrokTestMutex = GrokTestMutex(),
                            clock: GrokTestClock? = nil,
                            isDemo: @escaping @Sendable () -> Bool = { false },
                            fetchTimeout: TimeInterval = 25) -> GrokAccountClient {
        let clock = clock ?? GrokTestClock(instant)
        return GrokAccountClient(transport: transport, tokenStore: stores, usageStore: stores,
                                 authLock: mutex, now: { clock.now },
                                 sleep: { clock.advance($0) }, isDemo: isDemo, fetchTimeout: fetchTimeout)
    }

    private func authenticatedStores(snapshot: GrokUsageSnapshot? = nil,
                                     expiresIn: TimeInterval = 3_600) -> GrokTestStores {
        let id = UUID()
        let auth = GrokStoredAuth(connectionID: id, accessToken: "fixture-access-old",
                                  refreshToken: "fixture-refresh-old",
                                  expiresAt: instant.addingTimeInterval(expiresIn),
                                  refreshUncertain: false)
        return GrokTestStores(auth: auth, state: GrokUsageState(connectionID: id, snapshot: snapshot))
    }

    private func deviceData(expiresIn: Int = 300, interval: Int = 2) -> Data {
        json(["device_code": "fixture-device-code", "user_code": "FIXTURE-CODE",
              "verification_uri": "https://auth.x.ai/activate", "expires_in": expiresIn, "interval": interval])
    }

    private func tokenData(access: String = "fixture-access-new",
                           refresh: String = "fixture-refresh-new") -> Data {
        json(["access_token": access, "refresh_token": refresh, "token_type": "Bearer", "expires_in": 3_600])
    }

    private func billingData(percent: Any, period: String = "USAGE_PERIOD_TYPE_WEEKLY") -> Data {
        json(["config": ["creditUsagePercent": percent,
                         "currentPeriod": ["type": period,
                                           "start": iso(instant.addingTimeInterval(-3_600)),
                                           "end": iso(instant.addingTimeInterval(3_600))]]])
    }

    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
}

private struct GrokTestStoreCounts: Equatable {
    var tokenLoads = 0
    var tokenSaves = 0
    var tokenDeletes = 0
    var stateReads = 0
    var stateWrites = 0
}

private final class GrokTestStores: GrokTokenStoring, GrokUsageStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedAuth: GrokStoredAuth?
    private var storedState: GrokUsageState?
    private var storedCounts = GrokTestStoreCounts()

    init(auth: GrokStoredAuth? = nil, state: GrokUsageState? = nil) {
        storedAuth = auth
        storedState = state
    }

    var auth: GrokStoredAuth? { lock.withLock { storedAuth } }
    var state: GrokUsageState? { lock.withLock { storedState } }
    var counts: GrokTestStoreCounts { lock.withLock { storedCounts } }

    func load() throws -> GrokStoredAuth? {
        lock.withLock {
            storedCounts.tokenLoads += 1
            return storedAuth
        }
    }
    func save(_ record: GrokStoredAuth) throws {
        lock.withLock {
            storedCounts.tokenSaves += 1
            storedAuth = record
        }
    }
    func delete() throws {
        lock.withLock {
            storedCounts.tokenDeletes += 1
            storedAuth = nil
        }
    }
    func readState() throws -> GrokUsageState? {
        lock.withLock {
            storedCounts.stateReads += 1
            return storedState
        }
    }
    func writeState(_ state: GrokUsageState) throws {
        lock.withLock {
            storedCounts.stateWrites += 1
            storedState = state
        }
    }
}

private final class GrokTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Date
    private var waits: [TimeInterval] = []

    init(_ time: Date) { self.time = time }
    var now: Date { lock.withLock { time } }
    var delays: [TimeInterval] { lock.withLock { waits } }
    func advance(_ interval: TimeInterval) {
        lock.withLock {
            waits.append(interval)
            time = time.addingTimeInterval(interval)
        }
    }
}

private final class GrokTestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false
    var value: Bool {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private actor GrokResponseGate {
    private var requested = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var pending: [CheckedContinuation<GrokHTTPResponse, Never>] = []
    private var result: GrokHTTPResponse?

    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func response() async -> GrokHTTPResponse {
        requested = true
        observers.forEach { $0.resume() }
        observers.removeAll()
        if let result { return result }
        return await withCheckedContinuation { pending.append($0) }
    }
    func resolve(_ result: GrokHTTPResponse) {
        self.result = result
        pending.forEach { $0.resume(returning: result) }
        pending.removeAll()
    }
}

private actor GrokScriptTransport: GrokHTTPTransport {
    enum Step: Sendable {
        case response(Int, Data)
        case failure(GrokClientError)
        case gated(GrokResponseGate)
        case cancellableDelay(TimeInterval)
    }
    private var steps: [Step]
    private var requests: [URLRequest] = []

    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> GrokHTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw GrokClientError.network }
        let step = steps.removeFirst()
        switch step {
        case let .response(status, data): return .init(statusCode: status, data: data)
        case let .failure(error): throw error
        case let .gated(gate): return await gate.response()
        case let .cancellableDelay(seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw GrokClientError.network
        }
    }
    func recordedRequests() -> [URLRequest] { requests }
}

/// A synchronous release and async acquisition model the app/widget transaction boundary.
private final class GrokTestMutex: GrokAuthLocking, @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    private var waiters: [CheckedContinuation<any GrokAuthLease, Never>] = []
    private var contentionObservers: [CheckedContinuation<Void, Never>] = []
    private var count = 0

    var acquisitions: Int { lock.withLock { count } }
    var isHeld: Bool { lock.withLock { held } }

    func acquire() async throws -> any GrokAuthLease {
        try Task.checkCancellation()
        let lease: any GrokAuthLease = await withCheckedContinuation { continuation in
            let result = lock.withLock { () -> Bool in
                count += 1
                if held {
                    waiters.append(continuation)
                    contentionObservers.forEach { $0.resume() }
                    contentionObservers.removeAll()
                    return false
                }
                held = true
                return true
            }
            if result { continuation.resume(returning: GrokTestLease(self)) }
        }
        do {
            try Task.checkCancellation()
            return lease
        } catch {
            lease.release()
            throw error
        }
    }

    func waitUntilContended() async {
        await withCheckedContinuation { continuation in
            let alreadyWaiting = lock.withLock { () -> Bool in
                if !waiters.isEmpty { return true }
                contentionObservers.append(continuation)
                return false
            }
            if alreadyWaiting { continuation.resume() }
        }
    }

    fileprivate func release() {
        let next = lock.withLock { () -> CheckedContinuation<any GrokAuthLease, Never>? in
            if !waiters.isEmpty { return waiters.removeFirst() }
            held = false
            return nil
        }
        next?.resume(returning: GrokTestLease(self))
    }
}

private final class GrokTestLease: GrokAuthLease, @unchecked Sendable {
    private let lock = NSLock()
    private var owner: GrokTestMutex?
    init(_ owner: GrokTestMutex) { self.owner = owner }
    func release() {
        let current = lock.withLock { () -> GrokTestMutex? in
            let current = owner
            owner = nil
            return current
        }
        current?.release()
    }
    deinit { release() }
}

private final class GrokTestReadSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var waiting: [(Int, CheckedContinuation<Void, Never>)] = []

    var readCount: Int { lock.withLock { count } }
    func read() -> Bool {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            count += 1
            let ready = waiting.filter { count > $0.0 }.map { $0.1 }
            waiting.removeAll { count > $0.0 }
            return ready
        }
        ready.forEach { $0.resume() }
        return false
    }
    func waitForRead(after value: Int) async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock { () -> Bool in
                if count > value { return true }
                waiting.append((value, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}
