# CodexTime 1.0(18) App Store 메타데이터 저장 기준

2026-10-20 기준 App Store Connect의 정식 버전1.0에 연결한 빌드18의 저장 확인 기준입니다. 아래 부제목·프로모션·설명·키워드·영문 심사 메모를 저장했고, 페이지를 다시 연 뒤 표시 문자열이 일치함을 확인했습니다. 개인정보 정책 URL은 앱에 고정된 `5f8851900aa27ae1586fbb6ee0f5f96f35ece8e0` 커밋으로 맞췄으며 기존 개인정보 라벨·수동 출시 설정·심사 연락처를 유지했습니다. ‘심사에 추가’ 이후 제출 초안의 준비 항목에1.0(18)이 표시되고 ‘심사를 위해 제출’ 버튼이 활성화됐지만 최종 제출 버튼은 아직 실행하지 않았습니다. 메타데이터 저장·심사 준비 항목 추가는 최종 접수·승인·일반 공개를 뜻하지 않습니다. 연락처·로그인 코드·계정 수치는 이 파일에 기록하지 않습니다.

## 부제목

20 / 30자

```text
AI 사용량을 한눈에, 홈 화면 위젯
```

## 프로모션 텍스트

116 / 170자

```text
Codex·Grok·Claude의 남은 사용량을 iPhone과 홈 화면 위젯에서 확인하세요. 서비스별 계정 연결, 실제 확인 시각과 이전 값 표시를 제공하며 Mac·PC나 별도 API 키가 필요하지 않습니다.
```

## 설명

1174 / 4000자

```text
CodexTime은 지원되는 Codex·Grok·Claude 계정의 남은 사용량을 한 카드와 홈 화면 위젯에서 확인하는 비공식 유틸리티입니다. 서비스별로 본인 계정을 연결하며, Mac·PC·iCloud 중계나 별도 API 키가 필요하지 않습니다.

서비스별 연결
• Codex: ChatGPT 기기 인증 후 기본 사용량 한도와 리셋 시각, 제공되는 경우 누적 토큰을 표시합니다.
• Grok: xAI 기기 승인 후 구독 사용률과 한도 기간을 조회합니다. 공유 공개 인증 방식을 사용하므로 승인 화면에 Grok Build가 표시될 수 있습니다.
• Claude: 외부 승인 페이지의 일회성 결과를 앱에 붙여넣는 비공식 호환 연결입니다. 연결되면 현재 세션과 공통 주간 한도를 함께 표시합니다. Anthropic의 공식 타사 허용은 확인되지 않았으며 연결이 거부되거나 중단될 수 있습니다.

사용량과 갱신
• 앱 사용 중 약 10분마다 조회하고, 앱으로 돌아오면 오래된 값을 확인합니다.
• 위젯은 마지막 확인 시각을 표시하며 iOS가 허용하는 시점에 갱신합니다. 정확한 백그라운드 주기는 보장하지 않습니다.
• 조회가 실패하면 마지막 성공 값과 확인 시각을 유지하고, 지난 조회나 재연결 필요를 구분합니다.
• Grok·Claude의 공식 웹에서 직접 확인하는 수동 대안도 있습니다. 수동 웹 기록은 자동 갱신하지 않습니다.

개인정보와 예시
인증정보는 iCloud로 동기화되지 않는 기기 전용 보안 저장소에, 최소 사용량 숫자는 같은 기기의 앱·위젯 공유 저장소에 보관합니다. 개발자 서버·광고·추적·분석 SDK는 없습니다. 인증과 사용량 요청은 각 공급자에게 직접 전달되며 해당 공급자의 정보 처리 정책이 적용됩니다. 연결 해제는 이 앱의 해당 인증정보와 기록을 지웁니다.

로그인 없이 공개 예시 모드를 둘러볼 수 있습니다. 예시의 Codex 숫자는 합성 값이며 Grok·Claude는 미연결로 표시합니다. 실제 계정의 사용량과 구분합니다.

CodexTime은 OpenAI·xAI·Anthropic·Apple의 공식 제품이 아니며 제작·보증·제휴를 주장하지 않습니다. 사용 가능한 계정·구독과 공급자 인터페이스가 필요하고, 모든 계정의 연결이나 영구 로그인을 보장하지 않습니다. 대화를 제공하거나 모델 생성 요청을 보내는 앱이 아니며 API 결제 잔액이나 모든 특수 한도를 표시하지 않습니다.
```

## 키워드

40 / 100자

```text
AI,사용량,잔여량,위젯,한도,리셋,생산성,대시보드,usage,quota
```

