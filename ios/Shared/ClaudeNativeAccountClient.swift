import Foundation
import CoreFoundation

struct ClaudeNativeHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

protocol ClaudeNativeHTTPTransport: Sendable {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> ClaudeNativeHTTPResponse
}

private final class ClaudeNativeRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The session has no ambient cookies, credentials, disk cache, redirects, or model endpoint.
final class ClaudeNativeURLSessionTransport: ClaudeNativeHTTPTransport, @unchecked Sendable {
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
        session = URLSession(configuration: configuration, delegate: ClaudeNativeRedirectGuard(), delegateQueue: nil)
    }

    func send(_ request: URLRequest, maximumBytes: Int) async throws -> ClaudeNativeHTTPResponse {
        guard [ClaudeNativeConfiguration.tokenURL, ClaudeNativeConfiguration.usageURL]
            .contains(request.url), maximumBytes > 0, maximumBytes <= 524_288 else {
            throw ClaudeNativeClientError.invalidResponse
        }
        let isUsage = request.url == ClaudeNativeConfiguration.usageURL
        guard request.httpMethod == (isUsage ? "GET" : "POST"),
              !isUsage || request.httpBody == nil,
              (request.httpBody?.count ?? 0) <= 131_072 else {
            throw ClaudeNativeClientError.invalidResponse
        }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.url == request.url,
                  http.expectedContentLength <= Int64(maximumBytes) else {
                throw ClaudeNativeClientError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { throw ClaudeNativeClientError.invalidResponse }
                data.append(byte)
            }
            return ClaudeNativeHTTPResponse(statusCode: http.statusCode, data: data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ClaudeNativeClientError { throw error }
        catch { throw ClaudeNativeClientError.network }
    }
}

import CryptoKit
import Security

