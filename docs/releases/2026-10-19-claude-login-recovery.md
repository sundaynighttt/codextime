# Claude 로그인 제한 안내·화면 복구 — 1.0(15)

**현재 단계: external_processed / passed.** 빌드15의 로컬 테스트·Release 화면·archive 서명을 검증했다. **2026-10-19 22:38:48 KST TestFlight 업로드 성공, 22:41:37 KST Apple 테스트 가능 알림**으로 처리 완료와 기존 테스터 설치·업데이트 가능을 확인했다. Apple 처리 확인 최신은 **1.0(15)**다. ASC의 정확한 그룹 배정 UI·인원은 빌드15에서 확인하지 않았다. 이 단계는 실제 계정 인증·사용량·위젯 검증 완료를 뜻하지 않는다. 개인정보의 인증정보·캐시 경계와 정책 고정 링크 `694397676e700a164cb9d931b449a230267fe865`는 유지한다.

## 사용자 보고와 조사 범위

사용자는 TestFlight 빌드14를 사용한 실기기에서 **Grok 로그인 성공**, **Claude에서 Google 로그인 후 흰 화면과 복귀 불가**를 보고했다. Grok 사용량 읽기·위젯까지 검증됐다는 보고는 아니므로 로그인 성공만 기록한다.

빌드14 시뮬레이터에서 Claude의 Google 버튼을 누르면 공식 오류가 잠시 나타난 뒤 `accounts.google.com`의 빈 이메일 화면은 열렸다. 로그인 정보 입력·제출은 수행하지 않았고 로그인 이후의 흰 화면은 직접 재현하지 못했다. 따라서 사용자 증상의 전체 원인을 확정하지 않는다.

정적 검토에서는 `createWebView`가 HTTPS 새창 요청을 부모 웹뷰에 로드하고 `nil`을 반환해 새창·opener 관계를 보존하지 못하는 경로와 복귀 조작 부재를 확인했다. 이는 복구 동작을 보강할 근거이며 실제 로그인 이후 흰 화면의 단일 원인으로 확정한 것은 아니다.

## 공식 제약과 후보 동작

