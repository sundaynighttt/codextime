using System.ComponentModel;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using Button = System.Windows.Controls.Button;
using CheckBox = System.Windows.Controls.CheckBox;
using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace CodexTime.WinApp;

public sealed class ProviderActionEventArgs(UsageProviderID provider) : EventArgs
{
    public UsageProviderID Provider { get; } = provider;
}

public sealed class ProviderVisibilityEventArgs(UsageProviderID provider, bool enabled) : EventArgs
{
    public UsageProviderID Provider { get; } = provider;
    public bool Enabled { get; } = enabled;
}

public sealed class ResetVisibilityEventArgs(bool value) : EventArgs
{
    public bool Value { get; } = value;
}

/// <summary>App-owned connection actions. Authentication and reads belong to the controller.</summary>
public sealed class SetupWindow : Window
{
    private sealed record ProviderRow(CheckBox Enabled, TextBlock Status, TextBlock Quota,
        TextBlock Guidance, Button Connect, Button Login, Button Disconnect,
        CheckBox? Compared, Button? Verify)
    {
        public bool WasAwaitingVerification { get; set; }
    }

    private readonly AppSettings _settings;
    private readonly Dictionary<UsageProviderID, ProviderRow> _rows = [];
    private readonly TextBlock _heading = ProviderUi.Text("계정 연결을 시작하세요", 23);
    private readonly TextBlock _summary = ProviderUi.Text("", 12, ProviderUi.Secondary);
    private readonly ProviderStrip _preview = new();
    private readonly CheckBox _resetTime;
    private readonly Button _finish;
    private bool _updating;
    private bool _allowClose;

