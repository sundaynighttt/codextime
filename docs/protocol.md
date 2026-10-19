# Codex usage protocols

## macOS and Windows

CodexTime does not open Codex authentication files. It starts `codex app-server` as a child process and communicates over JSONL using standard input and output.

## Request sequence

1. `initialize`
2. `initialized`
3. `account/rateLimits/read`

## Consumed response fields

- `rateLimitsByLimitId.codex.primary.usedPercent`
- `rateLimitsByLimitId.codex.primary.resetsAt`
- `rateLimitsByLimitId.*.limitName`
- `rateLimitsByLimitId.*.secondary`
- the backward-compatible `rateLimits` snapshot when the keyed map is absent

`resetsAt` is interpreted as Unix epoch seconds. `usedPercent` is clamped into a remaining percentage using `100 - usedPercent`.

The monitor launches a fresh child process for each network refresh and terminates it after receiving a response. It does not attach to the Codex Desktop app's existing app-server session.

## iPhone

The iPhone app cannot run the local Codex CLI. It uses OpenAI's device-login flow and then requests the authenticated account's Codex usage metadata directly.

1. Request a device code from `auth.openai.com`.
2. Ask the user to approve that code on OpenAI's official device page.
3. Exchange and refresh the OAuth tokens with `auth.openai.com`.
4. Read the primary window's `used_percent` and `reset_at` fields from the ChatGPT usage response.
5. Read only `stats.lifetime_tokens` from the authenticated ChatGPT profile response.

The profile response can contain a display name, username, and profile image URL, but CodexTime does not decode or store them. Tokens stay in the shared iOS Keychain access group. The widget requests a new timeline after 30 minutes, but WidgetKit controls the actual execution time and may use the last cached snapshot.

### 1.0(9) 예시 모드와 개인정보 경계

공개 예시 모드는 `demoUsageSnapshot`을 사용하고 실제 캐시 `usageSnapshot`과 분리됩니다. 예시가 활성화되면 앱·위젯의 사용량 client는 Keychain이나 네트워크를 사용하기 전에 예시를 반환합니다. 새로고침은 예시의 갱신 시각만 변경합니다. `isDemo`는 선택 필드라 기존 실제 캐시도 해독할 수 있습니다.

프로필 JSON의 이름·사진을 저장하지 않는다는 것은 인증 토큰에 개인정보가 없다는 뜻이 아닙니다. ID 토큰에는 계정 정보가 포함될 수 있습니다. 실제 조회의 외부 전송, 로컬 저장, 연결 해제 범위는 [개인정보 처리방침](privacy-policy.md)을 따릅니다. 이 구현 자체가 외부 서비스의 독립 앱 이용 허가를 증명하지는 않습니다.

### 이력: 1.0(11) iPhone 3열 표시와 데이터 범위

앱의 작은 사각 카드와 `systemSmall` 위젯은 `Codex / Grok / Claude` 순서로 각 로고·이름·잔여 비율·상태를 가로 3열에 표시한다. 이 변경은 표시 계층만 확장하며, 실제 사용량은 기존 `CodexAccountClient`의 OpenAI 직접 인증·조회와 단일 `UsageSnapshot` 경로를 유지한다. Codex 스냅샷이 없으면 `— / 연결 필요`, 실제 잔여량이 0이면 `0%`로 구분한다. 앱의 Codex 상세에는 리셋·누적 토큰을 유지하고 소형 위젯 하단에는 리셋·갱신 시각을 표시한다.

Grok·Claude는 iPhone 인증·조회 구현이 없어 `— / 미지원`으로 표시한다. Codex의 실제 값이나 예시 값을 다른 공급자에 복제하지 않으며, 예시 모드에서도 두 칸은 미지원 상태를 유지한다. 로고가 보인다는 사실이 해당 계정 연결을 의미하지 않는다.

