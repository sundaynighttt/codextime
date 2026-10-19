import SwiftUI

struct UsageGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private var thirdPartyNotices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "라이선스 파일을 불러올 수 없습니다." }
        return text
    }

    var body: some View {
        NavigationStack {
            List {
                Section("남은 사용량 확인") {
                    Text("ChatGPT 계정을 연결하면 계정 응답의 기본 사용량 한도, 다음 리셋 시각과 제공되는 경우 누적 토큰을 표시합니다. 모든 한도 구간이나 API 결제 잔액을 표시하는 것은 아닙니다.")
                    Text("예시 데이터로 둘러보기는 누구나 사용할 수 있는 오프라인 기능입니다. 예시 값은 실제 계정이나 실시간 조회 결과가 아니며 앱과 위젯에 ‘예시’로 표시됩니다.")
                }
                Section("3열 카드") {
                    Text("Codex·Grok·Claude의 잔여율을 한 카드에 표시합니다. 연결하지 않은 서비스는 ‘—’로 남습니다. Mac의 사용량이나 계정 정보를 가져오지 않습니다.")
                    Text("Grok·Claude는 각 연결 버튼에서 공식 웹사이트에 직접 로그인한 뒤 사용량 화면의 숫자를 수동으로 확인합니다. 읽기 전에 사용률·잔여율과 구간을 선택하세요. 사용률을 선택하면 100에서 빼 잔여율로 표시합니다. Grok은 주간, Claude는 세션 또는 주간 값 하나를 선택합니다. 서로 다른 구간을 합산하지 않습니다.")
                    Text("웹 값에는 수동 확인 표시·구간·시각이 붙습니다. 1시간이 지나면 ‘지난 확인’으로 표시되며 자동으로 갱신되지 않습니다. 값이 남아 있어도 현재 잔여량과 다를 수 있으니 서비스의 공식 사용량 화면을 함께 확인하세요.")
                }
                Section("로고 라이선스") {
                    Text("서비스 로고는 CodexBar의 MIT 라이선스 리소스를 사용합니다. 각 서비스의 상표는 해당 소유자에게 있습니다.")
                    DisclosureGroup("라이선스 전문") {
                        Text(thirdPartyNotices)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                }
                Section("홈 화면 위젯") {
                    Text("홈 화면을 길게 누른 뒤 편집 → 위젯 추가 → CodexTime을 선택하세요. 앱에서 먼저 연결하거나 예시 보기를 시작하면 위젯에도 표시됩니다.")
                    Text("위젯은 Codex에 대해 약 30분 뒤 갱신을 요청하지만 실제 시각은 iOS가 결정합니다. 새로고침 버튼은 Codex만 조회합니다. Grok·Claude는 앱에서 마지막으로 수동 확인한 숫자만 표시하며 위젯에서 로그인하거나 웹을 조회하지 않습니다. 네트워크 오류 시 마지막 캐시가 남을 수 있습니다.")
                    Text("예시 모드에서는 실제 Grok·Claude 사용량을 섞어 표시하지 않습니다. 각 웹 값은 예시를 끝내면 다시 표시됩니다.")
                }
                Section("개인정보와 연결 해제") {
                    Text("Codex 로그인은 OpenAI의 외부 기기 인증 페이지에서 진행합니다. Codex 인증 토큰은 iCloud 동기화되지 않는 이 기기의 Keychain에 보관하며, 서명된 앱과 위젯만 공유합니다.")
                    Text("Grok·Claude 로그인은 앱 안에 열린 해당 서비스의 공식 웹페이지에서 직접 진행합니다. 웹 세션은 앱 실행 중 메모리에만 유지하고 앱 종료 후에는 다시 로그인해야 합니다. 웹 쿠키·토큰을 앱 코드로 꺼내거나 저장·전달하지 않습니다. 완료로 화면을 닫아도 실행 중인 앱의 웹 세션은 유지됩니다.")
                    Text("Grok·Claude에서 저장하는 것은 사용량 숫자, 사용률·잔여율 구분, 선택한 구간과 확인 시각뿐입니다. 이 기기의 앱과 위젯이 숫자 캐시만 공유합니다. 웹페이지 원문·비밀번호·대화 내용은 저장하지 않으며 개발자 서버나 iCloud로 전송하지 않습니다. 로그인·페이지 열기 자체에는 각 서비스의 정보 처리 정책이 적용됩니다.")
                    Text("계정 식별자는 인증 요청에 사용되고 사용량·리셋 시각·누적 토큰은 이 기기에 캐시됩니다. 프로필 응답의 이름·사진은 별도로 저장하지 않으며 대화 내용은 요청하지 않습니다. ID 토큰에는 계정 정보가 포함될 수 있습니다. 개발자 서버로 전송하지 않으며, OpenAI에는 인증·사용량 요청과 네트워크 정보가 전달됩니다.")
                    Text("Codex ‘연결 해제’는 이 기기의 Codex 로그인 토큰과 캐시를 삭제합니다. 각 웹 서비스의 ‘연결 해제·기록 삭제’는 해당 메모리 웹 세션과 숫자 캐시를 삭제합니다. 서비스 계정이나 구독을 삭제·해지하지 않으며 다른 브라우저의 로그인도 변경하지 않습니다.")
                    Text("광고, 추적, 분석 SDK, 앱 내 구매와 자체 회원가입은 없습니다. 공개 지원 페이지를 열면 GitHub의 접속 정보 처리 정책이 적용됩니다.")
                }
                Section("지원과 한계") {
                    Text("CodexTime은 각 서비스의 공식 제품이 아닙니다. 외부 인증·사용량 화면 변경에 따라 연결이나 숫자 읽기가 중단될 수 있습니다. Codex 조회에는 Codex 사용 권한이 있는 ChatGPT 계정이 필요하며, Grok·Claude는 자신의 계정에서 공식 사용량 화면을 열 수 있어야 합니다.")
                    Link("개인정보 처리방침", destination: URL(string: "https://github.com/sundaynighttt/codextime/blob/694397676e700a164cb9d931b449a230267fe865/docs/privacy-policy.md")!)
                    Link("문제 신고 및 지원", destination: URL(string: "https://github.com/sundaynighttt/codextime/issues")!)
                    Text("지원 요청에 로그인 코드, 토큰 또는 실제 계정 응답을 첨부하지 마세요.")
                        .font(.footnote)
                }
            }
            .navigationTitle("CodexTime 안내")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}
