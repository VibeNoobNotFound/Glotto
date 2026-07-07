using System;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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

        // Customize titlebar and extend layout
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);

        // Customize window size and position
        if (_appWindow != null)
        {
            _appWindow.Title = "Glotto Settings";
            CenterWindow();
        }
    }

    private void CenterWindow()
    {
        if (_appWindow == null) return;

        // Increased start size: 640 x 800
        var size = new Windows.Graphics.SizeInt32(640, 800);
        _appWindow.Resize(size);

        // Get DisplayArea to center window
        var displayArea = DisplayArea.GetFromWindowId(
            _appWindow.Id, DisplayAreaFallback.Primary);
        
        if (displayArea != null)
        {
            var workArea = displayArea.WorkArea;
            var x = workArea.X + (workArea.Width - size.Width) / 2;
            var y = workArea.Y + (workArea.Height - size.Height) / 2;
            _appWindow.Move(new Windows.Graphics.PointInt32(x, y));
        }
    }

    private void RecordHotkeyButton_Click(object sender, RoutedEventArgs e)
    {
        // Phase 1 hotkey recording placeholder
        System.Diagnostics.Debug.WriteLine("[SettingsWindow] Record hotkey button clicked");
    }

    private void ProvidersListView_DragItemsCompleted(ListViewBase sender, DragItemsCompletedEventArgs args)
    {
        // When drag reordering completes, update model priorities and save order
        ViewModel.UpdatePrioritiesAndSave();
    }
}
