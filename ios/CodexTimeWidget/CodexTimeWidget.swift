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
        .description("Codex 잔여량과 Grok·Claude의 마지막 수동 확인 값을 한눈에 봅니다.")
        .supportedFamilies([.systemSmall])
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    var webReadings: [WebUsageProvider: WebUsageReading] = [:]
    var webMetricReadings: [WebUsageMetric: WebUsageReading] = [:]
}

struct UsageTimelineProvider: TimelineProvider {
    private let usageStore = SharedUsageStore()
    private let webUsageStore = WebUsageStore()

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .demo())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = context.isPreview ? UsageSnapshot.demo() : usageStore.load()
        let now = Date()
        completion(UsageEntry(date: now, snapshot: snapshot,
                              webReadings: snapshot?.isDemo == true ? [:] : webUsageStore.loadAll(now: now),
                              webMetricReadings: snapshot?.isDemo == true ? [:] : webUsageStore.loadAllMetrics(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let snapshot: UsageSnapshot?
            do {
                snapshot = try await CodexAccountClient().fetchUsage()
            } catch {
                snapshot = usageStore.load()
            }

            let now = Date()
            let entry = UsageEntry(date: now, snapshot: snapshot,
                                   webReadings: snapshot?.isDemo == true ? [:] : webUsageStore.loadAll(now: now),
                                   webMetricReadings: snapshot?.isDemo == true ? [:] : webUsageStore.loadAllMetrics(now: now))
            completion(
                Timeline(
                    entries: [entry],
                    policy: .after(now.addingTimeInterval(30 * 60))
                )
            )
        }
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
                .accessibilityLabel("Codex 사용량 새로고침")
            }

            Spacer(minLength: 4)

            ProviderUsageColumns(snapshot: entry.snapshot, now: entry.date, compact: true,
                                 webReadings: entry.webReadings,
                                 webMetricReadings: entry.webMetricReadings)
                .invalidatableContent()

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Text(resetText)
                    .foregroundStyle(entry.snapshot == nil ? Color.secondary : Color.blue)
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
        guard let snapshot = entry.snapshot else { return "연결 필요" }
        return "리셋 \(UsageFormatter.remainingTime(until: snapshot.resetAt, now: entry.date))"
    }

    private var updateTimeText: String {
        guard let snapshot = entry.snapshot else { return "—:—" }
        return UsageFormatter.updateTime(snapshot.updatedAt)
    }

    private var updateTimeAccessibilityText: String {
        guard entry.snapshot != nil else { return "Codex 업데이트 시간 없음" }
        let source = entry.snapshot?.isDemo == true ? "예시 데이터" : "Codex"
        return "\(source), \(resetText), 마지막 업데이트 \(updateTimeText)"
    }
}

#Preview(as: .systemSmall) {
    CodexTimeWidget()
} timeline: {
    UsageEntry(date: Date(), snapshot: .demo())
}
