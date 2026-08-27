import Foundation

struct DeviceAuthorization: Identifiable, Equatable, Sendable {
    let deviceAuthID: String
    let userCode: String
    let interval: TimeInterval
    let verificationURL: URL

    var id: String { deviceAuthID }
}
struct AuthTokens: Codable, Equatable, Sendable {
    let idToken: String
    let accessToken: String
    let refreshToken: String
    let updatedAt: Date

    var accountID: String? {
        JWTClaims(token: idToken)?.chatGPTAccountID
    }

    var accessTokenExpiration: Date? {
        JWTClaims(token: accessToken)?.expiration
    }
}

struct JWTClaims {
    let payload: [String: Any]

    init?(token: String) {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }

        var encoded = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = encoded.count % 4
        if padding != 0 {
            encoded += String(repeating: "=", count: 4 - padding)
        }

        guard
            let data = Data(base64Encoded: encoded),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        payload = object
    }

    var expiration: Date? {
        guard let seconds = payload["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    var chatGPTAccountID: String? {
        let auth = payload["https://api.openai.com/auth"] as? [String: Any]
        return auth?["chatgpt_account_id"] as? String
    }
}

enum CodexClientError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidResponse
    case missingAccount
    case loginExpired
    case server(statusCode: Int)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "ChatGPT 연결이 필요합니다."
        case .invalidResponse:
            return "사용량 응답을 확인할 수 없습니다."
        case .missingAccount:
            return "ChatGPT 계정 정보를 확인할 수 없습니다."
        case .loginExpired:
            return "로그인이 만료되었습니다. 다시 연결해 주세요."
        case let .server(statusCode):
            return "서버 응답 오류 (\(statusCode))"
        case let .message(message):
            return message
        }
    }
}
