# CodexTime App Store 제출 현황

## 현재 후보 1.0(13) — iPhone 단독 공식 웹 사용량

- Codex 직접 로그인·조회와 3열 카드·위젯을 유지하고, Grok·Claude 각각의 공식 웹을 nonPersistent WKWebView에서 열어 직접 로그인·수동 퍼센트 확인을 추가한다. Mac·iCloud·Cursor·새 서버·API 키는 필요하지 않다.
- 사용자는 공식 사용량 화면을 확인하고 사용함/남음과 한도(Grok 주간, Claude 현재 세션/주간)를 정해 숫자 위치 읽기를 한 번 실행한다. 검증된 퍼센트와 고정 결과만 앱으로 반환하며 전체 페이지 원문·로그인 필드·쿠키·토큰을 열람·내보내거나 내부 quota API에 요청하지 않는다.
- 웹 세션은 앱 실행 중 메모리에만 유지하고 앱 종료·연결 해제 후 재로그인한다. 서비스·숫자·의미·한도·확인 시각만 App Group에 보관해 위젯이 마지막 수동 값을 표시한다. 자동 웹 갱신은 없고 1시간 뒤 지난 확인으로 표시한다. 연결 해제·기록 삭제, 유효하지 않은 값·예시 혼합 차단을 검증 대상으로 둔다.
- **빌드 13은 candidate/pending이며 최종 테스트·서명·실제 계정별 성공·TestFlight 업로드/처리는 아직 완료로 기록하지 않는다.** [현재 후보 기록](../releases/2026-10-19-ios-web-usage.md)에 검증·업로드·처리 결과를 각각 추가한다.
- ASC에서 마지막으로 확인한 정식 버전 1.0은 ‘제출 준비 중’이다. 아래 2026-09-04 심사 제출은 당시 이력이며 새 빌드 13의 심사 제출·일반 공개가 아니다.

## 1.0(12) / Mac 0.3.1 iCloud 후보 — 중단·미배포

공유20/Mac102/iPhone24 테스트와 시뮬레이터·Mac ad-hoc 패키징은 통과했으나 iPhone 앱·위젯의 CloudKit entitlement/프로필 불일치로 Release archive와 capability 재시도가 실패했다. Mac Developer ID export도 프로비저닝 대기 후 종료했다. TestFlight 업로드·Mac 정식 설치·실제 iCloud 송수신을 완료하지 않고 보류했다. 현재 웹 후보에는 해당 코드·CloudKit 권한을 넣지 않는다. [중단 이력](../releases/2026-10-19-private-icloud-sync.md).

## 1.0(11) TestFlight 업로드·처리 이력 — 2026-10-19

- 작은 3열 카드와 소형 위젯, 실제 인증·조회는 Codex뿐이며 Grok·Claude는 `— / 미지원`인 빌드다. 17개 테스트·시뮬레이터·서명 검증을 통과했다.
- 13:37:25 KST Xcode `Upload succeeded`·`EXPORT SUCCEEDED`, **13:38:53 KST Apple ready-to-test**로 업로드와 처리 완료를 구분 확인했다.
- 이후 ASC에서 기존 **CodexTime Internal 그룹 1명**, **빌드 11 설치 표시 1**을 확인했다. 이 그룹은 Xcode 빌드를 자동 포함하는 기존 설정이다. 설치 집계만으로 실제 로그인·사용량·위젯 기능 smoke 통과를 추정하지 않는다. [빌드 11 근거](../releases/2026-10-19-ios-three-provider-card.md).

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
- Codex는 본인 ChatGPT 계정으로 직접 인증한다. Grok·Claude는 공식 웹에서 사용자가 직접 로그인·수동 확인하며 자동 조회나 영구 로그인 유지로 소개하지 않는다. Mac·Codex CLI·Cursor·iCloud·별도 API 키가 필요하지 않다. 실제 계정별 성공과 배포 허용은 각각 별도로 확인한다.
- 기본 한도 구간만 표시한다. 모든 구간, 결제 크레딧, 리셋 실행 기능은 없다.
- 위젯은 30분 뒤 갱신을 요청하지만 실제 일정은 iOS가 결정한다.
- 공개 예시 모드는 로그인 없이 작동한다. 심사에만 보이는 숨겨진 경로나 실제 값처럼 꾸민 예시가 아니다.
- 기존 심사 메모의 예시 절차·Codex 직접 인증 설명에 더해 새 후보의 수동 웹 확인·앱 수명 세션·로컬 숫자 캐시·삭제·자동 갱신 없음도 실제 동작에 맞게 설명해야 한다. 새 메모를 ASC에 저장했다는 뜻이 아니다.
- 심사 연락처는 사용자 제공 기존 연락처를 App Store Connect에만 입력한다. 저장소에는 복제하지 않는다.

## 개인정보

현재 웹 후보의 계약은 [저장소 개인정보 방침](../privacy-policy.md)이다. Grok·Claude의 nonPersistent WebKit 공식 로그인, 앱 실행 중 세션 유지, 수동 숫자·의미·한도·시각만 App Group 보관, 연결 해제 시 캐시 삭제, 쿠키·토큰·원문 내보내기 없음, 자동 웹 갱신 없음을 설명한다. Codex의 기기 전용 Keychain·직접 요청 경로는 유지한다.

빌드 11까지 앱 방침 링크는 고정 커밋 `0405d909da7db6fd58a337e417d336b89e88fee3`을 사용했다. 중단된 iCloud 후보의 방침 커밋 `1fa6718bc59942b7bd1b6fd5f410bef6ea2dc4c6`은 별도 과거 계약이다. 두 고정 링크가 새 웹 정책으로 자동 갱신되지는 않는다. 새 후보 배포 전 실제 공개 정책 고정 링크·앱 내 링크·ASC 개인정보 레이블·심사 메모의 일치 여부를 확인해야 한다.

개발자 자체 서버·광고·추적·분석 SDK는 없다. 실제 Codex 인증·사용량 요청과 공식 웹 페이지 열기는 해당 외부 제공자에 접속·인증 요청 정보를 보내므로 ‘외부 처리가 전혀 없다’고 설명하지 않는다. 로그인 세션은 WebKit 메모리, Codex 인증 토큰은 기기 전용 Keychain, 사용량 숫자는 로컬 App Group에 구분 보관한다. 예시는 외부 요청을 수행하지 않으며 실제 웹 값을 섞지 않는다.

빌드 9 당시 ASC 개인정보 레이블은 사용자 ID·기타 사용 데이터·기타 진단 데이터를 앱 기능 목적·사용자 연결·추적 안 함으로 저장했고, 앱·위젯 PrivacyInfo.xcprivacy에 같은 분류와 UserDefaults 사유를 선언했다. 이는 빌드 13의 변경된 공식 웹 처리까지 ASC에서 확인·저장 완료했다는 증거가 아니다. Codex 연결 해제와 각 웹 서비스의 연결 해제·기록 삭제는 해당 기기 데이터를 정리하며 공급자 계정·구독을 삭제하지 않는다.

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