`SharedUsageStore`의 App Group은 같은 iPhone의 앱과 위젯 사이 저장소다. macOS의 다중 공급자 상태를 전달하는 서버·Mac 연결·기기 간 동기화 경로는 없다. 이번 UI 변경은 macOS Keychain·Cursor 인증정보를 읽거나 iPhone으로 전송하지 않으며 새 자격증명 접근·네트워크 공급자·지속 권한을 추가하지 않는다. Grok·Claude 실제 조회를 추가하려면 iPhone에서 사용할 인증 경로와 개인정보 처리 범위를 별도로 확정해야 한다.

## 현재 후보: macOS 0.3.1 / iPhone 1.0(12) 비공개 iCloud 동기화

이 절은 구현·검증 중인 후보의 데이터 계약이다. 배포·실제 계정 동기화·Apple 처리 완료를 뜻하지 않으며 실제 상태는 [README](../README.md)와 릴리스 기록에서 확인한다. iPhone Codex의 기존 직접 인증·`UsageSnapshot`·App Group·기기 전용 Keychain 경로는 유지한다. Grok은 사용자가 선택한 Mac → 본인 CloudKit → iPhone 경로를 추가하고 Claude 자동 연결은 차단한다.

### 전송 경계와 사용자 격리

공유 `Shared/UsageSync` 모듈의 `SyncedUsage`만 전송하며 허용 필드는 `provider`, `remainingPercent`, `resetAt`, `observedAt`, `status`다. `provider`는 고정 서비스 구분이고 상태는 `ready / disconnected / paused / blocked / failed`의 열거 값이다. Grok의 유효한 실제 조회 결과만 수치를 갖는다. 숨김·연결 해제·공급자 조회 실패는 해당 고정 상태와 빈 수치로 보내며 과거 성공 수치를 현재 성공처럼 재발행하지 않는다. 비율은 0~100 정수, 조회 시각은 공급자 조회 시각이며 클라우드 업로드 시각으로 최신성을 다시 시작하지 않는다. 잘못된 값은 실패 상태로 정규화한다. Claude는 직렬화 경계에서도 모든 수치·시각을 제거하고 `blocked`로 만든다.

비밀번호·인증/갱신 토큰·쿠키·인증 파일·계정 ID/이메일·기기 이름·구독 이름·누적 토큰·제품별 상세·원시 응답·원시 오류를 DTO에 넣지 않는다. 수신 측은 미지 필드가 추가된 payload를 거부한다. 개발자 서버·public/shared CloudKit 데이터베이스는 사용하지 않는다.

CloudKit 컨테이너는 `iCloud.com.sundaynighttt.codextime`, 접근 범위는 `privateCloudDatabase`다. 사용자의 iCloud 계정별 데이터베이스에 분리되며 같은 본인 Apple 계정의 기기만 이 경로로 결과를 공유한다. 계정 범위가 확인된 캐시만 사용한다. iCloud 로그아웃·계정 변경 감지 시 동기화 선택과 해당 로컬 캐시를 지우고 새 계정에서는 재동의를 요구한다. 인증 토큰이나 계정 식별자를 사용량 DTO로 동기화하지 않는다.

### 동의, 갱신, 오류, 삭제

Mac과 iPhone의 동기화 기본값은 꺼짐이며 각각의 명시적 설정이 필요하다. 이 설정은 기존 Grok 연결·웹 대조 gate를 우회하지 않는다. Mac이 깨어 있고 앱 실행·서비스 표시·연결·네트워크가 유지될 때 기존 600초 공급자 조회 결과를 전송한다. iPhone은 앱 새로고침·OS가 허용하는 위젯 갱신에서 결과를 읽는다. CloudKit 전달·WidgetKit 실행은 실시간이나 고정 10분 주기를 보장하지 않는다.

성공 값의 최신성 기준은 `observedAt`이다. 20분 경과 또는 동기화 실패 시 마지막 값과 조회 시각을 이전 정보로 구분하며 실패를 새 성공으로 덮어쓰지 않는다. 수신·계정 확인에 실패했거나 값이 없으면 `—`와 연결/오류 상태를 표시하고 0%나 100%를 만들지 않는다. 예시 모드에서는 실제 cloud cache를 섞거나 예시 수치를 업로드하지 않는다.

