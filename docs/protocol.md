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

## iPhone alpha

The iPhone app cannot run the local Codex CLI. It uses OpenAI's device-login flow and then requests the authenticated account's Codex usage metadata directly.

1. Request a device code from `auth.openai.com`.
2. Ask the user to approve that code on OpenAI's official device page.
3. Exchange and refresh the OAuth tokens with `auth.openai.com`.
4. Read the primary window's `used_percent` and `reset_at` fields from the ChatGPT usage response.

Tokens stay in the shared iOS Keychain access group. The widget requests a new timeline after 30 minutes, but WidgetKit controls the actual execution time and may use the last cached snapshot.

## Compatibility boundary

`app-server`, `account/rateLimits/read`, and the iPhone usage path are compatibility-sensitive interfaces. CodexTime's desktop parser ignores unrelated JSON-RPC notifications and initialization responses, but a renamed method, authentication change, or materially changed response shape will require a compatibility update.
