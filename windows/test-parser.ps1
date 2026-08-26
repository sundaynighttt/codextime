Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$project = Join-Path $PSScriptRoot 'CodexTime.Windows\CodexTime.Windows.csproj'
$localDotnet = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet\dotnet.exe'
$dotnet = if (Get-Command dotnet -ErrorAction SilentlyContinue) {
    (Get-Command dotnet).Source
} elseif (Test-Path $localDotnet) {
    $localDotnet
} else {
    throw '.NET 8 SDK was not found.'
}

& $dotnet build $project -c Release
if ($LASTEXITCODE -ne 0) { throw 'Windows build failed.' }

& $dotnet run --project $project -c Release --no-build -- --self-test
if ($LASTEXITCODE -ne 0) { throw 'Windows parser self-test failed.' }

Write-Output 'Windows build and parser tests passed'
