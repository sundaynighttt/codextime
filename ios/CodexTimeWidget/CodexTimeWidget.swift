import SwiftUI
import WidgetKit

@main
struct CodexTimeWidget: Widget {
    let kind = "CodexTimeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            CodexTimeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CodexTime")
        .description("연결한 Codex·Grok·Claude 잔여량을 아이폰에서 조회합니다.")
        .supportedFamilies([.systemSmall])
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    var webReadings: [WebUsageProvider: WebUsageReading] = [:]
    var webMetricReadings: [WebUsageMetric: WebUsageReading] = [:]
    var grokSnapshot: GrokUsageSnapshot? = nil
    var grokRequiresSignIn = false
    var claudeSnapshot: ClaudeNativeUsageSnapshot? = nil
    var claudeRequiresSignIn = false
}

struct UsageTimelineProvider: TimelineProvider {
    private let usageStore = SharedUsageStore()
    private let webUsageStore = WebUsageStore()
    private let grokUsageStore = GrokUsageStore()
    private let claudeUsageStore = ClaudeNativeUsageStore()

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .demo())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = context.isPreview ? UsageSnapshot.demo() : usageStore.load()
        let now = Date()
        completion(UsageEntry(date: now, snapshot: snapshot,
                              webReadings: snapshot?.isDemo == true ? [:] : webUsageStore.loadAll(now: now),
                              webMetricReadings: snapshot?.isDemo == true ? [:] : webUsageStore.loadAllMetrics(now: now),
                              grokSnapshot: snapshot?.isDemo == true ? nil : grokUsageStore.load(now: now),
                              claudeSnapshot: snapshot?.isDemo == true ? nil : claudeUsageStore.load(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            // Each provider is independent. Missing Codex auth cannot block another account.
            async let codex = refreshedCodex()
            async let grok = refreshedGrok()
            async let claude = refreshedClaude()
            let (snapshot, grokResult, claudeResult) = await (codex, grok, claude)
            let now = Date()
            // Re-read after every suspension. A sign-out or new account while a
            // slower provider was pending must retire that provider's old value.
            let grokState = try? grokUsageStore.readState()
            let claudeState = try? claudeUsageStore.readState()
            let isDemo = usageStore.isDemoEnabled || snapshot?.isDemo == true
            let entry = UsageEntry(date: now, snapshot: snapshot,
                                   webReadings: isDemo ? [:] : webUsageStore.loadAll(now: now),
                                   webMetricReadings: isDemo ? [:] : webUsageStore.loadAllMetrics(now: now),
                                   grokSnapshot: isDemo ? nil : grokState?.snapshot.flatMap { $0.isValid(at: now) ? $0 : nil },
                                   grokRequiresSignIn: !isDemo && grokState?.connectionID == grokResult.connectionID && grokResult.requiresSignIn,
                                   claudeSnapshot: isDemo ? nil : claudeState?.snapshot.flatMap { $0.isValid(at: now) ? $0 : nil },
                                   claudeRequiresSignIn: !isDemo && claudeState?.connectionID == claudeResult.connectionID && claudeResult.requiresSignIn)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    private func refreshedCodex() async -> UsageSnapshot? {
        do { return try await CodexAccountClient().fetchUsage() }
        catch { return usageStore.load() }
    }

    private func refreshedGrok() async -> (connectionID: UUID?, requiresSignIn: Bool) {
        guard !usageStore.isDemoEnabled else { return (nil, false) }
        let before = try? grokUsageStore.readState()?.connectionID
        do {
            _ = try await GrokAccountClient.shared.fetchUsage()
            return (try? grokUsageStore.readState()?.connectionID, false)
        } catch let error as GrokClientError {
            let after = try? grokUsageStore.readState()?.connectionID
            return (after, before == after && error.requiresSignIn)
        } catch { return (nil, false) }
    }

    private func refreshedClaude() async -> (connectionID: UUID?, requiresSignIn: Bool) {
        guard !usageStore.isDemoEnabled else { return (nil, false) }
        let before = try? claudeUsageStore.readState()?.connectionID
        do {
            _ = try await ClaudeNativeAccountClient.shared.fetchUsage()
            return (try? claudeUsageStore.readState()?.connectionID, false)
        } catch let error as ClaudeNativeClientError {
            let after = try? claudeUsageStore.readState()?.connectionID
            return (after, before == after && error.requiresSignIn)
        } catch { return (nil, false) }
    }

}

struct CodexTimeWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(entry.snapshot?.isDemo == true ? "예시" : "CodexTime")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button(intent: RefreshUsageIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .tint(.secondary)
                .accessibilityLabel("Codex·Grok·Claude 사용량 새로고침")
            }

            Spacer(minLength: 4)

            ProviderUsageColumns(snapshot: entry.snapshot, now: entry.date, compact: true,
                                 webReadings: entry.webReadings,
                                 webMetricReadings: entry.webMetricReadings,
                                 grokSnapshot: entry.grokSnapshot, grokRequiresSignIn: entry.grokRequiresSignIn,
                                 claudeSnapshot: entry.claudeSnapshot, claudeRequiresSignIn: entry.claudeRequiresSignIn)
                .invalidatableContent()

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Text(resetText)
                    .foregroundStyle(entry.snapshot == nil && entry.grokSnapshot == nil && entry.claudeSnapshot == nil ? Color.secondary : Color.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 4)

                Text(updateTimeText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .font(.system(size: 9, weight: .medium))
            .invalidatableContent()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(updateTimeAccessibilityText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resetText: String {
        if let snapshot = entry.snapshot {
            return "리셋 \(UsageFormatter.remainingTime(until: snapshot.resetAt, now: entry.date))"
        }
        if let grok = entry.grokSnapshot {
            if let reset = grok.resetAt {
                return "Grok 리셋 \(UsageFormatter.remainingTime(until: reset, now: entry.date))"
            }
            return entry.grokRequiresSignIn ? "Grok 재연결 필요" : "Grok 자동 조회"
        }
        if let claude = entry.claudeSnapshot {
            if let reset = claude.fiveHour.resetAt {
                return "Claude 리셋 \(UsageFormatter.remainingTime(until: reset, now: entry.date))"
            }
            return entry.claudeRequiresSignIn ? "Claude 재연결 필요" : "Claude 자동 조회"
        }
        return "계정 연결 필요"
    }

    private var updateTimeText: String {
        if let snapshot = entry.snapshot { return "Codex " + UsageFormatter.updateTime(snapshot.updatedAt) }
        if let grok = entry.grokSnapshot { return "Grok " + UsageFormatter.updateTime(grok.updatedAt) }
        if let claude = entry.claudeSnapshot { return "Claude " + UsageFormatter.updateTime(claude.updatedAt) }
        return "—:—"
    }

    private var updateTimeAccessibilityText: String {
        guard entry.snapshot != nil || entry.grokSnapshot != nil || entry.claudeSnapshot != nil else { return "업데이트 시간 없음" }
        return "\(resetText), 마지막 업데이트 \(updateTimeText)"
    }

}

#Preview(as: .systemSmall) {
    CodexTimeWidget()
} timeline: {
    UsageEntry(date: Date(), snapshot: .demo())
}