iPhone의 수신 해제는 해당 기기의 작업·로컬 캐시만 중지·정리하며 원격 삭제와 별개다. iPhone의 별도 iCloud 삭제 동작과 달리, Mac은 동기화 체크를 끄거나 `끄고 iCloud 값 삭제`를 선택할 때 로컬 중지·캐시 정리와 원격 삭제 요청을 함께 수행한다. 어느 기기든 Apple의 삭제 성공 응답 후에만 삭제 완료로 처리한다. 오프라인·오류는 `deletionPending`이며 재연결 후 재시도가 필요하다. 다른 Mac이 계속 동기화하면 새 레코드가 생길 수 있으므로 전체 중단에는 각 발신 Mac의 설정도 꺼야 한다. iPhone Codex 연결 해제는 기존 Codex 토큰·캐시 삭제이며 iCloud 동기화 설정·삭제를 대신하지 않는다.

### Claude의 현재 차단

Anthropic의 [Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)는 타사 개발자의 Claude.ai 인증정보·세션 토큰 수집·보관·중계를 제한한다. 현재 Claude 구독 Keychain/OAuth 경로는 앱 연결 선택과 무관하게 자격증명·HTTP 접근 전 차단한다. iCloud에도 Claude 실제 수치를 쓰지 않는다. iPhone 직접 웹 로그인·세션 수집·토큰 수동 입력·다른 인증 저장소 탐색을 대체 경로로 추가하지 않는다. 사용자는 공식 [Claude 사용량 페이지](https://claude.ai/settings/usage)를 직접 확인할 수 있다. 허용되는 외부 앱 조회 방식이나 공급자 허가가 확인된 뒤 별도 변경으로 검토해야 한다.

### 빌드 설정과 검증 경계

CloudKit 사용에는 Apple Developer에서 컨테이너와 각 앱 ID의 iCloud capability 연결, 해당 entitlement가 포함된 프로비저닝·서명이 필요하다. 앱·위젯은 동일 컨테이너와 환경을 사용해야 한다. 개발용 CloudKit 스키마와 배포용 production 스키마는 별도이며 TestFlight의 서명·production 스키마 접근까지 확인해야 실제 배포 연결 성공으로 보고할 수 있다. 단위 테스트·시뮬레이터·서명 빌드 성공만으로 실제 iCloud 동기화 성공을 주장하지 않는다.

## Compatibility boundary

`app-server`, `account/rateLimits/read`, and the iPhone usage and profile paths are compatibility-sensitive interfaces. CodexTime's desktop parser ignores unrelated JSON-RPC notifications and initialization responses, but a renamed method, authentication change, or materially changed response shape will require a compatibility update.


<a id="macos-공급자별-상태"></a>

## 이력: macOS v0.3.0 공급자별 상태

**이하 내용은 배포된 v0.3.0의 과거 동작 기록이다. 새 0.3.1 후보의 Claude 차단·선택적 iCloud 동기화가 우선하며, 과거 연결 승인·실조회 성공은 공급자 허용의 근거가 아니다.**

macOS v0.3.0은 `Codex / Grok / Claude`를 기본 모두 표시하며 하나의 네이티브 메뉴 막대 항목에서 순서를 유지한다. 사용자는 `계정 연결 및 표시` 창이나 메뉴에서 서비스별 표시를 선택한다. 기본 수치는 요약 대상으로 지정된 공통 한도 창 중 가장 적게 남은 잔여율을 내림해 표시한다. Claude의 Sonnet·Opus 등 모델별 특수 한도는 상세 메뉴에 남기고 공통 잔여율 계산에서는 제외한다. 응답에 없는 값이나 유효 범위 밖 값은 `—`이며 API 금액·추가 사용량·토큰 합계를 구독 잔여율로 바꾸지 않는다.

- 켜진 서비스만 시작 시·600초마다 독립 조회하며 개별 새로고침을 지원한다. 숨긴 서비스는 자동·수동·잠자기 복귀 조회를 차단하고 진행 중 소유 작업을 취소·정리한다. 숨김은 성공 스냅샷을 메모리에 유지하며, 다시 켜면 연결 허용 범위에서 조회를 재개한다.
- 모두 숨겨도 `사용량` 메뉴 막대 항목과 접근성 설명을 남겨 재설정할 수 있다. 표시 선택은 비민감 사용자 설정으로 저장하며 기본값은 세 서비스 모두 켜짐이다.
- 공급자별 중복 방지와 자동 조회의 15초 store deadline을 유지한다. Claude는 사용자별 앱 연결 동의 전 Keychain·HTTP 접근을 차단하고, Grok은 최초 연결 동의·웹 대조 완료 전 자동 자격증명·네트워크 접근을 차단한다.
- 사용자가 설정에서 시작한 `Claude 연결…`·`Cursor로 연결…`은 같은 공급자의 조회 슬롯을 사용한다. OS 권한 확인을 기다리는 시간에는 store의 15초 deadline을 적용하지 않는다. 실제 HTTP 요청은 공급자 transport의 별도 시간 제한을 유지하며, 권한 대기 중 자동·수동 중복 조회를 시작하지 않는다.
- 성공 응답과 마지막 성공 시각은 메모리에만 유지한다. 실패해도 이전 성공 값을 보존하고 즉시 stale로 표시한다. 마지막 성공 후 20분 경과도 stale이며 메뉴 막대 `*`와 메뉴의 이전 값 상태로 구분한다. 재시작 후 조회 전에는 `—`다.
- 메뉴에는 실제 제공되는 단기·주간·기타 한도, 각 reset, 마지막 성공, 권한 대기와 고정된 오류 문구를 구분한다. 원시 OS·CLI·HTTP 오류, 응답 본문, 계정 식별자와 인증정보는 표시·진단 로그·보고서에 남기지 않는다.
- 종료 시 timer를 중지하고 진행 중 조회 취소·정리를 기다린다. 아직 시작하지 않은 권한 요청은 취소한다. 이미 열린 OS 권한 대화상자는 사용자가 응답해야 반환할 수 있으므로 임의로 우회하거나 같은 요청을 다시 시작하지 않는다.

### 승인된 인증 접근과 권한 동작

공개 앱은 각 사용자의 공식 앱·CLI 로그인과 앱 내 연결 동의를 사용하며 개발자의 인증정보·계정 캐시를 배포하지 않는다. 추가 인증 입력은 Claude Code의 기본 macOS Keychain 항목과 Cursor 저장소의 `cursorAuth/accessToken` 한 항목이다. 두 토큰은 앱 프로세스 메모리에서 지정된 사용량·reset 조회에만 사용한다. 원본 인증정보 자체가 사용량 전용 권한인 것은 아니며 앱의 고정 호스트·경로·HTTP method·응답 필드로 목적을 제한한다. 일반 Grok의 별도 웹 쿠키나 기존 Grok Bot Safe Storage로 인증 범위를 넓히지 않는다.

Claude의 백그라운드 Keychain 조회는 `kSecUseAuthenticationUIFail`을 사용한다. OS 접근 승인이 필요하면 권한 필요 상태로 끝나며 자동으로 확인창을 열지 않는다. 사용자가 `Claude 연결…`에서 사용량 조회에 동의한 경우에만 `kSecUseAuthenticationUIAllow`를 허용한다. OS 암호 입력이나 로그인 제출은 사용자와 공식 앱·CLI가 처리한다.

Claude의 OS 권한 요청을 취소하거나 거부하면 비민감 거부 플래그를 앱 `UserDefaults`에 기억해 자동 재요청을 막으며 명시적인 연결 재시도에서만 해제한다. Claude는 앱 연결 허용 여부를, Grok은 최초 대조 뒤 검증 완료 여부를 기억한다. 연결·검증·거부·표시 플래그에는 인증정보·계정·실제 사용량 값이 없다. 앱은 인증정보를 갱신·마이그레이션·새로 저장하지 않고 refresh token을 사용하지 않는다. 브라우저 쿠키·대화 원문·세션 기록을 읽지 않으며 별도 인증 파일이나 비밀값 로그를 만들지 않는다. 허용 범위를 늘려야 하는 경우에는 자동 대체 경로를 시도하지 않는다.

Claude·Grok의 `연결 해제`는 새 요청을 막고 진행 중 소유 작업 정리가 끝난 뒤 해당 연결 플래그·성공 스냅샷·시각·오류를 지운다. 원본 Keychain·Cursor 인증정보를 삭제하지 않는다. 계정 변경 시 연결 해제와 공식 앱·CLI 로그인, 앱 재연결을 순서대로 수행하며 Grok은 웹 대조도 다시 요구한다. Codex 계정 변경은 공식 CLI에서 처리한 뒤 새로고침한다.

### 공급자별 조회 경로

**Codex:** 사용자가 공식 CLI의 `codex login`을 본인 계정으로 완료한 뒤 사용한다. 기존 `codex app-server`의 `initialize → initialized → account/rateLimits/read`를 유지한다. 인증 파일·브라우저 쿠키를 앱이 직접 읽지 않는다. 기존 nonblocking read·poll·12초 제한·소유 자식 프로세스 정리 안전장치도 유지한다.

**Grok (Cursor 기반 승인 경로):** `GrokSubscriptionUsageProviderClient`는 `CursorGrokCredentialSource`를 명시적으로 주입한 기존 사용량 HTTP client만 사용한다. 자격증명 입력은 Cursor의 `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`에서 아래 한 항목을 읽는 것으로 제한한다.

```sql
SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1
```

저장소는 read-only로 열고 최신 WAL 상태를 보존하는 읽기 경로를 사용한다. 다른 키·계정·선택 team·refresh token을 조회하지 않으며 DB·자격증명을 복사·갱신·마이그레이션하지 않는다. 항목 부재·잠금·지원하지 않는 형식·만료는 고정 오류로 끝낸다. 기존 Grok Bot Safe Storage·Keychain과 Grok Build CLI 구현은 소스에 보존하지만 이 wrapper의 기본·수동·진단 자격증명 공급원으로 선택하지 않는다.

네트워크 요청은 고정 `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus`에 ConnectRPC JSON으로 보낸다. 승인된 access token을 메모리에서 요청 인증에 사용하며 team header를 추가하지 않는다. 응답의 `usagePercent`·`nextResetTimestampUtc`와 공유·enterprise 구분 필드만 해석한다. 비율 부재·범위 오류·지원하지 않는 pooled enterprise 한도는 수치를 만들지 않는다. API 금액·Extra Usage Credits·제품별 사용 비중을 구독 공통 잔여율로 바꾸지 않는다.

자동 wrapper는 `requiresVerification=true`이며 `grokCursorUsageVerified`가 없으면 자격증명 읽기·네트워크 요청 전에 `.notConnected`로 끝난다. 최초 웹 대조를 위해 사용자가 `Cursor로 연결…`에서 사용량 조회에 동의한 경로만 이 gate를 통과한다. 실제 사용률·리셋을 [Grok 사용량 화면](https://grok.com/?_s=usage)과 대조한 뒤 `웹 값과 일치함 · 자동 갱신`과 확인창의 `일치함 · 10분 갱신 시작`을 선택해야 검증 플래그를 활성화한다. 이후 켜진 서비스만 600초마다 독립 갱신한다. 불일치하거나 계정·기간이 확인되지 않으면 연결 완료로 처리하지 않는다. 실제 계정 수치·날짜·제품별 사용 내역은 문서·원장·보고서에 저장하지 않는다.

공식 [Grok FAQ](https://docs.x.ai/grok/faq)의 Usage 표시를 대조 기준으로 사용한다. Cursor 인증으로 RPC가 응답했다는 사실만으로 일반 Grok의 같은 계정·구독 기간·공통 한도라고 단정하지 않는다. 제품별 비중은 사용 내역이며 별도 한도로 합산하지 않는다. 공개 비교자료는 [LoopLabsBar](https://github.com/RichStone/LoopLabsBar/blob/main/looplabsbar.1m.py), [CodexBar](https://github.com/steipete/CodexBar/blob/6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e/docs/grok.md), [codex-limits](https://github.com/thrr87/codex-limits/blob/c1508063a493b8fc433dcdf3cee013f717035805/Sources/CodexLimits/GrokBillingClient.swift)이며 실제 계정 대조를 대신하지 않는다.

**Claude:** 앱 연결 허용 플래그의 기본값은 꺼짐이며, 사용자가 `Claude 연결…`에서 동의하기 전에는 기본 Keychain이나 사용량 HTTP를 조회하지 않는다. 연결 시 현재 로컬 사용자의 기본 Keychain service `Claude Code-credentials` 항목에서 유효한 Claude Code OAuth access token만 앱 메모리에서 사용한다. 다른 프로필·인증 파일·Claude Desktop 저장소를 탐색하지 않는다. 고정 `GET https://api.anthropic.com/api/oauth/usage` 응답의 공통 `five_hour`·`seven_day`와 제공되는 `seven_day_sonnet`·`seven_day_opus`의 `utilization`·`resets_at`만 상태로 옮긴다. 모델별 창은 상세 정보이며 기본 공통 잔여율에서 제외한다. 금액·추가 사용량·계정 정보는 소비하지 않는다.

구독 계정 로그인은 공식 `claude auth login --claudeai` 경로에서 사용자가 완료하며, 앱은 토큰 갱신이나 Keychain 쓰기를 하지 않는다. 항목 부재·만료·401·403은 로그인 필요로 끝낸다. 자동 `/usage`·PTY·모델 요청을 실행하지 않으므로 해당 CLI 명령이 기존 transcript를 순회할 가능성에도 의존하지 않는다.

두 HTTP transport는 임시 세션을 사용하고 쿠키·인증 캐시·URL 캐시를 사용하지 않으며 redirect로 인증정보를 다른 경로에 전달하지 않는다. Claude OAuth usage와 Cursor 기반 `GetSandUsageStatus`는 외부 앱용 공개 안정 API 계약이 확인된 것은 아니다. 응답·인증 방식이 바뀌면 연결 오류로 끝내고 별도 호스트·DB 키·쿠키·refresh 경로를 자동 탐색하지 않는다.

### 조사 이력과 실제 검증의 구분

초기 읽기 전용 조사에서는 Grok Bot 공개 자동 조회 경로를 확인하지 못했고 Claude Code는 로그아웃 상태였다. 그때의 `auth status` 전용·미연결 설명은 과거 조사 결과다. 이후 설치 앱·CLI의 정적 코드로 위 경로를 확인하고 사용자의 지속 접근 승인을 받아 연결 코드를 추가했다.

2026-10-19 공식 Claude Code OAuth 로그인 후 설치 앱 0.2.4(2026101902)의 실제 Codex·Claude 사용량 응답 성공을 확인했다. 과거 Grok Bot 진단 2026101903은 지정 Keychain 항목 미발견으로 끝났다. 이후 사용자가 Bot 사용량 화면은 보인다고 확인하고 일반 Grok로 대상을 바꾸어 해당 추적을 중단했다. 2026101904는 새 대상의 미연결 경계를 보호하는 테스트를 포함해 79개 합성·회귀 테스트를 통과했으며, 일반 Grok 실조회 성공을 뜻하지 않는다. 동일 설치판의 background 진단에서 기존 Codex·Claude 실제 응답 성공을 다시 확인했고, Grok은 인증·네트워크 없는 미연결로 종료했다.

프로토콜 비교 참고: [CodexBar Grok](https://github.com/steipete/CodexBar/blob/main/docs/grok.md), [QuotaBar](https://github.com/hibik1725/ai-usage-monitor). 로고 라이선스는 [third-party-notices.md](third-party-notices.md)에 보존한다.
