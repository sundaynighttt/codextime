import Foundation

struct RateLimitWindow: Codable, Equatable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?
}

struct RateLimitSnapshot: Codable, Equatable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let planType: String?
}

struct RateLimitsResult: Codable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
}

private struct RateLimitsEnvelope: Codable {
    let result: RateLimitsResult?
    let error: JSONRPCError?
}

private struct JSONRPCError: Codable {
    let code: Int?
    let message: String
}

struct UsageBucket: Identifiable, Equatable {
    let id: String
    let name: String
    let primary: RateLimitWindow
    let secondary: RateLimitWindow?
    let planType: String?

    var remainingPercent: Int {
        min(100, max(0, 100 - primary.usedPercent))
    }

    var resetDate: Date? {
        primary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

struct UsageReport: Equatable {
    let buckets: [UsageBucket]

    var main: UsageBucket? {
        buckets.first(where: { $0.id == "codex" }) ?? buckets.first
    }
}

enum RateLimitParser {
    static func parse(line: Data) throws -> UsageReport? {
        guard
            let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
            object["error"] != nil || (object["result"] as? [String: Any])?["rateLimits"] != nil
        else {
            return nil
        }

        let envelope = try JSONDecoder().decode(RateLimitsEnvelope.self, from: line)
        if let error = envelope.error {
            throw MonitorError.server(error.message)
        }
        guard let result = envelope.result else {
            return nil
        }

        var snapshots = result.rateLimitsByLimitId ?? [:]
        let fallbackId = result.rateLimits.limitId ?? "codex"
        if snapshots[fallbackId] == nil {
            snapshots[fallbackId] = result.rateLimits
        }

        let buckets = snapshots.compactMap { key, snapshot -> UsageBucket? in
            guard let primary = snapshot.primary else { return nil }
            let id = snapshot.limitId ?? key
            let name: String
            if id == "codex" {
                name = "Codex"
            } else {
                name = snapshot.limitName ?? id
            }
            return UsageBucket(
                id: id,
                name: name,
                primary: primary,
                secondary: snapshot.secondary,
                planType: snapshot.planType
            )
        }
        .sorted { left, right in
            if left.id == "codex" { return true }
            if right.id == "codex" { return false }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }

        guard !buckets.isEmpty else {
            throw MonitorError.invalidResponse
        }
        return UsageReport(buckets: buckets)
    }
}

enum UsageFormatter {
    static func remainingTime(until resetDate: Date?, now: Date = Date()) -> String {
        guard let resetDate else { return "리셋 시간 미확인" }
        let seconds = max(0, Int(resetDate.timeIntervalSince(now)))
        if seconds == 0 { return "곧 리셋" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    static func compactTitle(for bucket: UsageBucket?, now: Date = Date()) -> String {
        guard let bucket else { return "Codex …" }
        return "Codex \(bucket.remainingPercent)% (\(remainingTime(until: bucket.resetDate, now: now)))"
    }

    static func detail(for bucket: UsageBucket, now: Date = Date()) -> String {
        "\(bucket.remainingPercent)% 남음 · \(remainingTime(until: bucket.resetDate, now: now))"
    }
}

enum MonitorError: LocalizedError, Equatable {
    case codexNotFound
    case launchFailed(String)
    case timeout
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "Codex CLI를 찾지 못했습니다."
        case let .launchFailed(message):
            return "Codex 실행 실패: \(message)"
        case .timeout:
            return "사용량 조회 시간이 초과됐습니다."
        case .invalidResponse:
            return "Codex 사용량 응답을 해석하지 못했습니다."
        case let .server(message):
            return "Codex 응답 오류: \(message)"
        }
    }
}
