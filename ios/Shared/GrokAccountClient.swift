import Foundation
import CoreFoundation

struct GrokHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

protocol GrokHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> GrokHTTPResponse
}

private final class GrokRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The session has no ambient cookies, credentials, disk cache, redirects, or model endpoint.
final class GrokURLSessionTransport: GrokHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration, delegate: GrokRedirectGuard(), delegateQueue: nil)
    }

    func send(_ request: URLRequest, maximumBytes: Int) async throws -> GrokHTTPResponse {
        guard [GrokConfiguration.deviceURL, GrokConfiguration.tokenURL, GrokConfiguration.billingURL]
            .contains(request.url), maximumBytes > 0, maximumBytes <= 524_288 else {
            throw GrokClientError.invalidResponse
        }
        let isBilling = request.url == GrokConfiguration.billingURL
        guard request.httpMethod == (isBilling ? "GET" : "POST"),
              !isBilling || request.httpBody == nil,
              (request.httpBody?.count ?? 0) <= 131_072 else {
            throw GrokClientError.invalidResponse
        }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.url == request.url,
                  http.expectedContentLength <= Int64(maximumBytes) else {
                throw GrokClientError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { throw GrokClientError.invalidResponse }
                data.append(byte)
            }
            return GrokHTTPResponse(statusCode: http.statusCode, data: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as GrokClientError { throw error }
        catch { throw GrokClientError.network }
    }
}

