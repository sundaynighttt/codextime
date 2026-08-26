using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;

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
    }

    public void UpdateReport(RateLimitReport? report, string? error, DateTimeOffset? updatedAt)
    {
        RowsPanel.Children.Clear();
        if (report is null)
        {
            MainPercentText.Text = "--%";
            MainResetText.Text = error ?? "Codex 사용량 확인 중";
            StatusText.Text = error is null ? "로컬 Codex 사용량" : "사용량 조회 실패";
        }
        else
        {
            MainPercentText.Text = $"{report.Main.Primary.RemainingPercent}%";
            MainResetText.Text = $"남음 · {UsageText.FormatCountdown(report.Main.Primary.ResetsAt)}";
            StatusText.Text = error is null ? "로컬 Codex 사용량" : "마지막 값 표시 중 · 새로고침 실패";
            foreach (var bucket in report.Buckets)
            {
                AddRow(bucket.Name, bucket.Primary);
                if (bucket.Secondary is not null)
                {
                    AddRow($"{bucket.Name} 보조", bucket.Secondary);
                }
            }
        }

        UpdatedText.Text = updatedAt is null
            ? "아직 업데이트되지 않음"
            : $"마지막 업데이트 {updatedAt.Value.LocalDateTime:HH:mm:ss}";
    }

    internal void ShowNear(NativeMethods.NativeRect anchor)
    {
        new WindowInteropHelper(this).EnsureHandle();
        if (!IsVisible)
        {
            Show();
        }
        Activate();
        NativeMethods.PositionPopup(_windowHandle, anchor, Width, Height);
    }

    private void AddRow(string name, LimitWindow window)
    {
        var border = new Border
        {
            Background = new SolidColorBrush(System.Windows.Media.Color.FromArgb(90, 52, 52, 57)),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(10, 7, 10, 7),
            Margin = new Thickness(0, 0, 0, 6)
        };
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new TextBlock
        {
            Text = name,
            Foreground = new SolidColorBrush(System.Windows.Media.Color.FromRgb(205, 206, 212)),
            FontSize = 11.5,
            VerticalAlignment = VerticalAlignment.Center
        };
        var right = new TextBlock
        {
            Text = $"{window.RemainingPercent}% · {UsageText.FormatCountdown(window.ResetsAt)}",
            Foreground = new SolidColorBrush(UsageColors.ForRemaining(window.RemainingPercent)),
            FontSize = 11.5,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(right, 1);
        grid.Children.Add(left);
        grid.Children.Add(right);
        border.Child = grid;
        RowsPanel.Children.Add(border);
    }

    private void CloseButton_OnClick(object sender, RoutedEventArgs e) => Hide();
}
