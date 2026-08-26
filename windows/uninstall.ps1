param(
    [switch] $RemoveSettings
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'CodexUsageMonitor'
$settingsRoot = Join-Path $env:LOCALAPPDATA 'CodexTime'
$prototypeExecutable = Join-Path $settingsRoot 'CodexTime.exe'
$prototypeUninstaller = Join-Path $settingsRoot 'uninstall.ps1'
$shortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\CodexTime.lnk'
$legacyShortcutPath = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Codex Usage Monitor.lnk'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

Get-Process -Name 'CodexTime' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
Remove-ItemProperty -Path $runKey -Name 'CodexTime' -ErrorAction SilentlyContinue
Remove-ItemProperty -Path $runKey -Name 'CodexUsageMonitor' -ErrorAction SilentlyContinue
Remove-Item -Path $shortcutPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $legacyShortcutPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $prototypeExecutable -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $prototypeUninstaller -Force -ErrorAction SilentlyContinue

if (Test-Path $installRoot) {
    Remove-Item -Path $installRoot -Recurse -Force
}

if ($RemoveSettings) {
    Remove-Item -LiteralPath $settingsRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'CodexTime uninstalled.'
