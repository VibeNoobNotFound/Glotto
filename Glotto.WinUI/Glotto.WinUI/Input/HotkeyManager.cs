// HotkeyManager.cs
// Port of the registerHotkey() call in GlottoApp.swift (using the KeyboardShortcuts package).
//
// Registers a global hotkey via RegisterHotKey on a dedicated message-only window.
// The message-only window approach is cleaner than routing WM_HOTKEY through the WinUI main window
// (avoids XAML message routing indirection we don't need).
//
// Phase 1 default: Ctrl+Shift+Space.
// Settings UI calls Update() to change it without restarting.

using System;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.UI.Dispatching;
using static Glotto.WinUI.Interop.NativeMethods;

namespace Glotto.WinUI.Input;

public sealed class HotkeyManager : IDisposable
{
    private const int HotkeyId = 1;

    // Default hotkey: Ctrl+Shift+Space
    private uint _modifiers = MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT;
    private uint _vk        = VK_SPACE;

    private IntPtr _hwnd    = IntPtr.Zero;
    private Thread? _thread;
    private volatile bool _running;

    // Strong reference to the WndProc delegate — MUST NOT be a local variable.
    // If the GC collects it, any WM_HOTKEY message will cause a crash.
    private readonly WndProc _wndProc;

    private readonly DispatcherQueue _dispatcherQueue;

    /// <summary>Raised on the UI thread when the hotkey is pressed.</summary>
    public event EventHandler? HotkeyTriggered;

    public HotkeyManager(DispatcherQueue dispatcherQueue)
    {
        _dispatcherQueue = dispatcherQueue;
        _wndProc = MessageWindowProc;  // store strong reference on the instance
    }

    public void Start()
    {
        _running = true;
        _thread = new Thread(MessageLoop)
        {
            IsBackground = true,
            Name = "GlottoHotkeyThread"
        };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
    }

    /// <summary>Change the registered hotkey (e.g. from Settings). Safe to call at any time.</summary>
    public void Update(uint newModifiers, uint newVk)
    {
        if (_hwnd == IntPtr.Zero) return;

        UnregisterHotKey(_hwnd, HotkeyId);
        _modifiers = newModifiers | MOD_NOREPEAT;
        _vk = newVk;
        var ok = RegisterHotKey(_hwnd, HotkeyId, _modifiers, _vk);
        if (!ok)
            System.Diagnostics.Debug.WriteLine($"[HotkeyManager] RegisterHotKey failed: {Marshal.GetLastWin32Error()}");
    }

    public void Dispose()
    {
        _running = false;
        if (_hwnd != IntPtr.Zero)
        {
            UnregisterHotKey(_hwnd, HotkeyId);
            DestroyWindow(_hwnd);
            _hwnd = IntPtr.Zero;
        }
    }

    // MARK: - Message loop (runs on dedicated STA thread)

    private void MessageLoop()
    {
        // Register a window class for our message-only window
        var className = $"GlottoHotkeyWindow_{Environment.ProcessId}";
        var wc = new WNDCLASSEX
        {
            cbSize      = (uint)Marshal.SizeOf<WNDCLASSEX>(),
            lpfnWndProc = _wndProc,
            lpszClassName = className,
            hInstance   = GetModuleHandle(null)
        };
        RegisterClassEx(ref wc);

        // Create a message-only window (HWND_MESSAGE as parent — receives messages but is invisible)
        _hwnd = CreateWindowEx(
            dwExStyle: 0,
            lpClassName: className,
            lpWindowName: null,
            dwStyle: 0,
            x: 0, y: 0, nWidth: 0, nHeight: 0,
            hWndParent: HWND_MESSAGE,
            hMenu: IntPtr.Zero,
            hInstance: GetModuleHandle(null),
            lpParam: IntPtr.Zero
        );

        if (_hwnd == IntPtr.Zero)
        {
            System.Diagnostics.Debug.WriteLine($"[HotkeyManager] CreateWindowEx failed: {Marshal.GetLastWin32Error()}");
            return;
        }

        var ok = RegisterHotKey(_hwnd, HotkeyId, _modifiers, _vk);
        if (!ok)
            System.Diagnostics.Debug.WriteLine($"[HotkeyManager] RegisterHotKey failed: {Marshal.GetLastWin32Error()}");

        // Pump messages until Dispose() sets _running = false
        while (_running)
        {
            if (PeekMessageW(out var msg, _hwnd, 0, 0, PM_REMOVE))
            {
                TranslateMessage(ref msg);
                DispatchMessageW(ref msg);
            }
            else
            {
                Thread.Sleep(10);
            }
        }
    }

    // MARK: - WndProc

    private IntPtr MessageWindowProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HotkeyId)
        {
            // Marshal to the WinUI dispatcher thread (same as @MainActor in Swift)
            _dispatcherQueue.TryEnqueue(() => HotkeyTriggered?.Invoke(this, EventArgs.Empty));
            return IntPtr.Zero;
        }
        return DefWindowProcW(hWnd, msg, wParam, lParam);
    }
}