actor GrokAccountClient {
    static let shared = GrokAccountClient()
    private let transport: any GrokHTTPTransport
    private let tokenStore: any GrokTokenStoring
    private let usageStore: any GrokUsageStoring
    private let authLock: any GrokAuthLocking
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let isDemo: @Sendable () -> Bool
    private let fetchTimeout: TimeInterval
    private var pending: (id: UUID, task: Task<GrokUsageSnapshot, Error>)?

    init(transport: any GrokHTTPTransport = GrokURLSessionTransport(),
         tokenStore: any GrokTokenStoring = GrokKeychainTokenStore(),
         usageStore: any GrokUsageStoring = GrokUsageStore(),
         authLock: any GrokAuthLocking = GrokAuthLock(),
         now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(nanoseconds: UInt64(min(max(0, $0), 3_600) * 1_000_000_000))
         },
         isDemo: @escaping @Sendable () -> Bool = { SharedUsageStore().isDemoEnabled },
         fetchTimeout: TimeInterval = 25) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.usageStore = usageStore
        self.authLock = authLock
        self.now = now
        self.sleep = sleep
        self.isDemo = isDemo
        self.fetchTimeout = fetchTimeout.isFinite ? min(max(fetchTimeout, 0.01), 25) : 25
    }

    func isAuthenticated() async -> Bool {
        guard !isDemo() else { return false }
        do {
            let lease = try await authLock.acquire()
            defer { lease.release() }
            guard !isDemo(), let state = try usageStore.readState(),
                  let auth = try tokenStore.load(),
                  auth.connectionID == state.connectionID,
                  auth.hasValidFields, !auth.refreshUncertain else { return false }
            return true
        } catch { return false }
    }

    func requestDeviceAuthorization() async throws -> GrokDeviceAuthorization {
        try checkActive()
        pending?.task.cancel()
        let connectionID = UUID()
        let lease = try await authLock.acquire()
        do {
            try checkActive()
            try usageStore.writeState(GrokUsageState(connectionID: connectionID, snapshot: nil))
            try tokenStore.delete()
            lease.release()
        } catch {
            lease.release()
            throw error
        }
        let request = formRequest(url: GrokConfiguration.deviceURL, fields: [
            "client_id": GrokConfiguration.clientID,
            "scope": GrokConfiguration.scope,
            "referrer": "codextime"
        ])
        let response = try await transport.send(request, maximumBytes: 65_536)
        try checkActive()
        guard response.statusCode == 200 else { throw Self.httpFailure(response.statusCode) }
        let fields = try Self.object(response.data, maximumBytes: 65_536)
        guard let deviceCode = fields["device_code"] as? String, GrokStoredAuth.validToken(deviceCode),
              let userCode = fields["user_code"] as? String, !userCode.isEmpty, userCode.utf8.count <= 128,
              !userCode.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let rawURL = fields["verification_uri"] as? String, rawURL.utf8.count <= 2_048,
              let url = URL(string: rawURL), Self.isVerificationURL(url),
              let expires = Self.number(fields["expires_in"]), expires > 0, expires <= 1_800 else {
            throw GrokClientError.invalidResponse
        }
        let interval = Self.number(fields["interval"]) ?? 5
        guard (1...60).contains(interval) else { throw GrokClientError.invalidResponse }
        try await checkConnection(connectionID)
        return GrokDeviceAuthorization(deviceCode: deviceCode, userCode: userCode,
            verificationURL: url, expiresAt: now().addingTimeInterval(expires),
            interval: interval, connectionID: connectionID)
    }

    func completeDeviceAuthorization(_ authorization: GrokDeviceAuthorization) async throws -> GrokUsageSnapshot {
        var interval = authorization.interval
        guard (1...60).contains(interval), GrokStoredAuth.validToken(authorization.deviceCode),
              authorization.expiresAt.timeIntervalSince(now()) <= 1_800 else {
            throw GrokClientError.invalidResponse
        }
        while now() < authorization.expiresAt {
            try checkActive()
            try await checkConnection(authorization.connectionID)
            try await sleep(min(interval, max(0, authorization.expiresAt.timeIntervalSince(now()))))
            try checkActive()
            guard now() < authorization.expiresAt else { break }
            try await checkConnection(authorization.connectionID)
            let response = try await transport.send(formRequest(url: GrokConfiguration.tokenURL, fields: [
                "client_id": GrokConfiguration.clientID,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": authorization.deviceCode
            ]), maximumBytes: 131_072)
            try checkActive()
            if response.statusCode == 200 {
                let auth = try Self.parseTokens(response.data, connectionID: authorization.connectionID,
                                                previous: nil, now: now())
                let lease = try await authLock.acquire()
                do {
                    try checkActive()
                    guard try usageStore.readState()?.connectionID == authorization.connectionID else {
                        throw GrokClientError.connectionChanged
                    }
                    try tokenStore.save(auth)
                    lease.release()
                } catch {
                    lease.release()
                    throw error
                }
                return try await fetchUsage(force: true)
            }
            let fields = try Self.object(response.data, maximumBytes: 131_072)
            switch fields["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval = min(interval + 5, 120)
            case "access_denied": throw GrokClientError.authorizationDenied
            case "expired_token", "invalid_grant": throw GrokClientError.loginExpired
            default: throw Self.httpFailure(response.statusCode)
            }
        }
        throw GrokClientError.loginExpired
    }

    /// Retires only this authorization; it cannot disconnect a newer login.
    func cancelDeviceAuthorization(_ authorization: GrokDeviceAuthorization) async throws {
        let lease = try await authLock.acquire()
        defer { lease.release() }
        guard try usageStore.readState()?.connectionID == authorization.connectionID else { return }
        pending?.task.cancel()
        try usageStore.writeState(GrokUsageState(connectionID: UUID(), snapshot: nil))
        try tokenStore.delete()
    }

    func fetchUsage(force: Bool = false) async throws -> GrokUsageSnapshot {
        try checkActive()
        if let pending {
            let result = try await pending.task.value
            try Task.checkCancellation()
            return result
        }
        let id = UUID()
        let timeout = fetchTimeout
        let task = Task {
            try await withThrowingTaskGroup(of: GrokUsageSnapshot.self) { group in
                group.addTask { try await self.performFetch(force: force) }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw GrokClientError.network
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw GrokClientError.network }
                return result
                // Structured scope waits for the cancelled owner to release its
                // network request and interprocess lease before returning.
            }
        }
        pending = (id, task)
        defer { if pending?.id == id { pending = nil } }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: { task.cancel() }
    }

    func signOut() async throws {
        pending?.task.cancel()
        let lease = try await authLock.acquire()
        defer { lease.release() }
        // Retire generation and clear numeric cache before removing credentials.
        try usageStore.writeState(GrokUsageState(connectionID: UUID(), snapshot: nil))
        try tokenStore.delete()
    }

    private func performFetch(force: Bool) async throws -> GrokUsageSnapshot {
        try checkActive()
        let lease = try await authLock.acquire()
        defer { lease.release() }
        try checkActive()
        guard let state = try usageStore.readState(),
              var auth = try tokenStore.load(),
              auth.connectionID == state.connectionID else { throw GrokClientError.notAuthenticated }
        guard !auth.refreshUncertain else { throw GrokClientError.refreshUncertain }
        guard auth.hasValidFields else { throw GrokClientError.loginExpired }
        if !force, let snapshot = state.snapshot, snapshot.isValid(at: now()),
           !snapshot.isStale(at: now(), maxAge: 600) { return snapshot }
        var didRefresh = false
        if auth.expiresAt.timeIntervalSince(now()) < 90 {
            auth = try await refresh(auth)
            didRefresh = true
        }
        try checkActive()
        var response = try await transport.send(billingRequest(auth), maximumBytes: 524_288)
        try checkActive()
        if response.statusCode == 401, !didRefresh {
            auth = try await refresh(auth)
            try checkActive()
            response = try await transport.send(billingRequest(auth), maximumBytes: 524_288)
            try checkActive()
        }
        guard response.statusCode == 200 else { throw Self.httpFailure(response.statusCode) }
        let snapshot = try Self.parseUsage(response.data, now: now())
        try checkActive()
        guard try usageStore.readState()?.connectionID == state.connectionID else {
            throw GrokClientError.connectionChanged
        }
        try usageStore.writeState(GrokUsageState(connectionID: state.connectionID, snapshot: snapshot))
        return snapshot
    }

    /// Caller holds the interprocess lease. Mark uncertain before sending a rotating token.
    private func refresh(_ current: GrokStoredAuth) async throws -> GrokStoredAuth {
        try checkActive()
        var uncertain = current
        uncertain.refreshUncertain = true
        try tokenStore.save(uncertain)
        do {
            let response = try await transport.send(formRequest(url: GrokConfiguration.tokenURL, fields: [
                "client_id": GrokConfiguration.clientID,
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken
            ]), maximumBytes: 131_072)
            guard response.statusCode == 200 else {
                if response.statusCode == 400 || response.statusCode == 401 { throw GrokClientError.loginExpired }
                throw GrokClientError.refreshUncertain
            }
            let replacement = try Self.parseTokens(response.data, connectionID: current.connectionID,
                                                   previous: current, now: now())
            // Keep a confirmed rotated credential even if this fetch was cancelled.
            // The active connection must still match before any credential write.
            guard try usageStore.readState()?.connectionID == current.connectionID else {
                throw GrokClientError.connectionChanged
            }
            try tokenStore.save(replacement)
            try Task.checkCancellation()
            return replacement
        } catch let error as GrokClientError {
            throw error == .loginExpired ? error : GrokClientError.refreshUncertain
        } catch is CancellationError { throw CancellationError() }
        catch { throw GrokClientError.refreshUncertain }
    }

    private func checkConnection(_ connectionID: UUID) async throws {
        let lease = try await authLock.acquire()
        defer { lease.release() }
        try checkActive()
        guard try usageStore.readState()?.connectionID == connectionID else {
            throw GrokClientError.connectionChanged
        }
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        guard !isDemo() else { throw GrokClientError.demoMode }
    }

    private func billingRequest(_ auth: GrokStoredAuth) -> URLRequest {
        var request = URLRequest(url: GrokConfiguration.billingURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + auth.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("CodexTime", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func formRequest(url: URL, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        request.httpBody = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        return request
    }

    static func parseUsage(_ data: Data, now: Date) throws -> GrokUsageSnapshot {
        let fields = try object(data, maximumBytes: 524_288)
        guard let config = fields["config"] as? [String: Any],
              let percent = number(config["creditUsagePercent"]),
              (0...100).contains(percent) else { throw GrokClientError.usageUnavailable }
        var period = GrokUsagePeriod.unknown
        var resetAt: Date?
        if let rawCurrent = config["currentPeriod"] {
            guard let current = rawCurrent as? [String: Any],
                  let rawEnd = current["end"] as? String, let end = isoDate(rawEnd) else {
                throw GrokClientError.invalidResponse
            }
            resetAt = end
            switch current["type"] as? String {
            case "USAGE_PERIOD_TYPE_WEEKLY": period = .weekly
            case "USAGE_PERIOD_TYPE_MONTHLY": period = .monthly
            default: period = .unknown
            }
            if let rawStart = current["start"] {
                guard let value = rawStart as? String, let start = isoDate(value),
                      start <= now, end > start else { throw GrokClientError.invalidResponse }
            }
        } else if let rawEnd = config["billingPeriodEnd"] {
            guard let value = rawEnd as? String, let end = isoDate(value) else {
                throw GrokClientError.invalidResponse
            }
            resetAt = end
            // A legacy billing date cannot supply a weekly/monthly quota classification.
        }
        let snapshot = GrokUsageSnapshot(usedPercent: percent, period: period, resetAt: resetAt, updatedAt: now)
        guard snapshot.isValid(at: now) else { throw GrokClientError.invalidResponse }
        return snapshot
    }

    private static func parseTokens(_ data: Data, connectionID: UUID,
                                    previous: GrokStoredAuth?, now: Date) throws -> GrokStoredAuth {
        let fields = try object(data, maximumBytes: 131_072)
        guard let access = fields["access_token"] as? String,
              let refresh = fields["refresh_token"] as? String ?? previous?.refreshToken,
              let duration = number(fields["expires_in"]), duration > 0, duration <= 366 * 86_400,
              (fields["token_type"] as? String)?.lowercased() == "bearer" else {
            throw GrokClientError.invalidResponse
        }
        let auth = GrokStoredAuth(connectionID: connectionID, accessToken: access, refreshToken: refresh,
                                  expiresAt: now.addingTimeInterval(duration), refreshUncertain: false)
        guard auth.hasValidFields else { throw GrokClientError.invalidResponse }
        return auth
    }

    private static func object(_ data: Data, maximumBytes: Int) throws -> [String: Any] {
        guard data.count <= maximumBytes,
              String(data: data, encoding: .utf8) != nil,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GrokClientError.invalidResponse
        }
        return object
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func isVerificationURL(_ url: URL) -> Bool {
        url.scheme == "https" && ["auth.x.ai", "accounts.x.ai"].contains(url.host?.lowercased() ?? "")
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
            && url.fragment == nil
    }

    private static func httpFailure(_ status: Int) -> GrokClientError {
        switch status {
        case 400, 401: return .loginExpired
        case 403: return .permissionRequired
        case 429: return .retryLater
        default: return .network
        }
    }
}
