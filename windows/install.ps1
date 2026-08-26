param(
    [switch] $EnableStartup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installRoot = Join-Path $env:LOCALAPPDATA 'CodexUsageMonitor'
$settingsRoot = Join-Path $env:LOCALAPPDATA 'CodexTime'
$prototypeExecutable = Join-Path $settingsRoot 'CodexTime.exe'
$prototypeUninstaller = Join-Path $settingsRoot 'uninstall.ps1'
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenu 'CodexTime.lnk'
$legacyShortcutPath = Join-Path $startMenu 'Codex Usage Monitor.lnk'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$legacyStartup = Get-ItemProperty -Path $runKey -Name 'CodexUsageMonitor' -ErrorAction SilentlyContinue
$currentStartup = Get-ItemProperty -Path $runKey -Name 'CodexTime' -ErrorAction SilentlyContinue
$startupWasEnabled = $EnableStartup -or $null -ne $legacyStartup -or $null -ne $currentStartup

Get-Process -Name 'CodexTime' -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like '*CodexUsageMonitor.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 300
Remove-Item -LiteralPath $prototypeExecutable -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $prototypeUninstaller -Force -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
$stagedExecutable = Join-Path $installRoot 'CodexTime.exe.new'
$stagedUninstaller = Join-Path $installRoot 'uninstall.ps1.new'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'CodexTime.exe') -Destination $stagedExecutable -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'uninstall.ps1') -Destination $stagedUninstaller -Force

@(
    'CodexUsage.psm1',
    'CodexUsageMonitor.ps1',
    'CodexUsageMonitor.vbs',
    'CodexTime.exe',
    'uninstall.ps1'
) | ForEach-Object {
    Remove-Item -LiteralPath (Join-Path $installRoot $_) -Force -ErrorAction SilentlyContinue
}
Move-Item -LiteralPath $stagedExecutable -Destination (Join-Path $installRoot 'CodexTime.exe')
Move-Item -LiteralPath $stagedUninstaller -Destination (Join-Path $installRoot 'uninstall.ps1')

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $installRoot 'CodexTime.exe'
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = 'Codex usage monitor'
$shortcut.Save()
Remove-Item -Path $legacyShortcutPath -Force -ErrorAction SilentlyContinue

Remove-ItemProperty -Path $runKey -Name 'CodexUsageMonitor' -ErrorAction SilentlyContinue
if ($startupWasEnabled) {
    $executable = Join-Path $installRoot 'CodexTime.exe'
    New-ItemProperty -Path $runKey -Name 'CodexTime' -PropertyType String -Value "`"$executable`"" -Force | Out-Null
}

Start-Process (Join-Path $installRoot 'CodexTime.exe')
Write-Host "CodexTime installed: $installRoot"
