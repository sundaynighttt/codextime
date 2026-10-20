import Foundation

/// Offline compatibility candidate, not an Anthropic-approved third-party OAuth integration.
/// Protocol constants describe public native-client precedents. No model endpoint is available.
enum ClaudeNativeConfiguration {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let scope = "user:profile"
    static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    static let callbackURL = URL(string: "https://platform.claude.com/oauth/code/callback")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "com.sundaynighttt.codextime.claude-native.tokens"
    static let keychainAccount = "claude-subscription"
}

/// The verifier stays in the client actor. This value cannot complete another client's login.
struct ClaudeNativeAuthorization: Equatable, Sendable, Identifiable {
    let id: UUID
    let authorizationURL: URL
    let expiresAt: Date
}

struct ClaudeNativeUsageWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let resetAt: Date?
    var remainingPercent: Double { 100 - usedPercent }

    fileprivate func isValid(updatedAt: Date) -> Bool {
        usedPercent.isFinite && (0...100).contains(usedPercent)
            && (resetAt.map { $0.timeIntervalSince1970.isFinite && $0 > updatedAt
                && $0.timeIntervalSince(updatedAt) < 366 * 86_400 } ?? true)
    }
}

/// Both windows and their observation time are accepted and replaced together.
struct ClaudeNativeUsageSnapshot: Codable, Equatable, Sendable {
    let fiveHour: ClaudeNativeUsageWindow
    let sevenDay: ClaudeNativeUsageWindow
    let updatedAt: Date

    func isValid(at now: Date) -> Bool {
        updatedAt.timeIntervalSince1970.isFinite && updatedAt.timeIntervalSince1970 >= 0
            && now.timeIntervalSince1970.isFinite && updatedAt <= now
            && fiveHour.isValid(updatedAt: updatedAt) && sevenDay.isValid(updatedAt: updatedAt)
    }

    func isStale(at now: Date, maxAge: TimeInterval = 1_200) -> Bool {
        !isValid(at: now) || !maxAge.isFinite || maxAge < 0
            || now.timeIntervalSince(updatedAt) >= maxAge
            || [fiveHour.resetAt, sevenDay.resetAt].compactMap { $0 }.contains { $0 <= now }
    }
}

enum ClaudeNativeClientError: LocalizedError, Equatable, Sendable {
    case notAuthenticated, loginExpired, authorizationDenied, invalidResponse, invalidCallback
    case usageUnavailable, permissionRequired, retryLater, connectionChanged, secureStorageUnavailable
    case refreshUncertain, network, demoMode, busy

    var requiresSignIn: Bool {
        switch self {
        case .notAuthenticated, .loginExpired, .authorizationDenied, .refreshUncertain: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Claude 연결이 필요합니다."
        case .loginExpired: return "Claude 로그인이 만료되었습니다. 다시 연결해 주세요."
        case .authorizationDenied: return "Claude 연결이 승인되지 않았습니다."
        case .invalidResponse: return "Claude 응답을 확인할 수 없습니다."
        case .invalidCallback: return "진행 중인 Claude 로그인과 일치하는 인증 결과가 아닙니다."
        case .usageUnavailable: return "Claude 사용량을 확인하지 못했습니다. 마지막 확인 값은 유지합니다."
        case .permissionRequired: return "이 Claude 계정의 사용량 조회 권한을 확인해 주세요."
        case .retryLater: return "Claude에서 잠시 뒤 다시 확인하도록 요청했습니다."
        case .connectionChanged: return "Claude 연결이 변경되어 이전 요청을 중단했습니다."
        case .secureStorageUnavailable: return "Claude 보안 저장소에 접근할 수 없습니다."
        case .refreshUncertain: return "Claude 인증 갱신 결과를 확인하지 못했습니다. 다시 연결해 주세요."
        case .network: return "Claude에 연결하지 못했습니다. 마지막 확인 값은 유지합니다."
        case .demoMode: return "예시를 끝낸 뒤 Claude를 연결해 주세요."
        case .busy: return "다른 Claude 연결 작업이 진행 중입니다. 잠시 뒤 다시 확인해 주세요."
        }
    }
}

struct ClaudeNativeStoredAuth: Codable, Equatable, Sendable {
    let connectionID: UUID
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    var refreshUncertain: Bool

    var hasValidFields: Bool {
        Self.validToken(accessToken) && Self.validToken(refreshToken)
            && expiresAt.timeIntervalSince1970.isFinite && expiresAt.timeIntervalSince1970 > 0
    }

    static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 32_768
            && !value.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0)
                || CharacterSet.controlCharacters.contains($0) }
    }
}
