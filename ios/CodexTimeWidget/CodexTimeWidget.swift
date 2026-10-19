import SwiftUI
import WidgetKit
import UsageSync

@main
struct CodexTimeWidget: Widget {
    let kind = "CodexTimeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            CodexTimeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("CodexTime")
        .description("Codex 직접 조회와 본인 Mac의 Grok iCloud 동기화 결과를 확인합니다. Claude는 허용 확인이 필요합니다.")
        .supportedFamilies([.systemSmall])
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    var cloud = CloudWidgetSnapshot()
}

struct CloudWidgetSnapshot {
    var readings: [SyncProvider: SyncedUsage] = [:]
    var isEnabled = false
    var hadError = false
}

struct UsageTimelineProvider: TimelineProvider {
    private let usageStore = SharedUsageStore()

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .demo())
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: Date(), snapshot: .demo()))
            return
        }
        Task {
            let cloud = await verifiedCloudSnapshot()
            completion(UsageEntry(date: Date(), snapshot: usageStore.load(), cloud: cloud))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let snapshot: UsageSnapshot?
            do {
                snapshot = try await CodexAccountClient().fetchUsage()
            } catch {
                snapshot = usageStore.load()
            }

            let cloud = await verifiedCloudSnapshot()
            let now = Date()
            var entries = [UsageEntry(date: now, snapshot: snapshot, cloud: cloud)]
            // Schedule the stale label even when iOS postpones the next network refresh.
            if let observedAt = cloud.readings[.grok]?.observedAt {
                let becomesStale = observedAt.addingTimeInterval(20 * 60 + 1)
                if becomesStale > now, becomesStale < now.addingTimeInterval(30 * 60) {
                    entries.append(UsageEntry(date: becomesStale, snapshot: snapshot, cloud: cloud))
                }
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    @MainActor
    private func verifiedCloudSnapshot() async -> CloudWidgetSnapshot {
        guard !usageStore.isDemoEnabled else { return CloudWidgetSnapshot() }
        let preferences = UserDefaults(suiteName: CodexConfiguration.appGroupID) ?? .standard
        // Never turn on sync from a widget. The engine checks the current iCloud scope
        // before accepting even a cached result and clears another account's data.
        guard UsageSyncCache.isRequestedEnabled(preferences: preferences) else { return CloudWidgetSnapshot() }
        let sync = UsageCloudSync(preferences: preferences)
        await sync.refresh()
        return CloudWidgetSnapshot(readings: sync.readings, isEnabled: sync.isEnabled,
                                   hadError: sync.state.hasCloudReadError)
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
                .accessibilityLabel("사용량 새로고침")
            }

            Spacer(minLength: 4)

            ProviderUsageColumns(snapshot: entry.snapshot, now: entry.date, compact: true,
                                 cloudReadings: entry.cloud.readings, cloudEnabled: entry.cloud.isEnabled,
                                 cloudHadError: entry.cloud.hadError)
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
