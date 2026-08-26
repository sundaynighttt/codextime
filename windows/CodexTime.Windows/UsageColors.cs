using System.Windows.Media;

namespace CodexTime.WinApp;

internal static class UsageColors
{
    internal static System.Windows.Media.Color ForRemaining(int? remainingPercent) => remainingPercent switch
    {
        null => System.Windows.Media.Color.FromRgb(115, 115, 122),
        > 50 => System.Windows.Media.Color.FromRgb(91, 214, 150),
        > 20 => System.Windows.Media.Color.FromRgb(236, 174, 73),
        _ => System.Windows.Media.Color.FromRgb(235, 91, 91)
    };
}
