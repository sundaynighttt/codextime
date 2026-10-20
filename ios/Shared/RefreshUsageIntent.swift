import AppIntents

struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "사용량 새로고침"
    static let description = IntentDescription("연결된 Codex·Grok·Claude 사용량을 조회해 위젯을 갱신합니다.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}
