# Contributing

Issues and focused pull requests are welcome, especially for Codex protocol compatibility and Windows runtime verification.

## Before opening a pull request

1. Keep changes scoped to one problem.
2. Never commit Codex authentication files, tokens, cookies, or private logs.
3. Run the relevant tests:

   ```bash
   swift test --package-path macos
   ```

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\windows\test-parser.ps1
   ```

4. Describe the operating system, Codex CLI version, expected behavior, and observed behavior.

Live integration tests are optional because they require a local signed-in Codex installation. Do not expose live response payloads if they contain account-specific metadata.

## Release maintainers

Pushing a version tag such as `v0.1.0` builds and publishes the macOS DMG and Windows ZIP. Without signing secrets, the workflow produces an ad-hoc signed, non-notarized macOS app and unsigned Windows PowerShell scripts.

To Developer ID-sign and notarize the macOS artifact, configure these GitHub Actions secrets:

- `MACOS_CERTIFICATE_P12`: base64-encoded Developer ID Application certificate (`.p12`)
- `MACOS_CERTIFICATE_PASSWORD`: password for that `.p12`
- `MACOS_KEYCHAIN_PASSWORD`: temporary CI keychain password
- `APPLE_DEVELOPER_IDENTITY`: full `Developer ID Application: ...` identity
- `APPLE_ID`: Apple developer account email
- `APPLE_APP_PASSWORD`: app-specific password for notarization
- `APPLE_TEAM_ID`: Apple Developer Team ID

Do not add any certificate, password, token, or notarization credential to the repository.
