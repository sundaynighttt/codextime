import SwiftUI

struct UsageGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("남은 사용량 확인") {
                    Text("ChatGPT 계정을 연결하면 계정 응답의 기본 사용량 한도, 다음 리셋 시각과 제공되는 경우 누적 토큰을 표시합니다. 모든 한도 구간이나 API 결제 잔액을 표시하는 것은 아닙니다.")
                    Text("예시 데이터로 둘러보기는 누구나 사용할 수 있는 오프라인 기능입니다. 예시 값은 실제 계정이나 실시간 조회 결과가 아니며 앱과 위젯에 ‘예시’로 표시됩니다.")
                }
                Section("홈 화면 위젯") {
                    Text("홈 화면을 길게 누른 뒤 편집 → 위젯 추가 → CodexTime을 선택하세요. 앱에서 먼저 연결하거나 예시 보기를 시작하면 위젯에도 표시됩니다.")
                    Text("위젯은 약 30분 뒤 갱신을 요청하지만 실제 시각은 iOS가 결정합니다. 새로고침 버튼과 마지막 업데이트 시각을 함께 확인하세요. 네트워크 오류 시 마지막 캐시가 남을 수 있습니다.")
                }
                Section("개인정보와 연결 해제") {
                    Text("로그인은 OpenAI의 외부 기기 인증 페이지에서 진행합니다. 비밀번호를 이 앱에 입력하지 않습니다. 인증 토큰은 iCloud 동기화되지 않는 이 기기의 Keychain에 보관하며, 서명된 앱과 위젯만 공유합니다.")
                    Text("계정 식별자는 인증 요청에 사용되고 사용량·리셋 시각·누적 토큰은 이 기기에 캐시됩니다. 프로필 응답의 이름·사진은 별도로 저장하지 않으며 대화 내용은 요청하지 않습니다. ID 토큰에는 계정 정보가 포함될 수 있습니다. 개발자 서버로 전송하지 않으며, OpenAI에는 인증·사용량 요청과 네트워크 정보가 전달됩니다.")
                    Text("‘연결 해제’는 이 기기의 앱 로그인 토큰과 사용량 캐시를 삭제합니다. ChatGPT 계정이나 구독을 삭제·해지하지 않습니다. OpenAI 계정 관리는 해당 서비스에서 직접 진행하세요.")
                    Text("광고, 추적, 분석 SDK, 앱 내 구매와 자체 회원가입은 없습니다. 공개 지원 페이지를 열면 GitHub의 접속 정보 처리 정책이 적용됩니다.")
                }
                Section("지원과 한계") {
                    Text("CodexTime은 OpenAI의 공식 제품이 아닙니다. 외부 인증·사용량 인터페이스 변경에 따라 연결이 중단될 수 있습니다. 실제 사용량 조회에는 Codex 사용 권한이 있는 ChatGPT 계정이 필요합니다.")
                    Link("개인정보 처리방침", destination: URL(string: "https://github.com/sundaynighttt/codextime/blob/0405d909da7db6fd58a337e417d336b89e88fee3/docs/privacy-policy.md")!)
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
