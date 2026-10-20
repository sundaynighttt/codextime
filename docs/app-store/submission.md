# CodexTime App Store 제출 현황

## 1.0(17) 로컬 후보 — 아이폰 단독 직접 연결

- **local_verified/passed:** 앱·위젯 빌드와 합성 XCTest170개 및 시뮬레이터 연결 화면 검증을 통과했다. 이 항목은 로컬 소스 후보의 범위다. Apple 처리 확인 최신은 아래 **1.0(16)**이며 빌드17의 업로드·Apple 처리·내부 테스터 배정·실제 기기 설치·사용량 대조는 아직 완료로 기록하지 않는다. 합성 시험과 실제 계정 성공을 구분한다.
- Grok은 xAI 기기 인증과 이 앱 전용 Keychain·billing 직접 조회 후보다. 공유 공개 OAuth 클라이언트이므로 승인 화면에 Grok Build가 표시될 수 있다. `openid offline_access grok-cli:access` 범위로 기기 코드가 발급됨은 확인했지만 실제 계정 billing 권한·공식 웹 숫자와 reset 대조·토큰 갱신은 미검증이다. CodexTime의 독립 등록·공식 승인을 뜻하지 않는다.
- Claude는 공개 Claude Code 클라이언트 선례를 참고한 독립 PKCE **비공식 호환 기술 후보**다. [공식 인증 지침](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)은 자체 앱의 Claude.ai 로그인과 구독 인증정보 수집·보관·중개를 제한한다. [공식 로그인 안내](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account)는 타사 개발자에게 API 키 경로를 안내하고 특정 타사 도구 허용은 Anthropic의 재량이라고 설명한다. 사용량 전용·개인 오픈소스·내부 TestFlight 명시 예외나 CodexTime의 허용은 확인하지 못했다. 실제 로그인·`user:profile` usage 권한·활성 배포 여부는 별도 판단하며 공개 구현 사례를 허가 근거로 사용하지 않는다.
- 연결된 직접 공급자는 앱 활성화·복귀·수동 새로고침·활성 중 10분 갱신, 위젯 타임라인에서 독립 조회하는 후보다. iOS가 실제 위젯 실행 시점을 결정하므로 정해진 백그라운드 간격을 보장하지 않는다. 수치 부재·만료·지난 조회·재연결 필요를 구분하고 실제 조회 시각만 표시한다.
- 인증은 이 앱이 새로 발급받은 토큰만 기기 전용 Keychain에 보관한다. App Group에는 최소 숫자·기간·리셋·실제 조회 시각과 연결 세대만 저장한다. 다른 앱·CLI·브라우저의 인증정보, Mac·PC·iCloud·개발자 중계 서버를 사용하지 않는다. 모델·대화·과거 세션 조회도 없다. 기존 nonPersistent WebKit 수동 확인을 별도 대체 경로로 유지한다.
- 새 개인정보 처리 범위는 [현재 정책](../privacy-policy.md)과 [프로토콜](../protocol.md)에 반영한다. 이 정책을 공개한 커밋에 앱 내 링크를 고정한 뒤 실제 archive의 URL·서명·권한을 확인해야 한다. ASC 개인정보 레이블·심사 메모를 저장했다는 뜻은 아니다.

## TestFlight 처리 완료 1.0(16) — Claude 세션·주간 한 번 읽기

