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
    var grokSnapshot: GrokUsageSnapshot? = nil
    var grokRequiresSignIn = false
    var claudeSnapshot: ClaudeNativeUsageSnapshot? = nil
    var claudeRequiresSignIn = false

    var id: PhoneUsageProvider { provider }
    private var availableSnapshot: UsageSnapshot? {
        provider == .codex ? snapshot : nil
    }
    private var availableGrokSnapshot: GrokUsageSnapshot? {
        guard provider == .grok, snapshot?.isDemo != true,
              let grokSnapshot, grokSnapshot.isValid(at: now) else { return nil }
        if grokRequiresSignIn, let manual = availableWebReading,
           manual.updatedAt >= grokSnapshot.updatedAt { return nil }
        return grokSnapshot
    }
    private var availableClaudeSnapshot: ClaudeNativeUsageSnapshot? {
        guard provider == .claude, snapshot?.isDemo != true,
              let claudeSnapshot, claudeSnapshot.isValid(at: now) else { return nil }
        // Choose one source for the pair. A new manual confirmation after a failed
        // native connection must not be hidden behind an older native account.
        if claudeRequiresSignIn,
           [WebUsageMetric.claudeWeekly, .claudeSession].compactMap({ availableReading(for: $0) })
            .contains(where: { $0.updatedAt >= claudeSnapshot.updatedAt }) { return nil }
        return claudeSnapshot
    }
    private var grokPeriodTitle: String {
        switch availableGrokSnapshot?.period {
        case .weekly: return "주간"
        case .monthly: return "월간"
        default: return "한도"
        }
    }
    private func observationTime(_ date: Date) -> String {
        if Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: now) {
            return UsageFormatter.updateTime(date)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
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
        return [WebUsageMetric.claudeWeekly, .claudeSession].map { metric in
            let direct = availableClaudeSnapshot
            let window = direct.map { metric == .claudeWeekly ? $0.sevenDay : $0.fiveHour }
            return WebUsageLimitDisplay(metric: metric, reading: availableReading(for: metric), now: now,
                isDemo: snapshot?.isDemo == true, nativeWindow: window,
                nativeUpdatedAt: direct?.updatedAt, nativeIsStale: direct?.isStale(at: now) ?? false,
                requiresSignIn: claudeRequiresSignIn)
        }
    }
    var percentText: String {
        if let snapshot = availableSnapshot { return "\(snapshot.remainingPercent)%" }
        if let direct = availableGrokSnapshot { return WebUsageReading.percentText(direct.remainingPercent) }
        if let direct = availableClaudeSnapshot { return WebUsageReading.percentText(direct.sevenDay.remainingPercent) }
        guard let reading = availableWebReading else { return "—" }
        return WebUsageReading.percentText(reading.remainingPercent)
    }
    var statusText: String {
        if provider == .codex {
            guard let snapshot = availableSnapshot else { return "연결 필요" }
            return snapshot.isDemo == true ? "예시" : "연결됨"
        }
        if let direct = availableGrokSnapshot {
            if grokRequiresSignIn { return "재연결 필요" }
            return (direct.isStale(at: now) ? "지난 조회 · " : "자동 · ") + grokPeriodTitle
        }
        if let direct = availableClaudeSnapshot {
            if claudeRequiresSignIn { return "재연결 필요" }
            return direct.isStale(at: now) ? "지난 조회" : "자동 조회"
        }
        if provider == .grok, grokRequiresSignIn, availableWebReading == nil, snapshot?.isDemo != true { return "연결 필요" }
        if provider == .claude, claudeRequiresSignIn, availableWebReading == nil, snapshot?.isDemo != true { return "연결 필요" }
        guard let reading = availableWebReading else {
            return snapshot?.isDemo == true ? "예시 없음" : "계정 연결"
        }
        return (reading.isStale(at: now) ? "지난 확인 · " : "수동 · ") + reading.metric.name
    }
    var timeText: String? {
        if let direct = availableGrokSnapshot { return observationTime(direct.updatedAt) }
        if let direct = availableClaudeSnapshot { return observationTime(direct.updatedAt) }
        return availableWebReading.map { $0.confirmationTimeText(at: now) }
    }
    var accessibilityText: String {
        if provider == .codex {
            guard let snapshot = availableSnapshot else { return "Codex, 잔여량 없음, ChatGPT 연결 필요" }
            return "Codex, \(snapshot.isDemo == true ? "예시 데이터, " : "")\(snapshot.remainingPercent)퍼센트 남음"
        }
        if provider == .claude {
            return "Claude, " + claudeLimits.map(\.accessibilityText).joined(separator: ", ")
        }
        if let direct = availableGrokSnapshot {
            return "Grok, \(grokPeriodTitle), 잔여율 \(WebUsageReading.percentText(direct.remainingPercent)), 사용률 \(WebUsageReading.percentText(direct.usedPercent)), \(statusText), 마지막 조회 \(observationTime(direct.updatedAt))"
        }
        guard let reading = availableWebReading else {
            let guidance = provider == .grok ? "앱에서 Grok 계정 연결 필요" : "앱에서 웹 연결 후 수동 확인 필요"
            return "\(provider.name), 잔여량 없음, \(snapshot?.isDemo == true ? "예시 데이터 없음" : guidance)"
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
    var nativeWindow: ClaudeNativeUsageWindow? = nil
    var nativeUpdatedAt: Date? = nil
    var nativeIsStale = false
    var requiresSignIn = false

    var id: WebUsageMetric { metric }
    var percentText: String {
        if let nativeWindow { return WebUsageReading.percentText(nativeWindow.remainingPercent) }
        return reading.map { WebUsageReading.percentText($0.remainingPercent) } ?? "—"
    }
    var confirmationText: String {
        if let date = nativeUpdatedAt {
            if requiresSignIn { return "재연결 필요" }
            let label = nativeIsStale ? "지난 " : "자동 "
            if Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: now) {
                return label + UsageFormatter.updateTime(date)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MM/dd HH:mm"
            return label + formatter.string(from: date)
        }
        guard let reading else { return isDemo ? "예시 없음" : "미확인" }
        return (reading.isStale(at: now) ? "지난 " : "확인 ") + reading.confirmationTimeText(at: now)
    }
    var accessibilityText: String {
        if let window = nativeWindow, let date = nativeUpdatedAt {
            return "\(metric.name), 잔여율 \(percentText), 사용률 \(WebUsageReading.percentText(window.usedPercent)), \(requiresSignIn ? "재연결 필요" : (nativeIsStale ? "지난 자동 조회" : "자동 조회")), 마지막 조회 \(UsageFormatter.updateTime(date))"
        }
        guard let reading else { return "\(metric.name), 잔여량 없음, \(isDemo ? "예시 데이터 없음" : "계정 연결 또는 수동 확인 필요")" }
        return "\(metric.name), 잔여율 \(percentText), 사용률 \(WebUsageReading.percentText(reading.usedPercent)), \(reading.isStale(at: now) ? "지난 확인" : "수동 확인"), 마지막 확인 \(reading.confirmationTimeText(at: now))"
    }
}

struct ProviderUsageColumns: View {
    let snapshot: UsageSnapshot?
    let now: Date
    var compact = false
    var webReadings: [WebUsageProvider: WebUsageReading] = [:]
    var webMetricReadings: [WebUsageMetric: WebUsageReading] = [:]
    var grokSnapshot: GrokUsageSnapshot? = nil
    var grokRequiresSignIn = false
    var claudeSnapshot: ClaudeNativeUsageSnapshot? = nil
    var claudeRequiresSignIn = false
    @ScaledMetric(relativeTo: .title) private var percentSize: CGFloat = 30

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 4 : 12) {
            ForEach(PhoneUsageProvider.allCases) { provider in
                let display = ProviderUsageDisplay(provider: provider, snapshot: snapshot,
                                                   webReadings: webReadings,
                                                   webMetricReadings: webMetricReadings, now: now,
                                                   grokSnapshot: grokSnapshot, grokRequiresSignIn: grokRequiresSignIn,
                                                   claudeSnapshot: claudeSnapshot, claudeRequiresSignIn: claudeRequiresSignIn)
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