## Notes for Review — English

3083 / 4000자

```text
Version 1.0, build 18. This is the same iPhone app and widget tested in TestFlight. It is an unofficial, read-only usage utility, not a chat client or a product endorsed by OpenAI, xAI, Anthropic, or Apple.

PUBLIC OFFLINE DEMO
On the first screen, tap "예시 데이터로 둘러보기" (Explore example data). No app account or provider login is needed. The app and small Home Screen widget label the data as examples. Only Codex has a sample number; Grok and Claude remain unconnected. This is a normal public feature, not a reviewer-only account or a substitute for testing account-based connections. End the demo to use real connections.

ACCOUNT CONNECTIONS
Codex: start ChatGPT connection, complete the provider's external device approval, and return to CodexTime.
Grok: tap Grok connection, approve the device code on xAI's external page, then return. The shared public OAuth client may be named "Grok Build" on that page. CodexTime does not claim independent vendor approval. Build 18 recovers transient network interruptions while awaiting approval and distinguishes approval failure from the first usage-query failure.
Claude: tap Claude connection, read the compatibility notice, and choose the compatibility connection. Approve on the external provider page and paste the one-time code#state result into the app. This implementation uses public native-client OAuth/PKCE precedents, including the Claude Code public client identifier. Anthropic's permission for this third-party application is not confirmed, and its policies restrict third-party subscription OAuth. The app discloses this limitation; technical login success is not presented as vendor authorization. The provider may reject or discontinue this route.
The app also offers official-web manual usage confirmation. Those web records are labeled manual and do not refresh automatically. Compatible provider accounts and plans are required for real data.

DATA AND REFRESH
The native clients request authentication and usage only, not conversations or model generation. Newly issued tokens stay in a non-synchronizing, device-only Keychain shared by this app and its widget. Minimal numeric usage, period, reset, and observation time stay in the device's App Group. There is no developer relay server, iCloud relay, advertising, tracking, analytics SDK, or in-app purchase. Provider network processing still applies. Disconnect removes this app's provider credentials and records, not the provider account or subscription.
Foreground refresh is approximately every 10 minutes and on return when data is old. WidgetKit decides background timing; a fixed interval is not guaranteed. Ordinary query failures preserve the last successful value and its actual timestamp.

VALIDATION
194 synthetic regression tests and macOS/Windows/iPhone CI passed. A user reported Claude login/display success in build 17 and Grok connection/usage-display success in build 18. Independent numeric/reset comparisons, long-term token refresh, and real-account widget timing remain unverified. No credentials or actual account values are included here.
```

## 적용·검토 경계

- 실제 제출 빌드는1.0(18)이며 새 바이너리 업로드나 기능 변경을 뜻하지 않습니다. 심사 제출·승인·일반 공개는 각각 확인 후 [제출 현황](submission.md)에 기록합니다.
- 로그인 필요 체크 해제는 공개 오프라인 예시를 로그인 없이 검토할 수 있다는 의미입니다. 세 서비스 실계정 연결 전체를 예시만으로 검증할 수 있다는 뜻은 아니며 그 절차와 한계를 위 메모에 명시했습니다.
- 앱의 고정 개인정보 정책 URL은 `5f8851900aa27ae1586fbb6ee0f5f96f35ece8e0` 커밋을 유지합니다. 저장소 정책의 최신 상태 설명이 고정 커밋 내용이나 앱 바이너리를 바꾸지는 않습니다. 인증·기기 보관·제공자 직접 요청·삭제의 데이터 범주는 변경하지 않습니다.
- 개인정보 라벨은 기존 사용자 ID·기타 사용 데이터·기타 진단 데이터, 앱 기능 목적·사용자 연결·추적 안 함 선언과 실제 App Store Connect 응답을 대조합니다. 자체 서버가 없다는 이유로 ‘수집 안 함’으로 자동 전환하지 않습니다.
- 스토어 스크린샷은 실제 제출 앱의 현재 화면을 사용하고 합성·예시 숫자는 실제 계정 수치로 소개하지 않습니다. 빌드17 소형 위젯 이미지의 기존 생성 출처를 빌드18 새 캡처로 바꾸지 않습니다.
- 서비스 로그인 성공은 타사 이용 허가를 입증하지 않습니다. 콘텐츠 권한 선언·공식 제휴·공급자 승인을 새로 확인했다고 쓰지 않습니다.

[현재 동작·검증 근거](../releases/2026-10-20-ios-direct-refresh.md) · [개인정보 처리방침](../privacy-policy.md)
