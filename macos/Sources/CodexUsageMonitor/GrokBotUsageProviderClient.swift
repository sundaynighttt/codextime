import CommonCrypto
import Darwin
import Foundation
import Security

enum GrokBotConnectionStage: String, Sendable {
    case storeUnavailable = "store_unavailable"
    case storeFormatOrActiveMissing = "store_format_or_active_missing"
    case keychainItemMissing = "keychain_item_missing"
    case keychainResultUnavailable = "keychain_result_unavailable"
    case decryptFailed = "decrypt_failed"
    case tokenMalformed = "token_malformed"
    case tokenExpired = "token_expired"
    case teamContextInvalid = "team_context_invalid"
    case httpAuthRejected = "http_auth_rejected"
    case quotaResponseInvalid = "quota_response_invalid"
    case permissionRequired = "permission_required"
    case permissionDenied = "permission_denied"
    case requestFailed = "request_failed"
}

/// Fixed stages only: never stores a token, account, path, OSStatus, or body.
final class GrokBotConnectionDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var value: GrokBotConnectionStage?
    var stage: GrokBotConnectionStage? {
        lock.lock(); defer { lock.unlock() }; return value
    }
    func record(_ stage: GrokBotConnectionStage) {
        lock.lock(); defer { lock.unlock() }; value = stage
    }
    func reset() { lock.lock(); defer { lock.unlock() }; value = nil }
}

enum GrokBotKeychainReadFailure: Error { case itemMissing, resultUnavailable }

/// Uses only Grok Bot's installed-account quota RPC. No login, refresh, migration,
/// cookie access, credential export, or credential writes are performed here.
struct GrokBotUsageProviderClient: UsageProviderClient {
    let id: ProviderID = .grok
    static let endpoint = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus")!

    private let credentials: any GrokBotCredentialSource
    private let transport: any GrokBotUsageTransport
    private let now: @Sendable () -> Date
    private let diagnostics: GrokBotConnectionDiagnostics?

