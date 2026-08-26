using System.Runtime.InteropServices;
using System.Text;

namespace CodexTime.WinApp;

internal static class NativeMethods
{
    private const int GwlExStyle = -20;
    private const int GwlHwndParent = -8;
    private const long WsExToolWindow = 0x00000080L;
    private const long WsExNoActivate = 0x08000000L;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoActivate = 0x0010;
    private const uint AbmGetState = 0x00000004;
    private const uint AbsAutoHide = 0x00000001;
    private const uint MonitorDefaultToNearest = 0x00000002;
    private static readonly IntPtr HwndTopmost = new(-1);

    internal static void ConfigureToolWindow(IntPtr window, bool noActivate)
    {
        var style = GetWindowLongPtr(window, GwlExStyle).ToInt64() | WsExToolWindow;
        if (noActivate)
        {
            style |= WsExNoActivate;
        }
        SetWindowLongPtr(window, GwlExStyle, new IntPtr(style));
    }

    internal static bool TryPositionTaskbarLabel(
        IntPtr window,
        double logicalWidth,
        double logicalHeight,
        out NativeRect bounds)
    {
        bounds = default;
        var taskbar = FindWindow("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero || !GetWindowRect(taskbar, out var taskbarRect))
        {
            return false;
        }

        if (GetWindowLongPtr(window, GwlHwndParent) != taskbar)
        {
            SetWindowLongPtr(window, GwlHwndParent, taskbar);
        }

        var tray = FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);
        var trayStart = tray != IntPtr.Zero && GetWindowRect(tray, out var trayRect)
            ? trayRect.Left
            : taskbarRect.Right - 220;
        var dpi = Math.Max(96u, GetDpiForWindow(taskbar));
        var width = (int)Math.Round(logicalWidth * dpi / 96d);
        var height = (int)Math.Round(logicalHeight * dpi / 96d);

        int left;
        int top;
        if (taskbarRect.Width >= taskbarRect.Height)
        {
            left = Math.Max(taskbarRect.Left + 8, trayStart - width - 8);
            top = taskbarRect.Top + Math.Max(0, (taskbarRect.Height - height) / 2);
        }
        else
        {
            left = taskbarRect.Left + Math.Max(0, (taskbarRect.Width - width) / 2);
            top = Math.Max(taskbarRect.Top + 8, taskbarRect.Bottom - height - 120);
        }

        bounds = new NativeRect(left, top, left + width, top + height);
        return SetWindowPos(window, HwndTopmost, left, top, width, height, SwpNoActivate);
    }

    internal static bool IsPrimaryTaskbarVisible()
    {
        var taskbar = FindWindow("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero || !IsWindowVisible(taskbar) || !GetWindowRect(taskbar, out var taskbarRect))
        {
            return false;
        }

        var data = new AppBarData { Size = (uint)Marshal.SizeOf<AppBarData>() };
        if ((SHAppBarMessage(AbmGetState, ref data) & AbsAutoHide) == 0)
        {
            return true;
        }

        var monitor = MonitorFromWindow(taskbar, MonitorDefaultToNearest);
        var monitorInfo = CreateMonitorInfo();
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref monitorInfo))
        {
            return true;
        }

