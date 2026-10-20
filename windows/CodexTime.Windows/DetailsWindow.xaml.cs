using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Input;
using System.Windows.Automation;
using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace CodexTime.WinApp;

public partial class DetailsWindow : Window
{
    private IntPtr _windowHandle;

    public DetailsWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) =>
        {
            _windowHandle = new WindowInteropHelper(this).Handle;
            NativeMethods.ConfigureToolWindow(_windowHandle, noActivate: false);
        };
        PreviewKeyDown += (_, args) =>
        {
            if (args.Key == Key.Escape) { Hide(); args.Handled = true; }
        };
        var setup = ProviderUi.Button("서비스 연결 및 표시 설정", "CodexTimeDetails-setup",
            (_, _) => SetupRequested?.Invoke(this, EventArgs.Empty));
        setup.HorizontalAlignment = HorizontalAlignment.Stretch;
        setup.Margin = new Thickness(0, 4, 0, 0);
        FooterPanel.Children.Add(setup);
        var note = ProviderUi.Text("* 이전 값 · 연결 실패 시 마지막으로 확인한 값이 유지됩니다.", 10.5, ProviderUi.Muted);
        note.Margin = new Thickness(0, 10, 0, 0);
        FooterPanel.Children.Add(note);
    }

    public event EventHandler? SetupRequested;

    public void UpdateProviders(IReadOnlyList<ProviderUsageState> states)
    {
        RowsPanel.Children.Clear();
        StatusText.Text = "구독 잔여량 · 서비스별 상태";
        if (states.Count == 0)
        {
            RowsPanel.Children.Add(ProviderUi.Text("표시 중인 서비스가 없습니다. 아래 설정에서 다시 선택하세요.", 12));
        }
        else
        {
            foreach (var id in UsageProviders.All)
                if (states.FirstOrDefault(state => state.Id == id) is { } state) AddProviderCard(state);
        }
    }

    internal void ShowNear(NativeMethods.NativeRect anchor)
    {
        new WindowInteropHelper(this).EnsureHandle();
        if (!IsVisible)
        {
            Show();
        }
        Activate();
        UpdateLayout();
        NativeMethods.PositionPopup(_windowHandle, anchor, ActualWidth, ActualHeight);
    }

    private void AddProviderCard(ProviderUsageState state)
    {
        var card = new Border
        {
            Background = ProviderUi.Card,
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(13),
            Margin = new Thickness(0, 0, 0, 10)
        };
        var stack = new StackPanel();
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition());
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(ProviderUi.Logo(state.Id));
        var name = ProviderUi.Text(state.Id.Name(), 13);
        name.FontWeight = FontWeights.SemiBold;
        name.Margin = new Thickness(8, 0, 0, 0);
        Grid.SetColumn(name, 1);
        header.Children.Add(name);
        var percent = ProviderUi.Text(ProviderUi.Value(state), 23);
        percent.FontWeight = FontWeights.SemiBold;
        percent.Foreground = new SolidColorBrush(UsageColors.ForRemaining(
            state.AwaitingVerification ? null : state.DisplayRemainingPercent));
        Grid.SetColumn(percent, 2);
        header.Children.Add(percent);
        stack.Children.Add(header);
        var status = ProviderUi.Text(ProviderUi.Status(state), 11, ProviderUi.Secondary);
        status.Margin = new Thickness(0, 6, 0, 7);
        stack.Children.Add(status);

        if (state.AwaitingVerification)
        {
            stack.Children.Add(ProviderUi.Text("간편 설정에서 Grok 웹의 사용률과 리셋 시각을 대조해 연결을 완료하세요.", 11, ProviderUi.Secondary));
        }
        else if (state.Snapshot is { } snapshot)
        {
            foreach (var window in snapshot.Windows) AddWindowRow(stack, window);
        }
        if (state.Error is { } error)
        {
            var message = ProviderUi.Text(error, 11, ProviderUi.Secondary);
            message.Margin = new Thickness(0, 4, 0, 0);
            stack.Children.Add(message);
        }
        var updated = ProviderUi.Text(state.LastSuccess is DateTimeOffset success
            ? $"마지막 확인 {success.LocalDateTime:g}" : "아직 확인된 값이 없습니다.", 10.5, ProviderUi.Muted);
        updated.Margin = new Thickness(0, 8, 0, 0);
        stack.Children.Add(updated);
        card.Child = stack;
        AutomationProperties.SetName(card, ProviderUi.Summary(state));
        RowsPanel.Children.Add(card);
    }

    private static void AddWindowRow(StackPanel parent, ProviderUsageWindow window)
    {
        var row = new Grid { Margin = new Thickness(0, 3, 0, 3) };
        row.ColumnDefinitions.Add(new ColumnDefinition());
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var label = ProviderUi.Text(window.Label, 11.5, ProviderUi.Secondary);
        label.Margin = new Thickness(0, 0, 10, 0);
        var quota = ProviderUi.Text(window.DisplayRemainingPercent is int percent ? $"{percent}% 남음" : "미확인", 11.5);
        Grid.SetColumn(quota, 1);
        row.Children.Add(label);
        row.Children.Add(quota);
        parent.Children.Add(row);
        var reset = window.ResetsAt is DateTimeOffset date
            ? $"리셋 {date.LocalDateTime:g} · {UsageText.FormatCountdown(date)}" : "리셋 시각 미확인";
        parent.Children.Add(ProviderUi.Text(reset, 10.5, ProviderUi.Muted));
    }

    private void CloseButton_OnClick(object sender, RoutedEventArgs e) => Hide();
}
