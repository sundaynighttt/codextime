Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CodexUsage.psm1') -Force

$sample = '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1788283270},"secondary":null,"planType":"pro"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":4,"windowDurationMins":10080,"resetsAt":1788283270},"secondary":null,"planType":"pro"},"codex_spark":{"limitId":"codex_spark","limitName":"Spark","primary":{"usedPercent":21,"windowDurationMins":300,"resetsAt":1787721941},"secondary":null,"planType":"pro"}}}}'
$report = ConvertFrom-CodexRateLimitResponse -Json $sample

if ($report.Main.RemainingPercent -ne 96) { throw '메인 잔여 퍼센트 파싱 실패' }
if ($report.Buckets.Count -ne 2) { throw '버킷 파싱 실패' }

$now = [datetime]'2026-08-26T09:00:00'
$reset = $now.AddDays(3).AddHours(17)
if ((Format-CodexCountdown -ResetDate $reset -Now $now) -ne '3d 17h') {
    throw '카운트다운 포맷 실패'
}

Write-Host 'Windows parser tests passed'
