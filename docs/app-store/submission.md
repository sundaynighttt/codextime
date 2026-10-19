# CodexTime App Store 제출 현황

## 현재 후보 1.0(12) — 본인 iCloud Grok 동기화

- 앱과 소형 위젯의 **Codex / Grok / Claude 가로 3열**을 유지한다. Codex는 기존 iPhone OpenAI 직접 인증·조회 경로를 보존한다.
- Grok은 macOS **0.3.1(2026101907)** 후보에서 조회·웹 대조한 최소 결과를 같은 본인 Apple 계정의 비공개 CloudKit 저장소로 전달한다. Mac·iPhone 모두 기본 꺼짐이며 각 기기에서 명시적으로 켠다. 최신 결과에는 깨어 있는 Mac·실행 중인 앱·연결·네트워크가 필요하다.
- 전송 필드는 서비스 구분·정수 잔여율·리셋·공급자 조회 시각·고정 상태뿐이다. 비밀번호·토큰·쿠키·계정 ID/이메일·기기 이름·구독 이름·누적 토큰·원시 응답·오류는 전송하지 않는다. 컨테이너 `iCloud.com.sundaynighttt.codextime`의 `privateCloudDatabase`를 사용한다.
- Claude는 [공식 인증 제한](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)에 따라 실제 값 없이 차단 상태를 표시한다. Mac Keychain/HTTP 접근과 Claude 수치 동기화도 차단하며, iPhone 웹 로그인·세션 수집·토큰 붙여넣기를 추가하지 않는다. 과거 macOS 0.3.0의 Claude 연결과 실조회 이력은 현재 허용 근거가 아니다.
- iCloud 계정 범위를 확인한 캐시만 사용하고 계정 변경·로그아웃 때 캐시와 동기화 선택을 지운다. 20분 지난 값·동기화 실패·미연결·실제 0%를 구분한다. iPhone 수신 해제는 로컬 전용이고 iCloud 삭제는 별도다. Mac에서 동기화를 끄거나 ‘끄고 iCloud 값 삭제’를 선택하면 로컬 중지와 원격 삭제 요청을 함께 수행한다. 어느 기기든 삭제 성공 응답이 없으면 삭제 대기로 남는다. 예시 모드는 실제 iCloud 데이터를 섞거나 샘플을 업로드하지 않는다.
- **iPhone 24개·공유 20개·Mac 102개 테스트와 시뮬레이터 검증은 통과했다.** Release archive는 앱·위젯 기존 프로필의 CloudKit 컨테이너 entitlement 불일치로 실패했다. 실제 CloudKit 전달·새 Mac 설치·TestFlight 업로드/처리는 미완료다. [후보 근거](../releases/2026-10-19-private-icloud-sync.md)·[README](../../README.md)·[릴리스 원장](../releases/release-ledger.json)을 확인한다.
- ASC에서 마지막으로 확인한 정식 버전 1.0 상태는 ‘제출 준비 중’이다. 아래 2026-09-04의 ‘심사 대기 중’은 당시 이력이며 현재 상태가 아니다. 새 후보의 App Store 심사 제출·일반 공개를 수행했다는 뜻이 아니다.

## 1.0(11) 3열 UI 업로드·처리 이력 — 2026-10-19

- 앱의 작은 사각 카드와 소형 위젯(`systemSmall`)에 Codex / Grok / Claude의 로고·이름·잔여 비율·상태를 가로 3열로 표시했다.
- 실제 인증·조회는 Codex뿐이며 Grok·Claude는 `— / 미지원`이었다. Mac 결과 전달·새 공급자 인증·iCloud 동기화는 포함하지 않는다.
- 시뮬레이터 빌드·단위 테스트 **17개**·서명 검증을 통과했다. 2026-10-19 **13:37:25 KST** Xcode의 `Upload succeeded`·`EXPORT SUCCEEDED`로 업로드 성공을 확인했다.
- **13:38:53 KST Apple 공식 메일의 빌드 1.0(11) ‘ready to test’ 알림으로 처리 완료를 확인했다.** 테스트 그룹 배포·실기기 설치는 별도로 확인하지 않았다. 이 상태는 빌드 12나 실제 Grok/Claude 연결의 검증 증거가 아니다. [빌드 11 근거](../releases/2026-10-19-ios-three-provider-card.md).

