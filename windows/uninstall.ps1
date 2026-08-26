Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'CodexUsageMonitor'
$shortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex Usage Monitor.lnk'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

Remove-ItemProperty -Path $runKey -Name 'CodexUsageMonitor' -ErrorAction SilentlyContinue
Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue

if (Test-Path $installRoot) {
    Remove-Item -Path $installRoot -Recurse -Force
}

Write-Host 'Codex Usage Monitor 제거 완료'
