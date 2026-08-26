using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;

namespace CodexTime.WinApp;

public partial class FloatingPillWindow : Window
{
    private readonly DispatcherTimer _visibilityTimer;
    private IntPtr _windowHandle;
    private NativeMethods.Point _dragStartCursor;
    private NativeMethods.NativeRect _dragStartBounds;
    private bool _pointerDown;
    private bool _dragging;
    private bool _requestedVisible;

    public FloatingPillWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) =>
        {
            _windowHandle = new WindowInteropHelper(this).Handle;
            NativeMethods.ConfigureToolWindow(_windowHandle, noActivate: true);
            HwndSource.FromHwnd(_windowHandle)?.AddHook(WindowProc);
        };
        _visibilityTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _visibilityTimer.Tick += (_, _) => UpdateFullscreenVisibility();
        Closed += (_, _) => _visibilityTimer.Stop();
    }

    public event EventHandler? ToggleDetailsRequested;
    public event EventHandler<PositionCommittedEventArgs>? PositionCommitted;

    internal NativeMethods.NativeRect AnchorBounds =>
        _windowHandle == IntPtr.Zero ? default : NativeMethods.GetBounds(_windowHandle);

    public void ShowPill(int? left, int? top)
    {
        _requestedVisible = true;
        new WindowInteropHelper(this).EnsureHandle();
        if (!IsVisible)
        {
            Show();
        }
        NativeMethods.PositionFloating(_windowHandle, left, top, Width, Height);
        _visibilityTimer.Start();
        UpdateFullscreenVisibility();
    }

    public void HidePill()
    {
        _requestedVisible = false;
        _visibilityTimer.Stop();
        Hide();
    }

    public void UpdateUsage(string text, int? remainingPercent, string tooltip)
    {
        UsageText.Text = text;
        ToolTip = tooltip;
        StatusDot.Fill = new SolidColorBrush(UsageColors.ForRemaining(remainingPercent));
    }

    private void UpdateFullscreenVisibility()
    {
        if (!_requestedVisible || _windowHandle == IntPtr.Zero)
        {
            return;
        }

        if (NativeMethods.IsForegroundFullscreenOnSameMonitor(_windowHandle))
        {
            Hide();
        }
        else if (!IsVisible)
        {
            Show();
            NativeMethods.PositionFloating(_windowHandle, AnchorBounds.Left, AnchorBounds.Top, Width, Height);
        }
    }

    private void BeginDrag()
    {
        _pointerDown = true;
        _dragging = false;
        _dragStartCursor = NativeMethods.GetCursorPosition();
        _dragStartBounds = NativeMethods.GetBounds(_windowHandle);
        NativeMethods.CaptureMouse(_windowHandle);
    }

    private void ContinueDrag()
    {
        if (!_pointerDown)
        {
            return;
        }

        var cursor = NativeMethods.GetCursorPosition();
        var deltaX = cursor.X - _dragStartCursor.X;
        var deltaY = cursor.Y - _dragStartCursor.Y;
        if (!_dragging && Math.Abs(deltaX) + Math.Abs(deltaY) < 5)
        {
            return;
        }

        _dragging = true;
        NativeMethods.MoveFloating(
            _windowHandle,
            _dragStartBounds.Left + deltaX,
            _dragStartBounds.Top + deltaY);
    }

    private void EndDrag()
    {
        if (!_pointerDown)
        {
            return;
        }

        _pointerDown = false;
        NativeMethods.ReleaseMouse();
        if (_dragging)
        {
            var bounds = NativeMethods.GetBounds(_windowHandle);
            PositionCommitted?.Invoke(this, new PositionCommittedEventArgs(bounds.Left, bounds.Top));
        }
        else
        {
            ToggleDetailsRequested?.Invoke(this, EventArgs.Empty);
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
        const int leftButtonDown = 0x0201;
        const int leftButtonUp = 0x0202;
        const int mouseMove = 0x0200;
        const int rightButtonUp = 0x0205;
        const int noActivate = 3;

        switch (message)
        {
            case mouseActivate:
                handled = true;
                return new IntPtr(noActivate);
            case leftButtonDown:
                BeginDrag();
                handled = true;
                break;
            case mouseMove:
                ContinueDrag();
                break;
            case leftButtonUp:
                EndDrag();
                handled = true;
                break;
            case rightButtonUp:
                OpenContextMenu();
                handled = true;
                break;
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

public sealed class PositionCommittedEventArgs(int left, int top) : EventArgs
{
    public int Left { get; } = left;
    public int Top { get; } = top;
}
