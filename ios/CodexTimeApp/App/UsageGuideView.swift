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
                    Text("예시 데이터로 둘러보기는 누구나 사용할 수 있는 오프라인 기능입니다. 예시 값은 실제 계정이나 실시간 조회 결과가 아니며 앱과 위젯에 ‘예시’로 표시됩니다. 예시 보기 중에는 iCloud 조회와 동기화 설정 조작을 일시 정지하고 실제 Grok 값을 숨깁니다.")
                }
                Section("3열 카드") {
                    Text("Codex·Grok·Claude를 한 카드에 표시합니다. Codex는 iPhone에서 직접 조회합니다. Grok은 본인 iCloud 동기화를 켠 경우 같은 Apple 계정의 Mac에서 읽은 결과를 표시합니다. Claude는 공급자 허용 확인이 필요하여 실제 값을 표시하지 않습니다.")
                }
                Section("Mac → iCloud 동기화") {
                    Text("기본은 꺼짐입니다. 켜면 본인 Apple 계정의 비공개 iCloud에 Grok 잔여율·리셋 시각·조회 시각·상태만 저장하고 앱·위젯에서 읽습니다. 서비스 토큰·비밀번호·대화 내용은 옮기지 않습니다. 개발자 서버를 거치지 않으며 iCloud 데이터는 Apple의 처리 정책을 따릅니다.")
                    Text("새 값을 받으려면 같은 Apple 계정의 Mac에서 CodexTime과 인터넷 연결이 동작해야 합니다. Mac이 꺼져 있으면 마지막 조회 시각과 20분 이후 오래된 정보 표시를 확인하세요. 네트워크 오류가 생기면 캐시임을 표시합니다.")
                    Text("‘이 iPhone에서 동기화 해제’는 이 기기의 수신과 동기화 캐시를 지웁니다. ‘iCloud 동기화 데이터 삭제’는 현재 Apple 계정의 동기화 결과도 지웁니다. 다른 Mac에서 동기화가 켜져 있으면 다시 저장될 수 있으므로 Mac에서도 해제하세요. iCloud 로그아웃·계정 변경이 확인되면 이전 계정의 캐시를 지웁니다. 위젯 반영 시점은 iOS 갱신 일정에 따릅니다.")
                    Text("ChatGPT 로그인과 iCloud 연결은 서로 독립적입니다. ChatGPT 연결 해제는 iCloud 동기화를 해제하지 않습니다. iPhone에서 Grok·Claude의 웹 로그인이나 인증 토큰을 수집하지 않습니다.")
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
                    Text("위젯은 약 30분 뒤 갱신을 요청하지만 실제 시각은 iOS가 결정합니다. 새로고침 버튼과 마지막 업데이트 시각을 함께 확인하세요. 네트워크 오류 시 마지막 캐시가 남을 수 있습니다.")
                }
                Section("개인정보와 연결 해제") {
                    Text("로그인은 OpenAI의 외부 기기 인증 페이지에서 진행합니다. 비밀번호를 이 앱에 입력하지 않습니다. 인증 토큰은 iCloud 동기화되지 않는 이 기기의 Keychain에 보관하며, 서명된 앱과 위젯만 공유합니다.")
                    Text("계정 식별자는 인증 요청에 사용되고 사용량·리셋 시각·누적 토큰은 이 기기에 캐시됩니다. 프로필 응답의 이름·사진은 별도로 저장하지 않으며 대화 내용은 요청하지 않습니다. ID 토큰에는 계정 정보가 포함될 수 있습니다. 개발자 서버로 전송하지 않으며, OpenAI에는 인증·사용량 요청과 네트워크 정보가 전달됩니다.")
                    Text("‘ChatGPT 연결 해제’는 이 기기의 ChatGPT 로그인 토큰과 Codex 사용량 캐시를 삭제합니다. ChatGPT 계정이나 구독을 삭제·해지하지 않습니다. OpenAI 계정 관리는 해당 서비스에서 직접 진행하세요.")
                    Text("광고, 추적, 분석 SDK, 앱 내 구매와 자체 회원가입은 없습니다. 공개 지원 페이지를 열면 GitHub의 접속 정보 처리 정책이 적용됩니다.")
                }
                Section("지원과 한계") {
                    Text("CodexTime은 OpenAI의 공식 제품이 아닙니다. 외부 인증·사용량 인터페이스 변경에 따라 연결이 중단될 수 있습니다. 실제 사용량 조회에는 Codex 사용 권한이 있는 ChatGPT 계정이 필요합니다.")
                    Link("개인정보 처리방침", destination: URL(string: "https://github.com/sundaynighttt/codextime/blob/1fa6718bc59942b7bd1b6fd5f410bef6ea2dc4c6/docs/privacy-policy.md")!)
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