Google은 앱이 통제하는 embedded user-agent로 OAuth 인증을 보내는 것을 제한한다. [Use secure browsers](https://developers.google.com/identity/protocols/oauth2/policies#use-secure-browsers), [WKWebView의 disallowed_useragent 설명](https://developers.google.com/identity/protocols/oauth2/native-app#disallowed_useragent)을 따른다. Google 버튼이나 빈 이메일 화면이 열리는 것만으로 이 환경에서 OAuth 완료가 지원된다고 설명하지 않는다.

빌드15는 Google/Claude 새창 로그인 진입을 지원 제한 안내로 중단하고 부모 화면을 새창 URL로 덮어쓰지 않는다. 이메일 대안, 뒤로·새로고침·고정된 공식 사용량 화면 복귀, 페이지 오류·웹 프로세스 종료 복구를 제공한다. 빌드14의 넓은 웹 화면과 기존 Grok 로그인·수동 숫자 읽기는 유지한다. **Google OAuth 완료는 미지원이며, 이번에 확인한 것은 제한 안내·부모 화면 보존·Claude로 복귀하는 동작이다.**

외부 Safari나 `ASWebAuthenticationSession`에서 로그인하면 현재 WKWebView에도 로그인된다고 약속하지 않는다. 별도 세션의 쿠키·토큰을 가져오거나 Google의 embedded OAuth 제한을 우회하지 않는다. Google 연결 해제·계정 권한 변경을 사용 조건으로 요구하지 않는다.

## Claude 공식 이메일 대안의 범위

[Claude 공식 로그인 안내](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account)는 이메일 로그인을 설명한다. 기존 Claude 계정과 **같은 이메일**을 사용한다. 로그인 메일의 링크를 다른 기기에서 열어 코드가 제공되면 요청했던 원래 공식 웹 화면에 사용자가 직접 입력한다. 앱·도구가 메일·코드를 읽거나 다른 저장소로 옮기지 않는다.

이 설명은 공식 대안 안내이며 현재 앱의 이메일 로그인·사용량 읽기가 실제 계정에서 완료됐다는 증거는 아니다. 계정·조직·추가 인증 조건에 따라 사용할 수 있는 흐름이 다를 수 있으므로 모든 계정의 로그인을 보장하지 않는다.

## 로컬 검증과 중간 실패 이력

- 소스 커밋은 `48015b582d0b73c90187eee5807140b49383cb88`이며 변경 5개 파일을 포함한다. 해당 커밋의 GitHub 후보 브랜치 push 성공을 확인했다.
- **XCTest 51개 통과**, 실패·건너뜀·경고·오류 0. 최초 추가 시험 중 4회 crash는 시험 fixture의 직접 `WKNavigation()` 생성·할당 해제 문제였고 정상 local HTML의 실제 WK navigation fixture로 고친 뒤 통과했다. 이를 실제 계정 로그인이나 앱 모델의 실패로 해석하지 않는다.
- iPhone17e Release의 초기 Claude landing에서 같은 프레임의 정상 빈 페이지에 오경고가 없음을 확인했다. Google 버튼은 `newWindowUnsupported` 안내를 띄우며 부모 Claude 화면을 보존했고 **Claude로 돌아가기**를 확인했다. 빈 이메일·Continue가 소프트웨어 키보드 위에 보이고 하단 숨김을 유지했다. 로그인 정보 입력·제출은 수행하지 않았다.
- Grok Release에서 `accounts.x.ai` 공식 로그인 선택 화면이 정상 표시되고 기존 웹 높이를 유지함을 확인했다. 로그인 정보 입력·제출은 하지 않았다.
- 최종 Release 컴파일 경고·오류0. 로그는 `~/Library/Developer/XcodeBuildMCP/workspaces/0.1.2-838a7ffdb7e8/logs/build_sim_2026-10-19T13-25-02-686Z_pid25339_7e6730a5.log`다. 시험 로그는 같은 logs 폴더의 `test_sim_2026-10-19T13-33-58-175Z_pid29657_c59946d1.log`, 결과 번들 식별은 `13-33-58-176Z_pid29657_d02e843b.xcresult`다.
- 첫 archive는 개발 팀 누락으로 실패했고 팀을 명시한 재시도에서 성공했다. `/tmp/codextime-ios-web-usage-15-archive.log` 858행의 archive 성공과 `/tmp/codextime-ios-web-usage-15.xcarchive`의 `codesign --deep --strict` 통과를 확인했다. 앱·위젯 모두 **1.0(15)**와 번들 식별자 `com.sundaynighttt.codextime.ios` / `com.sundaynighttt.codextime.ios.widget`을 확인했다.

## 업로드와 실제 계정 확인

**2026-10-19 22:38:48 KST** `/tmp/codextime-ios-web-usage-15-upload.log` 54~57행의 `Uploaded package is processing`, `Upload succeeded`, `Uploaded CodexTime`, `EXPORT SUCCEEDED`와 단일 업로드 프로세스 exit0을 확인했다. 이후 **22:41:37 KST(13:41:37 UTC)** Apple 알림 제목 **“CodexTime 1.0 (15) for iOS is now available to test.”**와 안내에서 빌드15 처리 완료 및 기존 테스터의 설치·업데이트 가능을 확인했다. iOS17 이상 iPhone의 [기존 테스터용 TestFlight](https://testflight.apple.com/v1/app/6805935440)에서 업데이트한다. 정식 App Store 공개나 새 공개 초대 링크 생성은 수행하지 않았다. 계정 이메일·테스터 식별자·메일 원문·추적값은 저장하지 않는다.

22:41~22:44 KST ASC 목록 확인은 기존 웹 세션이 로그인 화면으로 돌아가 중단됐다. 빌드15의 정확한 그룹 배정 UI·인원은 미확인이지만 Apple의 테스트 가능 알림으로 설치 가능 확인의 차단은 해소됐다. 이 확인을 위해 사용자 재로그인이나 재업로드가 필요하지 않다. 최신 외부 처리 포인터는15로 갱신했다.

사용자 사진의 **새 창 로그인 미지원** 안내는 빌드15의 navigation guard와 일치하며, 사용량 숫자 추출이 지원 구조를 확인하지 못해 읽기를 중단하는 경로와는 별개다. 사진만으로 설치된 정확한 빌드를 확정하지 않는다. 이후 Claude 웹의 **이 링크를 확인할 수 없습니다 / 다시 시도** 오류도 보고됐다. 요청 웹뷰·외부 브라우저 중 어디서 열었는지, 링크 만료·이미 사용 여부는 미확정이며 실제 Claude 연결은 완료되지 않았다. 인증 URL·사진·개인정보는 기록하지 않는다.

실제 Claude 이메일 로그인·공식 사용량 화면 도달·숫자 대조·위젯은 **사용자 TestFlight 검증 대기**다. 사용자는 실제 확인을 TestFlight에서 진행하겠다고 답했다. Google 로그인 자체가 정상화됐다고 설명하지 않는다. Grok은 사용자의 기존 로그인 성공 보고를 보존하고 새 빌드의 실제 숫자·위젯 E2E 완료로 확대하지 않는다. 실제 계정 수치·로그인 정보·인증 코드·원시 응답은 문서에 저장하지 않는다. 이전 [빌드14 UI·배포](2026-10-19-ios-web-height.md), [빌드13 기능·검증](2026-10-19-ios-web-usage.md)과 중단된 iCloud 후보의 이력은 유지한다.
