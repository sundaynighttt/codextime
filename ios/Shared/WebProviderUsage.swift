import Foundation

/// The only web-provider data shared with the widget. Authentication stays in WebKit memory.
enum WebUsageProvider: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case grok, claude

    var id: String { rawValue }
    var name: String { self == .grok ? "Grok" : "Claude" }
    var usageURL: URL {
        switch self {
        case .grok: return URL(string: "https://grok.com/?_s=usage")!
        case .claude: return URL(string: "https://claude.ai/settings/usage")!
        }
    }
}

enum WebUsageValueKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case used, remaining

    var id: String { rawValue }
    var name: String { self == .used ? "사용률" : "잔여율" }
}

enum WebUsageMetric: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case grokWeekly, claudeSession, claudeWeekly

    var id: String { rawValue }
    var provider: WebUsageProvider {
        switch self {
        case .grokWeekly: return .grok
        case .claudeSession, .claudeWeekly: return .claude
        }
    }
    var name: String {
        switch self {
        case .grokWeekly, .claudeWeekly: return "주간"
        case .claudeSession: return "세션"
        }
    }
}

struct WebUsageReading: Codable, Equatable, Sendable {
    let provider: WebUsageProvider
    let percent: Double
    let valueKind: WebUsageValueKind
    let metric: WebUsageMetric
    let updatedAt: Date

    var isValid: Bool {
        percent.isFinite && (0...100).contains(percent)
            && metric.provider == provider && updatedAt.timeIntervalSince1970.isFinite
    }

    func isValid(at now: Date) -> Bool {
        isValid && now.timeIntervalSince1970.isFinite && updatedAt <= now
    }

    var usedPercent: Double {
        guard isValid else { return .nan }
        return valueKind == .used ? percent : 100 - percent
    }

    var remainingPercent: Double {
        guard isValid else { return .nan }
        return valueKind == .remaining ? percent : 100 - percent
    }

    /// No automatic web refresh is implied, even before this threshold.
    func isStale(at now: Date) -> Bool {
        !isValid(at: now) || now.timeIntervalSince(updatedAt) >= 60 * 60
    }

    func confirmationTimeText(at now: Date) -> String {
        if Calendar.autoupdatingCurrent.isDate(updatedAt, inSameDayAs: now) {
            return UsageFormatter.updateTime(updatedAt)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: updatedAt)
    }

    static func percentText(_ percent: Double) -> String {
        percent.formatted(.number.precision(.fractionLength(0...2))) + "%"
    }
}
