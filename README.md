# Codex Usage Monitor

Codex의 남은 사용량과 리셋까지 남은 시간을 메뉴바 또는 시스템 트레이에서 바로 보여주는 개인용 유틸리티입니다.

- macOS: 메뉴바에 `Codex 96% (6d 16h)` 형태로 표시
- Windows: 트레이 아이콘에 잔여 퍼센트, 툴팁과 메뉴에 전체 상태 표시
- 별도 OpenAI API 키 불필요
- 브라우저 쿠키나 인증 토큰을 직접 읽지 않음
- 설치된 Codex CLI의 `app-server` 프로토콜과 현재 로그인 상태 사용

## 요구 사항

- Codex CLI가 설치되어 있고 ChatGPT 계정으로 로그인되어 있어야 합니다.
- 현재 구현은 Codex CLI `0.144.3`의 `account/rateLimits/read` 응답으로 검증했습니다.
- 이 프로토콜은 experimental이므로 Codex 업데이트 후 호환성 확인이 필요할 수 있습니다.

## macOS

```bash
cd macos
./scripts/install-macos.sh
```

기본 설치 위치는 `~/Applications/Codex Usage Monitor.app`입니다. 앱 메뉴에서 로그인 시 자동 실행을 켤 수 있습니다.

## Windows

PowerShell에서 저장소의 `windows` 폴더로 이동한 뒤 실행합니다.

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -EnableStartup
```

기본 설치 위치는 `%LOCALAPPDATA%\CodexUsageMonitor`입니다. Windows는 macOS처럼 트레이에 임의 문자열을 계속 표시할 수 없으므로 아이콘 안에 잔여 퍼센트를 그리고, 마우스를 올리거나 메뉴를 열면 리셋 시간을 보여줍니다.

제거할 때는 먼저 트레이 메뉴에서 앱을 종료한 뒤 설치 폴더의 `uninstall.ps1`을 실행합니다.

## 데이터 해석

Codex 응답의 `usedPercent`를 `100 - usedPercent`로 바꿔 남은 퍼센트를 표시합니다. 기본 메뉴바 값은 `limitId == "codex"`인 메인 주간 버킷을 사용하며, Spark 같은 별도 버킷은 상세 메뉴에 함께 표시합니다.
