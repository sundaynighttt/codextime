using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;

namespace CodexTime.WinApp;

public partial class TaskbarLabelWindow : Window
{
    private readonly DispatcherTimer _positionTimer;
    private IntPtr _windowHandle;
    private bool _requestedVisible;
    private NativeMethods.NativeRect _bounds;

    public TaskbarLabelWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) =>
        {
            _windowHandle = new WindowInteropHelper(this).Handle;
            NativeMethods.ConfigureToolWindow(_windowHandle, noActivate: true);
            HwndSource.FromHwnd(_windowHandle)?.AddHook(WindowProc);
            UpdateVisibilityAndPosition();
        };
        _positionTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _positionTimer.Tick += (_, _) => UpdateVisibilityAndPosition();
        Closed += (_, _) => _positionTimer.Stop();
    }

    public event EventHandler? ToggleDetailsRequested;

    internal NativeMethods.NativeRect AnchorBounds => _bounds;

    public void ShowLabel()
    {
        _requestedVisible = true;
        new WindowInteropHelper(this).EnsureHandle();
        _positionTimer.Start();
        UpdateVisibilityAndPosition();
    }

    public void HideLabel()
    {
        _requestedVisible = false;
        _positionTimer.Stop();
        Hide();
    }

    public void UpdateUsage(string text, int? remainingPercent, string tooltip)
    {
        UsageText.Text = text;
        ToolTip = tooltip;
        StatusDot.Fill = new SolidColorBrush(UsageColors.ForRemaining(remainingPercent));
    }

    private void UpdateVisibilityAndPosition()
    {
        if (!_requestedVisible || _windowHandle == IntPtr.Zero)
        {
            return;
        }

        var shouldShow = NativeMethods.IsPrimaryTaskbarVisible() &&
                         !NativeMethods.IsForegroundFullscreenOnSameMonitor(_windowHandle);
        if (!shouldShow)
        {
            Hide();
            return;
        }

        if (!NativeMethods.TryPositionTaskbarLabel(_windowHandle, Width, Height, out _bounds))
        {
            Hide();
            return;
        }

        if (!IsVisible)
        {
            Show();
            NativeMethods.TryPositionTaskbarLabel(_windowHandle, Width, Height, out _bounds);
        }
    }

    private IntPtr WindowProc(
        IntPtr window,
        int message,
        IntPtr wParam,
        IntPtr lParam,
        ref bool handled)
    {
        const int mouseActivate = 0x0021;
        const int leftButtonUp = 0x0202;
        const int rightButtonUp = 0x0205;
        const int noActivate = 3;

        if (message == mouseActivate)
        {
            handled = true;
            return new IntPtr(noActivate);
        }
        if (message == leftButtonUp)
        {
            Dispatcher.BeginInvoke(() => ToggleDetailsRequested?.Invoke(this, EventArgs.Empty));
            handled = true;
        }
        else if (message == rightButtonUp)
        {
            Dispatcher.BeginInvoke(OpenContextMenu);
            handled = true;
        }
        return IntPtr.Zero;
    }

    private void OpenContextMenu()
    {
        if (ContextMenu is null)
        {
            return;
        }
        ContextMenu.Placement = PlacementMode.MousePoint;
        ContextMenu.IsOpen = true;
    }
}
