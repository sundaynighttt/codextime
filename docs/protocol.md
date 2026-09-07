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

## Compatibility boundary

`app-server`, `account/rateLimits/read`, and the iPhone usage and profile paths are compatibility-sensitive interfaces. CodexTime's desktop parser ignores unrelated JSON-RPC notifications and initialization responses, but a renamed method, authentication change, or materially changed response shape will require a compatibility update.