        var visibleWidth = Math.Max(0,
            Math.Min(taskbarRect.Right, monitorInfo.Monitor.Right) -
            Math.Max(taskbarRect.Left, monitorInfo.Monitor.Left));
        var visibleHeight = Math.Max(0,
            Math.Min(taskbarRect.Bottom, monitorInfo.Monitor.Bottom) -
            Math.Max(taskbarRect.Top, monitorInfo.Monitor.Top));
        return taskbarRect.Width >= taskbarRect.Height ? visibleHeight > 4 : visibleWidth > 4;
    }

    internal static bool IsForegroundFullscreenOnSameMonitor(IntPtr referenceWindow)
    {
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero || foreground == referenceWindow)
        {
            return false;
        }

        var className = new StringBuilder(128);
        GetClassName(foreground, className, className.Capacity);
        if (className.ToString() is "Progman" or "WorkerW" or "Shell_TrayWnd" or
            "Shell_SecondaryTrayWnd" or "TaskListThumbnailWnd" or "MultitaskingViewFrame")
        {
            return false;
        }

        var referenceMonitor = MonitorFromWindow(referenceWindow, MonitorDefaultToNearest);
        var foregroundMonitor = MonitorFromWindow(foreground, MonitorDefaultToNearest);
        if (referenceMonitor == IntPtr.Zero || referenceMonitor != foregroundMonitor ||
            !GetWindowRect(foreground, out var foregroundRect))
        {
            return false;
        }

        var monitorInfo = CreateMonitorInfo();
        if (!GetMonitorInfo(referenceMonitor, ref monitorInfo))
        {
            return false;
        }

        const int tolerance = 1;
        return foregroundRect.Left <= monitorInfo.Monitor.Left + tolerance &&
               foregroundRect.Top <= monitorInfo.Monitor.Top + tolerance &&
               foregroundRect.Right >= monitorInfo.Monitor.Right - tolerance &&
               foregroundRect.Bottom >= monitorInfo.Monitor.Bottom - tolerance;
    }

    internal static NativeRect PositionFloating(
        IntPtr window,
        int? requestedLeft,
        int? requestedTop,
        double logicalWidth,
        double logicalHeight)
    {
        var dpi = Math.Max(96u, GetDpiForWindow(window));
        var width = (int)Math.Round(logicalWidth * dpi / 96d);
        var height = (int)Math.Round(logicalHeight * dpi / 96d);
        var screen = System.Windows.Forms.Screen.PrimaryScreen?.WorkingArea
                     ?? new System.Drawing.Rectangle(0, 0, 1920, 1080);
        var left = requestedLeft ?? screen.Right - width - 16;
        var top = requestedTop ?? screen.Top + 16;
        var requested = new NativeRect(left, top, left + width, top + height);
        var clamped = ClampToWorkArea(requested);
        SetWindowPos(window, HwndTopmost, clamped.Left, clamped.Top, width, height, SwpNoActivate);
        return new NativeRect(clamped.Left, clamped.Top, clamped.Left + width, clamped.Top + height);
    }

    internal static void MoveFloating(IntPtr window, int left, int top)
    {
        var rect = GetBounds(window);
        var clamped = ClampToWorkArea(new NativeRect(left, top, left + rect.Width, top + rect.Height));
        SetWindowPos(window, HwndTopmost, clamped.Left, clamped.Top, 0, 0, SwpNoActivate | SwpNoSize);
    }

    internal static NativeRect PositionPopup(IntPtr window, NativeRect anchor, double logicalWidth, double logicalHeight)
    {
        var monitor = MonitorFromWindow(window, MonitorDefaultToNearest);
        if (anchor.Width > 0 && anchor.Height > 0)
        {
            var anchorRect = anchor;
            monitor = MonitorFromRect(ref anchorRect, MonitorDefaultToNearest);
        }

        var monitorInfo = CreateMonitorInfo();
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref monitorInfo))
        {
            monitorInfo.Work = new NativeRect(0, 0, 1920, 1080);
        }

        var dpi = Math.Max(96u, GetDpiForWindow(window));
        var width = (int)Math.Round(logicalWidth * dpi / 96d);
        var height = (int)Math.Round(logicalHeight * dpi / 96d);
        var left = Math.Clamp(anchor.Right - width, monitorInfo.Work.Left, Math.Max(monitorInfo.Work.Left, monitorInfo.Work.Right - width));
        var top = anchor.Top - height - 8;
        if (top < monitorInfo.Work.Top)
        {
            top = anchor.Bottom + 8;
        }
        top = Math.Clamp(top, monitorInfo.Work.Top, Math.Max(monitorInfo.Work.Top, monitorInfo.Work.Bottom - height));
        SetWindowPos(window, HwndTopmost, left, top, width, height, SwpNoActivate);
        return new NativeRect(left, top, left + width, top + height);
    }

    internal static NativeRect GetBounds(IntPtr window) =>
        GetWindowRect(window, out var rect) ? rect : default;

    internal static Point GetCursorPosition()
    {
        GetCursorPos(out var point);
        return point;
    }

    internal static void CaptureMouse(IntPtr window) => SetCapture(window);

    internal static void ReleaseMouse() => ReleaseCapture();

    private static NativeRect ClampToWorkArea(NativeRect rect)
    {
        var copy = rect;
        var monitor = MonitorFromRect(ref copy, MonitorDefaultToNearest);
        var monitorInfo = CreateMonitorInfo();
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref monitorInfo))
        {
            return rect;
        }

        var left = Math.Clamp(rect.Left, monitorInfo.Work.Left, Math.Max(monitorInfo.Work.Left, monitorInfo.Work.Right - rect.Width));
        var top = Math.Clamp(rect.Top, monitorInfo.Work.Top, Math.Max(monitorInfo.Work.Top, monitorInfo.Work.Bottom - rect.Height));
        return new NativeRect(left, top, left + rect.Width, top + rect.Height);
    }

    private static MonitorInfo CreateMonitorInfo() => new()
    {
        Size = (uint)Marshal.SizeOf<MonitorInfo>()
    };

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string? windowName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string? windowName);

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr newValue);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr window, out NativeRect rectangle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder className, int maximumCount);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromRect(ref NativeRect rectangle, uint flags);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo monitorInfo);

    [DllImport("shell32.dll")]
    private static extern uint SHAppBarMessage(uint message, ref AppBarData data);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetCursorPos(out Point point);

    [DllImport("user32.dll")]
    private static extern IntPtr SetCapture(IntPtr window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReleaseCapture();

    [StructLayout(LayoutKind.Sequential)]
    internal struct NativeRect
    {
        internal NativeRect(int left, int top, int right, int bottom)
        {
            Left = left;
            Top = top;
            Right = right;
            Bottom = bottom;
        }

        internal int Left;
        internal int Top;
        internal int Right;
        internal int Bottom;
        internal readonly int Width => Right - Left;
        internal readonly int Height => Bottom - Top;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Point
    {
        internal int X;
        internal int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        internal uint Size;
        internal NativeRect Monitor;
        internal NativeRect Work;
        internal uint Flags;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AppBarData
    {
        internal uint Size;
        internal IntPtr Window;
        internal uint CallbackMessage;
        internal uint Edge;
        internal NativeRect Rectangle;
        internal IntPtr Parameter;
    }
}
