import XCTest
@testable import CodexTime

/// All tokens, grants, clocks, responses, and transports here are synthetic.
/// These tests never use a live account, Keychain, browser, or HTTP session.
final class ClaudeNativeAccountClientTests: XCTestCase {
    private let instant = Date(timeIntervalSince1970: 2_000_000_000)

    func testPKCEUsesTheRFC7636S256Vector() {
        XCTAssertEqual(ClaudeNativeAccountClient.challenge(for:
            "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testUsagePreservesZeroAndFractionalValuesAsOneObservation() throws {
        let snapshot = try ClaudeNativeAccountClient.parseUsage(usageData(five: 0, seven: 73.25), now: instant)
        XCTAssertEqual(snapshot.fiveHour.usedPercent, 0)
        XCTAssertEqual(snapshot.sevenDay.usedPercent, 73.25)
        XCTAssertEqual(snapshot.fiveHour.resetAt, instant.addingTimeInterval(3_600))
        XCTAssertEqual(snapshot.sevenDay.resetAt, instant.addingTimeInterval(86_400))
        XCTAssertEqual(snapshot.updatedAt, instant)
    }

    func testUsageNeverPublishesAPartialPairOrInventsMissingQuota() throws {
        for object: [String: Any] in [
            [:], ["five_hour": window(10)], ["seven_day": window(20)],
            ["five_hour": NSNull(), "seven_day": window(20)],
            ["five_hour": [:], "seven_day": window(20)],
            ["five_hour": ["used": 3, "limit": 100], "seven_day": window(20)]
        ] {
            XCTAssertThrowsError(try ClaudeNativeAccountClient.parseUsage(json(object), now: instant))
        }
    }

    func testUsageRejectsBooleanTextOutOfRangeAndMalformedReset() throws {
        for invalid: Any in [true, "12", -0.1, 100.1, NSNull()] {
            XCTAssertThrowsError(try ClaudeNativeAccountClient.parseUsage(usageData(five: invalid), now: instant))
        }
        for invalid: Any in ["nonsense", true, 42, iso(instant.addingTimeInterval(-1))] {
            let data = json(["five_hour": ["utilization": 10, "resets_at": invalid],
                             "seven_day": window(20)])
            XCTAssertThrowsError(try ClaudeNativeAccountClient.parseUsage(data, now: instant))
        }
    }

    func testUsageStalenessDoesNotRewriteTheObservationTime() throws {
        let snapshot = try ClaudeNativeAccountClient.parseUsage(usageData(), now: instant)
        XCTAssertFalse(snapshot.isStale(at: instant.addingTimeInterval(1_199)))
        XCTAssertTrue(snapshot.isStale(at: instant.addingTimeInterval(1_200)))
        XCTAssertFalse(snapshot.isValid(at: instant.addingTimeInterval(-1)))
        XCTAssertEqual(snapshot.updatedAt, instant)
    }

    func testAuthorizationIsLocalPKCEWithOnlyTheProfileScope() async throws {
        let stores = ClaudeFixtureStores()
        let transport = ClaudeFixtureTransport([])
        let client = makeClient(stores: stores, transport: transport)
        let authorization = try await client.beginAuthorization()
        let url = try XCTUnwrap(URLComponents(url: authorization.authorizationURL, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(url.queryItems)
        XCTAssertEqual(items.count, Set(items.map(\.name)).count)
        let fields = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "claude.ai")
        XCTAssertEqual(url.path, "/oauth/authorize")
        XCTAssertEqual(fields["scope"], "user:profile")
        XCTAssertEqual(fields["code_challenge_method"], "S256")
        XCTAssertEqual(fields["response_type"], "code")
        XCTAssertEqual(fields["client_id"], ClaudeNativeConfiguration.clientID)
        XCTAssertEqual(fields["redirect_uri"], ClaudeNativeConfiguration.callbackURL.absoluteString)
        XCTAssertGreaterThanOrEqual(fields["state"]?.count ?? 0, 32)
        XCTAssertEqual(fields["code_challenge"]?.count, 43)
        XCTAssertNil(fields["code_verifier"])
        XCTAssertNil(stores.auth)
        XCTAssertEqual(stores.state?.connectionID, authorization.id)
        XCTAssertEqual(authorization.expiresAt, instant.addingTimeInterval(600))
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testCompletionExchangesOwnGrantAndQueriesOnlyUsage() async throws {
        let stores = ClaudeFixtureStores()
        let transport = ClaudeFixtureTransport([.response(200, tokenData()), .response(200, usageData())])
        let client = makeClient(stores: stores, transport: transport)
        let authorization = try await client.beginAuthorization()
        let state = try authState(authorization)
        let snapshot = try await client.completeAuthorization(authorization, callbackURL: callback(state: state))
        XCTAssertEqual(snapshot.fiveHour.usedPercent, 12.5)
        XCTAssertEqual(stores.auth?.connectionID, authorization.id)
        XCTAssertEqual(stores.state?.snapshot, snapshot)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map(\.url), [ClaudeNativeConfiguration.tokenURL, ClaudeNativeConfiguration.usageURL])
        XCTAssertEqual(requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-new")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertNil(requests[1].httpBody)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[0].httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["grant_type"] as? String, "authorization_code")
        XCTAssertEqual(body["code"] as? String, "fixture-code")
        XCTAssertEqual(body["state"] as? String, state)
        XCTAssertEqual(body["redirect_uri"] as? String, ClaudeNativeConfiguration.callbackURL.absoluteString)
        let verifier = try XCTUnwrap(body["code_verifier"] as? String)
        let authorize = try XCTUnwrap(URLComponents(url: authorization.authorizationURL, resolvingAgainstBaseURL: false))
        let challenge = authorize.queryItems?.first { $0.name == "code_challenge" }?.value
        XCTAssertEqual(ClaudeNativeAccountClient.challenge(for: verifier), challenge)
    }

    func testCallbackRejectsSpoofedHostsPortsFragmentsDuplicateOrWrongStateBeforeHTTP() async throws {
        let stores = ClaudeFixtureStores()
        let transport = ClaudeFixtureTransport([])
        let client = makeClient(stores: stores, transport: transport)
        let authorization = try await client.beginAuthorization()
        let state = try authState(authorization)
        let original = callback(state: state)
        let bad = [
            "http://platform.claude.com/oauth/code/callback?code=x&state=\(state)",
            "https://platform.claude.com.attacker.invalid/oauth/code/callback?code=x&state=\(state)",
            "https://platform.claude.com:443/oauth/code/callback?code=x&state=\(state)",
            "https://user@platform.claude.com/oauth/code/callback?code=x&state=\(state)",
            original.absoluteString + "#fragment", original.absoluteString + "&state=\(state)",
            original.absoluteString + "&code=second", original.absoluteString + "&extra=ignored",
            callback(state: "wrong-state").absoluteString
        ]
        for raw in bad {
            do {
                _ = try await client.completeAuthorization(authorization, callbackURL: try XCTUnwrap(URL(string: raw)))
                XCTFail("Untrusted callback must fail")
            } catch { XCTAssertEqual(error as? ClaudeNativeClientError, .invalidCallback) }
        }
        XCTAssertNil(stores.auth)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testAuthorizationExpiresBeforeAnyTokenExchange() async throws {
        let clock = ClaudeFixtureClock(instant)
        let stores = ClaudeFixtureStores()
        let transport = ClaudeFixtureTransport([])
        let client = makeClient(stores: stores, transport: transport, clock: clock)
        let authorization = try await client.beginAuthorization()
        clock.advance(600)
        do {
            _ = try await client.completeAuthorization(authorization, callbackURL: callback(state: try authState(authorization)))
            XCTFail("Expired authorization must require a new flow")
        } catch { XCTAssertEqual(error as? ClaudeNativeClientError, .loginExpired) }
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testOldAuthorizationCannotReplaceOrCancelANewerConnection() async throws {
        let stores = ClaudeFixtureStores()
        let transport = ClaudeFixtureTransport([])
        let client = makeClient(stores: stores, transport: transport)
        let old = try await client.beginAuthorization()
        let newer = try await client.beginAuthorization()
        try await client.cancelAuthorization(old)
        XCTAssertEqual(stores.state?.connectionID, newer.id)
        do {
            _ = try await client.completeAuthorization(old, callbackURL: callback(state: try authState(old)))
            XCTFail("Replaced authorization must not issue a token exchange")
        } catch { }
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testCancelledAuthorizationRejectsALateTokenResponse() async throws {
        let stores = ClaudeFixtureStores()
        let gate = ClaudeFixtureGate()
        let transport = ClaudeFixtureTransport([.gated(gate)])
        let mutex = ClaudeFixtureMutex()
        let client = makeClient(stores: stores, transport: transport, mutex: mutex)
        let authorization = try await client.beginAuthorization()
        let responseURL = callback(state: try authState(authorization))
        let completing = Task { try await client.completeAuthorization(authorization, callbackURL: responseURL) }
        await gate.waitUntilRequested()
        let cancelling = Task { try await client.cancelAuthorization(authorization) }
        await mutex.waitUntilContended()
        await gate.resolve(.init(statusCode: 200, data: tokenData()))
        try await cancelling.value
        _ = try? await completing.value
        XCTAssertNil(stores.auth)
        XCTAssertNil(stores.state?.snapshot)
        XCTAssertNotEqual(stores.state?.connectionID, authorization.id)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testFreshCacheAvoidsHTTPButForceFetchUsesARealObservationTime() async throws {
        let clock = ClaudeFixtureClock(instant)
        let cached = try ClaudeNativeAccountClient.parseUsage(usageData(five: 0), now: instant.addingTimeInterval(-599))
        let stores = authenticatedStores(snapshot: cached)
        let transport = ClaudeFixtureTransport([.response(200, usageData(five: 41.25))])
        let client = makeClient(stores: stores, transport: transport, clock: clock)
        let first = try await client.fetchUsage()
        XCTAssertEqual(first, cached)
        var requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
        clock.advance(10)
        let second = try await client.fetchUsage(force: true)
        XCTAssertEqual(second.fiveHour.usedPercent, 41.25)
        XCTAssertEqual(second.updatedAt, instant.addingTimeInterval(10))
        requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testUnauthorizedUsageRotatesOnceAndRetriesWithTheNewAccessToken() async throws {
        let stores = authenticatedStores()
        let transport = ClaudeFixtureTransport([
            .response(401, json(["error": "ignored"])), .response(200, tokenData()), .response(200, usageData(five: 18))
        ])
        let client = makeClient(stores: stores, transport: transport)
        let result = try await client.fetchUsage(force: true)
        XCTAssertEqual(result.fiveHour.usedPercent, 18)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map(\.url), [ClaudeNativeConfiguration.usageURL, ClaudeNativeConfiguration.tokenURL,
                                            ClaudeNativeConfiguration.usageURL])
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-old")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer fixture-access-new")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: requests[1].httpBody ?? Data()) as? [String: Any])
        XCTAssertEqual(body["scope"] as? String, "user:profile")
        XCTAssertEqual(body["grant_type"] as? String, "refresh_token")
        XCTAssertEqual(stores.auth?.refreshToken, "fixture-refresh-new")
        XCTAssertFalse(stores.auth?.refreshUncertain ?? true)
    }

    func testASecondUnauthorizedResponseNeverLoopsRefresh() async throws {
        let stores = authenticatedStores()
        let transport = ClaudeFixtureTransport([.response(401, Data()), .response(200, tokenData()), .response(401, Data())])
        let client = makeClient(stores: stores, transport: transport)
        do { _ = try await client.fetchUsage(force: true); XCTFail("Repeated rejection must stop") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .loginExpired) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.filter { $0.url == ClaudeNativeConfiguration.tokenURL }.count, 1)
    }

    func testAmbiguousRotationIsPersistedAndCannotBeRetriedByAnotherClient() async throws {
        let cached = try ClaudeNativeAccountClient.parseUsage(usageData(five: 35), now: instant.addingTimeInterval(-2_000))
        let stores = authenticatedStores(snapshot: cached, expiresIn: -1)
        let mutex = ClaudeFixtureMutex()
        let transport = ClaudeFixtureTransport([.failure(.network)])
        let first = makeClient(stores: stores, transport: transport, mutex: mutex)
        do { _ = try await first.fetchUsage(force: true); XCTFail("Uncertain refresh must require sign-in") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .refreshUncertain) }
        XCTAssertTrue(stores.auth?.refreshUncertain ?? false)
        XCTAssertEqual(stores.state?.snapshot, cached)
        let second = makeClient(stores: stores, transport: transport, mutex: mutex)
        do { _ = try await second.fetchUsage(force: true); XCTFail("Do not repeat possibly consumed refresh token") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .refreshUncertain) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testRefreshResponseMustProvideAFreshTokenFamily() async throws {
        let stores = authenticatedStores(expiresIn: -1)
        let transport = ClaudeFixtureTransport([.response(200, json([
            "access_token": "fixture-access-new", "token_type": "Bearer", "expires_in": 3_600
        ]))])
        let client = makeClient(stores: stores, transport: transport)
        do { _ = try await client.fetchUsage(force: true); XCTFail("Missing rotated refresh token must fail") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .refreshUncertain) }
        XCTAssertTrue(stores.auth?.refreshUncertain ?? false)
        XCTAssertEqual(stores.auth?.refreshToken, "fixture-refresh-old")
    }

    func testDemoStopsBeforeStoresLocksAndNetwork() async {
        let stores = ClaudeFixtureStores()
        let mutex = ClaudeFixtureMutex()
        let transport = ClaudeFixtureTransport([])
        let client = makeClient(stores: stores, transport: transport, mutex: mutex, isDemo: { true })
        let authenticated = await client.isAuthenticated()
        XCTAssertFalse(authenticated)
        do { _ = try await client.beginAuthorization(); XCTFail("Demo cannot authorize") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .demoMode) }
        do { _ = try await client.fetchUsage(force: true); XCTFail("Demo cannot fetch") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .demoMode) }
        XCTAssertEqual(stores.operationCount, 0)
        XCTAssertEqual(mutex.acquisitions, 0)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testEnteringDemoDuringHTTPPreservesTheOldAtomicPair() async throws {
        let previous = try ClaudeNativeAccountClient.parseUsage(usageData(), now: instant.addingTimeInterval(-2_000))
        let stores = authenticatedStores(snapshot: previous)
        let demo = ClaudeFixtureFlag()
        let gate = ClaudeFixtureGate()
        let transport = ClaudeFixtureTransport([.gated(gate)])
        let client = makeClient(stores: stores, transport: transport, isDemo: { demo.value })
        let fetch = Task { try await client.fetchUsage(force: true) }
        await gate.waitUntilRequested()
        demo.value = true
        await gate.resolve(.init(statusCode: 200, data: usageData(five: 99)))
        do { _ = try await fetch.value; XCTFail("Demo cannot publish a real response") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .demoMode) }
        XCTAssertEqual(stores.state?.snapshot, previous)
    }

    func testInvalidUsageKeepsBothPreviousWindowsAndTimestamp() async throws {
        let previous = try ClaudeNativeAccountClient.parseUsage(usageData(), now: instant.addingTimeInterval(-2_000))
        let stores = authenticatedStores(snapshot: previous)
        let transport = ClaudeFixtureTransport([.response(200, json(["five_hour": window(99)]))])
        let client = makeClient(stores: stores, transport: transport)
        do { _ = try await client.fetchUsage(force: true); XCTFail("Partial pair must not be published") }
        catch { }
        XCTAssertEqual(stores.state?.snapshot, previous)
    }

    func testConcurrentClientsShareOneRotationAndFreshNumericCache() async throws {
        let stores = authenticatedStores(expiresIn: -1)
        let mutex = ClaudeFixtureMutex()
        let gate = ClaudeFixtureGate()
        let transport = ClaudeFixtureTransport([.gated(gate), .response(200, usageData(five: 27))])
        let first = makeClient(stores: stores, transport: transport, mutex: mutex)
        let second = makeClient(stores: stores, transport: transport, mutex: mutex)
        let a = Task { try await first.fetchUsage() }
        await gate.waitUntilRequested()
        let b = Task { try await second.fetchUsage() }
        await mutex.waitUntilContended()
        await gate.resolve(.init(statusCode: 200, data: tokenData()))
        let resultA = try await a.value
        let resultB = try await b.value
        XCTAssertEqual(resultA, resultB)
        XCTAssertEqual(resultA.fiveHour.usedPercent, 27)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.filter { $0.url == ClaudeNativeConfiguration.tokenURL }.count, 1)
    }

