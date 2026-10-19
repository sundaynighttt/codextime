# Security policy

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository when available. If it is unavailable, open a minimal issue asking for a private contact channel without publishing exploit details.

Do not include any of the following in an issue, pull request, screenshot, or log attachment:

- authentication files, access or refresh tokens, session cookies, API keys, or login codes
- raw account responses, account identifiers, email addresses, or actual quota/reset details
- complete home-directory paths when they reveal private account names

## Supported version and candidate boundary

The latest commit on `main` is the supported development baseline. Release records distinguish uploaded, processed, installed, and publicly released builds; a source change alone proves none of those states. CodexTime depends on compatibility-sensitive provider interfaces, so compatibility fixes may follow provider changes rather than a fixed long-term support schedule.

The security contract below targets the **macOS 0.3.1 (2026101907) / iPhone 1.0(12) iCloud candidate**. Signed artifacts, CloudKit configuration, real cross-device sync, and TestFlight delivery require separate evidence. This policy does not claim those deployment checks have completed. See the [README](README.md) and [protocol](docs/protocol.md) for the current state and historical behavior.

## Provider authentication

The macOS and Windows apps invoke the locally installed Codex CLI and ask its app server for rate-limit metadata. They do not read or store Codex credential files directly. Windows remains Codex-only.

The iPhone app preserves its independent OpenAI device-login flow. It stores access and refresh tokens in a non-synchronizing, device-only iOS Keychain item shared by the signed app and widget extension. Codex usage is cached in their App Group container. Codex authentication and usage are not sent through the optional iCloud bridge.

The macOS Cursor-backed Grok adapter reads only `cursorAuth/accessToken` from Cursor's `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, using a read-only single-key query. It sends only the fixed `POST https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus` RPC. It does not fall back to another entry, account, team, cookie, refresh token, or legacy Grok Bot credential source. The token is used in memory, never in the cloud payload. Its original permissions are not inherently usage-only; app code restricts requests to the fixed usage operation.

Grok's initial manual usage/reset result must match the user's web usage screen for the same account and subscription period before automatic access is activated. Until verification, automatic paths stop before credential or network access. A failed or unconfirmed comparison is not a completed connection. Provider interfaces may change or be unavailable for some subscriptions.

**The current Claude subscription credential path is blocked before Keychain access or HTTP.** Anthropic's [Authentication and credential use rules](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use) restrict third-party collection, storage, and intermediation of Claude.ai credentials and session tokens. App consent does not override this restriction. The candidate neither reads Claude subscription credentials nor syncs Claude quota values; it directs users to the [official usage page](https://claude.ai/settings/usage). It adds no web-session capture, token-paste flow, alternative credential search, or inference requests as a workaround.

macOS v0.3.0 previously used Claude Code's default Keychain item and the OAuth usage endpoint after user consent. That behavior is historical, not the current candidate contract or evidence of provider authorization. Users retaining that older build should disconnect Claude. Previous success and OS permission approval do not establish permission for third-party credential use.

## Local fetching and visibility

All three service entries remain visible by default, including an unavailable Claude state. Hiding a provider blocks automatic, manual, and wake-triggered fetching and cancels owned work. A menu target remains when all providers are hidden. Connected and visible supported services refresh independently every 600 seconds.

The ordinary macOS provider cache stays in memory. Disconnecting Grok stops owned work and clears the app's connection/verification state and snapshot; it does not delete the original Cursor credential or log out the official app. Before a service account change, stop cloud syncing, disconnect, sign in through the official app, and complete a fresh comparison. Credentials are never refreshed, migrated, modified, or exported by these adapters. Cookies, conversation transcripts, raw responses, and raw errors are excluded from logging and diagnostics.

## Opt-in private CloudKit bridge

Cloud sync is **off by default on each device**. The user must enable both the Mac sender and iPhone receiver. It uses only `iCloud.com.sundaynighttt.codextime` and the signed-in user's `privateCloudDatabase`; no public/shared database or CodexTime-operated relay is used. Apple stores and transports the selected usage fields under its iCloud policies.

`Shared/UsageSync` accepts only the typed `SyncedUsage` payload: provider, integer remaining percentage, reset time, provider observation time, and a fixed status enum. Unknown fields are rejected. Passwords, tokens, cookies, authentication files, account IDs/emails, device names, subscription names, lifetime tokens, usage breakdowns, raw responses, and raw errors are excluded. Claude always serializes as blocked with no quota or timestamps. A paused, disconnected, blocked, or failed Grok state contains no quota values.

Cloud records are separated by the current iCloud user's private database. A one-way account scope is kept locally to verify the cache and each operation; it is not included in usage payloads. App and widget cache use requires a verified current account scope. Account change or sign-out clears local cloud readings and the opt-in setting. This does not delete records in the former account.

Latest Grok observations require an awake Mac, a running app, an enabled and verified provider, and network access. CloudKit delivery and WidgetKit execution have no real-time guarantee. Staleness uses the provider's observation time, not cloud upload time: readings older than 20 minutes are marked old. Cloud network failures preserve a distinguishable previous value where available; missing values are not converted into 0% or 100%. Demo mode does not mix real cloud values or upload synthetic quotas.

On iPhone, stopping reception clears only that device's local cloud cache and prevents new reads; deleting iCloud data is a separate action. On Mac, switching sync off or choosing “끄고 iCloud 값 삭제” stops publishing, clears the local cloud cache, and also requests deletion from the current private database. Either platform considers deletion complete only after acknowledgment from CloudKit. Failure/offline deletion remains pending and retryable without silently re-enabling sync. Ordered mutations and operation generations prevent older queued saves from overtaking the local delete. Another enabled sender may create a new record later, so users must disable every sender when stopping the service entirely.

Codex sign-out on iPhone removes its local Codex tokens and cache; it is independent of cloud disable/delete. Neither action deletes a provider account or cancels a subscription. See the [privacy policy](docs/privacy-policy.md) for user-facing retention and deletion details.

## Distribution and verification

CloudKit requires a matching Developer container, app capabilities, entitlements, provisioning profiles, and environment. Production schema access must be verified for signed distribution/TestFlight builds. Unit tests, simulator UI, and archive signing do not establish actual iCloud account isolation or cross-device delivery on their own.

Downloads contain no developer credentials or real account cache. Account quota, used percentages, reset dates, and product breakdowns do not belong in source documents or release records. No version sends analytics or forwards usage data through a CodexTime-operated server. Choosing CloudKit explicitly sends only the allowlisted result fields to Apple.
