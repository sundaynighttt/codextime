# Codex app-server protocol note

앱은 Codex 인증 파일을 직접 열지 않고 `codex app-server` 자식 프로세스와 JSONL로 통신합니다.

요청 순서:

1. `initialize`
2. `initialized`
3. `account/rateLimits/read`

사용 필드:

- `rateLimitsByLimitId.codex.primary.usedPercent`
- `rateLimitsByLimitId.codex.primary.resetsAt`
- `rateLimitsByLimitId.*.limitName`
- `rateLimitsByLimitId.*.secondary`

`resetsAt`은 Unix epoch seconds입니다. 프로세스는 조회마다 새로 시작하고 응답 수신 후 종료하므로 Codex Desktop 앱의 기존 app-server 세션과 결합되지 않습니다.
