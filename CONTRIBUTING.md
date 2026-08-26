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