/// Independent, offline-tested native compatibility candidate. Provider permission and
/// live account compatibility must be established separately before product activation.
actor ClaudeNativeAccountClient {
    static let shared = ClaudeNativeAccountClient()
    private let transport: any ClaudeNativeHTTPTransport
    private let tokenStore: any ClaudeNativeTokenStoring
    private let usageStore: any ClaudeNativeUsageStoring
    private let authLock: any ClaudeNativeAuthLocking
    private let now: @Sendable () -> Date
    private let isDemo: @Sendable () -> Bool
    private let fetchTimeout: TimeInterval
    private var pending: (id: UUID, task: Task<ClaudeNativeUsageSnapshot, Error>)?
    private var authorization: PendingAuthorization?

    private struct PendingAuthorization {
        let descriptor: ClaudeNativeAuthorization
        let verifier: String
        let state: String
    }

    init(transport: any ClaudeNativeHTTPTransport = ClaudeNativeURLSessionTransport(),
         tokenStore: any ClaudeNativeTokenStoring = ClaudeNativeTokenStore(),
         usageStore: any ClaudeNativeUsageStoring = ClaudeNativeUsageStore(),
         authLock: any ClaudeNativeAuthLocking = ClaudeNativeAuthLock(),
         now: @escaping @Sendable () -> Date = { Date() },
         isDemo: @escaping @Sendable () -> Bool = { SharedUsageStore().isDemoEnabled },
         fetchTimeout: TimeInterval = 25) {
        self.transport = transport
        self.tokenStore = tokenStore
        self.usageStore = usageStore
        self.authLock = authLock
        self.now = now
        self.isDemo = isDemo
        self.fetchTimeout = fetchTimeout.isFinite ? min(max(fetchTimeout, 0.01), 25) : 25
    }

    func isAuthenticated() async -> Bool {
        guard !isDemo() else { return false }
        do {
            let lease = try await authLock.acquire()
            defer { lease.release() }
            guard !isDemo(), let state = try usageStore.readState(),
                  let auth = try tokenStore.load(), auth.connectionID == state.connectionID,
                  auth.hasValidFields, !auth.refreshUncertain else { return false }
            return true
        } catch { return false }
    }

    /// Builds the provider's HTTPS sign-in URL without any account request.
    func beginAuthorization() async throws -> ClaudeNativeAuthorization {
        try checkActive()
        let verifier = try Self.randomString()
        let state = try Self.randomString()
        let id = UUID()
        var components = URLComponents(url: ClaudeNativeConfiguration.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: ClaudeNativeConfiguration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: ClaudeNativeConfiguration.callbackURL.absoluteString),
            URLQueryItem(name: "scope", value: ClaudeNativeConfiguration.scope),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else { throw ClaudeNativeClientError.invalidResponse }
        let descriptor = ClaudeNativeAuthorization(id: id, authorizationURL: url,
                                                   expiresAt: now().addingTimeInterval(600))
        pending?.task.cancel()
        let lease = try await authLock.acquire()
        defer { lease.release() }
        try checkActive()
        try usageStore.writeState(ClaudeNativeUsageState(connectionID: id, snapshot: nil))
        try tokenStore.delete()
        authorization = PendingAuthorization(descriptor: descriptor, verifier: verifier, state: state)
        return descriptor
    }

    func completeAuthorization(_ descriptor: ClaudeNativeAuthorization,
                               callbackURL: URL) async throws -> ClaudeNativeUsageSnapshot {
        try checkActive()
        let session = try activeAuthorization(descriptor)
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "platform.claude.com",
              components.port == nil, components.user == nil, components.password == nil,
              components.percentEncodedPath == "/oauth/code/callback", components.fragment == nil,
              let items = components.queryItems, !items.isEmpty,
              Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ ["code", "state", "error", "error_description"].contains($0.name) }),
              items.first(where: { $0.name == "state" })?.value == session.state else {
            throw ClaudeNativeClientError.invalidCallback
        }
        if items.contains(where: { $0.name == "error" }) {
            guard !items.contains(where: { $0.name == "code" }) else { throw ClaudeNativeClientError.invalidCallback }
            authorization = nil
            throw ClaudeNativeClientError.authorizationDenied
        }
        guard !items.contains(where: { $0.name == "error_description" }),
              let code = items.first(where: { $0.name == "code" })?.value,
              Self.validCode(code) else { throw ClaudeNativeClientError.invalidCallback }
        return try await exchange(code: code, session: session)
    }

    /// The provider's one-time code screen can be used on a phone without desktop relay.
    /// A bare code is rejected because it cannot prove the caller's returned OAuth state.
    func completeAuthorization(_ descriptor: ClaudeNativeAuthorization,
                               pastedCode: String) async throws -> ClaudeNativeUsageSnapshot {
        try checkActive()
        let session = try activeAuthorization(descriptor)
        let parts = pastedCode.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2, String(parts[1]) == session.state,
              Self.validCode(String(parts[0])) else { throw ClaudeNativeClientError.invalidCallback }
        return try await exchange(code: String(parts[0]), session: session)
    }

    func cancelAuthorization(_ descriptor: ClaudeNativeAuthorization) async throws {
        let lease = try await authLock.acquire()
        defer { lease.release() }
        if authorization?.descriptor.id == descriptor.id { authorization = nil }
        guard try usageStore.readState()?.connectionID == descriptor.id else { return }
        pending?.task.cancel()
        try usageStore.writeState(ClaudeNativeUsageState(connectionID: UUID(), snapshot: nil))
        try tokenStore.delete()
    }

    func fetchUsage(force: Bool = false) async throws -> ClaudeNativeUsageSnapshot {
        try checkActive()
        if let pending {
            let result = try await pending.task.value
            try Task.checkCancellation()
            return result
        }
        let id = UUID()
        let timeout = fetchTimeout
        let task = Task {
            try await withThrowingTaskGroup(of: ClaudeNativeUsageSnapshot.self) { group in
                group.addTask { try await self.performFetch(force: force) }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw ClaudeNativeClientError.network
                }
                defer { group.cancelAll() }
                guard let result = try await group.next() else { throw ClaudeNativeClientError.network }
                return result
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
        authorization = nil
        pending?.task.cancel()
        let lease = try await authLock.acquire()
        defer { lease.release() }
        try usageStore.writeState(ClaudeNativeUsageState(connectionID: UUID(), snapshot: nil))
        try tokenStore.delete()
    }

    private func activeAuthorization(_ descriptor: ClaudeNativeAuthorization) throws -> PendingAuthorization {
        guard let session = authorization, session.descriptor == descriptor else {
            throw ClaudeNativeClientError.invalidCallback
        }
        guard descriptor.expiresAt > now() else {
            authorization = nil
            throw ClaudeNativeClientError.loginExpired
        }
        return session
    }

    private func exchange(code: String, session: PendingAuthorization) async throws -> ClaudeNativeUsageSnapshot {
        // Consume before suspension: the one-time code must never be exchanged twice.
        authorization = nil
        let id = session.descriptor.id
        let lease = try await authLock.acquire()
        do {
            try checkActive()
            guard try usageStore.readState()?.connectionID == id else { throw ClaudeNativeClientError.connectionChanged }
            let request = try tokenRequest([
                "grant_type": "authorization_code", "client_id": ClaudeNativeConfiguration.clientID,
                "redirect_uri": ClaudeNativeConfiguration.callbackURL.absoluteString,
                "code": code, "state": session.state, "code_verifier": session.verifier
            ])
            let response = try await transport.send(request, maximumBytes: 131_072)
            guard response.statusCode == 200 else { throw Self.httpFailure(response.statusCode) }
            let auth = try Self.parseTokens(response.data, connectionID: id, now: now())
            guard try usageStore.readState()?.connectionID == id else { throw ClaudeNativeClientError.connectionChanged }
            // Preserve a confirmed new grant if the caller was cancelled after HTTP success.
            try tokenStore.save(auth)
            lease.release()
        } catch {
            lease.release()
            throw error
        }
        try checkActive()
        return try await fetchUsage(force: true)
    }

    private func performFetch(force: Bool) async throws -> ClaudeNativeUsageSnapshot {
        try checkActive()
        let lease = try await authLock.acquire()
        defer { lease.release() }
        try checkActive()
        guard let state = try usageStore.readState(), var auth = try tokenStore.load(),
              auth.connectionID == state.connectionID else { throw ClaudeNativeClientError.notAuthenticated }
        guard !auth.refreshUncertain else { throw ClaudeNativeClientError.refreshUncertain }
        guard auth.hasValidFields else { throw ClaudeNativeClientError.loginExpired }
        if !force, let snapshot = state.snapshot, !snapshot.isStale(at: now(), maxAge: 600) { return snapshot }
        var didRefresh = false
        if auth.expiresAt.timeIntervalSince(now()) < 90 {
            auth = try await refresh(auth)
            didRefresh = true
        }
        try checkActive()
        var response = try await transport.send(usageRequest(auth), maximumBytes: 524_288)
        try checkActive()
        if response.statusCode == 401, !didRefresh {
            auth = try await refresh(auth)
            try checkActive()
            response = try await transport.send(usageRequest(auth), maximumBytes: 524_288)
            try checkActive()
        }
        guard response.statusCode == 200 else { throw Self.httpFailure(response.statusCode) }
        let snapshot = try Self.parseUsage(response.data, now: now())
        try checkActive()
        guard try usageStore.readState()?.connectionID == state.connectionID else {
            throw ClaudeNativeClientError.connectionChanged
        }
        try usageStore.writeState(ClaudeNativeUsageState(connectionID: state.connectionID, snapshot: snapshot))
        return snapshot
    }

    /// Hold the process-shared lease and persist uncertainty before spending a rotating token.
    private func refresh(_ current: ClaudeNativeStoredAuth) async throws -> ClaudeNativeStoredAuth {
        try checkActive()
        var uncertain = current
        uncertain.refreshUncertain = true
        try tokenStore.save(uncertain)
        do {
            let response = try await transport.send(try tokenRequest([
                "grant_type": "refresh_token", "client_id": ClaudeNativeConfiguration.clientID,
                "refresh_token": current.refreshToken, "scope": ClaudeNativeConfiguration.scope
            ]), maximumBytes: 131_072)
            guard response.statusCode == 200 else {
                if response.statusCode == 400 || response.statusCode == 401 { throw ClaudeNativeClientError.loginExpired }
                throw ClaudeNativeClientError.refreshUncertain
            }
            // A missing rotated refresh token is never replaced with the old, possibly spent token.
            let replacement = try Self.parseTokens(response.data, connectionID: current.connectionID, now: now())
            guard try usageStore.readState()?.connectionID == current.connectionID else {
                throw ClaudeNativeClientError.connectionChanged
            }
            try tokenStore.save(replacement)
            try Task.checkCancellation()
            return replacement
        } catch let error as ClaudeNativeClientError {
            throw error == .loginExpired ? error : ClaudeNativeClientError.refreshUncertain
        } catch is CancellationError { throw CancellationError() }
        catch { throw ClaudeNativeClientError.refreshUncertain }
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        guard !isDemo() else { throw ClaudeNativeClientError.demoMode }
    }

    private func usageRequest(_ auth: ClaudeNativeStoredAuth) -> URLRequest {
        var request = URLRequest(url: ClaudeNativeConfiguration.usageURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + auth.accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("CodexTime", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func tokenRequest(_ fields: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: ClaudeNativeConfiguration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        return request
    }

    static func parseUsage(_ data: Data, now: Date) throws -> ClaudeNativeUsageSnapshot {
        let object = try object(data, maximumBytes: 524_288)
        func window(_ key: String) throws -> ClaudeNativeUsageWindow {
            guard let fields = object[key] as? [String: Any],
                  let percent = number(fields["utilization"]), (0...100).contains(percent),
                  fields.keys.contains("resets_at") else { throw ClaudeNativeClientError.usageUnavailable }
            let resetAt: Date?
            if fields["resets_at"] is NSNull { resetAt = nil }
            else {
                guard let value = fields["resets_at"] as? String, value.utf8.count <= 128,
                      let date = isoDate(value) else { throw ClaudeNativeClientError.invalidResponse }
                resetAt = date
            }
            return ClaudeNativeUsageWindow(usedPercent: percent, resetAt: resetAt)
        }
        let snapshot = try ClaudeNativeUsageSnapshot(fiveHour: window("five_hour"),
                                                     sevenDay: window("seven_day"), updatedAt: now)
        guard snapshot.isValid(at: now) else { throw ClaudeNativeClientError.invalidResponse }
        return snapshot
    }

    private static func parseTokens(_ data: Data, connectionID: UUID, now: Date) throws -> ClaudeNativeStoredAuth {
        let fields = try object(data, maximumBytes: 131_072)
        guard let access = fields["access_token"] as? String,
              let refresh = fields["refresh_token"] as? String,
              let duration = number(fields["expires_in"]), duration > 0, duration <= 366 * 86_400,
              (fields["token_type"] as? String)?.lowercased() == "bearer" else {
            throw ClaudeNativeClientError.invalidResponse
        }
        if let rawScope = fields["scope"] {
            guard let scope = rawScope as? String, scope.split(separator: " ").contains("user:profile") else {
                throw ClaudeNativeClientError.permissionRequired
            }
        }
        let auth = ClaudeNativeStoredAuth(connectionID: connectionID, accessToken: access, refreshToken: refresh,
                                          expiresAt: now.addingTimeInterval(duration), refreshUncertain: false)
        guard auth.hasValidFields else { throw ClaudeNativeClientError.invalidResponse }
        return auth
    }

    private static func object(_ data: Data, maximumBytes: Int) throws -> [String: Any] {
        guard data.count <= maximumBytes, String(data: data, encoding: .utf8) != nil,
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeNativeClientError.invalidResponse
        }
        return fields
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func challenge(for verifier: String) -> String {
        urlSafe(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ClaudeNativeClientError.secureStorageUnavailable
        }
        return urlSafe(Data(bytes))
    }

    private static func urlSafe(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func validCode(_ value: String) -> Bool {
        value.utf8.count <= 4_096 && ClaudeNativeStoredAuth.validToken(value)
    }

    private static func httpFailure(_ status: Int) -> ClaudeNativeClientError {
        switch status {
        case 400, 401: return .loginExpired
        case 403: return .permissionRequired
        case 429: return .retryLater
        default: return .network
        }
    }
}
