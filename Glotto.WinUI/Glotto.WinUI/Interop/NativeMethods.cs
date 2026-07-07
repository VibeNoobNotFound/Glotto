// NativeMethods.cs
// All Win32 P/Invoke declarations for Glotto.
// Grouped by functional area; every external symbol used in the project is declared here.

using System;
using System.Runtime.InteropServices;

namespace Glotto.WinUI.Interop;

internal static class NativeMethods
{
    // ─── Structs ─────────────────────────────────────────────────────────────

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT
    {
        public int left;
        public int top;
        public int right;
        public int bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct POINT
    {
        public int x;
        public int y;
    }

    // ─── Keyboard hook ────────────────────────────────────────────────────────

    internal const int WH_KEYBOARD_LL = 13;
    internal const int HC_ACTION = 0;

    internal const int WM_KEYDOWN  = 0x0100;
    internal const int WM_KEYUP    = 0x0101;
    internal const int WM_SYSKEYDOWN = 0x0104;
    internal const int WM_SYSKEYUP   = 0x0105;

    internal delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern IntPtr SetWindowsHookExW(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    internal static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", EntryPoint = "GetModuleHandleW", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern IntPtr GetModuleHandle(string? lpModuleName);

    [StructLayout(LayoutKind.Sequential)]
    internal struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    // Virtual key codes used by the hook
    internal const uint VK_BACK    = 0x08;
    internal const uint VK_TAB     = 0x09;
    internal const uint VK_RETURN  = 0x0D;
    internal const uint VK_SHIFT   = 0x10;
    internal const uint VK_CONTROL = 0x11;
    internal const uint VK_MENU    = 0x12;  // Alt
    internal const uint VK_ESCAPE  = 0x1B;
    internal const uint VK_SPACE   = 0x20;
    internal const uint VK_LEFT    = 0x25;
    internal const uint VK_UP      = 0x26;
    internal const uint VK_RIGHT   = 0x27;
    internal const uint VK_DOWN    = 0x28;
    internal const uint VK_1       = 0x31;
    internal const uint VK_2       = 0x32;
    internal const uint VK_3       = 0x33;
    internal const uint VK_4       = 0x34;
    internal const uint VK_5       = 0x35;
    internal const uint VK_LWIN    = 0x5B;
    internal const uint VK_RWIN    = 0x5C;

    // Hook flags
    internal const uint LLKHF_EXTENDED    = 0x01;
    internal const uint LLKHF_INJECTED    = 0x10;
    internal const uint LLKHF_ALTDOWN     = 0x20;
    internal const uint LLKHF_UP          = 0x80;

    [DllImport("user32.dll")]
    internal static extern short GetAsyncKeyState(uint vKey);

    [DllImport("user32.dll")]
    internal static extern short GetKeyState(int nVirtKey);

    [DllImport("user32.dll", EntryPoint = "MapVirtualKeyW", CharSet = CharSet.Unicode)]
    internal static extern uint MapVirtualKeyW(uint uCode, uint uMapType);

    // ─── Hotkey registration ──────────────────────────────────────────────────

    internal const int WM_HOTKEY = 0x0312;

    internal const uint MOD_ALT     = 0x0001;
    internal const uint MOD_CONTROL = 0x0002;
    internal const uint MOD_SHIFT   = 0x0004;
    internal const uint MOD_WIN     = 0x0008;
    internal const uint MOD_NOREPEAT = 0x4000;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    // ─── Message-only window for hotkey ──────────────────────────────────────

    internal static readonly IntPtr HWND_MESSAGE = new(-3);

    internal delegate IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct WNDCLASSEX
    {
        public uint cbSize;
        public uint style;
        public WndProc lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public IntPtr hInstance;
        public IntPtr hIcon;
        public IntPtr hCursor;
        public IntPtr hbrBackground;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpszMenuName;
        [MarshalAs(UnmanagedType.LPWStr)] public string? lpszClassName;
        public IntPtr hIconSm;
    }

    [DllImport("user32.dll", EntryPoint = "RegisterClassExW", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern ushort RegisterClassEx(ref WNDCLASSEX lpwcx);

    [DllImport("user32.dll", EntryPoint = "CreateWindowExW", SetLastError = true, CharSet = CharSet.Unicode)]
    internal static extern IntPtr CreateWindowEx(
        uint dwExStyle,
        string lpClassName,
        string? lpWindowName,
        uint dwStyle,
        int x, int y, int nWidth, int nHeight,
        IntPtr hWndParent,
        IntPtr hMenu,
        IntPtr hInstance,
        IntPtr lpParam);

    [DllImport("user32.dll", EntryPoint = "DefWindowProcW", CharSet = CharSet.Unicode)]
    internal static extern IntPtr DefWindowProcW(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    internal struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int ptX;
        public int ptY;
    }

    [DllImport("user32.dll", EntryPoint = "PeekMessageW", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PeekMessageW(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax, uint wRemoveMsg);

    internal const uint PM_REMOVE = 0x0001;

    [DllImport("user32.dll", EntryPoint = "TranslateMessage")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll", EntryPoint = "DispatchMessageW", CharSet = CharSet.Unicode)]
    internal static extern IntPtr DispatchMessageW(ref MSG lpmsg);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyWindow(IntPtr hWnd);

    // ─── SendInput ────────────────────────────────────────────────────────────

    internal const int INPUT_KEYBOARD = 1;
    internal const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    internal const uint KEYEVENTF_KEYUP       = 0x0002;
    internal const uint KEYEVENTF_UNICODE     = 0x0004;

    [StructLayout(LayoutKind.Sequential)]
    internal struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct INPUT
    {
        [FieldOffset(0)] public int type;
        [FieldOffset(8)] public KEYBDINPUT ki;
        [FieldOffset(8)] public MOUSEINPUT mi;
        [FieldOffset(8)] public HARDWAREINPUT hi;
    }

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    // ─── Window style manipulation (for non-activating overlay) ─────────────

    internal const int GWL_EXSTYLE = -20;
    internal const uint WS_EX_NOACTIVATE  = 0x08000000;
    internal const uint WS_EX_TOOLWINDOW  = 0x00000080;
    internal const uint WS_EX_APPWINDOW   = 0x00040000;
    internal const uint WS_EX_TOPMOST     = 0x00000008;

    internal static readonly IntPtr HWND_TOPMOST   = new(-1);
    internal static readonly IntPtr HWND_NOTOPMOST = new(-2);

    internal const uint SWP_NOACTIVATE = 0x0010;
    internal const uint SWP_SHOWWINDOW = 0x0040;
    internal const uint SWP_NOMOVE     = 0x0002;
    internal const uint SWP_NOSIZE     = 0x0001;

    [DllImport("user32.dll", SetLastError = true, EntryPoint = "GetWindowLongPtrW", CharSet = CharSet.Unicode)]
    internal static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SetWindowLongPtrW", CharSet = CharSet.Unicode)]
    internal static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int x, int y, int cx, int cy, uint uFlags);

    // ─── DPI ─────────────────────────────────────────────────────────────────

    [DllImport("user32.dll")]
    internal static extern uint GetDpiForWindow(IntPtr hWnd);

    // ─── WinEvent hook (foreground window change) ─────────────────────────────

    internal const uint EVENT_SYSTEM_FOREGROUND = 0x0003;
    internal const uint WINEVENT_OUTOFCONTEXT   = 0x0000;

    internal delegate void WinEventProc(
        IntPtr hWinEventHook,
        uint @event,
        IntPtr hwnd,
        int idObject,
        int idChild,
        uint idEventThread,
        uint dwmsEventTime);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern IntPtr SetWinEventHook(
        uint eventMin,
        uint eventMax,
        IntPtr hmodWinEventProc,
        WinEventProc lpfnWinEventProc,
        uint idProcess,
        uint idThread,
        uint dwFlags);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    // ─── System Parameters & Mouse position ───────────────────────────────────

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SystemParametersInfoW(uint uiAction, uint uiParam, out RECT pvParam, uint fWinIni);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetCursorPos(out POINT lpPoint);
}
