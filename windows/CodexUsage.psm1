Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-CodexLaunch {
    $explicitPath = [Environment]::GetEnvironmentVariable('CODEX_CLI_PATH')
    if ($explicitPath) {
        $path = $explicitPath
    } else {
        $command = Get-Command codex -CommandType Application,ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command) {
            throw 'Codex CLI를 찾지 못했습니다. Codex를 설치하고 로그인한 뒤 다시 실행하세요.'
        }
        $path = [string]$command.Path
    }

    $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
    switch ($extension) {
        '.cmd' {
            return @{
                FileName = $env:ComSpec
                Arguments = "/d /s /c `"`"$path`" app-server`""
            }
        }
        '.bat' {
            return @{
                FileName = $env:ComSpec
                Arguments = "/d /s /c `"`"$path`" app-server`""
            }
        }
        '.ps1' {
            return @{
                FileName = 'powershell.exe'
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$path`" app-server"
            }
        }
        default {
            return @{
                FileName = $path
                Arguments = 'app-server'
            }
        }
    }
}

function ConvertFrom-CodexRateLimitResponse {
    param(
        [Parameter(Mandatory)]
        [string] $Json
    )

    $message = $Json | ConvertFrom-Json
    $errorProperty = $message.PSObject.Properties['error']
    if ($errorProperty -and $message.error) {
        throw "Codex 응답 오류: $($message.error.message)"
    }
    $resultProperty = $message.PSObject.Properties['result']
    if (-not $resultProperty -or -not $message.result) {
        return $null
    }
    $result = $message.result
    $rateLimitsProperty = $result.PSObject.Properties['rateLimits']
    if (-not $rateLimitsProperty -or -not $result.rateLimits) {
        return $null
    }

    $snapshots = @{}
    $byLimitProperty = $result.PSObject.Properties['rateLimitsByLimitId']
    if ($byLimitProperty -and $result.rateLimitsByLimitId) {
        foreach ($property in $result.rateLimitsByLimitId.PSObject.Properties) {
            $snapshots[$property.Name] = $property.Value
        }
    }

    $fallback = $result.rateLimits
    $fallbackIdProperty = $fallback.PSObject.Properties['limitId']
    $fallbackId = if ($fallbackIdProperty -and $fallback.limitId) { [string]$fallback.limitId } else { 'codex' }
    if (-not $snapshots.ContainsKey($fallbackId)) {
        $snapshots[$fallbackId] = $fallback
    }

    $buckets = foreach ($entry in $snapshots.GetEnumerator()) {
        $snapshot = $entry.Value
        $primaryProperty = $snapshot.PSObject.Properties['primary']
        if (-not $primaryProperty -or -not $snapshot.primary) { continue }
        $limitIdProperty = $snapshot.PSObject.Properties['limitId']
        $limitNameProperty = $snapshot.PSObject.Properties['limitName']
        $secondaryProperty = $snapshot.PSObject.Properties['secondary']
        $id = if ($limitIdProperty -and $snapshot.limitId) { [string]$snapshot.limitId } else { [string]$entry.Key }
        $name = if ($id -eq 'codex') {
            'Codex'
        } elseif ($limitNameProperty -and $snapshot.limitName) {
            [string]$snapshot.limitName
        } else {
            $id
        }

        $primaryResetProperty = $snapshot.primary.PSObject.Properties['resetsAt']
        $hasSecondary = $secondaryProperty -and $snapshot.secondary
        $secondaryResetProperty = if ($hasSecondary) { $snapshot.secondary.PSObject.Properties['resetsAt'] } else { $null }

        [pscustomobject]@{
            Id = $id
            Name = $name
            RemainingPercent = [Math]::Min(100, [Math]::Max(0, 100 - [int]$snapshot.primary.usedPercent))
            ResetsAt = if ($primaryResetProperty -and $null -ne $snapshot.primary.resetsAt) {
                [DateTimeOffset]::FromUnixTimeSeconds([int64]$snapshot.primary.resetsAt).LocalDateTime
            } else { $null }
            SecondaryRemainingPercent = if ($hasSecondary) {
                [Math]::Min(100, [Math]::Max(0, 100 - [int]$snapshot.secondary.usedPercent))
            } else { $null }
            SecondaryResetsAt = if ($hasSecondary -and $secondaryResetProperty -and $null -ne $snapshot.secondary.resetsAt) {
                [DateTimeOffset]::FromUnixTimeSeconds([int64]$snapshot.secondary.resetsAt).LocalDateTime
            } else { $null }
        }
    }

    $ordered = @($buckets | Sort-Object @{ Expression = { if ($_.Id -eq 'codex') { 0 } else { 1 } } }, Name)
    if ($ordered.Count -eq 0) {
        throw 'Codex 사용량 응답에 표시할 한도가 없습니다.'
    }

    $main = @($ordered | Where-Object Id -eq 'codex' | Select-Object -First 1)
    if ($main.Count -eq 0) { $main = @($ordered[0]) }

    [pscustomobject]@{
        Main = $main[0]
        Buckets = $ordered
    }
}

function Get-CodexRateLimitReport {
    $launch = Resolve-CodexLaunch
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $launch.FileName
    $startInfo.Arguments = $launch.Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Codex app-server를 시작하지 못했습니다.'
    }
    $standardErrorTask = $process.StandardError.ReadToEndAsync()

    try {
        $requests = @(
            @{ id = 1; method = 'initialize'; params = @{ clientInfo = @{ name = 'codex-usage-monitor-windows'; version = '0.1.0' } } },
            @{ method = 'initialized' },
            @{ id = 2; method = 'account/rateLimits/read' }
        )
        foreach ($request in $requests) {
            $process.StandardInput.WriteLine(($request | ConvertTo-Json -Compress -Depth 6))
        }
        $process.StandardInput.Flush()

        $deadline = [DateTime]::UtcNow.AddSeconds(12)
        while ([DateTime]::UtcNow -lt $deadline) {
            $readTask = $process.StandardOutput.ReadLineAsync()
            $remaining = [Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds)
            if (-not $readTask.Wait($remaining)) { break }
            $line = $readTask.Result
            if ($null -eq $line) { break }
            $report = ConvertFrom-CodexRateLimitResponse -Json $line
            if ($report) { return $report }
        }
        throw 'Codex 사용량 조회 시간이 초과됐습니다.'
    } finally {
        if (-not $process.HasExited) {
            try { $process.Kill() } catch { }
        }
        [void]$standardErrorTask
        $process.Dispose()
    }
}

function Format-CodexCountdown {
    param(
        [AllowNull()]
        $ResetDate,
        [datetime] $Now = (Get-Date)
    )

    if ($null -eq $ResetDate) { return '리셋 시간 미확인' }
    $span = ([datetime]$ResetDate) - $Now
    if ($span.TotalSeconds -le 0) { return '곧 리셋' }
    if ($span.Days -gt 0) { return "$($span.Days)d $($span.Hours)h" }
    if ($span.Hours -gt 0) { return "$($span.Hours)h $($span.Minutes)m" }
    return "$([Math]::Max(1, $span.Minutes))m"
}

Export-ModuleMember -Function Get-CodexRateLimitReport, ConvertFrom-CodexRateLimitResponse, Format-CodexCountdown