    func testDeadlineDrainsItsTransactionAndLeavesRotationUncertain() async throws {
        let stores = authenticatedStores(expiresIn: -1)
        let mutex = ClaudeFixtureMutex()
        let transport = ClaudeFixtureTransport([.cancellableDelay(5)])
        let client = makeClient(stores: stores, transport: transport, mutex: mutex, fetchTimeout: 0.02)
        do { _ = try await client.fetchUsage(force: true); XCTFail("Fetch must have an owned deadline") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .network) }
        XCTAssertFalse(mutex.isHeld)
        XCTAssertTrue(stores.auth?.refreshUncertain ?? false)
        do { _ = try await client.fetchUsage(force: true); XCTFail("Do not repeat timed-out rotation") }
        catch { XCTAssertEqual(error as? ClaudeNativeClientError, .refreshUncertain) }
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        try await client.signOut()
        XCTAssertFalse(mutex.isHeld)
        XCTAssertNil(stores.auth)
        XCTAssertNil(stores.state?.snapshot)
    }

    private func makeClient(stores: ClaudeFixtureStores, transport: ClaudeFixtureTransport,
                            mutex: ClaudeFixtureMutex = ClaudeFixtureMutex(),
                            clock: ClaudeFixtureClock? = nil,
                            isDemo: @escaping @Sendable () -> Bool = { false },
                            fetchTimeout: TimeInterval = 25) -> ClaudeNativeAccountClient {
        let clock = clock ?? ClaudeFixtureClock(instant)
        return ClaudeNativeAccountClient(transport: transport, tokenStore: stores, usageStore: stores,
            authLock: mutex, now: { clock.now }, isDemo: isDemo, fetchTimeout: fetchTimeout)
    }

    private func authenticatedStores(snapshot: ClaudeNativeUsageSnapshot? = nil,
                                     expiresIn: TimeInterval = 3_600) -> ClaudeFixtureStores {
        let id = UUID()
        return ClaudeFixtureStores(auth: ClaudeNativeStoredAuth(connectionID: id,
            accessToken: "fixture-access-old", refreshToken: "fixture-refresh-old",
            expiresAt: instant.addingTimeInterval(expiresIn), refreshUncertain: false),
            state: ClaudeNativeUsageState(connectionID: id, snapshot: snapshot))
    }

    private func authState(_ authorization: ClaudeNativeAuthorization) throws -> String {
        let parts = try XCTUnwrap(URLComponents(url: authorization.authorizationURL, resolvingAgainstBaseURL: false))
        return try XCTUnwrap(parts.queryItems?.first { $0.name == "state" }?.value)
    }
    private func callback(state: String) -> URL {
        var url = URLComponents(url: ClaudeNativeConfiguration.callbackURL, resolvingAgainstBaseURL: false)!
        url.queryItems = [.init(name: "code", value: "fixture-code"), .init(name: "state", value: state)]
        return url.url!
    }
    private func tokenData() -> Data {
        json(["access_token": "fixture-access-new", "refresh_token": "fixture-refresh-new",
              "token_type": "Bearer", "expires_in": 3_600])
    }
    private func usageData(five: Any = 12.5, seven: Any = 40) -> Data {
        json(["five_hour": ["utilization": five, "resets_at": iso(instant.addingTimeInterval(3_600))],
              "seven_day": ["utilization": seven, "resets_at": iso(instant.addingTimeInterval(86_400))]])
    }
    private func window(_ value: Any) -> [String: Any] {
        ["utilization": value, "resets_at": iso(instant.addingTimeInterval(86_400))]
    }
    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
}

