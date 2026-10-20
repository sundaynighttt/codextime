using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Button = System.Windows.Controls.Button;
using CheckBox = System.Windows.Controls.CheckBox;

namespace CodexTime.WinApp;

/// <summary>UI-only synthetic checks; no controller, disk settings, login, or usage requests.</summary>
public static class ProviderUiSelfTests
{
    public static void Run()
    {
        var states = WindowsPreview.ExampleStates();
        var strip = new ProviderStrip();
        strip.UpdateProviders(states, false);
        Check(strip.Children.Count == 3, "three default provider groups");
        Check(strip.Summary.Contains("Codex · 73%") && strip.Summary.Contains("Grok · 82%")
            && strip.Summary.Contains("Claude · 64%"), "provider-specific summaries");
        strip.UpdateProviders([states[1]], false);
        Check(strip.Children.Count == 1 && strip.Summary.StartsWith("Grok"), "one visible service");
        strip.UpdateProviders([], false);
        Check(strip.Children.Count == 1 && strip.Children[0] is TextBlock { Text: "사용량" }
            && strip.Summary.Contains("간편 설정"), "all-hidden recovery stays reachable");

        var stale = new ProviderUsageState(UsageProviderID.Codex)
        {
            Snapshot = new(UsageProviderID.Codex,
                [new("primary", "5시간 한도", 100, DateTimeOffset.Now.AddHours(1))]),
            LastSuccess = DateTimeOffset.Now.AddMinutes(-21), Failure = ProviderFailure.Timeout
        };
        Check(ProviderUi.Value(stale) == "100%*", "100 percent and stale marker");
        Check(!ProviderUi.Value(stale).Contains('(') && ProviderUi.Value(stale, true).Contains('('), "reset time is optional");
        var pending = new ProviderUsageState(UsageProviderID.Grok)
        {
            Snapshot = states[1].Snapshot, AwaitingVerification = true, Failure = null
        };
        Check(ProviderUi.Value(pending) == "—" && ProviderUi.Status(pending).Contains("대조 대기"), "unconfirmed values never look connected");
        var unknown = new ProviderUsageState(UsageProviderID.Claude);
        Check(ProviderUi.Value(unknown) == "—", "unknown stays unknown");
        var zero = new ProviderUsageState(UsageProviderID.Claude)
        {
            Snapshot = new(UsageProviderID.Claude, [new("primary", "주간 한도", 0)]), Failure = null
        };
        Check(ProviderUi.Value(zero) == "0%", "zero remains a real quota");

        var taskbar = new TaskbarLabelWindow();
        var floating = new FloatingPillWindow();
        var details = new DetailsWindow();
        var settings = new AppSettings();
        var setup = new SetupWindow(settings);
        try
        {
            taskbar.UpdateProviders(states, false);
            WindowsPreview.LayoutContent(taskbar, taskbar.Width, 36);
            Check(taskbar.Width > 120 && taskbar.Width < 360, "compact three-provider taskbar width");
            EnsureWithin((FrameworkElement)taskbar.Content);
            floating.UpdateProviders(states, true);
            WindowsPreview.LayoutContent(floating, floating.Width, 40);
            EnsureWithin((FrameworkElement)floating.Content);
            taskbar.UpdateProviders([], false);
            Check(taskbar.Width >= 50 && taskbar.Width < 120, "all-hidden taskbar has a usable target");

            details.UpdateProviders(states);
            var detailRoot = WindowsPreview.LayoutContent(details, 400, 650);
            var detailSetup = Find<Button>(detailRoot, "CodexTimeDetails-setup");
            Check(detailSetup is not null && detailSetup.ActualWidth > 250 && detailSetup.ActualHeight >= 30,
                "details has reachable settings action");
            Check(Descendants(detailRoot).OfType<Border>().Count(border =>
                AutomationProperties.GetName(border).StartsWith("Codex ·")
                || AutomationProperties.GetName(border).StartsWith("Grok ·")
                || AutomationProperties.GetName(border).StartsWith("Claude ·")) == 3, "three detail cards");

            var changed = 0;
            setup.VisibilityChanged += (_, _) => changed++;
            setup.UpdateProviders(states);
            var setupRoot = WindowsPreview.LayoutContent(setup, 640, 760);
            Check(changed == 0, "rendering settings never emits a preference change");
            foreach (var id in UsageProviders.All)
            {
                var visible = Find<CheckBox>(setupRoot, $"CodexTimeConnection-{id}-visible");
                Check(visible is { IsChecked: true }, "all three services initially selected");
                var connect = Find<Button>(setupRoot, $"CodexTimeConnection-{id}-connect");
                Check(connect is not null && connect.Focusable && connect.ActualHeight >= 30,
                    "keyboard-accessible connection action");
                Check(connect!.ActualWidth > 55 && connect.ActualWidth < 250, "connection action has usable bounds");
            }
            var verify = Find<Button>(setupRoot, "CodexTimeConnection-Grok-verify");
            var compared = Find<CheckBox>(setupRoot, "CodexTimeConnection-Grok-compared");
            Check(verify is { IsEnabled: false } && compared is { IsEnabled: false }, "verification starts unavailable");
            setup.UpdateProviders([states[0], pending, states[2]]);
            Check(compared is { IsEnabled: true } && verify is { IsEnabled: false }, "Grok comparison requires user check");
            compared!.IsChecked = true;
            Check(verify!.IsEnabled, "comparison enables explicit confirmation");
            var verifyEvents = 0;
            setup.VerifyRequested += (_, args) => { if (args.Provider == UsageProviderID.Grok) verifyEvents++; };
            verify.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(verifyEvents == 1, "only explicit checked action confirms");
            setup.UpdateProviders(states);
            Check(compared.IsChecked == false && !verify.IsEnabled, "verification checkbox resets after completion");
            foreach (var id in UsageProviders.All) settings.Preferences(id).Enabled = false;
            setup.UpdateProviders(states);
            Check(changed == 0, "programmatic hide update does not emit user actions");
            Check(Descendants(setupRoot).OfType<ProviderStrip>().Single().Summary.Contains("표시 중인 서비스 없음"),
                "all-hidden settings preview preserves recovery copy");
            EnsureActionWidths(setupRoot);
        }
        finally
        {
            taskbar.Close(); floating.Close(); details.Close(); setup.Close();
        }
    }

    private static void EnsureWithin(FrameworkElement root)
    {
        foreach (var strip in Descendants(root).OfType<ProviderStrip>())
        {
            var offset = strip.TransformToAncestor(root).Transform(new System.Windows.Point(0, 0));
            Check(offset.X >= -1 && offset.X + strip.ActualWidth <= root.ActualWidth + 1,
                "strip fits the visible surface");
        }
    }

    private static void EnsureActionWidths(FrameworkElement root)
    {
        foreach (var button in Descendants(root).OfType<Button>().Where(button => button.IsVisible || button.ActualWidth > 0))
        {
            Check(button.ActualWidth <= 600 && button.ActualWidth > 0, "setup action fits card width");
        }
    }

    private static T? Find<T>(DependencyObject root, string id) where T : DependencyObject =>
        Descendants(root).OfType<T>().FirstOrDefault(value => AutomationProperties.GetAutomationId(value) == id);

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        yield return root;
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
            foreach (var child in Descendants(VisualTreeHelper.GetChild(root, index))) yield return child;
    }

    private static void Check(bool condition, string name)
    {
        if (!condition) throw new InvalidOperationException($"Provider UI self-test failed: {name}");
    }
}
