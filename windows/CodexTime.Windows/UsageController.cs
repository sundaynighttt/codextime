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

namespace CodexTime.WinApp;

public sealed class UsageController : IDisposable
{
    private readonly AppSettings _settings = SettingsStore.Load();
    private readonly ProviderMonitor _monitor;
    private readonly Dispatcher _dispatcher = Dispatcher.CurrentDispatcher;
    private readonly TaskbarLabelWindow _taskbarLabel = new();
    private readonly FloatingPillWindow _floatingPill = new();
    private readonly DetailsWindow _details = new();
    private readonly SetupWindow _setup;
    private readonly DispatcherTimer _refreshTimer;
    private readonly DispatcherTimer _countdownTimer;
    private readonly Forms.NotifyIcon _trayIcon;
    private readonly Forms.ContextMenuStrip _trayMenu;
    private DrawingIcon? _currentTrayIcon;
    private volatile bool _disposed;

    public UsageController()
    {
        _monitor = new ProviderMonitor(_settings);
        _monitor.Changed += (_, _) =>
        {
            if (!_disposed && !_dispatcher.HasShutdownStarted) _dispatcher.BeginInvoke(UpdateDisplays);
        };
        _setup = new SetupWindow(_settings);
        _setup.ConnectRequested += async (_, args) => await RunAsync(() => ConnectAsync(args.Provider));
        _setup.LoginRequested += async (_, args) => await RunAsync(async () =>
        {
            // An interactive Cursor login can change the account/pool. Do not
            // carry a previous account's web comparison into the next login.
            if (args.Provider == UsageProviderID.Grok) await _monitor.DisconnectAsync(args.Provider);
            ProviderLoginService.Login(args.Provider);
        });
        _setup.OpenUsageRequested += (_, args) => Run(() => ProviderLoginService.OpenUsage(args.Provider));
        _setup.VerifyRequested += (_, args) => Verify(args.Provider);
        _setup.DisconnectRequested += async (_, args) => await RunAsync(() => _monitor.DisconnectAsync(args.Provider));
        _setup.VisibilityChanged += async (_, args) => await RunAsync(() => _monitor.SetEnabledAsync(args.Provider, args.Enabled));
        _setup.ShowResetTimeChanged += (_, args) => Run(() =>
        {
            _settings.ShowResetTime = args.Value;
            SettingsStore.Save(_settings);
            UpdateDisplays();
        });
        _details.SetupRequested += (_, _) => ShowSetup();
        _taskbarLabel.ToggleDetailsRequested += (_, _) => ToggleDetails(_taskbarLabel.AnchorBounds);
        _floatingPill.ToggleDetailsRequested += (_, _) => ToggleDetails(_floatingPill.AnchorBounds);
        _floatingPill.PositionCommitted += (_, args) =>
        {
            _settings.FloatingLeftPx = args.Left;
            _settings.FloatingTopPx = args.Top;
            Run(() => SettingsStore.Save(_settings));
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
            Text = "CodexTime · Codex · Grok · Claude",
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
        _refreshTimer.Tick += async (_, _) => await RunAsync(_monitor.RefreshAllAsync);
        _countdownTimer = new DispatcherTimer { Interval = TimeSpan.FromMinutes(1) };
        _countdownTimer.Tick += (_, _) => UpdateDisplays();
    }

    public async Task StartAsync()
    {
        ApplyDisplayMode();
        UpdateDisplays();
        _refreshTimer.Start();
        _countdownTimer.Start();
        if (!_settings.HasCompletedSetup) ShowSetup();
        await _monitor.RefreshAllAsync();
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
        Run(() => SettingsStore.Save(_settings));
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

        _details.UpdateProviders(_monitor.States);
        _details.ShowNear(anchor);
    }

    private void UpdateDisplays()
    {
        if (_disposed) return;
        var states = _monitor.States;
        var visible = states.Where(state => _settings.Preferences(state.Id).Enabled).ToArray();
        _taskbarLabel.UpdateProviders(visible, _settings.ShowResetTime);
        _floatingPill.UpdateProviders(visible, _settings.ShowResetTime);
        _details.UpdateProviders(states);
        _setup.UpdateProviders(states);
        var remaining = visible.Where(state => !state.AwaitingVerification)
            .Select(state => state.DisplayRemainingPercent).Where(value => value.HasValue).DefaultIfEmpty(null).Min();
        var label = visible.Length == 0 ? "CodexTime · 모든 서비스 숨김 · 간편 설정에서 표시"
            : string.Join(" · ", visible.Select(state => $"{state.Id.Name()} {(state.AwaitingVerification ? "--" : state.DisplayRemainingPercent?.ToString() ?? "--")}%"
                + (state.AwaitingVerification ? " 대조 필요" : state.IsStale ? " 이전 값" : string.Empty)));
        UpdateTrayIcon(remaining, label);
    }

    private void ShowSetup()
    {
        _details.Hide();
        _setup.UpdateProviders(_monitor.States);
        if (!_setup.IsVisible) _setup.Show();
        _setup.Activate();
        if (!_settings.HasCompletedSetup)
        {
            _settings.HasCompletedSetup = true;
            Run(() => SettingsStore.Save(_settings));
        }
    }

    private async Task ConnectAsync(UsageProviderID provider)
    {
        var message = provider switch
        {
            UsageProviderID.Claude => "Claude 사용량 연결을 허용할까요?\n\n"
                + "본인 Windows 기본 프로필의 %USERPROFILE%\\.claude\\.credentials.json을 읽고 accessToken·만료·scope만 사용하여 "
                + "https://api.anthropic.com/api/oauth/usage에 잔여 한도를 조회합니다.\n\n"
                + "토큰을 별도로 저장하거나 출력하지 않고, 쿠키·브라우저 저장소에 접근하지 않습니다. refresh token을 사용하거나 갱신하지 않습니다. "
                + "만료되면 공식 Claude Code에서 직접 다시 로그인해야 합니다. 연결 후 10분마다 조회합니다.",
            UsageProviderID.Grok => "Grok Bot 사용량 연결을 허용할까요?\n\n"
                + "%APPDATA%\\Cursor\\User\\globalStorage\\state.vscdb의 cursorAuth/accessToken 항목 하나만 읽어 "
                + "https://api2.cursor.sh/aiserver.v1.DashboardService/GetSandUsageStatus에 주간 한도를 한 번 조회합니다.\n\n"
                + "Cursor 로그인에 연결된 Grok Bot 한도입니다. Grok 웹 구독과 같은 한도 풀이라고 추정하지 않습니다. "
                + "본인 Grok 웹 사용량과 사용률·주간 리셋이 같은지 직접 대조한 뒤 확인해야 10분 자동 조회가 켜집니다.\n\n"
                + "토큰을 별도로 저장하거나 출력하지 않고, 쿠키·브라우저 저장소·refresh token에 접근하지 않습니다. "
                + "Cursor 또는 Grok 계정을 바꾸면 연결을 해제하고 새로 연결하여 웹 대조를 다시 해 주세요.",
            _ => "본인 공식 Codex CLI 로그인으로 잔여 한도를 조회합니다. 연결할까요?"
        };
        if (System.Windows.MessageBox.Show(_setup, message, $"{provider.Name()} 사용량 연결",
            MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        await _monitor.ConnectAsync(provider);
    }

    private void Verify(UsageProviderID provider)
    {
        if (provider != UsageProviderID.Grok) return;
        var state = _monitor.States.First(item => item.Id == provider);
        var window = state.Snapshot?.DisplayWindow;
        if (state.IsRefreshing || state.Failure is not null || window?.RemainingPercent is null || state.LastSuccess is null)
        {
            System.Windows.MessageBox.Show(_setup, "먼저 연결하여 주간 한도를 조회해 주세요.", "Grok 웹 대조");
            return;
        }
        var used = 100 - window.RemainingPercent.Value;
        var reset = window.ResetsAt?.ToLocalTime().ToString("yyyy-MM-dd HH:mm zzz") ?? "미확인";
        var message = $"조회된 Grok Bot 주간 사용률: {used:0.##}% 사용\n주간 리셋: {reset}\n\n"
            + "본인 Grok 웹 사용량 화면에서 사용률과 리셋을 직접 확인했고, 정확히 같은 주간 한도 풀임을 확인했나요? "
            + "확인하면 이 계정의 자동 조회를 켭니다. 다르거나 확실하지 않으면 ‘아니요’를 눌러 주세요.";
        if (window.ResetsAt is null)
        {
            System.Windows.MessageBox.Show(_setup, "주간 리셋을 확인할 수 없어 자동 조회를 켤 수 없습니다. 다시 연결하여 확인해 주세요.", "Grok 웹 대조");
            return;
        }
        if (System.Windows.MessageBox.Show(_setup, message, "Grok 웹 대조",
            MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) == MessageBoxResult.Yes)
            Run(() => _monitor.VerifyGrok(state.LastSuccess));
    }

    private static void Run(Action action)
    {
        try { action(); }
        catch { ShowOperationFailure(); }
    }

    private static async Task RunAsync(Func<Task> action)
    {
        try { await action(); }
        catch { ShowOperationFailure(); }
    }

    private static void ShowOperationFailure() => System.Windows.MessageBox.Show(
        "작업을 완료하지 못했습니다. 간편 설정에서 상태를 확인하고 다시 시도해 주세요.",
        "CodexTime", MessageBoxButton.OK, MessageBoxImage.Information);

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
            refresh.Click += async (_, _) => await RunAsync(_monitor.RefreshAllAsync);
            menu.Items.Add(refresh);
            var setup = new MenuItem { Header = "간편 설정 · 계정 연결" };
            setup.Click += (_, _) => ShowSetup();
            menu.Items.Add(setup);
            foreach (var provider in UsageProviders.All)
            {
                var visible = new MenuItem { Header = $"{provider.Name()} 표시", IsCheckable = true,
                    IsChecked = _settings.Preferences(provider).Enabled };
                visible.Click += async (_, _) => await RunAsync(() => _monitor.SetEnabledAsync(provider, visible.IsChecked));
                menu.Items.Add(visible);
            }
            var reset = new MenuItem { Header = "리셋 시간 표시", IsCheckable = true, IsChecked = _settings.ShowResetTime };
            reset.Click += (_, _) => Run(() =>
            {
                _settings.ShowResetTime = reset.IsChecked;
                SettingsStore.Save(_settings);
                UpdateDisplays();
            });
            menu.Items.Add(reset);
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
            startup.Click += (_, _) => Run(() => StartupManager.IsEnabled = !StartupManager.IsEnabled);
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
        refresh.Click += async (_, _) => await RunAsync(_monitor.RefreshAllAsync);
        _trayMenu.Items.Add(refresh);
        var setup = new Forms.ToolStripMenuItem("간편 설정 · 계정 연결");
        setup.Click += (_, _) => ShowSetup();
        _trayMenu.Items.Add(setup);
        foreach (var provider in UsageProviders.All)
        {
            var visible = new Forms.ToolStripMenuItem($"{provider.Name()} 표시")
            { Checked = _settings.Preferences(provider).Enabled };
            visible.Click += async (_, _) => await RunAsync(() => _monitor.SetEnabledAsync(provider, !visible.Checked));
            _trayMenu.Items.Add(visible);
        }
        var reset = new Forms.ToolStripMenuItem("리셋 시간 표시") { Checked = _settings.ShowResetTime };
        reset.Click += (_, _) => Run(() =>
        {
            _settings.ShowResetTime = !reset.Checked;
            SettingsStore.Save(_settings);
            UpdateDisplays();
        });
        _trayMenu.Items.Add(reset);
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
        startup.Click += (_, _) => Run(() => StartupManager.IsEnabled = !StartupManager.IsEnabled);
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
        _monitor.Dispose();
        _refreshTimer.Stop();
        _countdownTimer.Stop();
        _trayIcon.Visible = false;
        _trayIcon.Dispose();
        _currentTrayIcon?.Dispose();
        _trayMenu.Dispose();
        _taskbarLabel.Close();
        _floatingPill.Close();
        _details.Close();
        _setup.Close();
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
