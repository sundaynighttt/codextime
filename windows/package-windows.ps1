param(
    [string] $Version = '0.2.0',
    [string] $Runtime = 'win-x64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$distRoot = Join-Path $repoRoot 'dist'
$artifactName = "CodexTime-Windows-$Version"
$stageRoot = Join-Path $distRoot $artifactName
$zipPath = Join-Path $distRoot "$artifactName.zip"
$publishRoot = Join-Path $distRoot "windows-publish-$Runtime"
$project = Join-Path $PSScriptRoot 'CodexTime.Windows\CodexTime.Windows.csproj'
$localDotnet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
$dotnet = if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    (Get-Command dotnet).Source
} elseif (Test-Path $localDotnet) {
    $localDotnet
} else {
    throw '.NET 8 SDK was not found.'
}

if (Test-Path $stageRoot) { Remove-Item -Path $stageRoot -Recurse -Force }
if (Test-Path $zipPath) { Remove-Item -Path $zipPath -Force }
if (Test-Path $publishRoot) { Remove-Item -Path $publishRoot -Recurse -Force }
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null

& $dotnet publish $project -c Release -r $Runtime --self-contained true `
    -p:Version=$Version -p:PublishSingleFile=true -p:PublishTrimmed=false `
    -o $publishRoot
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }

$files = @('install.ps1', 'uninstall.ps1', 'INSTALL.txt')
foreach ($file in $files) {
    Copy-Item -Path (Join-Path $PSScriptRoot $file) -Destination $stageRoot
}
Copy-Item -Path (Join-Path $publishRoot 'CodexTime.exe') -Destination $stageRoot
Copy-Item -Path (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $stageRoot 'LICENSE.txt')

Compress-Archive -Path $stageRoot -DestinationPath $zipPath -CompressionLevel Optimal
Remove-Item -Path $publishRoot -Recurse -Force
Write-Output $zipPath
