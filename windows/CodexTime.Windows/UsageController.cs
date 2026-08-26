using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using DrawingColor = System.Drawing.Color;
using DrawingFont = System.Drawing.Font;
using DrawingIcon = System.Drawing.Icon;
using Forms = System.Windows.Forms;
using MediaColor = System.Windows.Media.Color;

namespace CodexTime.WinApp;

public sealed class UsageController : IDisposable
{
    private readonly AppSettings _settings = SettingsStore.Load();
    private readonly CodexAppServerClient _client = new();
    private readonly SemaphoreSlim _refreshGate = new(1, 1);
    private readonly TaskbarLabelWindow _taskbarLabel = new();
    private readonly FloatingPillWindow _floatingPill = new();
    private readonly DetailsWindow _details = new();
    private readonly DispatcherTimer _refreshTimer;
    private readonly DispatcherTimer _countdownTimer;
    private readonly Forms.NotifyIcon _trayIcon;
    private readonly Forms.ContextMenuStrip _trayMenu;
    private DrawingIcon? _currentTrayIcon;
    private RateLimitReport? _report;
    private DateTimeOffset? _lastUpdated;
    private string? _lastError;
    private bool _disposed;

    public UsageController()
    {
        _taskbarLabel.ToggleDetailsRequested += (_, _) => ToggleDetails(_taskbarLabel.AnchorBounds);
        _floatingPill.ToggleDetailsRequested += (_, _) => ToggleDetails(_floatingPill.AnchorBounds);
        _floatingPill.PositionCommitted += (_, args) =>
        {
            _settings.FloatingLeftPx = args.Left;
            _settings.FloatingTopPx = args.Top;
            SettingsStore.Save(_settings);
        };

        _taskbarLabel.ContextMenu = CreateWpfContextMenu();
        _floatingPill.ContextMenu = CreateWpfContextMenu();
        _details.ContextMenu = CreateWpfContextMenu();

        _trayMenu = new Forms.ContextMenuStrip();
        _trayMenu.Opening += RebuildTrayMenu;
        _currentTrayIcon = CreateTrayIcon(null);
        _trayIcon = new Forms.NotifyIcon
        {
            Visible = true,
            Text = "CodexTime · 사용량 확인 중",
            Icon = _currentTrayIcon,
            ContextMenuStrip = _trayMenu
        };
        _trayIcon.MouseClick += (_, args) =>
        {
            if (args.Button == Forms.MouseButtons.Left)
            {
                var cursor = Forms.Control.MousePosition;
                ToggleDetails(new NativeMethods.NativeRect(cursor.X, cursor.Y, cursor.X + 1, cursor.Y + 1));
            }
        };

        _refreshTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(10) };
        _refreshTimer.Tick += async (_, _) => await RefreshAsync();
        _countdownTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        _countdownTimer.Tick += (_, _) => UpdateDisplays();
    }

    public async Task StartAsync()
    {
        ApplyDisplayMode();
        UpdateDisplays();
        _refreshTimer.Start();
        _countdownTimer.Start();
        await RefreshAsync();
    }

    private async Task RefreshAsync()
    {
        if (!await _refreshGate.WaitAsync(0))
        {
            return;
        }

        try
        {
            _lastError = null;
            UpdateDisplays();
            _report = await _client.FetchAsync();
            _lastUpdated = DateTimeOffset.Now;
        }
        catch (Exception exception)
        {
            _lastError = exception.Message;
            AppLog.Write(exception);
        }
        finally
        {
            _refreshGate.Release();
            UpdateDisplays();
        }
    }

    private void ApplyDisplayMode()
    {
        _details.Hide();
        if (_settings.DisplayMode == DisplayMode.TaskbarLabel)
        {
            _floatingPill.HidePill();
            _taskbarLabel.ShowLabel();
        }
        else
        {
            _taskbarLabel.HideLabel();
            _floatingPill.ShowPill(_settings.FloatingLeftPx, _settings.FloatingTopPx);
        }
    }

    private void SwitchMode(DisplayMode mode)
    {
        if (_settings.DisplayMode == mode)
        {
            return;
        }
        _settings.DisplayMode = mode;
        SettingsStore.Save(_settings);
        ApplyDisplayMode();
        UpdateDisplays();
    }

    private void ToggleDetails(NativeMethods.NativeRect anchor)
    {
        if (_details.IsVisible)
        {
            _details.Hide();
            return;
        }

        _details.UpdateReport(_report, _lastError, _lastUpdated);
        _details.ShowNear(anchor);
    }

    private void UpdateDisplays()
    {
        var primary = _report?.Main.Primary;
        var remaining = primary?.RemainingPercent;
        string label;
        string tooltip;
        if (primary is null)
        {
            label = _lastError is null ? "Codex --% · 확인 중" : "Codex --% · 오류";
            tooltip = _lastError ?? "Codex 사용량 확인 중";
        }
        else
        {
            var countdown = UsageText.FormatCountdown(primary.ResetsAt);
            label = $"Codex {primary.RemainingPercent}% · {countdown}";
            tooltip = $"{primary.RemainingPercent}% 남음 · {countdown}";
            if (_lastError is not null)
            {
                tooltip += " · 새로고침 실패";
            }
        }

        _taskbarLabel.UpdateUsage(label, remaining, tooltip);
        _floatingPill.UpdateUsage(label, remaining, tooltip);
        _details.UpdateReport(_report, _lastError, _lastUpdated);
        UpdateTrayIcon(remaining, label);
    }

    private void UpdateTrayIcon(int? remaining, string tooltip)
    {
        var newIcon = CreateTrayIcon(remaining);
        var oldIcon = _currentTrayIcon;
        _trayIcon.Icon = newIcon;
        _currentTrayIcon = newIcon;
        _trayIcon.Text = tooltip.Length <= 63 ? tooltip : tooltip[..63];
        oldIcon?.Dispose();
    }

    private ContextMenu CreateWpfContextMenu()
    {
        var menu = new ContextMenu();
        menu.Opened += (_, _) =>
        {
            menu.Items.Clear();
            var refresh = new MenuItem { Header = "지금 새로고침" };
            refresh.Click += async (_, _) => await RefreshAsync();
            menu.Items.Add(refresh);
            menu.Items.Add(new Separator());

            var taskbar = new MenuItem
            {
                Header = "작업표시줄 라벨",
                IsCheckable = true,
                IsChecked = _settings.DisplayMode == DisplayMode.TaskbarLabel
            };
            taskbar.Click += (_, _) => SwitchMode(DisplayMode.TaskbarLabel);
            menu.Items.Add(taskbar);

            var floating = new MenuItem
            {
                Header = "우상단 미니 위젯",
                IsCheckable = true,
                IsChecked = _settings.DisplayMode == DisplayMode.FloatingPill
            };
            floating.Click += (_, _) => SwitchMode(DisplayMode.FloatingPill);
            menu.Items.Add(floating);
            menu.Items.Add(new Separator());

            var startup = new MenuItem
            {
                Header = "로그인 시 자동 실행",
                IsCheckable = true,
                IsChecked = StartupManager.IsEnabled
            };
            startup.Click += (_, _) => StartupManager.IsEnabled = !StartupManager.IsEnabled;
            menu.Items.Add(startup);

            var exit = new MenuItem { Header = "종료" };
            exit.Click += (_, _) => System.Windows.Application.Current.Shutdown();
            menu.Items.Add(exit);
        };
        return menu;
    }

    private void RebuildTrayMenu(object? sender, CancelEventArgs e)
    {
        _trayMenu.Items.Clear();
        var refresh = new Forms.ToolStripMenuItem("지금 새로고침");
        refresh.Click += async (_, _) => await RefreshAsync();
        _trayMenu.Items.Add(refresh);
        _trayMenu.Items.Add(new Forms.ToolStripSeparator());

        var taskbar = new Forms.ToolStripMenuItem("작업표시줄 라벨")
        {
            Checked = _settings.DisplayMode == DisplayMode.TaskbarLabel
        };
        taskbar.Click += (_, _) => SwitchMode(DisplayMode.TaskbarLabel);
        _trayMenu.Items.Add(taskbar);

        var floating = new Forms.ToolStripMenuItem("우상단 미니 위젯")
        {
            Checked = _settings.DisplayMode == DisplayMode.FloatingPill
        };
        floating.Click += (_, _) => SwitchMode(DisplayMode.FloatingPill);
        _trayMenu.Items.Add(floating);
        _trayMenu.Items.Add(new Forms.ToolStripSeparator());

        var startup = new Forms.ToolStripMenuItem("로그인 시 자동 실행")
        {
            Checked = StartupManager.IsEnabled
        };
        startup.Click += (_, _) => StartupManager.IsEnabled = !StartupManager.IsEnabled;
        _trayMenu.Items.Add(startup);

        var exit = new Forms.ToolStripMenuItem("종료");
        exit.Click += (_, _) => System.Windows.Application.Current.Shutdown();
        _trayMenu.Items.Add(exit);
    }

    private static DrawingIcon CreateTrayIcon(int? remaining)
    {
        using var bitmap = new Bitmap(32, 32);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        graphics.Clear(DrawingColor.Transparent);
        var mediaColor = UsageColors.ForRemaining(remaining);
        using var background = new SolidBrush(DrawingColor.FromArgb(mediaColor.R, mediaColor.G, mediaColor.B));
        graphics.FillEllipse(background, 1, 1, 30, 30);
        var text = remaining?.ToString() ?? "?";
        var fontSize = text.Length >= 3 ? 9.5f : text.Length == 2 ? 11.5f : 13f;
        using var font = new DrawingFont(
            "Segoe UI",
            fontSize,
            System.Drawing.FontStyle.Bold,
            System.Drawing.GraphicsUnit.Pixel);
        using var format = new StringFormat
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center
        };
        graphics.DrawString(text, font, Brushes.White, new RectangleF(0, 0, 32, 31), format);
        var handle = bitmap.GetHicon();
        try
        {
            return (DrawingIcon)DrawingIcon.FromHandle(handle).Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _refreshTimer.Stop();
        _countdownTimer.Stop();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _currentTrayIcon?.Dispose();
        _trayMenu.Dispose();
        _taskbarLabel.Close();
        _floatingPill.Close();
        _details.Close();
        _refreshGate.Dispose();
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyIcon(IntPtr icon);
}

internal static class UsageText
{
    internal static string FormatCountdown(DateTimeOffset? resetDate)
    {
        if (resetDate is null)
        {
            return "리셋 미확인";
        }

        var span = resetDate.Value - DateTimeOffset.Now;
        if (span.TotalSeconds <= 0)
        {
            return "곧 리셋";
        }
        if (span.Days > 0)
        {
            return $"{span.Days}d {span.Hours}h";
        }
        if (span.Hours > 0)
        {
            return $"{span.Hours}h {span.Minutes}m";
        }
        return $"{Math.Max(1, span.Minutes)}m";
    }
}
