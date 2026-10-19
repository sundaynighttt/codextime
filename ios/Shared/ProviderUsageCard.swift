import SwiftUI

enum PhoneUsageProvider: String, CaseIterable, Identifiable {
    case codex, grok, claude

    var id: String { rawValue }
    var name: String {
        switch self {
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .claude: return "Claude"
        }
    }
    var logoName: String { "provider-" + rawValue }
    var webProvider: WebUsageProvider? {
        switch self {
        case .codex: return nil
        case .grok: return .grok
        case .claude: return .claude
        }
    }
}

struct ProviderUsageDisplay: Identifiable {
    let provider: PhoneUsageProvider
    let snapshot: UsageSnapshot?
    var webReadings: [WebUsageProvider: WebUsageReading] = [:]
    var webMetricReadings: [WebUsageMetric: WebUsageReading] = [:]
    var now: Date = Date()

    var id: PhoneUsageProvider { provider }
    private var availableSnapshot: UsageSnapshot? {
        provider == .codex ? snapshot : nil
    }
    private func availableReading(for metric: WebUsageMetric) -> WebUsageReading? {
        guard snapshot?.isDemo != true, metric.provider == provider.webProvider else { return nil }
        let reading = webMetricReadings[metric] ?? webReadings[metric.provider]
        guard let reading, reading.metric == metric, reading.provider == metric.provider,
              reading.isValid(at: now) else { return nil }
        return reading
    }
    private var availableWebReading: WebUsageReading? {
        switch provider {
        case .codex: return nil
        case .grok: return availableReading(for: .grokWeekly)
        case .claude: return availableReading(for: .claudeWeekly) ?? availableReading(for: .claudeSession)
        }
    }
    var claudeLimits: [WebUsageLimitDisplay] {
        guard provider == .claude else { return [] }
        return [WebUsageMetric.claudeWeekly, .claudeSession].map {
            WebUsageLimitDisplay(metric: $0, reading: availableReading(for: $0), now: now,
                                 isDemo: snapshot?.isDemo == true)
        }
    }
    var percentText: String {
        if let snapshot = availableSnapshot { return "\(snapshot.remainingPercent)%" }
        guard let reading = availableWebReading else { return "—" }
        return WebUsageReading.percentText(reading.remainingPercent)
    }
    var statusText: String {
        if provider == .codex {
            guard let snapshot = availableSnapshot else { return "연결 필요" }
            return snapshot.isDemo == true ? "예시" : "연결됨"
        }
        guard let reading = availableWebReading else {
            return snapshot?.isDemo == true ? "예시 없음" : "웹 연결"
        }
        return (reading.isStale(at: now) ? "지난 확인 · " : "수동 · ") + reading.metric.name
    }
    var timeText: String? {
        availableWebReading.map { $0.confirmationTimeText(at: now) }
    }
    var accessibilityText: String {
        if provider == .codex {
            guard let snapshot = availableSnapshot else { return "Codex, 잔여량 없음, ChatGPT 연결 필요" }
            return "Codex, \(snapshot.isDemo == true ? "예시 데이터, " : "")\(snapshot.remainingPercent)퍼센트 남음"
        }
        if provider == .claude {
            return "Claude, " + claudeLimits.map(\.accessibilityText).joined(separator: ", ")
        }
        guard let reading = availableWebReading else {
            return "\(provider.name), 잔여량 없음, \(snapshot?.isDemo == true ? "예시 데이터 없음" : "앱에서 웹 연결 후 수동 확인 필요")"
        }
        return "\(provider.name), \(reading.metric.name), 잔여율 \(WebUsageReading.percentText(reading.remainingPercent)), 사용률 \(WebUsageReading.percentText(reading.usedPercent)), \(statusText), 마지막 확인 \(reading.confirmationTimeText(at: now))"
    }
}

/// Per-limit labels and dates are kept together in both app and widget rendering.
struct WebUsageLimitDisplay: Identifiable {
    let metric: WebUsageMetric
    let reading: WebUsageReading?
    let now: Date
    var isDemo = false

    var id: WebUsageMetric { metric }
    var percentText: String { reading.map { WebUsageReading.percentText($0.remainingPercent) } ?? "—" }
    var confirmationText: String {
        guard let reading else { return isDemo ? "예시 없음" : "미확인" }
        return (reading.isStale(at: now) ? "지난 " : "확인 ") + reading.confirmationTimeText(at: now)
    }
    var accessibilityText: String {
        guard let reading else { return "\(metric.name), 잔여량 없음, \(isDemo ? "예시 데이터 없음" : "수동 확인 필요")" }
        return "\(metric.name), 잔여율 \(percentText), 사용률 \(WebUsageReading.percentText(reading.usedPercent)), \(reading.isStale(at: now) ? "지난 확인" : "수동 확인"), 마지막 확인 \(reading.confirmationTimeText(at: now))"
    }
}

struct ProviderUsageColumns: View {
    let snapshot: UsageSnapshot?
    let now: Date
    var compact = false
    var webReadings: [WebUsageProvider: WebUsageReading] = [:]
    var webMetricReadings: [WebUsageMetric: WebUsageReading] = [:]
    @ScaledMetric(relativeTo: .title) private var percentSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 4 : 12) {
            ForEach(PhoneUsageProvider.allCases) { provider in
                let display = ProviderUsageDisplay(provider: provider, snapshot: snapshot,
                                                   webReadings: webReadings,
                                                   webMetricReadings: webMetricReadings, now: now)
                VStack(spacing: compact ? 3 : 7) {
                    Image(provider.logoName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: compact ? 16 : 24, height: compact ? 16 : 24)
                        .accessibilityHidden(true)

                    Text(provider.name)
                        .font(compact ? .system(size: 9, weight: .medium) : .caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if provider == .claude {
                        VStack(spacing: compact ? 4 : 7) {
                            ForEach(display.claudeLimits) { limit in
                                VStack(spacing: 1) {
                                    Text(limit.metric.name + " " + limit.percentText)
                                        .font(.system(size: compact ? 11 : min(percentSize * 0.55, 19), weight: .semibold))
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.65)
                                    Text(limit.confirmationText)
                                        .font(compact ? .system(size: 7) : .caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(limit.accessibilityText)
                                .accessibilityIdentifier("claude-limit-" + limit.metric.rawValue)
                            }
                        }
                        .invalidatableContent()
                    } else {
                        Text(display.percentText)
                            .font(.system(size: compact ? 20 : min(percentSize, 40), weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .invalidatableContent()

                        Text(display.statusText)
                            .font(compact ? .system(size: 8) : .caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text(display.timeText ?? " ")
                            .font(compact ? .system(size: 8) : .caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(display.accessibilityText)
                .accessibilityIdentifier("provider-" + provider.rawValue)
            }
        }
    }
}
