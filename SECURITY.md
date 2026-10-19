# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository when available. If it is unavailable, open a minimal issue asking for a private contact channel without publishing exploit details.

Do not include any of the following in an issue, pull request, screenshot, or log attachment:

- Codex or ChatGPT authentication files
- access tokens, refresh tokens, session cookies, or API keys
- complete home-directory paths when they reveal private account names

## Supported version

The latest commit on `main` is the supported development version. CodexTime depends on an experimental Codex protocol, so compatibility fixes may follow Codex CLI releases rather than a fixed long-term support schedule.

## Security model

The macOS and Windows apps invoke the locally installed Codex CLI and ask its app server for rate-limit metadata. They do not read or store Codex credential files directly.

The macOS v0.3.0 connection model requires each user to sign in to their own official apps or CLIs. Downloads contain no developer credentials or account cache. The additional sources are Claude Code's default Keychain item and the single `cursorAuth/accessToken` entry in Cursor's `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`. App-level consent is required before each additional connection can read its source. Tokens are used only in app memory. Windows remains Codex-only; iPhone behavior is unchanged.

The Claude adapter sends only usage requests to `https://api.anthropic.com/api/oauth/usage`. The Cursor-backed Grok wrapper uses the fixed `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus` RPC. The single-key query is read-only, with no fallback to another database entry, account, team, cookie, or legacy Grok Bot credential source. The original credentials are not intrinsically scoped to usage-only access; app code limits their use to these fixed requests. These internal interfaces have no guaranteed external-app stability and may be unavailable for some account or subscription types.

Grok's initial manual usage/reset result must match the user's Grok web usage screen before automatic access is activated. While the verification gate is false, automatic requests stop before reading credentials or contacting the network. A failed comparison must not be reported as a completed connection. After verification, enabled connections refresh independently every 600 seconds. Quota snapshots stay in app memory; only non-sensitive consent, verification, denial, and visibility preferences are persisted. Account quota, used percentages, reset dates, and product breakdowns do not belong in source documents or release records.

All three providers are visible by default. Hiding a provider also blocks its automatic, manual, and wake-triggered queries and cancels owned work, while retaining the last successful snapshot in memory. With all providers hidden, a Usage menu target remains available. Disconnecting Claude or Grok revokes the app's connection flags, waits for owned cleanup, and clears its cached snapshot; it does not delete the original credential or log out the official app. Account changes require disconnecting and reconnecting, including a new web comparison for Grok.

Only an explicit Claude connection action can request an OS authorization prompt; background refreshes fail without prompting. A denial is remembered until another explicit connection attempt. OS response time is excluded from the manual store deadline, while network I/O remains bounded. The adapters do not log in, refresh tokens, create or modify credentials, read browser cookies or conversation transcripts, or export credentials to files. Raw account responses, credentials, and raw errors are excluded from logs and diagnostics. Model-specific limits do not determine the shared summary percentage.

The iPhone alpha uses OpenAI's device-login flow. It stores access and refresh tokens in a non-synchronizing iOS Keychain item shared only by the signed app and widget extension. The usage snapshot is stored in their App Group container. No CodexTime version sends analytics or forwards usage data through a CodexTime-operated server.
