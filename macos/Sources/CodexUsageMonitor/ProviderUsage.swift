import Foundation

/// The order is intentional: every provider keeps a visible menu-bar slot.
enum ProviderID: String, CaseIterable, Identifiable, Sendable {
    case codex
    case grok
    case claude

    var id: String { rawValue }

    var name: String {
        switch self {
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .claude: return "Claude"
        }
    }
}

struct ProviderUsageWindow: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let remainingPercent: Double?
    let resetDate: Date?
    let durationMinutes: Int?
    let countsTowardSummary: Bool

    init(
        id: String,
        label: String,
        remainingPercent: Double?,
        resetDate: Date? = nil,
        durationMinutes: Int? = nil,
        countsTowardSummary: Bool = true
    ) {
        self.id = id
        self.label = label
        // Missing or malformed quotas remain unknown; never turn them into 0/100.
        self.remainingPercent = remainingPercent.flatMap {
            $0.isFinite && (0...100).contains($0) ? $0 : nil
        }
        self.resetDate = resetDate.flatMap {
            $0.timeIntervalSince1970.isFinite ? $0 : nil
        }
        self.durationMinutes = durationMinutes.flatMap { $0 > 0 ? $0 : nil }
        self.countsTowardSummary = countsTowardSummary
    }

    /// Round down so the compact display never overstates the remaining quota.
    var displayRemainingPercent: Int? {
        remainingPercent.map { Int($0.rounded(.down)) }
    }
}

struct ProviderUsageSnapshot: Equatable, Sendable {
    let provider: ProviderID
    let windows: [ProviderUsageWindow]
    let planName: String?

    init(provider: ProviderID, windows: [ProviderUsageWindow], planName: String? = nil) {
        self.provider = provider
        self.windows = windows
        self.planName = planName
    }

    /// Shared quota determines the summary; model-specific windows remain details.
    /// A depleted shared weekly window stays visible even if a short window is full.
    var displayWindow: ProviderUsageWindow? {
        windows.filter { $0.countsTowardSummary && $0.remainingPercent != nil }.min {
            $0.remainingPercent! < $1.remainingPercent!
        }
    }

    var displayRemainingPercent: Int? { displayWindow?.displayRemainingPercent }
}

/// Only these fixed messages may reach the UI. Raw server/CLI errors can contain
/// credentials, request bodies or private account details and must not be shown.
enum ProviderUsageFailure: Error, LocalizedError, Equatable, Sendable {
    case notInstalled
    case notConnected
    case authenticationRequired
    case permissionRequired
    case permissionDenied
    case unsupported
    case timeout
    case invalidResponse
    case queryFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "공식 사용량 조회 CLI가 설치되지 않았습니다."
        case .notConnected: return "사용량 조회가 연결되지 않았습니다."
        case .authenticationRequired: return "공식 앱 또는 CLI 로그인이 필요합니다."
        case .permissionRequired: return "사용량 조회 권한이 필요합니다. 메뉴에서 연결 권한을 요청해 주세요."
        case .permissionDenied: return "사용자가 사용량 조회 권한 요청을 취소하거나 거부했습니다."
        case .unsupported: return "현재 로그인 방식의 잔여 한도 조회를 지원하지 않습니다."
        case .timeout: return "사용량 조회 시간이 초과됐습니다."
        case .invalidResponse: return "잔여 한도 응답을 확인하지 못했습니다."
        case .queryFailed: return "사용량을 조회하지 못했습니다. 다시 시도해 주세요."
        }
    }
}

protocol UsageProviderClient: Sendable {
    var id: ProviderID { get }

    /// Implementations must bound I/O and stop cancellable owned work on cancellation.
    /// An explicit OS authorization dialog can wait for the user; the store keeps
    /// that request occupied until it returns and all cleanup has completed.
    func fetchUsage() async throws -> ProviderUsageSnapshot
}

struct ProviderUsageState: Equatable, Sendable {
    static let staleAfter: TimeInterval = 20 * 60

    let id: ProviderID
    var snapshot: ProviderUsageSnapshot?
    var lastSuccess: Date?
    var lastAttempt: Date?
    var failure: ProviderUsageFailure?
    var isRefreshing = false
    var connectionIsPending = false

    var error: String? { failure?.errorDescription }
    var displayRemainingPercent: Int? { snapshot?.displayRemainingPercent }

    func isStale(now: Date = Date()) -> Bool {
        guard let lastSuccess else { return false }
        return failure != nil || now.timeIntervalSince(lastSuccess) > Self.staleAfter
    }
}

/// Keeps the existing app-server parser, deadline, cancellation and child cleanup.
struct CodexUsageProviderClient: UsageProviderClient {
    let id: ProviderID = .codex
    private let client: CodexAppServerClient

    init(client: CodexAppServerClient = CodexAppServerClient()) {
        self.client = client
    }

    func fetchUsage() async throws -> ProviderUsageSnapshot {
        do {
            let report = try await client.fetchRateLimits()
            guard let bucket = report.main else { throw ProviderUsageFailure.invalidResponse }
            var windows = [Self.window(bucket.primary, id: "primary", fallback: "기본 한도")]
            if let secondary = bucket.secondary {
                windows.append(Self.window(secondary, id: "secondary", fallback: "추가 한도"))
            }
            return ProviderUsageSnapshot(provider: id, windows: windows, planName: bucket.planType)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ProviderUsageFailure {
            throw failure
        } catch let error as MonitorError {
            switch error {
            case .codexNotFound: throw ProviderUsageFailure.notInstalled
            case .timeout: throw ProviderUsageFailure.timeout
            case .invalidResponse: throw ProviderUsageFailure.invalidResponse
            case .launchFailed, .server: throw ProviderUsageFailure.queryFailed
            }
        } catch {
            throw ProviderUsageFailure.queryFailed
        }
    }

    private static func window(_ window: RateLimitWindow, id: String, fallback: String) -> ProviderUsageWindow {
        let label: String
        switch window.windowDurationMins {
        case 10_080: label = "주간 한도"
        case let minutes? where minutes > 0 && minutes < 1_440: label = "단기 한도"
        case 1_440: label = "일간 한도"
        case let minutes? where minutes >= 40_320 && minutes <= 44_640: label = "월간 한도"
        default: label = fallback
        }
        let remaining = (0...100).contains(window.usedPercent) ? Double(100 - window.usedPercent) : nil
        return ProviderUsageWindow(
            id: id,
            label: label,
            remainingPercent: remaining,
            resetDate: window.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            durationMinutes: window.windowDurationMins
        )
    }
}
