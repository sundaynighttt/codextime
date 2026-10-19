using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Button = System.Windows.Controls.Button;
using Orientation = System.Windows.Controls.Orientation;
using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace CodexTime.WinApp;

/// <summary>One compact, ordered group shared by both always-visible surfaces.</summary>
public sealed class ProviderStrip : StackPanel
{
    public ProviderStrip()
    {
        Orientation = Orientation.Horizontal;
        VerticalAlignment = VerticalAlignment.Center;
        IsHitTestVisible = false;
    }

    public string Summary { get; private set; } = "사용량 메뉴";

    public void UpdateProviders(IReadOnlyList<ProviderUsageState> states, bool showResetTime)
    {
        Children.Clear();
        var ordered = UsageProviders.All.Select(id => states.FirstOrDefault(state => state.Id == id))
            .Where(state => state is not null).Cast<ProviderUsageState>().ToArray();
        if (ordered.Length == 0)
        {
            Children.Add(ProviderUi.Text("사용량", 13, ProviderUi.Foreground));
            Summary = "사용량 메뉴 · 표시 중인 서비스 없음 · 간편 설정에서 다시 표시할 수 있습니다.";
        }
        else
        {
            for (var index = 0; index < ordered.Length; index++)
            {
                var state = ordered[index];
                var group = new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    VerticalAlignment = VerticalAlignment.Center,
                    Margin = new Thickness(0, 0, index == ordered.Length - 1 ? 0 : 12, 0)
                };
                group.Children.Add(ProviderUi.Logo(state.Id, 15));
                var value = ProviderUi.Text(ProviderUi.Value(state, showResetTime), 13, ProviderUi.Foreground);
                value.Margin = new Thickness(5, 0, 0, 0);
                value.FontWeight = FontWeights.SemiBold;
                group.Children.Add(value);
                group.ToolTip = ProviderUi.Summary(state);
                AutomationProperties.SetName(group, ProviderUi.Summary(state));
                Children.Add(group);
            }
            Summary = string.Join(" · ", ordered.Select(ProviderUi.Summary));
        }
        ToolTip = Summary;
        AutomationProperties.SetName(this, Summary);
    }
}

internal static class ProviderUi
{
    internal static readonly SolidColorBrush Foreground = Brush("#F5F5F6");
    internal static readonly SolidColorBrush Secondary = Brush("#B9BAC1");
    internal static readonly SolidColorBrush Muted = Brush("#A0A2AC");
    internal static readonly SolidColorBrush Card = Brush("#343439");