private final class ClaudeFixtureStores: ClaudeNativeTokenStoring, ClaudeNativeUsageStoring, @unchecked Sendable {
    private let mutex = NSLock()
    private var storedAuth: ClaudeNativeStoredAuth?
    private var storedState: ClaudeNativeUsageState?
    private var operations = 0
    init(auth: ClaudeNativeStoredAuth? = nil, state: ClaudeNativeUsageState? = nil) {
        storedAuth = auth
        storedState = state
    }
    var auth: ClaudeNativeStoredAuth? { mutex.withLock { storedAuth } }
    var state: ClaudeNativeUsageState? { mutex.withLock { storedState } }
    var operationCount: Int { mutex.withLock { operations } }
    func load() throws -> ClaudeNativeStoredAuth? { mutex.withLock { operations += 1; return storedAuth } }
    func save(_ auth: ClaudeNativeStoredAuth) throws { mutex.withLock { operations += 1; storedAuth = auth } }
    func delete() throws { mutex.withLock { operations += 1; storedAuth = nil } }
    func readState() throws -> ClaudeNativeUsageState? { mutex.withLock { operations += 1; return storedState } }
    func writeState(_ state: ClaudeNativeUsageState) throws { mutex.withLock { operations += 1; storedState = state } }
}

private final class ClaudeFixtureClock: @unchecked Sendable {
    private let mutex = NSLock()
    private var time: Date
    init(_ time: Date) { self.time = time }
    var now: Date { mutex.withLock { time } }
    func advance(_ seconds: TimeInterval) { mutex.withLock { time = time.addingTimeInterval(seconds) } }
}

