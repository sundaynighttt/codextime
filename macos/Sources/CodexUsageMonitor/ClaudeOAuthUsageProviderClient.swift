import CoreFoundation
import Foundation
import Security

/// A credential is used only inside the app. It is intentionally not Codable,
/// printable, persisted, included in provider snapshots, or sent to diagnostics.
struct ClaudeUsageCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    fileprivate let accessToken: String
    let expiresAt: Date
    var description: String { "ClaudeUsageCredential(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: ["credential": "redacted"]) }

    init(accessToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }
}

protocol ClaudeUsageCredentialSource: Sendable {
    func loadCredential(now: Date) async throws -> ClaudeUsageCredential
}

/// Reads only the default Claude Code credential item for the current local
/// user. Custom profiles, auth files and browser credentials are not searched.
struct ClaudeUsageKeychainSource: ClaudeUsageCredentialSource {
    static let service = "Claude Code-credentials"
    private let allowAuthenticationUI: Bool
    private let permissionState: ClaudeUsageKeychainPermissionState

    /// Use true only for a user-initiated connection action. Background refreshes
    /// fail without prompting when macOS has not granted access to this app.
    init(allowAuthenticationUI: Bool = false,
         permissionState: ClaudeUsageKeychainPermissionState = .shared) {
        self.allowAuthenticationUI = allowAuthenticationUI
        self.permissionState = permissionState
    }

    func loadCredential(now: Date) async throws -> ClaudeUsageCredential {
        try await ClaudeUsageKeychainReader.shared.read(now: now, allowAuthenticationUI: allowAuthenticationUI,
                                                       permissionState: permissionState)
    }
}

/// Stores only a fixed denial bit, never credentials or private account data.
final class ClaudeUsageKeychainPermissionState: @unchecked Sendable {
    static let shared = ClaudeUsageKeychainPermissionState()
    static let deniedKey = "claudeUsageKeychainAccessDenied"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func beginAttempt(allowAuthenticationUI: Bool) throws {
        if allowAuthenticationUI {
            // An explicit connect action authorizes exactly one new access attempt.
            defaults.removeObject(forKey: Self.deniedKey)
        } else if defaults.bool(forKey: Self.deniedKey) {
            throw ProviderUsageFailure.permissionDenied
        }
    }

    func failure(for status: OSStatus) -> ProviderUsageFailure {
        switch status {
        case errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem:
            defaults.set(true, forKey: Self.deniedKey)
            return .permissionDenied
        case errSecInteractionNotAllowed: return .permissionRequired
        case errSecItemNotFound: return .authenticationRequired
        default: return .queryFailed
        }
    }
}

private actor ClaudeUsageKeychainReader {
    static let shared = ClaudeUsageKeychainReader()
    private var pending: (id: UUID, task: Task<ClaudeUsageCredential, Error>)?

    func read(now: Date, allowAuthenticationUI: Bool,
              permissionState: ClaudeUsageKeychainPermissionState) async throws -> ClaudeUsageCredential {
        try Task.checkCancellation()
        if let pending {
            let credential = try await pending.task.value
            try Task.checkCancellation()
            return credential
        }
        try permissionState.beginAttempt(allowAuthenticationUI: allowAuthenticationUI)
        let id = UUID()
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let rawAccount = NSUserName()
            let account = rawAccount.range(of: #"^[a-zA-Z0-9._-]+$"#, options: .regularExpression) != nil
                ? rawAccount : "claude-code-user"
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: ClaudeUsageKeychainSource.service,
                kSecAttrAccount as String: account,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true,
                kSecUseAuthenticationUI as String:
                    allowAuthenticationUI ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            guard status == errSecSuccess else { throw permissionState.failure(for: status) }
            guard let data = result as? Data, data.count <= 65_536 else {
                throw ProviderUsageFailure.authenticationRequired
            }
            return try ClaudeUsageCredentialParser.parse(data: data, now: now)
        }
        pending = (id, task)
        // A macOS access dialog is an OS-owned user interaction and may remain
        // pending until answered. Do not orphan it or launch duplicate reads.
        let result = await task.result
        if pending?.id == id { pending = nil }
        try Task.checkCancellation()
        return try result.get()
    }
}

enum ClaudeUsageCredentialParser {
    static func parse(data: Data, now: Date) throws -> ClaudeUsageCredential {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty, token.utf8.count <= 16_384,
              !token.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0)
                    || CharacterSet.controlCharacters.contains($0) }),
              let expiryNumber = oauth["expiresAt"] as? NSNumber,
              CFGetTypeID(expiryNumber) != CFBooleanGetTypeID(), expiryNumber.doubleValue.isFinite
        else { throw ProviderUsageFailure.authenticationRequired }
        let expiry = Date(timeIntervalSince1970: expiryNumber.doubleValue / 1_000)
        guard expiry > now.addingTimeInterval(15) else {
            // Token renewal remains the official CLI's responsibility.
            throw ProviderUsageFailure.authenticationRequired
        }
        guard let scopes = oauth["scopes"] as? [String], scopes.contains("user:profile") else {
            throw ProviderUsageFailure.unsupported
        }
        return ClaudeUsageCredential(accessToken: token, expiresAt: expiry)
    }
}

