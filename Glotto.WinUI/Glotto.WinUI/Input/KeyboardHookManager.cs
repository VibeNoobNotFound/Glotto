// KeyboardHookManager.cs
// Port of EventTapManager.swift.
//
// Owns the WH_KEYBOARD_LL hook that intercepts keystrokes system-wide while composition mode is armed.
//
// CRITICAL GOTCHA (§6.1 of the Windows implementation plan):
//   The LowLevelKeyboardProc delegate MUST be stored as a field on the instance.
//   If it becomes a local variable or inline lambda, the GC can collect it and crash the
//   process on the next keystroke. The delegate is pinned to the instance lifetime.
//
// CRITICAL: The hook callback must return fast (WH_KEYBOARD_LL timeout ~300ms).
//   Never do network calls or UI Automation inside the callback.
//   All real work is dispatched to the UI thread via DispatcherQueue.TryEnqueue.

using System;
using System.Runtime.InteropServices;
using Glotto.WinUI.Composition;
using Glotto.WinUI.Interop;
using Microsoft.UI.Dispatching;
using static Glotto.WinUI.Interop.NativeMethods;

namespace Glotto.WinUI.Input;

public sealed class KeyboardHookManager : IDisposable
{
    // ── IMPORTANT: these fields MUST be instance fields, never locals ────────
    private LowLevelKeyboardProc? _proc;  // strong reference — GC must not collect this
    private IntPtr _hookHandle = IntPtr.Zero;
    // ─────────────────────────────────────────────────────────────────────────

    private readonly DispatcherQueue _dispatcherQueue;
    private CompositionController? _compositionController;

    public bool IsArmed { get; private set; }

    public KeyboardHookManager(DispatcherQueue dispatcherQueue)
    {
        _dispatcherQueue = dispatcherQueue;
    }

    public void SetCompositionController(CompositionController controller)
        => _compositionController = controller;

    // MARK: - Arm / disarm

    public void Arm()
    {
        if (IsArmed) return;
        if (!InstallHook())
        {
            System.Diagnostics.Debug.WriteLine("[KeyboardHookManager] Failed to install WH_KEYBOARD_LL hook");
            return;
        }
        IsArmed = true;
        System.Diagnostics.Debug.WriteLine("[KeyboardHookManager] Armed ✓");
    }

    public void Disarm()
    {
        if (!IsArmed) return;
        RemoveHook();
        // Cancel any in-progress composition
        _dispatcherQueue.TryEnqueue(() => _compositionController?.CancelComposition());
        IsArmed = false;
        System.Diagnostics.Debug.WriteLine("[KeyboardHookManager] Disarmed");
    }

    public void Toggle()
    {
        if (IsArmed) Disarm(); else Arm();
    }

    // MARK: - Hook installation

    private bool InstallHook()
    {
        _proc = HookCallback;   // assign to the FIELD — this is the delegate lifetime pin
        _hookHandle = SetWindowsHookExW(
            WH_KEYBOARD_LL,
            _proc,
            GetModuleHandle(null),
            0   // dwThreadId = 0 → global hook
        );
        if (_hookHandle == IntPtr.Zero)
        {
            System.Diagnostics.Debug.WriteLine(
                $"[KeyboardHookManager] SetWindowsHookEx failed: {Marshal.GetLastWin32Error()}");
            return false;
        }
        return true;
    }