    init(
        allowAuthenticationUI: Bool = false,
        credentials: (any GrokBotCredentialSource)? = nil,
        transport: any GrokBotUsageTransport = GrokBotURLSessionTransport(),
        now: @escaping @Sendable () -> Date = { Date() },
        diagnostics: GrokBotConnectionDiagnostics? = nil
    ) {
        self.credentials = credentials ?? GrokBotStoredCredentials(allowAuthenticationUI: allowAuthenticationUI, diagnostics: diagnostics)
        self.transport = transport
        self.now = now
        self.diagnostics = diagnostics
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        diagnostics?.reset()
        do {
            try Task.checkCancellation()
            let authorization = try await readAuthorizationOffMainThread()
            let token = authorization.accessToken
            try Task.checkCancellation()
            if let stage = Self.accessTokenFailure(token, now: now()) {
                diagnostics?.record(stage)
                throw ProviderUsageFailure.authenticationRequired
            }
            var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.httpShouldHandleCookies = false
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let teamID = authorization.selectedTeamID {
                request.setValue(String(teamID), forHTTPHeaderField: "x-cursor-team-id")
            }
            let response = try await transport.send(request)
            try Task.checkCancellation()
            switch response.statusCode {
            case 200:
                do { return try Self.decodeQuota(response.body) }
                catch { diagnostics?.record(.quotaResponseInvalid); throw error }
            case 401, 403:
                diagnostics?.record(.httpAuthRejected)
                throw ProviderUsageFailure.authenticationRequired
            case 408, 504:
                throw ProviderUsageFailure.timeout
            default:
                throw ProviderUsageFailure.queryFailed
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProviderUsageFailure {
            if diagnostics?.stage == nil {
                diagnostics?.record(failure == .permissionDenied ? .permissionDenied : failure == .permissionRequired ? .permissionRequired : .requestFailed)
            }
            throw failure
        } catch let error as URLError {
            diagnostics?.record(.requestFailed)
            if Task.isCancelled { throw CancellationError() }
            throw error.code == .timedOut ? ProviderUsageFailure.timeout : .queryFailed
        } catch {
            // Never publish raw errors, HTTP bodies, filesystem paths, or tokens.
            diagnostics?.record(.requestFailed)
            throw ProviderUsageFailure.queryFailed
        }
    }

    private func readAuthorizationOffMainThread() async throws -> GrokBotAuthorization {
        let source = credentials
        let work = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let result = try source.readAuthorization()
            try Task.checkCancellation()
            return result
        }
        // Always await the owned worker, including cancellation. A user-visible
        // OS permission dialog must resolve before this provider is retried.
        return try await withTaskCancellationHandler {
            let result = try await work.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            work.cancel()
        }
    }

    static func isUnexpiredAccessToken(_ token: String, now: Date) -> Bool {
        accessTokenFailure(token, now: now) == nil
    }

    private static func accessTokenFailure(_ token: String, now: Date) -> GrokBotConnectionStage? {
        guard token.utf8.count <= 32_768,
              !token.contains(where: { $0.isWhitespace || $0.isNewline }) else { return .tokenMalformed }
        let pieces = token.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, !pieces[0].isEmpty, !pieces[2].isEmpty,
              pieces[1].utf8.count <= 16_384 else { return .tokenMalformed }
        var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let expiry = try? JSONDecoder().decode(TokenExpiry.self, from: data),
              expiry.exp.isFinite else { return .tokenMalformed }
        // This is an expiry check, not JWT signature verification. The official
        // service authenticates the token. Expired tokens are never refreshed.
        return expiry.exp > now.timeIntervalSince1970 + 30 ? nil : .tokenExpired
    }

    static func decodeQuota(_ data: Data) throws -> ProviderUsageSnapshot {
        guard data.count <= 65_536,
              let quota = try? JSONDecoder().decode(Quota.self, from: data) else {
            throw ProviderUsageFailure.invalidResponse
        }
        guard quota.usesPooledEnterpriseAllowance != true else {
            throw ProviderUsageFailure.unsupported
        }
        guard let used = quota.usagePercent, used.isFinite, (0...100).contains(used) else {
            throw ProviderUsageFailure.invalidResponse
        }
        let reset = quota.nextResetTimestampUtc.flatMap { value -> Date? in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let result = formatter.date(from: value) { return result }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: value)
        }
        return ProviderUsageSnapshot(provider: .grok, windows: [
            ProviderUsageWindow(
                id: "weekly", label: quota.isUnified == true ? "공유 주간 한도" : "Grok Bot 주간 한도",
                remainingPercent: 100 - used, resetDate: reset, durationMinutes: 10_080
            )
        ])
    }

    private struct TokenExpiry: Decodable { let exp: Double }
    private struct Quota: Decodable {
        let usagePercent: Double?
        let nextResetTimestampUtc: String?
        let usesPooledEnterpriseAllowance: Bool?
        let isUnified: Bool?
    }
}

struct GrokBotAuthorization: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let accessToken: String
    let selectedTeamID: Int?
    init(accessToken: String, selectedTeamID: Int? = nil) {
        self.accessToken = accessToken
        self.selectedTeamID = selectedTeamID
    }
    var description: String { "GrokBotAuthorization(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: ["accessToken": "<redacted>", "selectedTeamID": "<redacted>"], displayStyle: .struct)
    }
}

protocol GrokBotCredentialSource: Sendable {
    func readAuthorization() throws -> GrokBotAuthorization
}

protocol GrokBotPermissionState: Sendable {
    func isDenied() -> Bool
    func setDenied(_ denied: Bool)
}

struct GrokBotSavedPermissionState: GrokBotPermissionState {
    private static let key = "grokBotKeychainAccessDenied"
    func isDenied() -> Bool { UserDefaults.standard.bool(forKey: Self.key) }
    func setDenied(_ denied: Bool) { UserDefaults.standard.set(denied, forKey: Self.key) }
}