    internal static SolidColorBrush Brush(string hex) =>
        new((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(hex));

    internal static TextBlock Text(string text, double size = 12, System.Windows.Media.Brush? foreground = null) => new()
    {
        Text = text,
        Foreground = foreground ?? Foreground,
        FontFamily = new System.Windows.Media.FontFamily("Segoe UI"),
        FontSize = size,
        TextWrapping = TextWrapping.Wrap,
        VerticalAlignment = VerticalAlignment.Center
    };

    internal static FrameworkElement Logo(UsageProviderID id, double size = 20)
    {
        // The same transparent artwork used on Mac and iPhone; render its alpha as
        // a template so the logos retain contrast on the dark Windows surfaces.
        var source = new BitmapImage(new Uri(
            $"pack://application:,,,/Assets/{id.ToString().ToLowerInvariant()}.png", UriKind.Absolute));
        var logo = new Border
        {
            Width = size,
            Height = size,
            Background = Foreground,
            OpacityMask = new ImageBrush(source) { Stretch = Stretch.Uniform },
            VerticalAlignment = VerticalAlignment.Center
        };
        AutomationProperties.SetName(logo, id.Name());
        return logo;
    }

    internal static string Value(ProviderUsageState state, bool showResetTime = false)
    {
        // An unconfirmed Grok connection must not look like an accepted quota.
        if (state.AwaitingVerification) return "—";
        if (state.DisplayRemainingPercent is not int percent) return "—";
        var value = $"{percent}%{(state.IsStale ? "*" : "")}";
        if (showResetTime && state.Snapshot?.DisplayWindow?.ResetsAt is DateTimeOffset reset)
        {
            value += $" ({UsageText.FormatCountdown(reset)})";
        }
        return value;
    }

    internal static string Status(ProviderUsageState state)
    {
        if (state.IsRefreshing) return state.Snapshot is null ? "확인 중…" : "새로고침 중…";
        if (state.AwaitingVerification) return "웹 대조 대기 · 자동 갱신 꺼짐";
        if (state.IsStale) return "이전 값 · 다시 확인 필요";
        if (state.Snapshot is not null && state.Failure is null)
            return state.DisplayRemainingPercent.HasValue ? "연결 완료" : "응답 확인 · 수치 미제공";
        return state.Failure switch
        {
            ProviderFailure.AuthenticationRequired => "로그인 필요",
            ProviderFailure.NotInstalled => "설치 필요",
            ProviderFailure.PermissionRequired => "연결 권한 필요",
            ProviderFailure.NotConnected => "미연결",
            ProviderFailure.Unsupported => "지원 형식 확인 필요",
            null => "조회 전",
            _ => "새로고침 실패"
        };
    }

    internal static string Summary(ProviderUsageState state)
    {
        var value = state.AwaitingVerification ? "웹 대조 전" : state.DisplayRemainingPercent is int percent
            ? $"{percent}% 남음{(state.IsStale ? " · 이전 값" : "")}" : "잔여량 미확인";
        var reset = state.Snapshot?.DisplayWindow?.ResetsAt is DateTimeOffset date
            ? $" · 리셋 {date.LocalDateTime:g}" : "";
        return $"{state.Id.Name()} · {value} · {Status(state)}{reset}";
    }

    internal static Button Button(string title, string automationId, RoutedEventHandler clicked)
    {
        var button = new Button
        {
            Content = title,
            Padding = new Thickness(11, 7, 11, 7),
            Margin = new Thickness(0, 0, 8, 6),
            Foreground = Foreground,
            Background = Brush("#414148"),
            BorderBrush = Brush("#666670"),
            BorderThickness = new Thickness(1),
            Cursor = System.Windows.Input.Cursors.Hand,
            MinHeight = 32,
            FontSize = 12
        };
        // Keep native focus and keyboard handling; the template only changes the
        // existing rounded dark appearance, including disabled and focused states.
        var border = new FrameworkElementFactory(typeof(Border));
        border.Name = "ButtonSurface";
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(7));
        border.SetBinding(Border.BackgroundProperty, new System.Windows.Data.Binding("Background")
            { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetBinding(Border.BorderBrushProperty, new System.Windows.Data.Binding("BorderBrush")
            { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.SetValue(Border.BorderThicknessProperty, new Thickness(1));
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        content.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Center);
        content.SetBinding(FrameworkElement.MarginProperty, new System.Windows.Data.Binding("Padding")
            { RelativeSource = System.Windows.Data.RelativeSource.TemplatedParent });
        border.AppendChild(content);
        var template = new ControlTemplate(typeof(Button)) { VisualTree = border };
        var focus = new Trigger { Property = System.Windows.Controls.Button.IsKeyboardFocusedProperty, Value = true };
        focus.Setters.Add(new Setter(Border.BorderBrushProperty, Brush("#97BFFF"), "ButtonSurface"));
        var hover = new Trigger { Property = System.Windows.Controls.Button.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Border.BackgroundProperty, Brush("#51515A"), "ButtonSurface"));
        var disabled = new Trigger { Property = System.Windows.Controls.Button.IsEnabledProperty, Value = false };
        disabled.Setters.Add(new Setter(System.Windows.Controls.Button.OpacityProperty, 0.48));
        template.Triggers.Add(focus);
        template.Triggers.Add(hover);
        template.Triggers.Add(disabled);
        button.Template = template;
        button.Click += clicked;
        AutomationProperties.SetAutomationId(button, automationId);
        AutomationProperties.SetName(button, title);
        return button;
    }
}
