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

The macOS v0.3.0 connection model requires each user to sign in to their own official apps or CLIs. Downloads contain no developer credentials or account cache. The additional sources are Claude Code's default Keychain item and the single `cursorAuth/accessToken` entry in Cursor's `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`. App-level consent is required before each additional connection can read its source. Tokens are used only in app memory. Windows remains Codex-only. These desktop v0.3.0 sources are independent of the iPhone web candidate described below.

The Claude adapter sends only usage requests to `https://api.anthropic.com/api/oauth/usage`. The Cursor-backed Grok wrapper uses the fixed `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus` RPC. The single-key query is read-only, with no fallback to another database entry, account, team, cookie, or legacy Grok Bot credential source. The original credentials are not intrinsically scoped to usage-only access; app code limits their use to these fixed requests. These internal interfaces have no guaranteed external-app stability and may be unavailable for some account or subscription types.

Grok's initial manual usage/reset result must match the user's Grok web usage screen before automatic access is activated. While the verification gate is false, automatic requests stop before reading credentials or contacting the network. A failed comparison must not be reported as a completed connection. After verification, enabled connections refresh independently every 600 seconds. Quota snapshots stay in app memory; only non-sensitive consent, verification, denial, and visibility preferences are persisted. Account quota, used percentages, reset dates, and product breakdowns do not belong in source documents or release records.

All three providers are visible by default. Hiding a provider also blocks its automatic, manual, and wake-triggered queries and cancels owned work, while retaining the last successful snapshot in memory. With all providers hidden, a Usage menu target remains available. Disconnecting Claude or Grok revokes the app's connection flags, waits for owned cleanup, and clears its cached snapshot; it does not delete the original credential or log out the official app. Account changes require disconnecting and reconnecting, including a new web comparison for Grok.

Only an explicit Claude connection action can request an OS authorization prompt; background refreshes fail without prompting. A denial is remembered until another explicit connection attempt. OS response time is excluded from the manual store deadline, while network I/O remains bounded. The adapters do not log in, refresh tokens, create or modify credentials, read browser cookies or conversation transcripts, or export credentials to files. Raw account responses, credentials, and raw errors are excluded from logs and diagnostics. Model-specific limits do not determine the shared summary percentage.

## iPhone direct Codex and manual web usage

Codex keeps the existing OpenAI device-login flow. Its access and refresh tokens stay in a non-synchronizing, device-only iOS Keychain item shared by the signed app and widget extension. Codex usage is cached in their App Group container.

iPhone **1.0(16), distributed through TestFlight**, uses separate, nonpersistent WKWebView sessions for the official Grok and Claude sites. Users log in and handle password, 2FA, and SSO steps directly in those pages. App code does not enumerate, copy, export, or persist web cookies, tokens, or password fields. There is no cookie import from Safari, another app, or a Mac, and no private quota API or login/challenge bypass. Official-site requests go directly through WebKit to the service and its login providers; no developer relay or iCloud bridge is used.

For Grok, a read requires the user to confirm that the official usage screen is visible, choose used/remaining and the weekly limit, and arm a single direct percentage tap. The tap is consumed for reading and expires after 15 seconds. The bounded in-page check returns only a validated percentage with success status or a fixed failure enum; page bodies, raw text, account details, and authentication material are not returned to Swift or logs. Navigation or changed reading context cancels the pending read. Unsupported page structures fail without manufacturing a value. If a bounded visible label explicitly states used or remaining, it must agree with the user's chosen meaning; disagreement aborts without returning that label. A failed or cancelled read does not erase a previous valid reading.

For Claude in build 16, the user taps Read usage once on the official site. A bounded local check accepts only the visible session and common all-model weekly labels with matching meter percentages. Both validated numeric results must be present before either limit is saved; partial, ambiguous, navigation-invalidated, or cancelled results keep both previous values and timestamps. Model-specific limits are excluded. Label text, page bodies, credentials, web storage, and network responses are not returned to the app.

Web sessions last for the app process. Closing the connection sheet cancels the read but keeps the same in-memory session; explicit disconnect or app termination ends it. Only provider, percentage, used/remaining meaning, chosen limit, and check time persist in the local App Group cache. Invalid values, future timestamps, and mismatched provider/limit combinations are rejected. Session expiry does not silently refresh the cached number. Cards and widgets label it as a manual check, with its limit and timestamp; after one hour it is marked as a past check. The widget and Codex refresh do not run web reads or advance that timestamp. Disconnect and record deletion clear that provider's web session and cached number, independently of Codex sign-out. Demo mode must not expose actual web readings or start a web connection.

Builds 13–15 are historical. Build 16 passed local parser/cache tests and Release signing, and its TestFlight upload and Apple ready-to-test notification are recorded separately in the release ledger. Real-account iPhone numeric and widget verification remains outstanding. Successful login or public source code does not establish provider permission or App Store approval. The interrupted iCloud branch candidates, which reused the Mac 0.3.1 build number independently of the public desktop release and used iPhone 1.0(12), are preserved as [unshipped history](docs/releases/2026-10-19-private-icloud-sync.md), not active dependencies of this web implementation. See the [privacy policy](docs/privacy-policy.md) and [protocol](docs/protocol.md) for retention and deletion details.

No CodexTime version sends analytics or forwards usage data through a CodexTime-operated server.