private final class GrokBotAuthenticationUIAllowance: @unchecked Sendable {
    private let lock = NSLock()
    private var available: Bool
    init(_ available: Bool) { self.available = available }
    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let result = available
        available = false
        return result
    }
}

struct GrokBotStoredCredentials: GrokBotCredentialSource {
    static let keychainService = "Grok Bot Safe Storage"
    static let keychainAccount = "Grok Bot"
    private let readStore: @Sendable () throws -> Data
    private let readPassword: @Sendable (Bool) throws -> Data
    private let permission: any GrokBotPermissionState
    private let authenticationUI: GrokBotAuthenticationUIAllowance
    private let diagnostics: GrokBotConnectionDiagnostics?

    init(
        allowAuthenticationUI: Bool = false,
        readStore: @escaping @Sendable () throws -> Data = { try Self.readApprovedStore() },
        readPassword: @escaping @Sendable (Bool) throws -> Data = { try Self.readApprovedKeychainItem($0) },
        permission: any GrokBotPermissionState = GrokBotSavedPermissionState(),
        diagnostics: GrokBotConnectionDiagnostics? = nil
    ) {
        self.readStore = readStore
        self.readPassword = readPassword
        self.permission = permission
        authenticationUI = GrokBotAuthenticationUIAllowance(allowAuthenticationUI)
        self.diagnostics = diagnostics
    }

    func readAuthorization() throws -> GrokBotAuthorization {
        do {
            let allowUI = authenticationUI.consume()
            if allowUI { permission.setDenied(false) }
            if permission.isDenied() {
                diagnostics?.record(.permissionDenied)
                throw ProviderUsageFailure.permissionDenied
            }
            let store: Data
            do { store = try readStore() }
            catch { diagnostics?.record(.storeUnavailable); throw ProviderUsageFailure.authenticationRequired }
            let selection: StoredToken
            let ciphertext: Data
            do {
                guard store.count <= 1_048_576 else { throw ProviderUsageFailure.authenticationRequired }
                selection = try JSONDecoder().decode(StoredToken.self, from: store)
                ciphertext = try Self.ciphertext(selection.value, expectedScope: selection.scope)
            } catch {
                diagnostics?.record(.storeFormatOrActiveMissing)
                throw (error as? ProviderUsageFailure) ?? .authenticationRequired
            }
            var password: Data
            do { password = try readPassword(allowUI) }
            catch ProviderUsageFailure.permissionDenied {
                permission.setDenied(true)
                diagnostics?.record(.permissionDenied)
                throw ProviderUsageFailure.permissionDenied
            } catch ProviderUsageFailure.permissionRequired {
                diagnostics?.record(.permissionRequired)
                throw ProviderUsageFailure.permissionRequired
            } catch GrokBotKeychainReadFailure.itemMissing {
                diagnostics?.record(.keychainItemMissing)
                throw ProviderUsageFailure.authenticationRequired
            } catch {
                diagnostics?.record(.keychainResultUnavailable)
                throw ProviderUsageFailure.authenticationRequired
            }
            defer { password.resetBytes(in: 0..<password.count) }
            var plaintext: Data
            do { plaintext = try GrokBotSafeStorage.decrypt(ciphertext, password: password) }
            catch { diagnostics?.record(.decryptFailed); throw ProviderUsageFailure.authenticationRequired }
            defer { plaintext.resetBytes(in: 0..<plaintext.count) }
            guard let token = String(data: plaintext, encoding: .utf8), !token.isEmpty else {
                diagnostics?.record(.tokenMalformed)
                throw ProviderUsageFailure.authenticationRequired
            }
            let selectedTeamID: Int?
            if let storedTeam = selection.selectedTeam {
                do {
                    let encryptedTeam = try Self.ciphertext(storedTeam, expectedScope: selection.scope)
                    var teamData = try GrokBotSafeStorage.decrypt(encryptedTeam, password: password)
                    defer { teamData.resetBytes(in: 0..<teamData.count) }
                    guard let value = String(data: teamData, encoding: .utf8),
                          let number = Int(value), number > 0 else {
                        throw ProviderUsageFailure.authenticationRequired
                    }
                    selectedTeamID = number
                } catch {
                    diagnostics?.record(.teamContextInvalid)
                    throw (error as? ProviderUsageFailure) ?? .authenticationRequired
                }
            } else { selectedTeamID = nil }
            return GrokBotAuthorization(accessToken: token, selectedTeamID: selectedTeamID)
        } catch let failure as ProviderUsageFailure {
            throw failure
        } catch {
            throw ProviderUsageFailure.authenticationRequired
        }
    }

