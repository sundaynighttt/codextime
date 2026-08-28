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
        .description("남은 Codex 사용량과 리셋 시간을 표시합니다.")
        .supportedFamilies([.systemSmall])
    }
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct UsageTimelineProvider: TimelineProvider {
    private let usageStore = SharedUsageStore()

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let snapshot = context.isPreview ? UsageSnapshot.placeholder : usageStore.load()
        completion(UsageEntry(date: Date(), snapshot: snapshot))
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
            let entry = UsageEntry(date: now, snapshot: snapshot)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Codex")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Spacer(minLength: 8)

                Button(intent: RefreshUsageIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .tint(.secondary)
                .accessibilityLabel("Codex 사용량 새로고침")
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(percentText)
                    .font(.system(size: 50, weight: .bold, design: .default))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .invalidatableContent()

                Text(resetText)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .invalidatableContent()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var percentText: String {
        guard let snapshot = entry.snapshot else { return "--%" }
        return "\(snapshot.remainingPercent)%"
    }

    private var resetText: String {
        guard let snapshot = entry.snapshot else { return "연결 필요" }
        return UsageFormatter.remainingTime(until: snapshot.resetAt, now: entry.date)
    }

    private var accessibilityText: String {
        guard let snapshot = entry.snapshot else {
            return "CodexTime, ChatGPT 연결 필요"
        }
        return "Codex 사용량 \(snapshot.remainingPercent)퍼센트 남음, 리셋까지 \(resetText)"
    }
}

#Preview(as: .systemSmall) {
    CodexTimeWidget()
} timeline: {
    UsageEntry(date: Date(), snapshot: .placeholder)
}
