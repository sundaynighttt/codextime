param(
    [switch] $EnableStartup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'CodexUsageMonitor'
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenu 'Codex Usage Monitor.lnk'

if (Test-Path $installRoot) {
    $backupRoot = "$installRoot.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Move-Item -Path $installRoot -Destination $backupRoot
}

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'CodexUsage.psm1') -Destination $installRoot
Copy-Item -Path (Join-Path $PSScriptRoot 'CodexUsageMonitor.ps1') -Destination $installRoot
Copy-Item -Path (Join-Path $PSScriptRoot 'CodexUsageMonitor.vbs') -Destination $installRoot
Copy-Item -Path (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $installRoot

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'wscript.exe'
$shortcut.Arguments = "`"$(Join-Path $installRoot 'CodexUsageMonitor.vbs')`""
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = 'Codex 남은 사용량 모니터'
$shortcut.Save()

if ($EnableStartup) {
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $launcher = Join-Path $installRoot 'CodexUsageMonitor.vbs'
    New-ItemProperty -Path $runKey -Name 'CodexUsageMonitor' -PropertyType String -Value "wscript.exe `"$launcher`"" -Force | Out-Null
}

Start-Process 'wscript.exe' -ArgumentList "`"$(Join-Path $installRoot 'CodexUsageMonitor.vbs')`""
Write-Host "설치 완료: $installRoot"
