# CodexTime

[![CI](https://github.com/sundaynighttt/codextime/actions/workflows/ci.yml/badge.svg)](https://github.com/sundaynighttt/codextime/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sundaynighttt/codextime?display_name=tag)](https://github.com/sundaynighttt/codextime/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

See your remaining Codex allowance and reset countdown without opening the usage settings page.

- **macOS:** `Codex 95% (6d 16h)` in the menu bar
- **Windows:** `Codex 95% · 6d 16h` beside the notification area, or in an optional draggable top-right mini widget
- Refreshes the Codex allowance every 10 minutes and updates the local countdown every minute
- Uses your existing Codex CLI login; no separate OpenAI API key is required
- Does not read browser cookies or authentication-token files directly

> [!IMPORTANT]
> CodexTime is an unofficial community project and is not affiliated with or endorsed by OpenAI. It relies on the experimental Codex `app-server` protocol, which may change in a future Codex release.

## Preview

![CodexTime macOS menu preview](docs/screenshots/macos-menu-preview.jpg)

The preview uses sample values so a contributor's private allowance is never published.

## Requirements

- Codex CLI installed and signed in with a ChatGPT account
- macOS 13 or newer for the menu-bar app
- Windows 10/11; the release executable is self-contained, with Windows PowerShell 5.1 used only by the installer
- Swift 6 toolchain only when building the macOS app from source

The current implementation has been tested against Codex CLI `0.144.3` and `0.150.0-alpha.8` using the `account/rateLimits/read` method.

## Install on macOS

Download `CodexTime-macOS-<version>.dmg` from the [latest release](https://github.com/sundaynighttt/codextime/releases/latest), open it, and drag **Codex Usage Monitor** to Applications.

The macOS DMG in `v0.1.1` and later is signed with a Developer ID certificate and notarized by Apple. Gatekeeper can therefore verify the downloaded app without requiring an **Open Anyway** override. Release assets also include `SHA256SUMS.txt` for integrity checks.

To build from source instead:

Clone the repository and run the installer:

```bash
git clone https://github.com/sundaynighttt/codextime.git
cd codextime/macos
./scripts/install-macos.sh
```

The app is built, ad-hoc signed, and installed at:

```text
~/Applications/Codex Usage Monitor.app
```

Open the menu-bar item and enable **Launch at Login** if desired. The app uses Apple's standard login-item API and macOS may ask you to approve it in System Settings.

The GitHub release workflow signs and notarizes public macOS artifacts. Local source builds remain ad-hoc signed because the maintainer's Developer ID credentials are never included in the repository.

## Install on Windows

Download `CodexTime-Windows-<version>.zip` from the [latest release](https://github.com/sundaynighttt/codextime/releases/latest), extract it, open PowerShell in the extracted folder, and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -EnableStartup
```

The Windows executable and PowerShell installer are currently not code-signed. Inspect them in this public repository and verify the release checksum if your environment requires signed code.

To build and install from the repository, install the .NET 8 SDK and run:

```powershell
.\windows\test-parser.ps1
.\windows\package-windows.ps1 -Version 0.2.0
Expand-Archive .\dist\CodexTime-Windows-0.2.0.zip .\dist\install
powershell -ExecutionPolicy Bypass -File .\dist\install\CodexTime-Windows-0.2.0\install.ps1 -EnableStartup
```

The installer copies the self-contained app to:

```text
%LOCALAPPDATA%\CodexUsageMonitor\CodexTime.exe
```

By default, CodexTime places a compact text label immediately to the left of the Windows notification area. It stays out of Alt+Tab, does not take keyboard focus, tracks taskbar movement, and hides with an auto-hidden taskbar or a fullscreen app. Click it for details. Right-click it to refresh, switch to the draggable top-right mini widget, toggle startup, or quit. A tray icon remains available as a fallback control surface.

To uninstall, quit CodexTime from its tray menu and run:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\CodexUsageMonitor\uninstall.ps1"
```

## How it works

CodexTime starts `codex app-server` as a short-lived child process and exchanges JSONL messages:

1. `initialize`
2. `initialized`
3. `account/rateLimits/read`

It converts `usedPercent` into a remaining value with `100 - usedPercent`, and converts the Unix `resetsAt` value into a local countdown. The main display prefers the bucket whose `limitId` is `codex`; model-specific buckets such as Spark appear in the detail menu.

See [docs/protocol.md](docs/protocol.md) for the fields CodexTime consumes.

## Privacy and security

- CodexTime delegates authentication to the installed Codex CLI.
- It does not parse `auth.json`, browser cookies, access tokens, or refresh tokens.
- Rate-limit data stays on the local machine.
- No analytics or telemetry are included.
- The child `app-server` process is terminated after each refresh.

Please do not attach Codex authentication files or tokens to bug reports. See [SECURITY.md](SECURITY.md) for reporting security issues.

## Configuration

GUI applications can have a smaller `PATH` than your terminal. CodexTime checks common Codex locations automatically. To use a custom executable, set:

```text
CODEX_CLI_PATH=/absolute/path/to/codex
```

On Windows this may point to `codex.exe`, `codex.cmd`, `codex.bat`, or `codex.ps1`.

## Troubleshooting

### Codex CLI not found

Confirm that `codex --version` works in a terminal, then restart CodexTime. If Codex is installed in a custom location, set `CODEX_CLI_PATH`.

### Usage lookup fails after a Codex update

Run `codex app-server --help`. If the command or `account/rateLimits/read` protocol changed, open an issue with the Codex CLI version and the error message. Never include authentication files.

### Windows label is hidden

The taskbar label intentionally hides while the taskbar is auto-hidden or another app is fullscreen on the same monitor. The tray icon remains available under `^`; right-click it to switch to the top-right mini widget if preferred.

## Development

macOS tests and build:

```bash
swift test --package-path macos
./macos/scripts/build-macos.sh
```

Optional live integration test using your current Codex login:

```bash
CODEX_LIVE_TEST=1 swift test --package-path macos --filter fetchesLiveCodexUsageWhenEnabled
```

Windows build and parser tests require the .NET 8 SDK:

```powershell
powershell -ExecutionPolicy Bypass -File .\windows\test-parser.ps1
```

Build release packages locally:

```bash
./macos/scripts/package-macos.sh 0.1.0
```

```powershell
.\windows\package-windows.ps1 -Version 0.2.0
```

Pushing a `v*` tag runs [.github/workflows/release.yml](.github/workflows/release.yml), attaches both packages and `SHA256SUMS.txt` to a GitHub Release, and generates release notes. Optional macOS signing uses the repository secrets documented in [CONTRIBUTING.md](CONTRIBUTING.md).

## 한국어 요약

CodexTime은 Codex의 남은 사용량과 리셋까지 남은 시간을 macOS 메뉴바 또는 Windows 작업표시줄 라벨에 표시합니다. Windows에서는 우상단 미니 위젯 모드로 전환할 수도 있습니다.

- macOS 설치: `macos/scripts/install-macos.sh`
- Windows 설치: `windows/install.ps1 -EnableStartup`
- 최신 DMG/ZIP: [GitHub Releases](https://github.com/sundaynighttt/codextime/releases/latest)
- 별도 API 키 불필요
- Codex 인증 파일과 브라우저 쿠키를 직접 읽지 않음
- Codex의 experimental `app-server` 프로토콜 변경 시 호환성 수정이 필요할 수 있음

## License

[MIT](LICENSE)
