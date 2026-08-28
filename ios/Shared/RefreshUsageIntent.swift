import AppIntents

struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "Codex 사용량 새로고침"
    static let description = IntentDescription("Codex 사용량 위젯을 최신 정보로 갱신합니다.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}