private final class ClaudeFixtureFlag: @unchecked Sendable {
    private let mutex = NSLock()
    private var stored = false
    var value: Bool {
        get { mutex.withLock { stored } }
        set { mutex.withLock { stored = newValue } }
    }
}

private actor ClaudeFixtureGate {
    private var requested = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var waiters: [CheckedContinuation<ClaudeNativeHTTPResponse, Never>] = []
    private var result: ClaudeNativeHTTPResponse?
    func waitUntilRequested() async {
        if requested { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func response() async -> ClaudeNativeHTTPResponse {
        requested = true
        observers.forEach { $0.resume() }
        observers.removeAll()
        if let result { return result }
        return await withCheckedContinuation { waiters.append($0) }
    }
    func resolve(_ result: ClaudeNativeHTTPResponse) {
        self.result = result
        waiters.forEach { $0.resume(returning: result) }
        waiters.removeAll()
    }
}

private actor ClaudeFixtureTransport: ClaudeNativeHTTPTransport {
    enum Step: Sendable {
        case response(Int, Data)
        case failure(ClaudeNativeClientError)
        case gated(ClaudeFixtureGate)
        case cancellableDelay(TimeInterval)
    }
    private var steps: [Step]
    private var requests: [URLRequest] = []
    init(_ steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> ClaudeNativeHTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw ClaudeNativeClientError.network }
        switch steps.removeFirst() {
        case let .response(status, data): return .init(statusCode: status, data: data)
        case let .failure(error): throw error
        case let .gated(gate): return await gate.response()
        case let .cancellableDelay(seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ClaudeNativeClientError.network
        }
    }
    func recordedRequests() -> [URLRequest] { requests }
}

private final class ClaudeFixtureMutex: ClaudeNativeAuthLocking, @unchecked Sendable {
    private let mutex = NSLock()
    private var held = false
    private var count = 0
    private var waiters: [CheckedContinuation<any ClaudeNativeAuthLease, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []
    var acquisitions: Int { mutex.withLock { count } }
    var isHeld: Bool { mutex.withLock { held } }
    func acquire() async throws -> any ClaudeNativeAuthLease {
        try Task.checkCancellation()
        let lease: any ClaudeNativeAuthLease = await withCheckedContinuation { continuation in
            let immediate = mutex.withLock { () -> Bool in
                count += 1
                if held {
                    waiters.append(continuation)
                    observers.forEach { $0.resume() }
                    observers.removeAll()
                    return false
                }
                held = true
                return true
            }
            if immediate { continuation.resume(returning: ClaudeFixtureLease(self)) }
        }
        do { try Task.checkCancellation(); return lease }
        catch { lease.release(); throw error }
    }
    func waitUntilContended() async {
        await withCheckedContinuation { continuation in
            let immediate = mutex.withLock { () -> Bool in
                if !waiters.isEmpty { return true }
                observers.append(continuation)
                return false
            }
            if immediate { continuation.resume() }
        }
    }
    fileprivate func release() {
        let next = mutex.withLock { () -> CheckedContinuation<any ClaudeNativeAuthLease, Never>? in
            if !waiters.isEmpty { return waiters.removeFirst() }
            held = false
            return nil
        }
        next?.resume(returning: ClaudeFixtureLease(self))
    }
}

private final class ClaudeFixtureLease: ClaudeNativeAuthLease, @unchecked Sendable {
    private let mutex = NSLock()
    private var owner: ClaudeFixtureMutex?
    init(_ owner: ClaudeFixtureMutex) { self.owner = owner }
    func release() {
        let previous = mutex.withLock { () -> ClaudeFixtureMutex? in
            defer { owner = nil }
            return owner
        }
        previous?.release()
    }
    deinit { release() }
}
