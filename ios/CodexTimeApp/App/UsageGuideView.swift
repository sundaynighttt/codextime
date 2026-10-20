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
                    Text("Grok은 공식 xAI 승인 페이지에서 본인 계정을 연결하면 사용량을 직접 조회합니다. 공유 로그인 방식을 사용하므로 승인 화면에 Grok Build가 표시될 수 있습니다. 구독 사용률과 한도 기간을 읽으며 선불 API 잔액을 잔여율로 대신하지 않습니다.")
                    Text("Claude는 iPhone에서 외부 승인 페이지를 열고 code#state 인증 결과를 붙여넣는 호환 연결을 시도할 수 있습니다. 공식 타사 앱용 허용과 실계정 호환성은 확인되지 않았습니다. 연결에 성공하면 세션·공통 주간 한도를 함께 읽습니다. 지원되지 않으면 ‘웹에서 직접 확인’에서 ‘사용량 읽기’를 누르세요. Grok의 수동 웹 확인도 남아 있으며 웹 기록은 자동 갱신하지 않습니다.")
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
                    Text("앱이 활성 상태일 때 연결된 Codex·Grok과 호환 연결에 성공한 Claude는 약 10분마다 조회하고, 앱으로 돌아오면 오래된 값을 확인합니다. 위젯은 약 30분 뒤 갱신을 요청하지만 실제 시각은 iOS가 결정합니다. 새로고침은 직접 연결된 서비스를 조회합니다. 수동 웹 기록은 마지막 확인 값만 표시합니다. 일반 조회 실패 시 마지막 값과 실제 확인 시각을 유지합니다.")
                    Text("예시 모드에서는 실제 Grok·Claude 사용량을 섞어 표시하지 않습니다. 각 웹 값은 예시를 끝내면 다시 표시됩니다.")
                }
                Section("개인정보와 연결 해제") {
                    Text("Codex·Grok은 각 공급자의 공식 외부 기기 인증 페이지에서 로그인합니다. Claude 호환 연결은 공식 외부 승인 페이지의 일회용 결과를 사용합니다. 로그인 유지를 위한 인증정보는 iCloud 동기화되지 않는 이 기기의 보안 저장소에 보관하며, 같은 서명 그룹의 앱과 위젯만 공유합니다. Grok·Claude 인증정보는 사용량 조회에만 사용하며 대화나 모델 생성 요청을 보내지 않습니다.")
                    Text("Claude와 Grok의 수동 웹 확인은 앱 안에 열린 공식 웹페이지에서 직접 로그인합니다. 이 웹 세션은 앱 실행 중 메모리에만 유지하고 앱 종료 후에는 다시 로그인해야 합니다. 웹 쿠키·토큰을 앱 코드로 꺼내거나 저장·전달하지 않습니다. 완료로 화면을 닫아도 실행 중인 앱의 웹 세션은 유지됩니다.")
                    Text("사용량 기록에는 숫자, 한도 기간, 제공되는 리셋과 실제 확인 시각을 저장합니다. 직접 연결의 인증정보는 숫자 캐시와 분리해 보관합니다. 웹페이지 원문·비밀번호·대화 내용은 저장하지 않으며 개발자 서버나 iCloud로 전송하지 않습니다. 로그인·조회·페이지 열기에는 각 서비스의 정보 처리 정책이 적용됩니다.")
                    Text("계정 식별자는 인증 요청에 사용되고 사용량·리셋 시각·누적 토큰은 이 기기에 캐시됩니다. 프로필 응답의 이름·사진은 별도로 저장하지 않으며 대화 내용은 요청하지 않습니다. ID 토큰에는 계정 정보가 포함될 수 있습니다. 개발자 서버로 전송하지 않으며, OpenAI에는 인증·사용량 요청과 네트워크 정보가 전달됩니다.")
                    Text("Codex ‘연결 해제’는 이 기기의 Codex 인증정보와 캐시를 삭제합니다. Grok·Claude 계정 화면의 ‘연결 해제·기록 삭제’는 해당 직접 연결의 인증정보와 사용량, 수동 웹 기록을 지웁니다. 새 인증을 발급하면 이전 계정의 직접 조회 값도 비웁니다. 웹 화면의 삭제는 해당 웹 세션과 수동 숫자만 지웁니다. 서비스 계정·구독이나 다른 브라우저의 로그인은 변경하지 않습니다.")
                    Text("광고, 추적, 분석 SDK, 앱 내 구매와 자체 회원가입은 없습니다. 공개 지원 페이지를 열면 GitHub의 접속 정보 처리 정책이 적용됩니다.")
                }
                Section("지원과 한계") {
                    Text("CodexTime은 각 서비스의 공식 제품이 아닙니다. 외부 인증·사용량 응답과 웹 화면 변경에 따라 연결이나 조회가 중단될 수 있습니다. Codex는 Codex 사용 권한이 있는 ChatGPT 계정, Grok 직접 조회는 지원되는 Grok 구독과 사용량 응답이 필요합니다. Claude 호환 연결은 계정별 허용 여부 확인이 필요하며 자동 지원이 보장되지 않습니다. 수동 웹 확인은 본인의 공식 사용량 화면을 열 수 있어야 합니다.")
                    Link("개인정보 처리방침", destination: URL(string: "https://github.com/sundaynighttt/codextime/blob/9cd429d37b04dabc3ebb303072d1c9c04d371a56/docs/privacy-policy.md")!)
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
