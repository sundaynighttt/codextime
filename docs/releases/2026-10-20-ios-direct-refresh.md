# iPhone 1.0(17) — 아이폰 단독 직접 조회 후보

2026-10-20 기준 로컬 검증 후보다. Apple 처리 확인 최신은 1.0(16)이며 새 업로드·처리·실기기 계정 검증을 구분한다. Mac·PC·Cursor·iCloud·개발자 중계 서버를 사용하지 않는다.

## 동작

- Grok: xAI 공유 공개 OAuth 기기 승인 → 앱 전용 Keychain → 고정 billing GET. 구독 기간의 주간·월간·미분류를 구별하고 사용률을 잔여율로 바꾼다. `openid offline_access grok-cli:access` 최소 범위에서 익명 기기 코드 발급 HTTP200은 확인했다. `billing:read` 단독 추가 조합은 현 클라이언트에서 invalid_scope였으므로 사용하지 않는다. 계정 승인 이후 billing 권한·웹 숫자 대조는 미검증이다. 승인 화면에 Grok Build가 표시될 수 있으며 CodexTime의 독립 등록·공식 승인을 뜻하지 않는다.
- Claude: 공개 프로토콜 사실을 참고해 독립 구현한 PKCE 호환 후보. 공식 HTTPS 승인 → 사용자 직접 code#state 입력 → 엄격한 state 검증 → 토큰 교환 → 고정 usage GET. 세션 5시간·주간7일을 동일 조회 시각의 한 쌍으로 갱신한다. 최소 user:profile 범위의 실제 usage 권한과 실제 인증 갱신은 미검증이다.
- 직접 연결된 각 서비스는 독립적으로 활성화·복귀 시 오래된 값을 확인하고, 앱 활성 중 600초 간격·수동 새로고침·위젯 타임라인에서 조회한다. 위젯은 30분 이후 갱신을 요청하지만 실행 시각·빈도는 iOS가 결정한다. 앱이 닫힌 상태의 정확한 주기를 보장하지 않는다.
- 사용량 요청은 최대25초와 취소 정리·공유 잠금으로 제한한다. 갱신 토큰의 불확실한 회전 결과를 다시 사용하지 않고 재연결을 요청한다. 새 계정 세대와 연결 해제는 이전 숫자를 무효화한다. 다른 공급자가 느린 동안 해제된 계정의 위젯 결과도 최종 캐시 재확인으로 폐기한다.
- 기존 비영구 WebKit 수동 확인은 별도 대체 경로로 유지한다. 수동 숫자·자동 숫자·지난 조회·재연결 필요를 구분한다. 예시 모드에서 실제 인증정보·네트워크에 접근하지 않는다.

## 인증 허용과 기술 호환성

[xAI 공식 OpenClaw 안내](https://x.ai/news/grok-openclaw)와 [공유 OAuth 문서](https://docs.openclaw.ai/providers/xai), [xAI billing 소스](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-shell/src/extensions/billing.rs)는 기술 근거다. 익명 기기 코드 발급 성공은 계정별 사용량 권한·수치 일치까지 입증하지 않는다.

[Anthropic 공식 인증 지침](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)은 자체 앱의 Claude.ai 로그인 및 구독 인증정보 수집·보관·중개를 제한한다. [공식 로그인 안내](https://support.claude.com/en/articles/13189465-log-in-to-your-claude-account)의 특정 타사 도구 허용은 Anthropic의 재량이다. CodexTime의 허용이나 사용량 전용·개인 OSS·내부 TestFlight 명시 예외는 확인되지 않았다. 공개 clientID와 구현 선례를 허가 증거로 대체하지 않으며 공식 지원·App Store 출시 완료로 표시하지 않는다.

외부 소스 코드를 복사하지 않고 프로토콜 사실과 자체 구현을 사용했다. 공개 선례의 실제 LICENSE가 없는 경우 README의 라이선스 표기만으로 복제 허가를 추정하지 않았다.

## 검증

- iPhone17e/iOS26.5 시뮬레이터 앱·위젯 빌드 및 실행 성공.
- XCTest **170개 통과, 실패0, 건너뜀0**. Grok core22·model13·표시9, Claude core21·model17·표시8과 기존80개를 포함한다.
- PKCE/state·정확한 callback·만료·재로그인·늦은 응답·공유 회전·모호한 회전·25초 취소·원자적 한도·데모·공급자 분리·새 수동 기록 우선 회귀 포함.
- 시뮬레이터의 로그인 전3열 카드·Grok 직접 연결 화면·Claude 제한 안내와 호환 연결 화면을 확인했다. 실제 계정 로그인·계정HTTP·타 앱 Keychain·쿠키·토큰·세션 원문은 검사하지 않았다.
- Release archive의 앱·위젯이 모두1.0(17)이며 코드 서명 검증을 통과했다. 배포용 내보내기·최종 배포 서명은 별도 확인한다.
- 고정 소스의 실제 소형 위젯 뷰로 합성 문서 이미지17을 생성했다. 인증 클라이언트·저장소·네트워크 없는 별도 미리보기 호스트만 사용하고 제거했다.
- 독립 최종 기술 리뷰에 확정 P1/P2 없음.
- 실제 계정의 승인·usage 권한·공식 웹의 값/리셋 대조·앱/위젯 동시 표시·자연스러운 토큰 갱신은 사용자의 TestFlight 확인 대상이다. 모델 호출·메시지 생성은 하지 않는다.

## 배포 상태

현재 소스 후보 1.0(17), 로컬 검증 완료. Release archive·서명·GitHub CI·TestFlight 업로드 및 Apple 처리 결과는 확인 후 이 절과 원장을 갱신한다. 공개 App Store 출시는 수행하지 않았다.

새 개인정보 정책 고정 커밋: `5f8851900aa27ae1586fbb6ee0f5f96f35ece8e0`. 앱은 이 공개 커밋의 정책 URL을 사용한다.