    public SetupWindow(AppSettings settings)
    {
        _settings = settings;
        Title = "CodexTime 간편 설정";
        Width = 660;
        Height = 790;
        MinWidth = 580;
        MinHeight = 480;
        Background = ProviderUi.Brush("#1C1C1F");
        Foreground = ProviderUi.Foreground;
        FontFamily = new System.Windows.Media.FontFamily("Segoe UI");
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        PreviewKeyDown += (_, args) =>
        {
            if (args.Key == Key.Escape) { Hide(); args.Handled = true; }
        };
        var layout = new Grid { Margin = new Thickness(24, 22, 24, 18) };
        layout.RowDefinitions.Add(new RowDefinition());
        layout.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var stack = new StackPanel { Margin = new Thickness(0, 0, 10, 0) };
        var scroll = new ScrollViewer
        {
            Content = stack,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        layout.Children.Add(scroll);
        _heading.FontWeight = FontWeights.SemiBold;
        stack.Children.Add(_heading);
        _summary.Margin = new Thickness(0, 7, 0, 16);
        AutomationProperties.SetAutomationId(_summary, "CodexTimeSetup-summary");
        stack.Children.Add(_summary);
        var preview = new Border
        {
            Child = _preview,
            Background = ProviderUi.Brush("#29292D"),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(14, 11, 14, 11),
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new Thickness(0, 0, 0, 15)
        };
        AutomationProperties.SetName(preview, "작업표시줄 미리보기");
        stack.Children.Add(preview);
        var introduction = ProviderUi.Text(
            "① 사용할 서비스 선택 → ② 본인 계정 연결 → ③ 잔여량 확인\n표시를 끈 서비스는 자동 조회도 중지합니다. 계정 비밀번호를 이 앱에 입력하지 않습니다.",
            12, ProviderUi.Secondary);
        introduction.Margin = new Thickness(0, 0, 0, 17);
        stack.Children.Add(introduction);
        foreach (var id in UsageProviders.All) stack.Children.Add(CreateProviderCard(id));

        var footer = new Grid { Margin = new Thickness(0, 13, 0, 0) };
        footer.ColumnDefinitions.Add(new ColumnDefinition());
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _resetTime = new CheckBox
        {
            Content = "작업표시줄에 리셋 시간도 표시",
            Foreground = ProviderUi.Secondary,
            VerticalAlignment = VerticalAlignment.Center,
            IsChecked = settings.ShowResetTime,
            FontSize = 12
        };
        AutomationProperties.SetAutomationId(_resetTime, "CodexTimeSetup-reset-time");
        _resetTime.Checked += ResetChanged;
        _resetTime.Unchecked += ResetChanged;
        footer.Children.Add(_resetTime);
        _finish = ProviderUi.Button("나중에 설정", "CodexTimeSetup-finish", (_, _) => Hide());
        _finish.Margin = new Thickness(12, 0, 0, 0);
        _finish.IsDefault = false;
        Grid.SetColumn(_finish, 1);
        footer.Children.Add(_finish);
        Grid.SetRow(footer, 1);
        layout.Children.Add(footer);
        Content = layout;
        UpdateProviders(UsageProviders.All.Select(id => new ProviderUsageState(id)).ToArray());
    }

    public event EventHandler<ProviderActionEventArgs>? ConnectRequested;
    public event EventHandler<ProviderActionEventArgs>? LoginRequested;
    public event EventHandler<ProviderActionEventArgs>? OpenUsageRequested;
    public event EventHandler<ProviderActionEventArgs>? VerifyRequested;
    public event EventHandler<ProviderActionEventArgs>? DisconnectRequested;
    public event EventHandler<ProviderVisibilityEventArgs>? VisibilityChanged;
    public event EventHandler<ResetVisibilityEventArgs>? ShowResetTimeChanged;

    public void UpdateProviders(IReadOnlyList<ProviderUsageState> states)
    {
        _updating = true;
        try
        {
            var selected = UsageProviders.All.Where(id => _settings.Preferences(id).Enabled).ToArray();
            var connected = states.Count(state => selected.Contains(state.Id) && state.Snapshot is not null
                && state.Failure is null && !state.AwaitingVerification);
            var complete = selected.Length > 0 && connected == selected.Length;
            _heading.Text = complete ? "설정이 완료됐습니다" : "계정 연결을 시작하세요";
            _summary.Text = selected.Length == 0 ? "표시할 서비스를 선택하세요. 언제든 다시 켤 수 있습니다."
                : complete ? $"설정 완료 · 선택한 {selected.Length}개 서비스를 10분마다 자동 갱신합니다."
                : $"{selected.Length}개 중 {connected}개 연결 완료 · 아래에서 필요한 단계를 진행하세요.";
            _finish.Content = complete ? "설정 완료" : "나중에 설정";
            AutomationProperties.SetName(_finish, complete ? "설정 완료" : "나중에 설정");
            _resetTime.IsChecked = _settings.ShowResetTime;
            _preview.UpdateProviders(states.Where(state => selected.Contains(state.Id)).ToArray(), _settings.ShowResetTime);
            foreach (var id in UsageProviders.All)
            {
                var state = states.FirstOrDefault(value => value.Id == id) ?? new ProviderUsageState(id);
                var row = _rows[id];
                var enabled = _settings.Preferences(id).Enabled;
                row.Enabled.IsChecked = enabled;
                row.Status.Text = enabled ? ProviderUi.Status(state) : "표시 꺼짐 · 자동 조회 중지";
                row.Quota.Text = QuotaDescription(state);
                row.Guidance.Text = Guidance(state);
                row.Connect.IsEnabled = enabled && !state.IsRefreshing;
                row.Connect.Content = state.IsRefreshing ? "확인 중…"
                    : state.Snapshot is not null && state.Failure is null ? "새로고침" : "기존 계정 연결";
                AutomationProperties.SetName(row.Connect, $"{id.Name()} {row.Connect.Content}");
                row.Login.IsEnabled = enabled && !state.IsRefreshing;
                row.Login.Visibility = state.Snapshot is not null && state.Failure is null && !state.AwaitingVerification
                    ? Visibility.Collapsed : Visibility.Visible;
                row.Disconnect.IsEnabled = !state.IsRefreshing;
                if (row.Compared is not null && row.Verify is not null)
                {
                    if (state.AwaitingVerification != row.WasAwaitingVerification) row.Compared.IsChecked = false;
                    row.Compared.IsEnabled = enabled && state.AwaitingVerification && !state.IsRefreshing;
                    row.Verify.IsEnabled = row.Compared.IsEnabled && row.Compared.IsChecked == true;
                    row.WasAwaitingVerification = state.AwaitingVerification;
                }
            }
        }
        finally { _updating = false; }
    }

    // A title-bar close dismisses the reusable settings window. Controller disposal
    // calls this explicit Close method to release it at application shutdown.
    public new void Close()
    {
        _allowClose = true;
        base.Close();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowClose && !System.Windows.Application.Current.Dispatcher.HasShutdownStarted)
        {
            e.Cancel = true;
            Hide();
        }
        base.OnClosing(e);
    }