- **external_processed/passed:** 사용자가 Claude 로그인 성공·공식 사용량 패널 도달을 보고했고 부모가 제공 화면을 확인했다. 실제 수치·사진·인증 URL은 기록하지 않는다. 로그인 성공과 새 파서·캐시·위젯 실계정 검증은 구분한다.
- 기존 strict 사용량 URL 조건으로 실제 패널에서 읽기 버튼이 숨거나 로그인 안내가 남고, 의미·한도·숫자 위치 선택이 복잡한 문제에 대응한다. Claude 공식 HTTPS 호스트에서 사용자가 **사용량 읽기**를 누를 때만 보이는 패널의 정해진 한국어·영어 라벨과 숫자를 제한된 DOM 검사로 구분한다.
- 현재 세션·전체 모델 주간의 두 숫자가 모두 검증돼야 한도별로 갱신하고 부분 결과·실패는 두 이전 값·시각을 유지한다. 두 한도를 별도로 보관하며 주간을 대표로, 세션을 앱·위젯에 별도로 표시한다. 모델별 한도·첫 퍼센트 추정·한도 합산은 제외한다. Grok은 기존 의미·한도 선택과 위치 탭 읽기를 유지한다.
- 인증 입력·쿠키·토큰·웹 저장소·전체 페이지 원문·네트워크 응답에 접근하지 않는다. Google/새창 제한·복귀와 메모리 웹 세션은 유지한다. 웹 자동 갱신은 없다.
- **80개 XCTest·최종 Release·archive 서명 통과**, 앱·위젯 모두1.0(16)을 확인했다. 소스 `0effad7`을 후보 브랜치에 공개했고 **2026-10-19 23:40:44 KST 업로드 성공·23:43:46 KST Apple 테스트 가능 알림**을 확인했다. iOS17 이상 iPhone의 [기존 테스터용 TestFlight](https://testflight.apple.com/v1/app/6805935440)에서 업데이트할 수 있다. 정확한 ASC 그룹 UI·인원과 빌드16의 iPhone 실계정 숫자·위젯 대조는 미확인이며 재업로드·ASC 재로그인은 필요하지 않다. [실제 DOM 구조·fixture·Release·배포 근거](../releases/2026-10-19-claude-usage-reader.md). 새 개인정보 계약 `9cd429d37b04dabc3ebb303072d1c9c04d371a56`의 공개와 앱 고정 링크를 확인했다.

## TestFlight 처리 완료 1.0(15) — Claude 로그인 제한 안내·복구

- **external_processed/passed:** 사용자 빌드14 실기기 Grok 로그인 성공·Claude Google 로그인 후 흰 화면/복귀 불가 보고에 대응한다. Grok 사용량·위젯까지 통과한 것으로 추정하지 않는다.
- 빌드14 시뮬레이터는 Google 빈 이메일 페이지까지 열렸으나 로그인 정보를 입력하지 않아 로그인 이후 흰 화면은 직접 재현하지 못했다. 정적 새창/opener 계약 손실과 복귀 조작 부재를 확인했고 전체 원인은 미확정이다.
- Google의 [embedded OAuth 제한](https://developers.google.com/identity/protocols/oauth2/policies#use-secure-browsers)에 따라 Google/Claude 새창 진입을 안내 후 중단하고 부모 페이지를 덮어쓰지 않는다. Google OAuth 완료는 미지원이며 제한 안내와 Claude 화면 복귀를 검증했다. 공식 이메일 대안과 뒤로·새로고침·고정 사용량 복귀·오류/프로세스 종료 복구를 추가한다.
- [Claude 공식 이메일 경로](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account)는 같은 계정 이메일을 사용한다. 실제 앱 내 완료는 미검증이다. 외부 브라우저 세션 자동 이전·쿠키/토큰 복사·Google 연결 해제나 계정 권한 변경을 요구하지 않는다.
- **51개 XCTest·Release 컴파일(실패/건너뜀/경고/오류0), iPhone17e의 Google 제한 안내·부모 보존·Claude 복귀·빈 이메일/키보드, Release archive·엄격 서명을 통과했다.** 앱·위젯 모두1.0(15)와 각 번들 식별자를 확인했다. Grok Release의 공식 로그인 선택 화면도 로그인 정보 입력 없이 표시됨을 확인했다. **2026-10-19 22:38:48 KST** 단일 업로드 프로세스 exit0과 Xcode `Upload succeeded`·`Uploaded CodexTime`·`EXPORT SUCCEEDED`를 확인했다. **22:41:37 KST Apple 테스트 가능 알림**으로 처리 완료와 기존 테스터 설치·업데이트 가능을 확인했다. iOS17 이상 iPhone의 [기존 테스터용 TestFlight](https://testflight.apple.com/v1/app/6805935440)를 이용한다. ASC 웹 세션이 로그인 화면으로 돌아가 빌드15의 정확한 그룹 UI·인원은 미확인이지만 이메일 근거로 설치 가능 확인의 차단은 해소됐다. 이를 위한 사용자 재로그인·재업로드는 필요하지 않으며 최신 외부 처리 포인터는15로 갱신했다. [시각·알림 제목·검증 근거](../releases/2026-10-19-claude-login-recovery.md). 정책 고정 링크694는 유지한다.
- 사용자 사진의 새창 로그인 미지원은 navigation guard와 일치하며 사용량 숫자 추출이 지원 구조를 확인하지 못해 읽기를 중단하는 경로와는 별개다. 사진만으로 정확한 설치 버전을 확정하지 않는다. 이후 Claude 링크 확인 오류가 보고됐으며 요청 웹뷰/외부 브라우저·만료·이미 사용 여부는 미확정이다. 실제 Claude 이메일 로그인·사용량 대조·위젯은 사용자 TestFlight 검증 대기이며 연결 완료나 Google OAuth 정상화로 기록하지 않는다. 계정 정보·인증 URL·사진은 저장하지 않는다.

## TestFlight 처리 완료 1.0(14) — 웹 로그인 영역 확대

- 빌드13 공통 연결 화면의 긴 안내·숫자 설정 때문에 로그인 웹 영역이 좁아지는 문제를 수리했다. 네이티브 상단 공급자/호스트, 도움말·읽기 설정 시트, 기본 한 줄 하단, 키보드 시 하단 숨김·키보드 닫기를 적용했다.
- 같은 WKWebView 세션과 네이티브 웹 폼 스크롤을 유지한다. View와 빌드 설정만 변경하고 인증·사용량 모델·Coordinator·파서·캐시·권한은 변경하지 않았다. 정책 고정 커밋 `6943976`을 유지한다.
- **external_processed/passed:** iPhone 17e / iOS 26.5의 빈 Claude·Grok 로그인 폼·소프트웨어 키보드·버튼 접근·설정/도움말 복원, XCTest42·Debug/Release·Release archive·엄격 서명을 통과했다. 앱/위젯 1.0(14), App Group·Keychain만 사용하며 CloudKit 권한은 없다.
- 로그인 정보 입력·제출은 수행하지 않았다. 실제 계정 인증·숫자 대조·실기기 smoke 통과로 확대하지 않는다. **2026-10-19 21:39:25 KST 빌드14 TestFlight 업로드에 성공**했다. Xcode의 `Uploaded package is processing`·`Upload succeeded`·`Uploaded CodexTime`·`EXPORT SUCCEEDED`를 확인했다. **21:42~21:43 KST** ASC에서 업로드 상태 완료·제출 준비 완료·90일 유효를 확인하고 [빌드14 상세](https://appstoreconnect.apple.com/teams/8874948e-3fee-4bea-a414-67a4c0f0e7d8/apps/6805935440/testflight/ios/9b6de1a7-c183-4198-a084-9dfe9be7182a)에서 **CodexTime Internal 내부 1명 배정**을 확인했다. 기존 내부 테스터가 설치·업데이트할 수 있다. **21:44 KST** 새 UI 테스트 안내의 저장 완료 상태도 확인했다. 사용자 기기의 설치·실계정 기능 smoke를 완료했다고 추정하지 않는다. 이 내용은 빌드14의 처리·내부 배정 근거이며 최신 후보 포인터는 상단 원장을 따른다. [UI 수리 근거](../releases/2026-10-19-ios-web-height.md).

## TestFlight 처리 완료 1.0(13) — iPhone 단독 공식 웹 사용량

- Codex 직접 로그인·조회와 3열 카드·위젯을 유지하고, Grok·Claude 각각의 공식 웹을 nonPersistent WKWebView에서 열어 직접 로그인·수동 퍼센트 확인을 추가한다. Mac·iCloud·Cursor·새 서버·API 키는 필요하지 않다.
- 사용자는 공식 사용량 화면을 확인하고 사용함/남음과 한도(Grok 주간, Claude 현재 세션/주간)를 정해 숫자 위치 읽기를 한 번 실행한다. 검증된 퍼센트와 고정 결과만 앱으로 반환하며 전체 페이지 원문·로그인 필드·쿠키·토큰을 열람·내보내거나 내부 quota API에 요청하지 않는다.
- 웹 세션은 앱 실행 중 메모리에만 유지하고 앱 종료·연결 해제 후 재로그인한다. 서비스·숫자·의미·한도·확인 시각만 App Group에 보관해 위젯이 마지막 수동 값을 표시한다. 자동 웹 갱신은 없고 1시간 뒤 지난 확인으로 표시한다. 연결 해제·기록 삭제, 유효하지 않은 값·예시 혼합 차단을 검증 대상으로 둔다.
- **빌드 13은 external_processed/passed다.** XCTest 42개(Codex17/웹13/캐시12), 오프라인 Node 96개 사례, Release 3열·연결 버튼·예시 비활성/복원, 앱·위젯 1.0(13) 서명 검증을 통과했다. CloudKit 권한을 포함하지 않는다.
- **2026-10-19 21:13:48 KST** Xcode `Upload succeeded`·`Uploaded CodexTime`·`EXPORT SUCCEEDED`로 TestFlight 업로드를 완료했다. 직전 상태는 `Uploaded package is processing`이었다. 21:15 KST 처리 중을 거쳐 **약 21:18 KST 제출 준비 완료·90일 유효**와 기존 **CodexTime Internal 그룹 1명** 배정을 [빌드 상세](https://appstoreconnect.apple.com/teams/8874948e-3fee-4bea-a414-67a4c0f0e7d8/apps/6805935440/testflight/ios/4e556a52-67f9-4190-a95a-09dca4272252)에서 확인했다. 기존 테스터가 TestFlight에서 설치·업데이트할 수 있다. 빌드 13 실기기 설치·실제 Grok/Claude 로그인·숫자 대조는 사용자 TestFlight 검증 예정이며 아직 완료를 뜻하지 않는다. 정식 App Store 공개·새 공개 초대 링크 생성은 수행하지 않았다. [현재 후보 근거](../releases/2026-10-19-ios-web-usage.md)에 각각 구분한다.
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
- 빌드16 배포본은 Codex 직접 인증·Grok/Claude 공식 웹 수동 확인을 설명한다. 빌드17 직접 연결은 위의 로컬 후보 범위로 구분하며 실제 계정 자동 조회·영구 로그인·모든 계정 성공·공급자 승인으로 소개하지 않는다. 수동 웹의 Claude Google/새창 제한도 유지한다. Mac·Codex CLI·Cursor·iCloud·별도 API 키가 필요하지 않으며 실제 계정별 성공과 배포 허용은 각각 별도로 확인한다.
- 기본 한도 구간만 표시한다. 모든 구간, 결제 크레딧, 리셋 실행 기능은 없다.
- 위젯은 30분 뒤 갱신을 요청하지만 실제 일정은 iOS가 결정한다.
- 공개 예시 모드는 로그인 없이 작동한다. 심사에만 보이는 숨겨진 경로나 실제 값처럼 꾸민 예시가 아니다.
- 심사 메모는 해당 제출 빌드의 실제 동작에 맞춰야 한다. 빌드16의 수동 웹 확인·앱 수명 세션과, 활성 배포가 결정될 경우 빌드17의 직접 인증·기기 전용 토큰·최소 캐시·삭제·OS 갱신 제한을 구분한다. 후보 기능이나 제한을 심사에서 숨기지 않으며 새 메모를 ASC에 저장했다는 뜻이 아니다.
- 심사 연락처는 사용자 제공 기존 연락처를 App Store Connect에만 입력한다. 저장소에는 복제하지 않는다.

## 개인정보

현재 소스 후보의 계약은 [저장소 개인정보 방침](../privacy-policy.md)이다. 빌드17 직접 연결의 이 앱 전용 기기 Keychain·공급자 직접 요청·최소 숫자 캐시·인증 갱신·연결 해제 범위와, 유지되는 수동 WebKit 경로의 앱 수명 세션·수동 숫자·자동 웹 갱신 없음을 구분한다. Codex의 기존 직접 인증·조회는 유지한다. Claude 후보의 공식 허용과 활성 배포는 별도로 확인한다.

빌드 11까지 앱 방침 링크는 고정 커밋 `0405d909da7db6fd58a337e417d336b89e88fee3`을 사용했다. 중단된 iCloud 후보의 방침 커밋 `1fa6718bc59942b7bd1b6fd5f410bef6ea2dc4c6`은 별도 과거 계약이다. 두 고정 링크가 새 웹 정책으로 자동 갱신되지는 않는다. 빌드 13은 새 정책 커밋 [`694397676e700a164cb9d931b449a230267fe865`](https://github.com/sundaynighttt/codextime/blob/694397676e700a164cb9d931b449a230267fe865/docs/privacy-policy.md)을 앱 내 링크에 고정하고 후보 브랜치에 공개했다. ASC 개인정보 레이블·심사 메모의 현재 동작 일치 여부는 별도 확인 항목이며 저장 완료를 주장하지 않는다.

개발자 자체 서버·광고·추적·분석 SDK는 없다. 실제 Codex 인증·사용량 요청과 공식 웹 페이지 열기는 해당 외부 제공자에 접속·인증 요청 정보를 보내므로 ‘외부 처리가 전혀 없다’고 설명하지 않는다. 수동 로그인 세션은 WebKit 메모리, Codex와 직접 연결 후보의 앱 전용 인증 토큰은 기기 전용 Keychain, 사용량 숫자는 로컬 App Group에 구분 보관한다. 예시는 외부 요청을 수행하지 않으며 실제 웹 값을 섞지 않는다.

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
