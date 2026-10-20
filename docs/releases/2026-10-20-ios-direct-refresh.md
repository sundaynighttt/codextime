# iPhone 1.0(17) — 아이폰 단독 직접 조회 후보

2026-10-20 기준 아이폰 단독 직접 조회 기술 후보다. 빌드17은 13:21:13 KST 업로드 성공 후 App Store Connect의 처리 완료를 확인했다. Apple 처리 완료와 CodexTime Internal 그룹 배정을 확인했다. 실기기 설치·실계정 검증은 별도로 구분한다. 이후 TestFlight17 사용자 보고와 후속 빌드18 후보는 문서 하단에 이어 기록한다. Mac·PC·Cursor·iCloud·개발자 중계 서버를 사용하지 않는다.

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
- Release archive와 App Store 내보내기의 앱·위젯이 모두1.0(17)이며 Apple Distribution 코드 서명 검증을 통과했다. Team7FCZ5TAX3B, 기존 App Group·Keychain 그룹, 디버깅 비활성, iCloud 권한 없음, iPhone/iOS17 이상과 비면제 암호화 없음 선언을 확인했다. 시스템 신뢰 검사는 필요한 보안 서비스 접근에서 검증했으며 인증서·권한 설정은 변경하지 않았다.
- [최종 GitHub CI](https://github.com/sundaynighttt/codextime/actions/runs/39368369324): iPhone widget5분58초·macOS Swift2분4초·Windows WPF1분39초 모두 통과. [PR20](https://github.com/sundaynighttt/codextime/pull/20)은 검사 후 main에 병합했다(`bc0c82966fdeb3abc2ab2ccf1cfa65dafc42ee75`).
- 고정 소스의 실제 소형 위젯 뷰로 합성 문서 이미지17을 생성했다. 인증 클라이언트·저장소·네트워크 없는 별도 미리보기 호스트만 사용하고 제거했다.
- 독립 최종 기술 리뷰에 확정 P1/P2 없음.
- 실제 계정의 승인·usage 권한·공식 웹의 값/리셋 대조·앱/위젯 동시 표시·자연스러운 토큰 갱신은 사용자의 TestFlight 확인 대상이다. 모델 호출·메시지 생성은 하지 않는다.

## 배포 상태

1.0(17)은 Release·배포 서명·세 플랫폼 최종 CI 통과 후 **2026-10-20 13:21:13 KST 업로드 성공**했다. App Store Connect에서 빌드17의 **제출 준비 완료·CodexTime Internal 그룹·초대1명·설치 표시없음**을 13:25 KST 기준으로 확인했다. 이는 13:25 KST 당시의 관측이며 Apple 처리·내부 그룹 배정과 iPhone 설치·실계정 사용량 성공을 구분한다. 이후 사용자 보고는 아래 후속 절을 따른다. 공개 App Store 출시는 수행하지 않았다.

- 실행 소스: `40d2f2e11367051617ce1127fd6968c35835e932`와 동일한 앱 파일. 문서·이미지를 포함한 최종 검사 소스 `9f5dcb6f05ffd93dd9eacc0fcf3ff5acc8b41aa2`.
- 로컬 배포 IPA: 2,299,784 bytes, SHA256 `e6015797c212b340014496460a2e562c0542c7985d879456770102b3121e93aa`. 업로드는 동일 archive에서 Apple 자동 배포 경로로 수행하며 업로드용 임시 패키지의 보존을 주장하지 않는다.
- 업로드 처리 식별자: `4ac35106-3be9-4b90-9fd2-8f1df6625f59`. 인증정보나 계정별 사용량은 이 기록에 포함하지 않는다.

새 개인정보 정책 고정 커밋: `5f8851900aa27ae1586fbb6ee0f5f96f35ece8e0`. 앱은 이 공개 커밋의 정책 URL을 사용한다.

앱에 고정된 정책 커밋의 후보·배포 상태 문구는 작성 당시 기준이다. 처리 계약은 동일하며 업로드 이후의 현재 상태는 이 기록과 원장을 따른다. 최신 정책의 도입부는 반복되는 배포 상태를 원장 참조로 정리했다.


## 1.0(18) 후속 후보 — Grok 승인 후 앱 복귀

**local_verified/passed:** 빌드18은 Grok 연결 복귀 문제를 다루는 후속 로컬 검증본이다. 시뮬레이터 빌드·실행, 전체 XCTest194개, Release archive·App Store용 로컬 export·앱/위젯 배포 서명 검증을 통과했다. 최종 GitHub CI·TestFlight 업로드·Apple 처리·실기기 수정 확인은 아직 완료로 기록하지 않는다. Apple 처리 확인 최신은 **1.0(17)**이며 위의17 검증·배포 이력은 그대로 보존한다.

### TestFlight17 사용자 보고

- 사용자는 **Claude 로그인·표시 성공**을 보고했다. 이는 해당 사용자의 연결·화면 표시 성공 보고이며 공식 웹 숫자·리셋 대조, 위젯 동시 표시, 장기간 자동 갱신·자연스러운 토큰 회전 또는 Anthropic의 타사 허용 확인으로 확대하지 않는다. 인증정보·실제 사용량 숫자는 기록하지 않는다.
- 사용자는 **Grok 공식 승인 페이지에서는 성공했지만 CodexTime으로 돌아온 뒤 연결하지 못함**을 보고했다. 같은 오류 화면에 **Grok 연결** 버튼만 있고 연결됨·새로고침은 없었다는 추가 보고로, 사용할 수 있는 인증이 저장·확인되기 전 단계로 범위를 좁혔다. 기기 승인 대기·토큰 교환·검증·저장 중 정확한 실패 원인은 미확정이다. 공식 페이지의 승인 성공을 앱의 토큰 교환·usage 권한·billing 성공으로 단정하지 않는다. iOS의 일시적인 요청 취소·연결 단절 가능성과 실제 계정 응답 형식의 호환성을 각각 점검한다.

### 수정 범위와 검증 경계

- 기기 코드 승인 대기 중 일시적인 URLSession 취소·시간 초과·연결 단절은 같은 연결과 승인 만료 시간 안에서 재시도한다. 실제 Task 취소·연결 세대 변경·예시 전환·승인 거부·만료는 즉시 종료한다. 이 재시도를 불확실한 refresh token 재사용이나 무제한 재시도로 확대하지 않는다.
- 기기 인증 토큰 응답의 `token_type` 누락은 지원하되 명시된 잘못된 형식은 거부한다. 만료는 유효한 `expires_in` 또는 access token의 `exp`에서 검증하며 누락·비정상·만료된 값을 임의의 수명으로 대체하지 않는다. 실제 토큰·응답을 로그로 남기지 않는다.
- UI는 **연결 승인을 마무리하지 못함**과 **인증 완료 후 사용량 조회 실패**를 나누어 안내한다. 인증은 보관됐으나 usage 조회만 실패한 경우를 무조건 처음부터 로그인하라는 안내로 합치지 않으며, 조회 성공이나 수치를 만들지 않는다.
- 기존 `openid offline_access grok-cli:access` 범위·고정 xAI 인증/billing 경로·기기 전용 Keychain·앱/위젯 공유 잠금·연결 세대·숫자 캐시·삭제 계약을 유지한다. Mac·PC·iCloud·개발자 서버·다른 앱 인증정보·모델 호출은 추가하지 않는다. 개인정보 처리 범주의 변경 없이 앱 고정 정책 커밋 `5f8851900aa27ae1586fbb6ee0f5f96f35ece8e0`을 유지한다.

### 빌드18 검증 상태

- iPhone 시뮬레이터 빌드·실행 통과.
- iOS 통합 XCTest **194개 통과, 실패0, 건너뜀0, 실행8.5초**. 합성·회귀 검증이며 실제 계정의 승인·usage 요청이나 실기기 복귀 성공을 뜻하지 않는다.
- Release archive와 App Store용 로컬 export를 통과했다. 앱·위젯 모두1.0(18), Team7FCZ5TAX3B의 Apple Distribution strict/deep 서명, 기존 App Group·auth Keychain 그룹, 디버깅 비활성·iCloud 권한 없음·iPhone 전용·최소iOS17.0·고정 개인정보 정책 URL `5f8851900aa27ae1586fbb6ee0f5f96f35ece8e0`을 확인했다.
- 로컬 배포 IPA는 **2,322,180 bytes**, SHA256 `8449f07733a8c6ddf9cfe846bbfcb0b29a5e1cb6c318feec4aaf9c43b31400e5`다. 로컬 내보내기는 업로드·Apple 처리의 근거가 아니다.
- 읽기 전용 최종 동료 검토에서 차단 결함이 확인되지 않았다.
- 빌드18 최종 GitHub CI·TestFlight 업로드·Apple 처리·실기기 연결 복귀·usage 숫자/리셋 대조는 미확인이다. 실제17 실패 원인과18의 실기기 수정 효과를 확정하지 않으며 합성 검증과 구분한다.