    private FrameworkElement CreateProviderCard(UsageProviderID id)
    {
        var contents = new StackPanel();
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition());
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(ProviderUi.Logo(id));
        var title = ProviderUi.Text(id.Name(), 14);
        title.FontWeight = FontWeights.SemiBold;
        title.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(title, 1);
        header.Children.Add(title);
        var enabled = new CheckBox
        {
            Content = "표시 및 자동 조회",
            IsChecked = _settings.Preferences(id).Enabled,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = ProviderUi.Secondary,
            FontSize = 11.5,
            ToolTip = "끄면 작업표시줄에서 숨기고 이 서비스의 자동 사용량 조회를 중지합니다."
        };
        AutomationProperties.SetName(enabled, $"{id.Name()} 표시 및 자동 조회");
        AutomationProperties.SetAutomationId(enabled, $"CodexTimeConnection-{id}-visible");
        enabled.Checked += (_, _) => VisibilityToggled(id, true);
        enabled.Unchecked += (_, _) => VisibilityToggled(id, false);
        Grid.SetColumn(enabled, 2);
        header.Children.Add(enabled);
        contents.Children.Add(header);
        var status = ProviderUi.Text("미연결", 11.5, ProviderUi.Secondary);
        status.Margin = new Thickness(0, 10, 0, 7);
        contents.Children.Add(status);
        var quota = ProviderUi.Text("잔여 한도 · —\n리셋 · —", 12);
        contents.Children.Add(quota);
        var guidance = ProviderUi.Text("", 11.5, ProviderUi.Secondary);
        guidance.Margin = new Thickness(0, 10, 0, 12);
        contents.Children.Add(guidance);
        var actions = new WrapPanel();
        var connect = ActionButton(id, "기존 계정 연결", "connect", (_, _) => ConnectRequested?.Invoke(this, new(id)));
        var login = ActionButton(id, id == UsageProviderID.Grok ? "Cursor 로그인·설치 안내" : "로그인·설치 안내", "login",
            (_, _) => LoginRequested?.Invoke(this, new(id)));
        var usage = ActionButton(id, "공식 사용량 열기", "usage", (_, _) => OpenUsageRequested?.Invoke(this, new(id)));
        var disconnect = ActionButton(id, "연결 해제", "disconnect", (_, _) => DisconnectRequested?.Invoke(this, new(id)));
        actions.Children.Add(connect);
        actions.Children.Add(login);
        actions.Children.Add(usage);
        if (id != UsageProviderID.Codex) actions.Children.Add(disconnect);
        contents.Children.Add(actions);
        CheckBox? compared = null;
        Button? verify = null;
        if (id == UsageProviderID.Grok)
        {
            compared = new CheckBox
            {
                Content = "Grok 웹의 사용률·리셋 시각을 위 값과 대조했습니다.",
                Foreground = ProviderUi.Secondary,
                FontSize = 11.5,
                Margin = new Thickness(0, 8, 0, 10),
                IsEnabled = false
            };
            AutomationProperties.SetAutomationId(compared, "CodexTimeConnection-Grok-compared");
            verify = ActionButton(id, "대조 완료 · 자동 갱신 켜기", "verify", (_, _) =>
            {
                if (_rows[id].Compared is { IsChecked: true, IsEnabled: true })
                    VerifyRequested?.Invoke(this, new(id));
            });
            verify.IsEnabled = false;
            var compareButton = verify;
            var compareBox = compared;
            compared.Checked += (_, _) => compareButton.IsEnabled = compareBox.IsEnabled && compareBox.IsChecked == true;
            compared.Unchecked += (_, _) => compareButton.IsEnabled = false;
            contents.Children.Add(compared);
            contents.Children.Add(verify);
        }
        _rows[id] = new(enabled, status, quota, guidance, connect, login, disconnect, compared, verify);
        return new Border
        {
            Child = contents,
            Background = ProviderUi.Brush("#2B2B30"),
            CornerRadius = new CornerRadius(12),
            Padding = new Thickness(16),
            Margin = new Thickness(0, 0, 0, 13)
        };
    }

    private static Button ActionButton(UsageProviderID id, string title, string action, RoutedEventHandler clicked)
    {
        var button = ProviderUi.Button(title, $"CodexTimeConnection-{id}-{action}", clicked);
        AutomationProperties.SetName(button, $"{id.Name()} {title}");
        return button;
    }

    private static string QuotaDescription(ProviderUsageState state)
    {
        var window = state.Snapshot?.DisplayWindow ?? state.Snapshot?.Windows.FirstOrDefault();
        if (window is null) return "잔여 한도 · —\n리셋 · —";
        var value = window.DisplayRemainingPercent is int percent ? $"{percent}% 남음" : "—";
        if (state.AwaitingVerification && window.DisplayRemainingPercent is int candidate)
            value += $" (사용률 약 {100 - candidate}%)";
        var previous = state.AwaitingVerification ? " · 웹 대조 전 임시 값" : state.IsStale ? " · 이전 값" : "";
        var reset = window.ResetsAt is DateTimeOffset date ? date.LocalDateTime.ToString("g") : "미확인";
        return $"{window.Label} · {value}{previous}\n리셋 · {reset}";
    }

    private static string Guidance(ProviderUsageState state)
    {
        if (state.AwaitingVerification)
            return "‘공식 사용량 열기’로 Grok 웹의 사용률과 리셋 시각을 대조한 뒤 아래 확인란을 선택하세요. 확인 전에는 자동 갱신하지 않습니다. 정수 표시 방식에 따라 1% 차이가 날 수 있습니다.";
        if (state.Snapshot is not null && state.Failure is null)
            return "연결 완료 · 10분마다 자동 갱신합니다. 연결을 해제해도 공식 앱의 로그인은 유지됩니다.";
        if (state.Error is { } error && state.Failure != ProviderFailure.NotConnected)
            return error + " 로그인·설치 안내를 확인하거나 ‘기존 계정 연결’로 다시 시도하세요.";
        return state.Id switch
        {
            UsageProviderID.Codex => "공식 Codex 앱 또는 CLI에서 본인 계정으로 로그인한 뒤 ‘기존 계정 연결’을 누르세요.",
            UsageProviderID.Claude => "Claude Code에서 본인 구독 계정으로 로그인한 뒤 연결하세요. 연결 시 사용량 조회에 필요한 기존 인증 정보 접근에 동의합니다.",
            _ => "Cursor에 저장된 본인 Grok 계정을 연결합니다. 연결 후 Grok 웹과 처음 한 번 대조하세요. xAI API 크레딧 잔액은 이 사용량과 다릅니다."
        };
    }

    private void VisibilityToggled(UsageProviderID id, bool enabled)
    {
        if (!_updating) VisibilityChanged?.Invoke(this, new(id, enabled));
    }

    private void ResetChanged(object sender, RoutedEventArgs e)
    {
        if (!_updating) ShowResetTimeChanged?.Invoke(this, new(_resetTime.IsChecked == true));
    }
}
