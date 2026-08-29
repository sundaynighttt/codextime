import Foundation

actor CodexAccountClient {
    private let session: URLSession
    private let tokenStore: KeychainTokenStore
    private let usageStore: SharedUsageStore

    init(
        session: URLSession = .shared,
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        usageStore: SharedUsageStore = SharedUsageStore()
    ) {
        self.session = session
        self.tokenStore = tokenStore
        self.usageStore = usageStore
    }

    func isAuthenticated() -> Bool {
        (try? tokenStore.load()) != nil
    }

    func requestDeviceAuthorization() async throws -> DeviceAuthorization {
        let url = CodexConfiguration.authBaseURL
            .appending(path: "api/accounts/deviceauth/usercode")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeviceCodeRequest(clientID: CodexConfiguration.clientID))

        let (data, response) = try await session.data(for: request)
        try validate(response)
        let payload = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)

        return DeviceAuthorization(
            deviceAuthID: payload.deviceAuthID,
            userCode: payload.userCode,
            interval: TimeInterval(max(1, payload.interval)),
            verificationURL: CodexConfiguration.authBaseURL.appending(path: "codex/device")
        )
    }

    func completeDeviceAuthorization(_ authorization: DeviceAuthorization) async throws -> UsageSnapshot {
        let grant = try await pollForAuthorizationCode(authorization)
        let tokens = try await exchange(grant)
        guard tokens.accountID != nil else {
            throw CodexClientError.missingAccount
        }
        try tokenStore.save(tokens)
        return try await fetchUsage()
    }

    func fetchUsage() async throws -> UsageSnapshot {
        guard var tokens = try tokenStore.load() else {
            throw CodexClientError.notAuthenticated
        }

        if tokens.accessTokenExpiration?.timeIntervalSinceNow ?? 0 < 90 {
            tokens = try await refresh(tokens)
        }

        do {
            return try await requestUsage(tokens: tokens)
        } catch CodexClientError.server(statusCode: 401) {
            tokens = try await refresh(tokens)
            return try await requestUsage(tokens: tokens)
        }
    }

    func signOut() throws {
        try tokenStore.delete()
        usageStore.delete()
    }

    private func pollForAuthorizationCode(
        _ authorization: DeviceAuthorization
    ) async throws -> AuthorizationGrant {
        let url = CodexConfiguration.authBaseURL
            .appending(path: "api/accounts/deviceauth/token")
        let deadline = Date().addingTimeInterval(15 * 60)

        while Date() < deadline {
            try Task.checkCancellation()

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                DeviceTokenPollRequest(
                    deviceAuthID: authorization.deviceAuthID,
                    userCode: authorization.userCode
                )
            )

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                try Task.checkCancellation()
                guard DeviceAuthorizationRetryPolicy.shouldRetry(error) else {
                    throw error
                }
                try await waitForNextAuthorizationPoll(
                    interval: authorization.interval,
                    deadline: deadline
                )
                continue
            }

            guard let http = response as? HTTPURLResponse else {
                throw CodexClientError.invalidResponse
            }

            if (200..<300).contains(http.statusCode) {
                return try JSONDecoder().decode(AuthorizationGrant.self, from: data)
            }
            if http.statusCode != 403 && http.statusCode != 404 {
                throw CodexClientError.server(statusCode: http.statusCode)
            }

            try await waitForNextAuthorizationPoll(
                interval: authorization.interval,
                deadline: deadline
            )
        }

        throw CodexClientError.loginExpired
    }

    private func waitForNextAuthorizationPoll(
        interval: TimeInterval,
        deadline: Date
    ) async throws {
        let delay = min(interval, max(0, deadline.timeIntervalSinceNow))
        guard delay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    private func exchange(_ grant: AuthorizationGrant) async throws -> AuthTokens {
        let url = CodexConfiguration.authBaseURL.appending(path: "oauth/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "grant_type": "authorization_code",
            "code": grant.authorizationCode,
            "redirect_uri": CodexConfiguration.authBaseURL
                .appending(path: "deviceauth/callback").absoluteString,
            "client_id": CodexConfiguration.clientID,
            "code_verifier": grant.codeVerifier,
        ])

        let (data, response) = try await session.data(for: request)
        try validate(response)
        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthTokens(
            idToken: payload.idToken,
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            updatedAt: Date()
        )
    }

    private func refresh(_ current: AuthTokens) async throws -> AuthTokens {
        var request = URLRequest(url: CodexConfiguration.authBaseURL.appending(path: "oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            RefreshRequest(
                clientID: CodexConfiguration.clientID,
                grantType: "refresh_token",
                refreshToken: current.refreshToken
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexClientError.invalidResponse
        }
        if http.statusCode == 400 || http.statusCode == 401 {
            throw CodexClientError.loginExpired
        }
        try validate(http)

        let payload = try JSONDecoder().decode(RefreshResponse.self, from: data)
        guard let accessToken = payload.accessToken else {
            throw CodexClientError.invalidResponse
        }
        let tokens = AuthTokens(
            idToken: payload.idToken ?? current.idToken,
            accessToken: accessToken,
            refreshToken: payload.refreshToken ?? current.refreshToken,
            updatedAt: Date()
        )
        try tokenStore.save(tokens)
        return tokens
    }

    private func requestUsage(tokens: AuthTokens) async throws -> UsageSnapshot {
        guard let accountID = tokens.accountID else {
            throw CodexClientError.missingAccount
        }

        var request = URLRequest(url: CodexConfiguration.usageURL)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("codextime-ios/0.3.0-alpha.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validate(response)
        let payload = try JSONDecoder().decode(UsagePayload.self, from: data)
        let snapshot = try payload.snapshot()
        usageStore.save(snapshot)
        return snapshot
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CodexClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CodexClientError.server(statusCode: http.statusCode)
        }
    }

    private func formEncoded(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = values
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}

enum DeviceAuthorizationRetryPolicy {
    private static let retryableCodes: Set<URLError.Code> = [
        .cancelled,
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed,
        .notConnectedToInternet,
        .secureConnectionFailed,
    ]

    static func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return retryableCodes.contains(urlError.code)
    }
}

private struct DeviceCodeRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

struct DeviceCodeResponse: Decodable {
    let deviceAuthID: String
    let userCode: String
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
        case legacyUserCode = "usercode"
        case interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        userCode = try container.decodeIfPresent(String.self, forKey: .userCode)
            ?? container.decode(String.self, forKey: .legacyUserCode)
        if let int = try? container.decode(Int.self, forKey: .interval) {
            interval = int
        } else {
            let value = try container.decode(String.self, forKey: .interval)
            guard let int = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .interval,
                    in: container,
                    debugDescription: "interval must be an integer"
                )
            }
            interval = int
        }
    }
}

private struct DeviceTokenPollRequest: Encodable {
    let deviceAuthID: String
    let userCode: String

    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id"
        case userCode = "user_code"
    }
}

private struct AuthorizationGrant: Decodable {
    let authorizationCode: String
    let codeVerifier: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
        case codeVerifier = "code_verifier"
    }
}

private struct TokenResponse: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private struct RefreshRequest: Encodable {
    let clientID: String
    let grantType: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
    }
}

private struct RefreshResponse: Decodable {
    let idToken: String?
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}
