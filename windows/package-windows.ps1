param(
    [string] $Version = '0.1.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$distRoot = Join-Path $repoRoot 'dist'
$artifactName = "CodexTime-Windows-$Version"
$stageRoot = Join-Path $distRoot $artifactName
$zipPath = Join-Path $distRoot "$artifactName.zip"

if (Test-Path $stageRoot) { Remove-Item -Path $stageRoot -Recurse -Force }
if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

$files = @(
    'CodexUsage.psm1',
    'CodexUsageMonitor.ps1',
    'CodexUsageMonitor.vbs',
    'install.ps1',
    'uninstall.ps1',
    'INSTALL.txt'
)
foreach ($file in $files) {
    Copy-Item -Path (Join-Path $PSScriptRoot $file) -Destination $stageRoot
}
Copy-Item -Path (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $stageRoot 'LICENSE.txt')

Compress-Archive -Path $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal
Write-Output $zipPath
