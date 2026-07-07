// UiAutomationBridge.cs
// Port of AccessibilityBridge.swift.
//
// Reads UI Automation information from the currently focused UI element in any application.
// Uses FlaUI.UIA3 (NuGet) rather than raw COM UIA interop — the raw COM hierarchy in C#
// is genuinely painful (nested interface casts, manual IUIAutomation instantiation) in a way
// that the macOS AX C API isn't. FlaUI is a justified wrapper here (see §10 of the impl plan).
//
// DPI NOTE: FlaUI/UIA returns physical pixel coordinates.
// WinUI 3 AppWindow positioning uses logical pixels.
// Always convert: logical = physical / (GetDpiForWindow(hwnd) / 96.0)

using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;
using System;
using System.Drawing;
using static Glotto.WinUI.Interop.NativeMethods;

namespace Glotto.WinUI.Interop;

public sealed class UiAutomationBridge : IDisposable
{
    private readonly UIA3Automation _automation = new();

    // MARK: - Focused element

    /// <summary>
    /// Returns the UI Automation element that currently has keyboard focus, or null on failure.
    /// Uses the system-wide focused element rather than targeting a specific PID.
    /// </summary>
    public AutomationElement? GetFocusedElement()
    {
        try
        {
            return _automation.FocusedElement();
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[UiAutomationBridge] GetFocusedElement failed: {ex.Message}");
            return null;
        }
    }

    // MARK: - Caret / selection rect

    /// <summary>
    /// Returns the screen rectangle (physical pixels) of the insertion point in the focused element, or null.
    /// Used to position the candidate overlay panel directly beneath the cursor.
    ///
    /// Sequence:
    ///  1. Get TextPattern from the focused element.
    ///  2. Get the selection (array of TextRange).
    ///  3. Get bounding rectangles from the first text range.
    ///  4. Return the first rectangle (the caret position).
    /// </summary>
    public Rectangle? GetCaretRect(AutomationElement? element = null)
    {
        try
        {
            var target = element ?? GetFocusedElement();
            if (target is null) return null;

            var textPattern = target.Patterns.Text.PatternOrDefault;
            if (textPattern is null) return null;

            var selection = textPattern.GetSelection();
            if (selection is null || selection.Length == 0) return null;

            var rects = selection[0].GetBoundingRectangles();
            if (rects is null || rects.Length == 0) return null;

            var r = rects[0];
            return new Rectangle((int)r.X, (int)r.Y, (int)r.Width, (int)r.Height);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[UiAutomationBridge] GetCaretRect failed: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Returns the bounding rectangle (physical pixels) of the focused element itself, or null.
    /// Used as a fallback positioning anchor when the caret rect is unavailable.
    /// </summary>
    public Rectangle? GetElementRect(AutomationElement? element = null)
    {
        try
        {
            var target = element ?? GetFocusedElement();
            if (target is null) return null;

            var bounds = target.BoundingRectangle;
            return new Rectangle((int)bounds.X, (int)bounds.Y, (int)bounds.Width, (int)bounds.Height);
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[UiAutomationBridge] GetElementRect failed: {ex.Message}");
            return null;
        }
    }

    // MARK: - ValuePattern (opportunistic fast path)

    /// <summary>
    /// Attempt to set the value of a simple text field via ValuePattern.
    /// Returns true only if the write was verified by reading back the value and confirming
    /// the element's value changed as expected.
    ///
    /// Same verification discipline as macOS TextInjector.tryVerifiedAXInsertion:
    /// many apps (Word, some web inputs) report success from SetValue without actually
    /// changing anything — we verify by reading back.
    /// </summary>
    public bool TrySetValue(AutomationElement element, string text)
    {
        try
        {
            var valuePattern = element.Patterns.Value.PatternOrDefault;
            if (valuePattern is null || valuePattern.IsReadOnly) return false;

            var beforeValue = valuePattern.Value.Value ?? string.Empty;
            valuePattern.SetValue(text);

            var afterValue = valuePattern.Value.Value ?? string.Empty;
            // Verified: value changed. This is the "append at cursor" path — we just check
            // the string changed at all, since we can't easily read cursor position via ValuePattern.
            return afterValue != beforeValue;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[UiAutomationBridge] TrySetValue failed: {ex.Message}");
            return false;
        }
    }

    // MARK: - DPI conversion helpers

    /// <summary>
    /// Convert a physical pixel coordinate to a logical pixel coordinate for the given window.
    /// FlaUI/UIA returns physical pixels; WinUI 3 AppWindow.MoveAndResize uses physical pixels too
    /// (via RectInt32), so this is only needed when using other WinUI APIs that take logical coords.
    /// </summary>
    public static double PhysicalToLogical(double physicalPixels, IntPtr hwnd)
    {
        var dpi = GetDpiForWindow(hwnd);
        return physicalPixels / (dpi / 96.0);
    }

    public void Dispose() => _automation.Dispose();
}