    static func ciphertext(_ stored: String, expectedScope: String?) throws -> Data {
        guard !stored.hasPrefix("plaintext:") else { throw ProviderUsageFailure.unsupported }
        let encoded: String
        if stored.hasPrefix("scoped:v1:") {
            let fields = stored.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4, fields[2].count == 64,
                  fields[2].allSatisfy({ $0.isHexDigit }),
                  expectedScope == nil || String(fields[2]) == expectedScope else {
                throw ProviderUsageFailure.authenticationRequired
            }
            encoded = String(fields[3])
        } else {
            encoded = stored
        }
        guard let data = Data(base64Encoded: encoded), data.starts(with: Data("v10".utf8)),
              data.count > 3, (data.count - 3) % kCCBlockSizeAES128 == 0 else {
            throw ProviderUsageFailure.unsupported
        }
        return data
    }

    private static func readApprovedStore() throws -> Data {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot/sand-secrets.json").path
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw ProviderUsageFailure.authenticationRequired }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size > 0, metadata.st_size <= 1_048_576 else {
            throw ProviderUsageFailure.authenticationRequired
        }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { return result }
            if count < 0 {
                if errno == EINTR { continue }
                throw ProviderUsageFailure.authenticationRequired
            }
            guard result.count + count <= 1_048_576 else {
                throw ProviderUsageFailure.authenticationRequired
            }
            result.append(contentsOf: buffer.prefix(count))
        }
    }

    private static func readApprovedKeychainItem(_ allowAuthenticationUI: Bool) throws -> Data {
        // Electron 42.1.0 sets service=app_name+" Safe Storage", account=app_name.
        // SecItemCopyMatching alone never creates or modifies a Keychain item.
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
            kSecUseAuthenticationUI: allowAuthenticationUI ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail,
            kSecUseOperationPrompt: "CodexTime에서 Grok Bot 사용량을 조회합니다."
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { throw GrokBotKeychainReadFailure.itemMissing }
        if let failure = Self.keychainFailure(for: status) { throw failure }
        guard status == errSecSuccess, let data = result as? Data, !data.isEmpty else {
            // A denial is final for this attempt. Never try Chrome, another
            // account/service, an unencrypted token, or a new Keychain item.
            throw GrokBotKeychainReadFailure.resultUnavailable
        }
        return data
    }

    static func keychainFailure(for status: OSStatus) -> ProviderUsageFailure? {
        switch status {
        case errSecSuccess: return nil
        case errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem: return .permissionDenied
        case errSecInteractionNotAllowed: return .permissionRequired
        default: return .authenticationRequired
        }
    }

    /// Decode only the access-token field. Refresh tokens and other accounts'
    /// credential values are never decoded or decrypted.
    private struct StoredToken: Decodable {
        let value: String
        let scope: String?
        let selectedTeam: String?
        private enum Keys: String, CodingKey { case version; case accounts = "cursor-accounts"; case access = "cursor-access-token"; case team = "cursor-selected-team-id" }
        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Keys.self)
            if let version = try root.decodeIfPresent(Int.self, forKey: .version), version != 1 {
                throw ProviderUsageFailure.unsupported
            }
            if root.contains(.accounts) {
                let encoded = try root.decode(String.self, forKey: .accounts)
                guard let data = encoded.data(using: .utf8), data.count <= 1_048_576 else {
                    throw ProviderUsageFailure.authenticationRequired
                }
                let account = try JSONDecoder().decode(ActiveAccount.self, from: data)
                value = account.value
                scope = account.scope
                selectedTeam = account.selectedTeam
            } else {
                // Matches the installed app's single-account legacy store, but
                // still requires OS-encrypted v10 data and never migrates it.
                value = try root.decode(String.self, forKey: .access)
                scope = nil
                selectedTeam = try root.decodeIfPresent(String.self, forKey: .team)
            }
        }
    }

    private struct ActiveAccount: Decodable {
        let value: String
        let scope: String
        let selectedTeam: String?
        private enum Keys: String, CodingKey { case active, accounts }
        private struct AccountKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(_ value: String) { stringValue = value }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: Keys.self)
            scope = try root.decode(String.self, forKey: .active)
            guard scope.count == 64, scope.allSatisfy({ $0.isHexDigit }) else {
                throw ProviderUsageFailure.authenticationRequired
            }
            let accounts = try root.nestedContainer(keyedBy: AccountKey.self, forKey: .accounts)
            let active = try accounts.nestedContainer(keyedBy: AccountKey.self, forKey: AccountKey(scope))
            value = try active.decode(String.self, forKey: AccountKey("cursor-access-token"))
            selectedTeam = try active.decodeIfPresent(String.self, forKey: AccountKey("cursor-selected-team-id"))
        }
    }
}

