import Foundation

struct UsageSnapshot: Codable, Equatable, Sendable {
    let remainingPercent: Int
    let resetAt: Date
    let updatedAt: Date

    static let placeholder = UsageSnapshot(
        remainingPercent: 98,
        resetAt: Date().addingTimeInterval(3 * 86_400 + 17 * 3_600),
        updatedAt: Date()
    )
}

enum UsageFormatter {
    static func remainingTime(until resetDate: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(resetDate.timeIntervalSince(now)))
        if seconds == 0 { return "곧 리셋" }

        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    static func updateTime(_ date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}

struct UsagePayload: Decodable {
    let planType: String?
    let rateLimit: RateLimitDetails?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    func snapshot(now: Date = Date()) throws -> UsageSnapshot {
        guard let primary = rateLimit?.primaryWindow else {
            throw CodexClientError.invalidResponse
        }
        return UsageSnapshot(
            remainingPercent: min(100, max(0, 100 - primary.usedPercent)),
            resetAt: Date(timeIntervalSince1970: TimeInterval(primary.resetAt)),
            updatedAt: now
        )
    }
}

struct RateLimitDetails: Decodable {
    let primaryWindow: RateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
    }
}

struct RateLimitWindow: Decodable {
    let usedPercent: Int
    let resetAt: Int64

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
    }
}
