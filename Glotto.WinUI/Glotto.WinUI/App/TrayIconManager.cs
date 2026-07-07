// TrayIconManager.cs
// H.NotifyIcon.WinUI windowless tray icon bootstrap.
//
// IMPORTANT: TaskbarIcon must be declared in Application.Resources (App.xaml) and retrieved here
// with ForceCreate(). Creating TaskbarIcon purely in code without a XAML host does NOT work in
// H.NotifyIcon.WinUI — the icon will never appear in the system tray.
//
// Click API note (WinUI flavour differs from WPF):
//   - TrayMouseDoubleClick does NOT exist in H.NotifyIcon.WinUI.
//   - Use DoubleClickCommand (ICommand) for double-click.
//   - Right-click menu is handled automatically via MenuActivation="RightClick".
//
// Pattern reference: H.NotifyIcon.Apps.WinUI.Windowless sample
//   https://github.com/HavenDV/H.NotifyIcon/tree/master/src/apps/H.NotifyIcon.Apps.WinUI.Windowless

using System;
using System.Windows.Input;
using H.NotifyIcon;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Glotto.WinUI.Tray;

public sealed class TrayIconManager : IDisposable
{
    private readonly TaskbarIcon _taskbarIcon;
    private readonly Action _onToggle;
    private readonly Action _onOpenSettings;
    private readonly Action _onQuit;

    /// <param name="onToggle">Called on double-click or "Toggle" menu item.</param>
    /// <param name="onOpenSettings">Called on "Settings…" menu item.</param>
    /// <param name="onQuit">Called on "Quit" menu item.</param>
    public TrayIconManager(Action onToggle, Action onOpenSettings, Action onQuit)
    {
        _onToggle = onToggle;
        _onOpenSettings = onOpenSettings;
        _onQuit = onQuit;

        // Retrieve the TaskbarIcon that was declared in App.xaml Application.Resources.
        // ForceCreate() registers it with the system tray immediately.
        // enablesEfficiencyMode=false so we don't throttle the keyboard hook thread.
        _taskbarIcon = (TaskbarIcon)Application.Current.Resources["TrayIcon"];
        _taskbarIcon.ForceCreate(enablesEfficiencyMode: false);

        // Wire menu items (they were declared by name in App.xaml ContextFlyout)
        var flyout = (MenuFlyout)_taskbarIcon.ContextFlyout;
        WireMenuItem(flyout, "Toggle Composition Mode", () => _onToggle());
        WireMenuItem(flyout, "Settings\u2026", () => _onOpenSettings());
        WireMenuItem(flyout, "Quit Glotto", () => _onQuit());

        // Double-click toggles composition.
        // H.NotifyIcon.WinUI uses DoubleClickCommand (ICommand) — not a .NET event.
        _taskbarIcon.DoubleClickCommand = new RelayCommand(_onToggle);

        UpdateIconState(false);
    }

    // MARK: - State

    public void UpdateIconState(bool armed)
    {
        _taskbarIcon.ToolTipText = armed
            ? "Glotto - Armed (type phonetically)"
            : "Glotto - Idle (right-click for menu, double-click to arm)";

        // Update the GeneratedIconSource text to reflect state.
        // GeneratedIconSource is the correct H.NotifyIcon type for code-driven icon updates.
        _taskbarIcon.IconSource = new GeneratedIconSource
        {
            Text = armed ? "🔵" : "⭕",
            FontFamily = new("Segoe UI Emoji"),
            FontSize = 48
        };
    }

    // MARK: - Helpers

    private static void WireMenuItem(MenuFlyout flyout, string text, Action handler)
    {
        foreach (var item in flyout.Items)
        {
            if (item is MenuFlyoutItem mfi && mfi.Text == text)
            {
                mfi.Command = new RelayCommand(handler);
                return;
            }
        }
        // Item not found — add it programmatically as a fallback
        var newItem = new MenuFlyoutItem { Text = text, Command = new RelayCommand(handler) };
        flyout.Items.Add(newItem);
    }

    // MARK: - IDisposable

    public void Dispose()
    {
        _taskbarIcon.Dispose();
    }
}

/// <summary>
/// Minimal ICommand wrapper for wiring tray icon commands.
/// H.NotifyIcon.WinUI's DoubleClickCommand / LeftClickCommand accept ICommand.
/// </summary>
file sealed class RelayCommand(Action execute) : ICommand
{
    public event EventHandler? CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => execute();
}