    private void RemoveHook()
    {
        if (_hookHandle != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hookHandle);
            _hookHandle = IntPtr.Zero;
        }
        _proc = null;  // release delegate after hook is uninstalled
    }

    // MARK: - Hook callback (called by the OS on every system-wide keystroke)
    //
    // Rules:
    //   - Return IntPtr.Zero to PASS the event through (CallNextHookEx result).
    //   - Return (IntPtr)1 (non-zero, do NOT call CallNextHookEx) to SWALLOW the event.
    //   - NEVER do slow work here — dispatch everything to the UI thread.

    private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < HC_ACTION)
            return CallNextHookEx(_hookHandle, nCode, wParam, lParam);

        var isKeyDown = wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN;
        if (!isKeyDown)
            return CallNextHookEx(_hookHandle, nCode, wParam, lParam);

        var kbStruct = Marshal.PtrToStructure<KBDLLHOOKSTRUCT>(lParam);
        var vk = kbStruct.vkCode;
        var flags = kbStruct.flags;

        var controller = _compositionController;
        var isComposing = controller?.IsComposing ?? false;

        // Detect modifier-key combinations (Ctrl, Alt, Win) — these are shortcuts, not typing
        var isCtrl    = (NativeMethods.GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
        var isAlt     = (NativeMethods.GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
        var isWin     = (NativeMethods.GetAsyncKeyState(VK_LWIN) & 0x8000) != 0 ||
                        (NativeMethods.GetAsyncKeyState(VK_RWIN) & 0x8000) != 0;
        var isModified = isCtrl || isAlt || isWin;

        // ── While composing: intercept navigation / commit / cancel ──────────
        if (isComposing && controller != null)
        {
            switch (vk)
            {
                case VK_UP:
                    Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.ArrowUp()));
                    return (IntPtr)1;  // swallow

                case VK_DOWN:
                    Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.ArrowDown()));
                    return (IntPtr)1;

                case VK_LEFT:
                case VK_RIGHT:
                    // Navigation away: cancel composition but let the arrow key through
                    Dispatch(() => controller.CancelComposition());
                    return CallNextHookEx(_hookHandle, nCode, wParam, lParam);

                case VK_RETURN:
                    Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.Commit()));
                    return (IntPtr)1;

                case VK_SPACE:
                    Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.Space()));
                    return (IntPtr)1;

                case VK_ESCAPE:
                    Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.Escape()));
                    return (IntPtr)1;

                case VK_BACK:
                    Dispatch(() => controller.HandleBackspace());
                    return (IntPtr)1;

                case VK_1: Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.NumberSelect(1))); return (IntPtr)1;
                case VK_2: Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.NumberSelect(2))); return (IntPtr)1;
                case VK_3: Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.NumberSelect(3))); return (IntPtr)1;
                case VK_4: Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.NumberSelect(4))); return (IntPtr)1;
                case VK_5: Dispatch(() => controller.HandleSpecialKey(new Core.CompositionKey.NumberSelect(5))); return (IntPtr)1;
            }
        }

        // ── Modifier combos: cancel composition, pass through ────────────────
        if (isModified)
        {
            if (isComposing && controller != null)
                Dispatch(() => controller.CancelComposition());
            return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
        }

        // ── Standard Latin character ──────────────────────────────────────────
        var ch = VkToChar(vk, flags);
        if (ch != '\0' && char.IsAsciiLetter(ch))
        {
            Dispatch(() => _compositionController?.Receive(ch));
            return (IntPtr)1;  // swallow — Latin chars never appear in the target field
        }

        // ── Non-letter printable while composing: commit then let through ─────
        // (e.g. user typed '.' or ',' mid-composition)
        if (isComposing && controller != null && ch != '\0' && !char.IsControl(ch))
        {
            var suffix = ch.ToString();
            Dispatch(() => controller.CommitSelected(suffix));
            return (IntPtr)1;  // swallow — the suffix is injected by CommitSelected
        }

        return CallNextHookEx(_hookHandle, nCode, wParam, lParam);
    }

    // MARK: - Helpers

    /// <summary>Dispatch work to the WinUI main thread asynchronously (never blocks the hook callback).</summary>
    private void Dispatch(Action action) => _dispatcherQueue.TryEnqueue(action.Invoke);

    /// <summary>Convert a virtual key code to its character, accounting for shift state.</summary>
    private static char VkToChar(uint vk, uint flags)
    {
        // For standard ASCII letters: vk for A-Z maps to 0x41-0x5A (always uppercase).
        // Check Shift state to determine case.
        if (vk >= 0x41 && vk <= 0x5A)
        {
            var shifted = (NativeMethods.GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
            var capsLock = (NativeMethods.GetKeyState(0x14) & 0x0001) != 0;  // VK_CAPITAL
            var upper = shifted ^ capsLock;
            return (char)(upper ? vk : vk + 32);
        }

        // For other printable characters: use MapVirtualKey to get the OEM char.
        var scanCode = NativeMethods.MapVirtualKeyW(vk, 0);  // MAPVK_VK_TO_VSC
        var ch = (char)NativeMethods.MapVirtualKeyW(vk, 2);  // MAPVK_VK_TO_CHAR
        return ch;
    }

    public void Dispose() => RemoveHook();
}

// Forward declaration to avoid circular dependency at file level
// CompositionController.IsComposing and the methods it calls are declared in Composition/CompositionController.cs
