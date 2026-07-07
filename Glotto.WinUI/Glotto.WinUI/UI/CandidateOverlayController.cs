// CandidateOverlayController.cs
// Port of CandidateOverlayController.swift.
//
// Manages the floating non-activating candidate panel window.
// The window is created lazily on first show, and hidden (not destroyed) between compositions
// to avoid the overhead of Window creation on each session.
//
// THREADING: ALL window operations (create, show, hide, update, reposition)
// must happen on the UI dispatcher thread. This class dispatches everything
// via _dispatcherQueue. Callers may call from any thread.

using Glotto.WinUI.Core;
using Glotto.WinUI.Interop;
using Glotto.WinUI.UI;
using Microsoft.UI.Dispatching;
using System;
using System.Threading.Tasks;
using Windows.Graphics;
using static Glotto.WinUI.Interop.NativeMethods;

namespace Glotto.WinUI;

public sealed class CandidateOverlayController
{
    private CandidateOverlayWindow? _window;
    private bool _isPresented;
    private CompositionSession _lastSession;

    private readonly UiAutomationBridge _uia;
    private readonly DispatcherQueue _dispatcherQueue;

    private const int PanelWidth  = 320;
    private const int PanelPadding = 4;    // gap between caret bottom and panel top

    /// <summary>Raised when the user clicks a candidate row. Argument is the candidate index.</summary>
    public event EventHandler<int>? CandidateSelected;

    public CandidateOverlayController(UiAutomationBridge uia, DispatcherQueue dispatcherQueue)
    {
        _uia = uia;
        _dispatcherQueue = dispatcherQueue;
    }

    // MARK: - Show / update / hide (thread-safe — dispatches to UI thread internally)

    public void ShowOrUpdate(CompositionSession session)
    {
        _isPresented = true;
        _lastSession = session;

        _dispatcherQueue.TryEnqueue(() =>
        {
            EnsureWindowCreated();
            _window!.UpdateSession(session, isPresented: true);
            Reposition();
            _window.ShowNonActivating();
        });
    }

    public void Update(CompositionSession session)
    {
        _lastSession = session;

        _dispatcherQueue.TryEnqueue(() =>
        {
            _window?.UpdateSession(session, _isPresented);
        });
    }

    public void Hide()
    {
        if (!_isPresented) return;
        _isPresented = false;

        _dispatcherQueue.TryEnqueue(() =>
        {
            _window?.HideWindow();
        });
    }

    // MARK: - Positioning (must run on UI thread — called from within TryEnqueue block)

    /// <summary>
    /// Position the panel just below the caret rect from UiAutomationBridge.
    /// Falls back to focused element frame, then mouse cursor.
    /// Clamps to screen bounds so the panel is never partially off-screen.
    /// Must be called on the UI thread.
    /// </summary>
    public void Reposition()
    {
        if (_window is null) return;

        var hwnd = _window.GetHwnd();
        var dpi = GetDpiForWindow(hwnd);
        var scale = dpi / 96.0;

        System.Drawing.Rectangle? anchorRect = null;

        // Try caret rect first (physical pixels from UIA)
        var caretRect = _uia.GetCaretRect();
        if (caretRect.HasValue)
        {
            anchorRect = caretRect;
        }
        else
        {
            // Fallback: focused element bounding rect
            var elementRect = _uia.GetElementRect();
            if (elementRect.HasValue) anchorRect = elementRect;
        }

        int x, y, w, h;
        w = (int)(PanelWidth * scale);

        int estimatedHeight = 36; // Header / input row height
        if (!_lastSession.IsEmpty)
        {
            if (_lastSession.IsLoading)
            {
                estimatedHeight += 44;
            }
            else if (_lastSession.Candidates.Count == 0)
            {
                estimatedHeight += 38;
            }
            else
            {
                int rowCount = _lastSession.Candidates.Count;
                estimatedHeight += (rowCount * 48) + ((rowCount - 1) * 1) + 12;
            }
        }
        else
        {
            estimatedHeight += 38; // "Type to transliterate..." placeholder row
        }

        h = (int)(estimatedHeight * scale);

        if (anchorRect.HasValue)
        {
            // Position below the caret/element (physical pixels)
            x = anchorRect.Value.Left;
            y = anchorRect.Value.Bottom + PanelPadding;
        }
        else
        {
            // Last fallback: near the cursor
            NativeMethods.GetCursorPos(out NativeMethods.POINT pt);
            x = pt.x + 10;
            y = pt.y + 10;
        }

        // Clamp to screen bounds
        var (clampedX, clampedY) = ClampToScreen(x, y, w, h);
        _window.MoveAndResize(clampedX, clampedY, w, h);
    }

    // MARK: - Window management (must run on UI thread)

    private void EnsureWindowCreated()
    {
        if (_window is not null) return;
        _window = new CandidateOverlayWindow(_dispatcherQueue);
        _window.CandidateClicked += (_, idx) => CandidateSelected?.Invoke(this, idx);
    }

    // MARK: - Screen clamping

    private static (int x, int y) ClampToScreen(int x, int y, int w, int h)
    {
        // Get the work area of the primary monitor
        NativeMethods.SystemParametersInfoW(SPI_GETWORKAREA, 0, out NativeMethods.RECT workArea, 0);
        var clampedX = Math.Clamp(x, workArea.left, Math.Max(workArea.left, workArea.right - w));
        var clampedY = Math.Clamp(y, workArea.top, Math.Max(workArea.top, workArea.bottom - h));
        return (clampedX, clampedY);
    }

    private const uint SPI_GETWORKAREA = 0x0030;

    private UiAutomationBridge UiAutomationBridge => _uia;
}