struct ClaudeUsageHTTPResponse: Sendable {
    let statusCode: Int
    let data: Data
}

protocol ClaudeUsageTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> ClaudeUsageHTTPResponse
}

/// The only network destination is the CLI's usage endpoint. It is an internal
/// service API rather than a published external API and may change independently.
struct ClaudeOAuthUsageProviderClient: UsageProviderClient {
    let id: ProviderID = .claude
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let requestTimeout: TimeInterval = 8
    private let credentials: any ClaudeUsageCredentialSource
    private let transport: any ClaudeUsageTransport
    private let now: @Sendable () -> Date

    init(
        credentials: any ClaudeUsageCredentialSource = ClaudeUsageKeychainSource(),
        transport: any ClaudeUsageTransport = ClaudeUsageEphemeralTransport(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.transport = transport
        self.now = now
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        do {
            try Task.checkCancellation()
            let credential = try await credentials.loadCredential(now: now())
            try Task.checkCancellation()
            guard credential.expiresAt > now().addingTimeInterval(15) else {
                throw ProviderUsageFailure.authenticationRequired
            }
            var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: Self.requestTimeout)
            request.httpMethod = "GET"
            request.httpShouldHandleCookies = false
            request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let response = try await transport.fetch(request)
            try Task.checkCancellation()
            switch response.statusCode {
            case 200: return try ClaudeOAuthUsageParser.parse(data: response.data)
            case 401, 403: throw ProviderUsageFailure.authenticationRequired
            default: throw ProviderUsageFailure.queryFailed
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProviderUsageFailure {
            throw failure
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw ProviderUsageFailure.timeout
        } catch {
            // Never surface OS/network messages or response bodies.
            throw ProviderUsageFailure.queryFailed
        }
    }
}

struct ClaudeUsageEphemeralTransport: ClaudeUsageTransport {
    func fetch(_ request: URLRequest) async throws -> ClaudeUsageHTTPResponse {
        guard request.url == ClaudeOAuthUsageProviderClient.endpoint,
              request.httpMethod == "GET", request.httpBody == nil else {
            throw ProviderUsageFailure.unsupported
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = ClaudeOAuthUsageProviderClient.requestTimeout
        configuration.timeoutIntervalForResource = ClaudeOAuthUsageProviderClient.requestTimeout
        let delegate = ClaudeUsageSessionDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.url == ClaudeOAuthUsageProviderClient.endpoint else {
            throw ProviderUsageFailure.invalidResponse
        }
        // Error bodies may contain account details; do not download or parse them.
        guard response.statusCode == 200 else {
            return ClaudeUsageHTTPResponse(statusCode: response.statusCode, data: Data())
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 262_144 else { throw ProviderUsageFailure.invalidResponse }
            data.append(byte)
        }
        return ClaudeUsageHTTPResponse(statusCode: response.statusCode, data: data)
    }
}

final class ClaudeUsageSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward the bearer to a redirect, including a same-host redirect.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.host == "api.anthropic.com",
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

enum ClaudeOAuthUsageParser {
    static func parse(data: Data) throws -> ProviderUsageSnapshot {
        guard data.count <= 262_144,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderUsageFailure.invalidResponse
        }
        let fields: [(String, String, Int)] = [
            ("five_hour", "단기 한도", 300), ("seven_day", "주간 한도", 10_080),
            ("seven_day_sonnet", "Sonnet 주간 한도", 10_080),
            ("seven_day_opus", "Opus 주간 한도", 10_080)
        ]
        let windows = fields.compactMap { key, label, duration -> ProviderUsageWindow? in
            guard let value = root[key] as? [String: Any] else { return nil }
            let remaining: Double?
            if let used = value["utilization"] as? NSNumber,
               CFGetTypeID(used) != CFBooleanGetTypeID(), used.doubleValue.isFinite,
               (0...100).contains(used.doubleValue) {
                remaining = 100 - used.doubleValue
            } else { remaining = nil }
            return ProviderUsageWindow(id: key, label: label, remainingPercent: remaining,
                                       resetDate: resetDate(value["resets_at"]), durationMinutes: duration,
                                       countsTowardSummary: key == "five_hour" || key == "seven_day")
        }
        guard !windows.isEmpty else { throw ProviderUsageFailure.invalidResponse }
        // Identity, spend, credits, arbitrary labels, and all other API fields
        // are excluded from app state and diagnostics.
        return ProviderUsageSnapshot(provider: .claude, windows: windows)
    }

    private static func resetDate(_ value: Any?) -> Date? {
        guard let value = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }
}