enum GrokBotSafeStorage {
    // Electron 42.1.0 uses Chromium 148.0.7778.97 OSCrypt sync on macOS:
    // PBKDF2-HMAC-SHA1(password, "saltysalt", 1003, 16), AES-128-CBC/PKCS7,
    // a sixteen-space IV, and the v10 prefix. Unknown formats fail closed.
    static func decrypt(_ data: Data, password: Data) throws -> Data {
        guard data.starts(with: Data("v10".utf8)), data.count > 3,
              (data.count - 3) % kCCBlockSizeAES128 == 0, !password.isEmpty else {
            throw ProviderUsageFailure.unsupported
        }
        let salt = Array("saltysalt".utf8)
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        defer { _ = key.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        let derived = password.withUnsafeBytes { passwordBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2), passwordBytes.bindMemory(to: Int8.self).baseAddress,
                password.count, salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                1003, &key, key.count
            )
        }
        guard derived == kCCSuccess else { throw ProviderUsageFailure.authenticationRequired }
        let ciphertext = Data(data.dropFirst(3))
        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: ciphertext.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { inputBytes in
                CCCrypt(
                    CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    key, key.count, iv, inputBytes.baseAddress, ciphertext.count,
                    outputBytes.baseAddress, capacity, &written
                )
            }
        }
        guard status == kCCSuccess else {
            output.resetBytes(in: 0..<output.count)
            throw ProviderUsageFailure.authenticationRequired
        }
        output.count = written
        return output
    }
}

struct GrokBotUsageHTTPResponse: Sendable {
    let statusCode: Int
    let body: Data
}

protocol GrokBotUsageTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GrokBotUsageHTTPResponse
}

struct GrokBotURLSessionTransport: GrokBotUsageTransport {
    func send(_ request: URLRequest) async throws -> GrokBotUsageHTTPResponse {
        guard request.url == GrokBotUsageProviderClient.endpoint, request.httpMethod == "POST" else {
            throw ProviderUsageFailure.queryFailed
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ProviderUsageFailure.invalidResponse }
        guard response.statusCode == 200 else {
            return GrokBotUsageHTTPResponse(statusCode: response.statusCode, body: Data())
        }
        guard response.mimeType?.lowercased() == "application/json" else {
            throw ProviderUsageFailure.invalidResponse
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 65_536 else { throw ProviderUsageFailure.invalidResponse }
            data.append(byte)
        }
        return GrokBotUsageHTTPResponse(statusCode: response.statusCode, body: data)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) { completionHandler(nil) }
    }
}
