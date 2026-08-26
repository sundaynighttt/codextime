Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CodexUsageNativeMethods {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool DestroyIcon(IntPtr handle);
}
'@

Import-Module (Join-Path $PSScriptRoot 'CodexUsage.psm1') -Force

$script:Report = $null
$script:LastUpdated = $null
$script:CurrentIcon = $null
$script:TickCount = 0

function New-UsageIcon {
    param([AllowNull()] $Percent)

    $bitmap = [Drawing.Bitmap]::new(32, 32)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    try {
        $color = if ($null -eq $Percent) {
            [Drawing.Color]::FromArgb(90, 90, 95)
        } elseif ([int]$Percent -gt 50) {
            [Drawing.Color]::FromArgb(34, 139, 94)
        } elseif ([int]$Percent -gt 20) {
            [Drawing.Color]::FromArgb(220, 146, 28)
        } else {
            [Drawing.Color]::FromArgb(205, 62, 62)
        }
        $graphics.Clear([Drawing.Color]::Transparent)
        $brush = [Drawing.SolidBrush]::new($color)
        $graphics.FillEllipse($brush, 1, 1, 30, 30)
        $brush.Dispose()

        $text = if ($null -eq $Percent) { '?' } else { [string][int]$Percent }
        $fontSize = if ($text.Length -ge 3) { 9.5 } elseif ($text.Length -eq 2) { 11.5 } else { 13.0 }
        $font = [Drawing.Font]::new('Segoe UI', $fontSize, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
        $textBrush = [Drawing.Brushes]::White
        $format = [Drawing.StringFormat]::new()
        $format.Alignment = [Drawing.StringAlignment]::Center
        $format.LineAlignment = [Drawing.StringAlignment]::Center
        $graphics.DrawString($text, $font, $textBrush, [Drawing.RectangleF]::new(0, 0, 32, 31), $format)
        $font.Dispose()
        $format.Dispose()

        $handle = $bitmap.GetHicon()
        try {
            return ([Drawing.Icon]::FromHandle($handle)).Clone()
        } finally {
            [void][CodexUsageNativeMethods]::DestroyIcon($handle)
        }
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-StartupEnabled {
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $value = Get-ItemProperty -Path $runKey -Name 'CodexUsageMonitor' -ErrorAction SilentlyContinue
    return $null -ne $value
}

function Set-StartupEnabled {
    param([bool] $Enabled)
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ($Enabled) {
        $launcher = Join-Path $PSScriptRoot 'CodexUsageMonitor.vbs'
        New-ItemProperty -Path $runKey -Name 'CodexUsageMonitor' -PropertyType String -Value "wscript.exe `"$launcher`"" -Force | Out-Null
    } else {
        Remove-ItemProperty -Path $runKey -Name 'CodexUsageMonitor' -ErrorAction SilentlyContinue
    }
}

$tray = [Windows.Forms.NotifyIcon]::new()
$menu = [Windows.Forms.ContextMenuStrip]::new()
$statusItem = [Windows.Forms.ToolStripMenuItem]::new('Codex 사용량 확인 중…')
$statusItem.Enabled = $false
$detailsItem = [Windows.Forms.ToolStripMenuItem]::new('')
$detailsItem.Enabled = $false
$refreshItem = [Windows.Forms.ToolStripMenuItem]::new('지금 새로고침')
$usageSettingsItem = [Windows.Forms.ToolStripMenuItem]::new('Codex 사용량 설정 열기')
$startupItem = [Windows.Forms.ToolStripMenuItem]::new('로그인 시 자동 실행')
$startupItem.Checked = Get-StartupEnabled
$quitItem = [Windows.Forms.ToolStripMenuItem]::new('종료')

[void]$menu.Items.Add($statusItem)
[void]$menu.Items.Add($detailsItem)
[void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
[void]$menu.Items.Add($refreshItem)
[void]$menu.Items.Add($usageSettingsItem)
[void]$menu.Items.Add($startupItem)
[void]$menu.Items.Add([Windows.Forms.ToolStripSeparator]::new())
[void]$menu.Items.Add($quitItem)

$tray.ContextMenuStrip = $menu
$tray.Icon = New-UsageIcon -Percent $null
$script:CurrentIcon = $tray.Icon
$tray.Text = 'Codex 사용량 확인 중'
$tray.Visible = $true

function Update-TrayDisplay {
    if ($null -eq $script:Report) { return }
    $main = $script:Report.Main
    $countdown = Format-CodexCountdown -ResetDate $main.ResetsAt
    $statusItem.Text = "Codex $($main.RemainingPercent)% ($countdown)"
    $tray.Text = "Codex $($main.RemainingPercent)% · $countdown"

    $detailLines = foreach ($bucket in $script:Report.Buckets) {
        "$($bucket.Name) $($bucket.RemainingPercent)% · $(Format-CodexCountdown -ResetDate $bucket.ResetsAt)"
    }
    $detailsItem.Text = $detailLines -join ' / '

    $newIcon = New-UsageIcon -Percent $main.RemainingPercent
    $oldIcon = $script:CurrentIcon
    $tray.Icon = $newIcon
    $script:CurrentIcon = $newIcon
    if ($oldIcon) { $oldIcon.Dispose() }
}

function Refresh-Usage {
    $refreshItem.Enabled = $false
    $refreshItem.Text = '새로고침 중…'
    try {
        $script:Report = Get-CodexRateLimitReport
        $script:LastUpdated = Get-Date
        Update-TrayDisplay
    } catch {
        $statusItem.Text = 'Codex 사용량 확인 실패'
        $detailsItem.Text = $_.Exception.Message
        $tray.Text = 'Codex 사용량 확인 실패'
    } finally {
        $refreshItem.Text = '지금 새로고침'
        $refreshItem.Enabled = $true
    }
}

$refreshItem.Add_Click({ Refresh-Usage })
$usageSettingsItem.Add_Click({ Start-Process 'https://chatgpt.com/codex/settings/usage' })
$startupItem.Add_Click({
    try {
        Set-StartupEnabled -Enabled (-not $startupItem.Checked)
        $startupItem.Checked = Get-StartupEnabled
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Codex Usage Monitor') | Out-Null
    }
})
$quitItem.Add_Click({ [Windows.Forms.Application]::Exit() })
$tray.Add_DoubleClick({ Start-Process 'https://chatgpt.com/codex/settings/usage' })

$timer = [Windows.Forms.Timer]::new()
$timer.Interval = 60_000
$timer.Add_Tick({
    $script:TickCount++
    Update-TrayDisplay
    if (($script:TickCount % 10) -eq 0) { Refresh-Usage }
})

[Windows.Forms.Application]::add_ApplicationExit({
    $timer.Stop()
    $tray.Visible = $false
    if ($script:CurrentIcon) { $script:CurrentIcon.Dispose() }
    $tray.Dispose()
    $menu.Dispose()
})

Refresh-Usage
$timer.Start()
[Windows.Forms.Application]::Run()