## 1.0(10) TestFlight 업로드·처리 이력 — 2026-10-19

- iPhone Codex 앱·위젯 **1.0(10)**을 13:02:56 KST TestFlight/App Store Connect에 업로드했다. Xcode `Upload succeeded`와 `EXPORT SUCCEEDED` 확인.
- 14 tests·시뮬레이터 실행·Release archive·앱/위젯 서명 검증 통과. Codex 단일 표시 빌드로 macOS의 Claude·Grok 기능은 포함하지 않는다.
- 업로드 직후 처리 중이었으며, 13:04:42 KST Apple의 테스트 가능 알림으로 처리 완료를 확인했다. 테스트 그룹 배포·실기기 설치는 별도로 확인하지 않았다.

## 2026-09-04 확인 이력

- 앱: CodexTime, Apple ID `6805935440`
- iPhone 전용, iOS 17 이상, 버전 `1.0`, 빌드 `9`
- 08:37 KST App Store Connect 업로드 성공. Apple 처리 완료 후 정식 버전에서 빌드 9 선택·저장 확인. 심사 제출·승인·일반 공개와는 구분한다.
- 한국어, 유틸리티, 연령 등급 4+, 무료, 175개 국가·지역, 수동 출시 설정. Apple Silicon Mac·Vision Pro 호환 배포는 끄고 iPhone만 대상으로 한다.
- 설명·영문 심사 메모·개인정보 레이블 저장 및 6.9형 실제 스크린샷 2장 등록 완료. 6.5형도 6.9형 이미지를 상속한다.
- 사용자에게 ‘타사 콘텐츠를 사용하며 필요한 권한이 있음’이라는 선언 문구를 설명하고 권한 보유 확인을 받은 뒤, 해당 항목을 선택·저장했다. ‘타사 콘텐츠에 접근하지 않음’으로 우회하지 않았다. 권한 근거의 독립적인 법률 검증을 완료했다는 뜻은 아니다.
- **09:55 KST 정식 App Store 심사 제출 완료, 당시 ‘심사 대기 중’.** 제출 ID는 `08be042e-7fc3-4b69-b52f-250dcbbf00d8`이며 [접수 상세](https://appstoreconnect.apple.com/apps/6805935440/distribution/reviewsubmissions/details/08be042e-7fc3-4b69-b52f-250dcbbf00d8)에서 `1.0 (9)`를 확인했다. 심사 승인·일반 공개는 아직 이루어지지 않았다.
- 이전 TestFlight 0.3.0(1–8)은 내부 테스트 이력이다. 2026-09-04 App Store Connect에서 빌드 1은 내부 테스트 중, 2–8은 제출 준비 완료로 확인했다. 설치 건수만으로 실기기 검증 통과를 추정하지 않는다.

## 1.0(9) 변경 이력

기존 위젯 제목 옆 갱신 시각·새로고침 정렬(빌드 8)을 유지한다. 누구나 쓸 수 있는 오프라인 예시 모드, 예시/실제 캐시 분리, 앱과 위젯의 예시 표시, 이용 안내·개인정보·지원 링크, 앱 본문의 누적 토큰 표시를 추가했다. 실제 계정의 로그인 및 사용량 요청 경로는 변경하지 않았다.

## 스토어 표현과 심사 경계

- 비공식 읽기 전용 사용량 대시보드이며 OpenAI·xAI·Anthropic·Apple의 제작·보증을 주장하지 않는다.
- Codex 직접 조회에는 사용자의 ChatGPT 계정이 필요하며 Codex CLI·켜져 있는 Mac·별도 API 키는 필요하지 않다. Grok의 최신 결과는 같은 본인 iCloud 계정의 Mac에서 전달하므로 Mac 실행과 Grok 연결·웹 대조가 필요하다. Claude는 실제 연결이 차단된 상태이며 공식 사용량 페이지를 안내한다. 세 로고가 보인다는 사실을 세 서비스 모두 직접 로그인·조회된다는 설명으로 사용하지 않는다.
- Codex 기본 한도와 지원되는 Grok 공통 잔여율만 표시한다. 결제 크레딧·모델 실행·리셋 실행 기능은 없다.
- 위젯은 30분 뒤 갱신을 요청하지만 실제 일정은 iOS가 결정한다.
- 공개 예시 모드는 로그인 없이 작동한다. 심사에만 보이는 숨겨진 경로나 실제 값처럼 꾸민 예시가 아니다.
- 빌드 9의 기존 영문 심사 메모에는 `예시 데이터로 둘러보기 → 위젯 추가 → 예시 끝내기` 절차, OpenAI 외부 기기 인증과 `wham/usage`, `wham/profiles/me` 접근을 설명했다. 빌드 12를 제출할 때는 명시적 iCloud 선택, Mac 필요 조건, 허용 필드와 Apple 보관, 오래된 값·삭제 대기·Claude 차단도 현재 동작에 맞게 갱신해야 한다. 아직 ASC 메모 저장을 완료했다는 뜻이 아니다.
- 심사 연락처는 사용자 제공 기존 연락처를 App Store Connect에만 입력한다. 저장소에는 복제하지 않는다.

## 개인정보

현재 후보 계약은 [저장소 개인정보 방침](../privacy-policy.md)을 따른다. 새 CloudKit 전송·저장·삭제 내용을 담은 저장소 변경이 공개 고정 링크와 ASC 메타데이터에도 실제 반영됐는지 별도로 검증해야 한다.

빌드 12 후보의 앱 안내는 공개된 고정 커밋 `1fa6718bc59942b7bd1b6fd5f410bef6ea2dc4c6`의 [새 정책](https://github.com/sundaynighttt/codextime/blob/1fa6718bc59942b7bd1b6fd5f410bef6ea2dc4c6/docs/privacy-policy.md)을 가리킨다. 기존 배포 앱의 링크 `0405d909da7db6fd58a337e417d336b89e88fee3`는 과거 정책이며 자동 갱신되지 않는다. 소스 링크 수정만으로 배포 앱·ASC 개인정보 레이블까지 갱신됐다고 주장하지 않는다. 새 후보 배포 전 최종 번들 링크·ASC 레이블을 검증해야 한다.

개발자 자체 서버·광고·추적·분석 SDK는 없다. 실제 Codex 연결은 OpenAI에 인증·계정 식별·사용량 요청과 네트워크 정보를 보내며, 선택한 iCloud 동기화는 최소 사용량 필드를 Apple에 저장·전달한다. ‘어떤 데이터도 수집되지 않음’이라고 일괄 답하지 않는다. 토큰은 기기 전용 Keychain, Codex 캐시와 계정 범위가 확인된 iCloud 캐시는 로컬 저장소에 구분 보관한다. 비밀번호·인증 토큰·쿠키·계정 ID/이메일을 iCloud 사용량 payload에 넣지 않는다.

빌드 9 당시 ASC 개인정보 레이블은 보수적으로 사용자 ID·기타 사용 데이터·기타 진단 데이터를 앱 기능 목적·사용자 연결·추적 안 함으로 저장했다. 앱·위젯의 `PrivacyInfo.xcprivacy`도 해당 분류와 UserDefaults의 앱 내부·App Group 사용 사유를 선언했다. 이는 빌드 12의 변경된 CloudKit 처리까지 ASC에서 검토·저장 완료했다는 증거가 아니다.

Codex 연결 해제는 해당 기기의 Codex 토큰·캐시를 지우며 iCloud 동기화 선택과는 독립적이다. iPhone의 ‘이 iPhone에서 동기화 해제’는 수신·로컬 캐시만 정리하고, ‘iCloud 동기화 데이터 삭제’는 별도로 원격 삭제를 요청한다. Mac의 동기화 끄기 또는 ‘끄고 iCloud 값 삭제’는 전송·로컬 캐시 중지와 원격 삭제 요청을 함께 수행한다. 두 기기 모두 Apple의 성공 응답 후에만 삭제 완료로 처리하며 오프라인·실패는 삭제 대기로 남긴다. iCloud 계정 변경은 로컬 선택·캐시를 지우지만 이전 계정의 클라우드 레코드를 삭제하지 않는다. 각 기능은 외부 서비스 계정·구독 삭제와 다르다.

## 1.0(9) 검증 이력

- iOS 단위 테스트 14개 통과: 기존 파싱·표시, 예시 식별, 실제 캐시 보존, 갱신 시각, 네트워크 요청 없는 예시 및 종료 검증 포함.
- iPhone 17 Pro Max/iOS 26.5 시뮬레이터 앱 실행·예시·새로고침·안내 화면 확인.
- 시뮬레이터를 entitlement 포함 ad-hoc 서명으로 실행해 App Group을 통한 위젯 `예시 / 73% / 누적 토큰` 전달 확인. 무서명 시뮬레이터 실행은 공유 저장소 확인 근거로 사용하지 않는다.
- App Store용 archive 및 앱/위젯 코드 서명 검증 통과, 업로드 성공.
- [GitHub CI](https://github.com/sundaynighttt/codextime/actions/runs/33819164677): macOS Swift, Windows WPF, iPhone widget 모두 성공.
- 6.9형 1320×2868 PNG: 실제 앱의 예시 사용량 화면, 이용 안내 화면. 실제 계정 데이터나 합성 UI를 사용하지 않는다.
- 새 빌드의 실기기 실제 계정 로그인은 아직 별도 검증하지 않았다.

## 1.0(9) 소스 및 이미지 식별

- 업로드 소스: `a56efb7` (개인정보 방침 고정 커밋 `0405d90` 포함)
- Apple 처리된 빌드 UUID: `0784ea2e-a387-4a0f-bef5-48025a3cc36f`
- [PR #13](https://github.com/sundaynighttt/codextime/pull/13)은 기존 위젯 변경 PR #12 위에 쌓은 별도 PR이다. main 병합·데스크톱 태그·새 GitHub Release는 하지 않았다.
- `01-usage-demo.png` SHA-256: `12dbae73498c4555eaf9ff41d4d0c2e4dca97d123f247d27bdf0c46aad8ab621`
- `02-guide.png` SHA-256: `84193b8646c13813df7b60efcb8b2db2168807c8a8edebf4b6365e792b75daef`

## 재현

`ios/project.yml`에서 버전·빌드를 정하고 XcodeGen을 실행한다. App Store export 설정은 `ios/Config/ExportOptions-AppStore.plist`다. 로컬 `dist/`의 archive·배포 로그·스크린샷은 Git에 포함하지 않는다. 업로드 성공 로그만으로 Apple 처리·심사 통과를 주장하지 않는다. [릴리스 원장](../releases/release-ledger.json)과 README의 기준선을 함께 갱신한다.

## 심사 이후 경계

Apple의 심사 결과에 따라 보완하며, 승인 후에도 수동 출시 전까지 일반 공개하지 않는다. 콘텐츠 권한 선언은 사용자의 권한 보유 확인에 근거했다. 단순 로그인 성공이나 GitHub 소스 공개, 심사 접수를 서비스 이용 허가 증거로 대체하지 않는다. [Codex 인증 안내](https://learn.chatgpt.com/docs/auth)는 Codex의 기기 인증 방식을 설명하지만 이 앱의 독립 배포에 대한 별도 허락을 확인해 주지는 않는다. [OpenAI 이용약관](https://openai.com/policies/row-terms-of-use/)의 구체적인 적용·허용 범위에 관한 독립 검토는 수행하지 않았다.
