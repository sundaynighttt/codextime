import AppIntents

struct RefreshUsageIntent: AppIntent {
    static let title: LocalizedStringResource = "사용량 새로고침"
    static let description = IntentDescription("Codex 조회와 활성화한 iCloud 동기화의 위젯 갱신을 요청합니다.")
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        .result()
    }
}
