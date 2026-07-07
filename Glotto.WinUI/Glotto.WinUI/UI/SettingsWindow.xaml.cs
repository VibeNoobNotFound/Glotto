using System;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using WinRT.Interop;

namespace Glotto.WinUI.UI;

public sealed partial class SettingsWindow : Window
{
    public SettingsViewModel ViewModel { get; }

    private readonly AppWindow? _appWindow;

    public SettingsWindow()
    {
        ViewModel = new SettingsViewModel();
        InitializeComponent();
        
        // Wire up data context for commands to reference
        RecordHotkeyButton.DataContext = ViewModel;

        var hwnd = WindowNative.GetWindowHandle(this);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        _appWindow = AppWindow.GetFromWindowId(windowId);

        // Customize window size
        if (_appWindow != null)
        {
            _appWindow.Resize(new Windows.Graphics.SizeInt32(560, 680));
            
            // Set title bar styling if possible
            _appWindow.Title = "Glotto Settings";
        }
    }

    private void RecordHotkeyButton_Click(object sender, RoutedEventArgs e)
    {
        // Phase 1 hotkey recording placeholder
        // In full implementation, this turns the button into listening mode, listens to the next key down, and updates HotkeyManager
        System.Diagnostics.Debug.WriteLine("[SettingsWindow] Record hotkey button clicked");
    }
}
