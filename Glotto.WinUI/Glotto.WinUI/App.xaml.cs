using System;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Glotto.WinUI.Tray;
using Glotto.WinUI.Composition;
using Glotto.WinUI.Core;
using Glotto.WinUI.Input;
using Glotto.WinUI.Interop;
using Glotto.WinUI.Services;
using Glotto.WinUI.UI;
using static Glotto.WinUI.Interop.NativeMethods;

namespace Glotto.WinUI
{
    /// <summary>
    /// Provides application-specific behavior to supplement the default Application class.
    /// </summary>
    public partial class App : Application
    {
        private TrayIconManager? _trayIconManager;
        private SettingsWindow? _settingsWindow;
        
        // Infrastructure / controller graph
        private UiAutomationBridge? _uiaBridge;
        private TextInjector? _textInjector;
        private TransliterationService? _transliterationService;
        private CandidateOverlayController? _overlayController;
        private CompositionController? _compositionController;
        private KeyboardHookManager? _keyboardHookManager;
        private HotkeyManager? _hotkeyManager;

        // Foreground window event hook handle
        private IntPtr _winEventHook = IntPtr.Zero;
        private WinEventProc? _winEventProc;

        /// <summary>
        /// Initializes the singleton application object.  This is the first line of authored code
        /// executed, and as such is the logical equivalent of main() or WinMain().
        /// </summary>
        public App()
        {
            InitializeComponent();
        }

        /// <summary>
        /// Invoked when the application is launched.
        /// </summary>
        protected override void OnLaunched(Microsoft.UI.Xaml.LaunchActivatedEventArgs args)
        {
            var dispatcherQueue = DispatcherQueue.GetForCurrentThread();

            // 1. Build the controller graph
            _uiaBridge = new UiAutomationBridge();
            _textInjector = new TextInjector(_uiaBridge);
            _transliterationService = new TransliterationService();
            _overlayController = new CandidateOverlayController(_uiaBridge, dispatcherQueue);
            
            _compositionController = new CompositionController(
                LanguageProfile.Sinhala, 
                _transliterationService, 
                _textInjector, 
                _overlayController,
                dispatcherQueue
            );

            _keyboardHookManager = new KeyboardHookManager(dispatcherQueue);
            _keyboardHookManager.SetCompositionController(_compositionController);

            _hotkeyManager = new HotkeyManager(dispatcherQueue);
            _hotkeyManager.HotkeyTriggered += OnHotkeyTriggered;
            _hotkeyManager.Start();

            // 2. Initialize Tray Icon
            _trayIconManager = new TrayIconManager(
                onToggle: ToggleComposition,
                onOpenSettings: OpenSettings,
                onQuit: QuitApp
            );

            // 3. Register Foreground App Change WinEventHook
            // When user switches apps, cancel current composition cleanly (same as macOS counterpart)
            _winEventProc = OnForegroundWindowChanged;
            _winEventHook = SetWinEventHook(
                EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
                IntPtr.Zero, _winEventProc, 0, 0, WINEVENT_OUTOFCONTEXT
            );

            System.Diagnostics.Debug.WriteLine("[App] Glotto Windows Backend Started ✓");
        }

        private void OnHotkeyTriggered(object? sender, EventArgs e)
        {
            ToggleComposition();
        }

        private void ToggleComposition()
        {
            if (_keyboardHookManager is null) return;

            _keyboardHookManager.Toggle();
            var armed = _keyboardHookManager.IsArmed;

            _trayIconManager?.UpdateIconState(armed);
        }

        private void OpenSettings()
        {
            if (_settingsWindow is not null)
            {
                _settingsWindow.Activate();
                return;
            }

            _settingsWindow = new SettingsWindow();
            _settingsWindow.Closed += (s, e) => _settingsWindow = null;
            _settingsWindow.Activate();
        }

        private void OnForegroundWindowChanged(
            IntPtr hWinEventHook, uint @event, IntPtr hwnd, int idObject, int idChild, uint idEventThread, uint dwmsEventTime)
        {
            // Hop to dispatcher to ensure thread safety
            _compositionController?.CancelComposition();
        }

        private void QuitApp()
        {
            // Clean up hooks and resources
            if (_winEventHook != IntPtr.Zero)
            {
                UnhookWinEvent(_winEventHook);
            }
            
            _keyboardHookManager?.Dispose();
            _hotkeyManager?.Dispose();
            _trayIconManager?.Dispose();
            _uiaBridge?.Dispose();

            Exit();
        }
    }
}
