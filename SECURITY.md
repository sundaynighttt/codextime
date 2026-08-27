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

The iPhone alpha uses OpenAI's device-login flow. It stores access and refresh tokens in a non-synchronizing iOS Keychain item shared only by the signed app and widget extension. The usage snapshot is stored in their App Group container. No CodexTime version sends analytics or forwards usage data through a CodexTime-operated server.
