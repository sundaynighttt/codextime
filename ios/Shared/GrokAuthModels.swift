import Foundation

enum GrokConfiguration {
    // xAI's documented shared public OAuth client. The approval page may say Grok Build.
    static let clientID = "b1a00492-073a-47ea-816f-4c329264a828"
    static let scope = "openid offline_access grok-cli:access"
    static let deviceURL = URL(string: "https://auth.x.ai/oauth2/device/code")!
    static let tokenURL = URL(string: "https://auth.x.ai/oauth2/token")!
    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    static let keychainService = "com.sundaynighttt.codextime.grok.tokens"
    static let keychainAccount = "supergrok"
}

struct GrokDeviceAuthorization: Equatable, Sendable, Identifiable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let expiresAt: Date
    let interval: TimeInterval
    let connectionID: UUID

    var id: UUID { connectionID }

    init(deviceCode: String, userCode: String, verificationURL: URL,
         expiresAt: Date, interval: TimeInterval, connectionID: UUID = UUID()) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresAt = expiresAt
        self.interval = interval
        self.connectionID = connectionID
    }
}

enum GrokUsagePeriod: String, Codable, Equatable, Sendable {
    case weekly, monthly, unknown
    var name: String {
        switch self {
        case .weekly: return "주간"
        case .monthly: return "월간"
        case .unknown: return "사용 한도"
        }
    }
}

struct GrokUsageSnapshot: Codable, Equatable, Sendable {
    let usedPercent: Double
    let period: GrokUsagePeriod
    let resetAt: Date?
    let updatedAt: Date

    var remainingPercent: Double { 100 - usedPercent }

    func isValid(at now: Date) -> Bool {
        usedPercent.isFinite && (0...100).contains(usedPercent)
            && updatedAt.timeIntervalSince1970.isFinite && updatedAt.timeIntervalSince1970 >= 0
            && now.timeIntervalSince1970.isFinite && updatedAt <= now
            && (resetAt.map { $0.timeIntervalSince1970.isFinite && $0 > updatedAt
                && $0.timeIntervalSince(updatedAt) < 366 * 86_400 } ?? true)
    }

    func isStale(at now: Date, maxAge: TimeInterval = 1_200) -> Bool {
        !isValid(at: now) || !maxAge.isFinite || maxAge < 0 || now.timeIntervalSince(updatedAt) >= maxAge
            || (resetAt.map { $0 <= now } ?? false)
    }
}

enum GrokClientError: LocalizedError, Equatable, Sendable {
    case notAuthenticated, loginExpired, authorizationDenied, invalidResponse, usageUnavailable
    case permissionRequired, retryLater, connectionChanged, secureStorageUnavailable
    case refreshUncertain, network, demoMode, busy

    var requiresSignIn: Bool {
        switch self {
        case .notAuthenticated, .loginExpired, .authorizationDenied, .refreshUncertain: return true
        default: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Grok 연결이 필요합니다."
        case .loginExpired: return "Grok 로그인이 만료되었습니다. 다시 연결해 주세요."
        case .authorizationDenied: return "Grok 연결이 승인되지 않았습니다."
        case .invalidResponse: return "Grok 응답을 확인할 수 없습니다."
        case .usageUnavailable: return "구독 사용률을 확인하지 못했습니다. 마지막 확인 값이 있으면 유지합니다."
        case .permissionRequired: return "이 Grok 계정의 사용량 조회 권한을 확인해 주세요."
        case .retryLater: return "Grok에서 잠시 뒤 다시 확인하도록 요청했습니다."
        case .connectionChanged: return "Grok 연결이 변경되어 이전 요청을 중단했습니다."
        case .secureStorageUnavailable: return "Grok 보안 저장소에 접근할 수 없습니다."
        case .refreshUncertain: return "Grok 인증 갱신 결과를 확인하지 못했습니다. 안전하게 다시 연결해 주세요."
        case .network: return "Grok에 연결하지 못했습니다. 마지막 확인 값은 유지합니다."
        case .demoMode: return "예시를 끝낸 뒤 Grok을 연결해 주세요."
        case .busy: return "다른 Grok 연결 작업이 진행 중입니다. 잠시 뒤 다시 확인해 주세요."
        }
    }
}

struct GrokStoredAuth: Codable, Equatable, Sendable {
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
