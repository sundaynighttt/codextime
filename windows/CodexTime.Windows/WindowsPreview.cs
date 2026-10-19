using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using FlowDirection = System.Windows.FlowDirection;

namespace CodexTime.WinApp;

/// <summary>Offline documentation images. Never creates a controller or opens account storage.</summary>
public static class WindowsPreview
{
    public static void Render(string directory)
    {
        Directory.CreateDirectory(directory);
        var states = ExampleStates();
        var taskbar = new TaskbarLabelWindow();
        var floating = new FloatingPillWindow();
        var details = new DetailsWindow();
        var setup = new SetupWindow(new AppSettings());
        try
        {
            taskbar.UpdateProviders(states, false);
            SaveContent(taskbar, Path.Combine(directory, "windows-taskbar-three-providers.png"), taskbar.Width, 36);
            floating.UpdateProviders(states, false);
            SaveContent(floating, Path.Combine(directory, "windows-floating-three-providers.png"), floating.Width, 40);
            details.UpdateProviders(states);
            SaveContent(details, Path.Combine(directory, "windows-details-three-providers.png"), 400, 650);
            setup.UpdateProviders(UsageProviders.All.Select(id => new ProviderUsageState(id)).ToArray());
            SaveContent(setup, Path.Combine(directory, "windows-setup-before-login.png"), 640, 760);
        }
        finally
        {
            taskbar.Close();
            floating.Close();
            details.Close();
            setup.Close();
        }
    }

    internal static ProviderUsageState[] ExampleStates()
    {
        // Both quota and time are synthetic. Keep time relative so preview jobs
        // show a current, accepted example rather than a historical stale state.
        var now = DateTimeOffset.Now;
        return
        [
            Example(UsageProviderID.Codex, 73, now, "5시간 한도", now.AddHours(3).AddMinutes(24)),
            Example(UsageProviderID.Grok, 82, now, "Grok 구독 한도", now.AddHours(4).AddMinutes(12)),
            new ProviderUsageState(UsageProviderID.Claude)
            {
                Snapshot = new(UsageProviderID.Claude,
                [
                    new("session", "현재 세션", 86, now.AddHours(2).AddMinutes(18)),
                    new("weekly", "주간 공통 한도", 64, now.AddDays(3).AddHours(17))
                ]),
                LastSuccess = now, LastAttempt = now, Failure = null
            }
        ];
    }

    private static ProviderUsageState Example(UsageProviderID id, int percent, DateTimeOffset now,
        string label, DateTimeOffset reset) => new(id)
    {
        Snapshot = new(id, [new("primary", label, percent, reset)]),
        LastSuccess = now, LastAttempt = now, Failure = null
    };

    internal static FrameworkElement LayoutContent(Window window, double width, double height)
    {
        var content = (FrameworkElement)window.Content;
        content.Measure(new System.Windows.Size(width, height));
        content.Arrange(new Rect(0, 0, width, height));
        content.UpdateLayout();
        return content;
    }

    private static void SaveContent(Window window, string path, double width, double height)
    {
        var content = LayoutContent(window, width, height);
        const int captionHeight = 36;
        var caption = new FormattedText("합성 예시 · 실제 계정 데이터가 아닙니다", CultureInfo.GetCultureInfo("ko-KR"),
            FlowDirection.LeftToRight, new Typeface("Segoe UI"), 11, ProviderUi.Secondary, 1);
        var outputWidth = Math.Max(width, Math.Ceiling(caption.Width) + 18);
        var visual = new DrawingVisual();
        using (var context = visual.RenderOpen())
        {
            context.DrawRectangle(ProviderUi.Brush("#151518"), null, new Rect(0, 0, outputWidth, height + captionHeight));
            context.DrawText(caption, new System.Windows.Point(9, 10));
            var brush = new VisualBrush(content) { Stretch = Stretch.Fill };
            context.DrawRectangle(brush, null, new Rect((outputWidth - width) / 2, captionHeight, width, height));
        }
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(outputWidth), (int)Math.Ceiling(height) + captionHeight,
            96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        var png = new PngBitmapEncoder();
        png.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        png.Save(stream);
    }
}
