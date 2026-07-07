// TextInjector.cs
// Port of TextInjector.swift — but priority order is REVERSED from macOS (see §9 of the impl plan).
//
// macOS order: AX → clipboard → synthetic keystroke
// Windows order: SendInput Unicode → clipboard → verified ValuePattern
//
// Rationale: Windows has no UIA equivalent of kAXSelectedTextAttribute for rich text.
// Microsoft's own docs cite handwriting/voice recognition as the intended use case for
// KEYEVENTF_UNICODE — it's the correct primary mechanism, not a last resort.
//
// UIPI caveat: SendInput silently fails for elevated target apps. GetLastError() is unreliable
// for detecting this. Accepted limitation — do not retry.

using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using Windows.ApplicationModel.DataTransfer;
using static Glotto.WinUI.Interop.NativeMethods;

namespace Glotto.WinUI.Interop;

public sealed class TextInjector
{
    private readonly UiAutomationBridge _uia;

    public TextInjector(UiAutomationBridge uia)
    {
        _uia = uia;
    }

    // MARK: - Main entry point

    /// <summary>
    /// Removes <paramref name="latinCharCount"/> characters before the cursor via backspace key events,
    /// then injects <paramref name="candidate"/> using the best available method.
    /// </summary>
    public async Task InjectAsync(string candidate, int latinCharCount)
    {
        // Step 1: always delete via real VK_BACK key events.
        // Never via UIA — this prevents double-mutation races (same lesson as the macOS fix).
        if (latinCharCount > 0)
        {
            DeleteLatinBuffer(latinCharCount);
            // Give the target app's event loop a moment to process the backspaces.
            // Synthetic events are posted asynchronously relative to the receiving app.
            await Task.Delay(15);
        }

        // Step 2: SendInput Unicode (primary path — not last resort on Windows)
        if (InjectViaSendInput(candidate))
        {
            System.Diagnostics.Debug.WriteLine("[TextInjector] ✓ SendInput path");
            return;
        }

        // Step 3: Clipboard paste (fallback for apps that filter KEYEVENTF_UNICODE)
        System.Diagnostics.Debug.WriteLine("[TextInjector] SendInput path failed — trying clipboard paste");
        if (await InjectViaClipboardAsync(candidate))
        {
            System.Diagnostics.Debug.WriteLine("[TextInjector] ✓ Clipboard path");
            return;
        }

        // Step 4: Verified ValuePattern.SetValue (opportunistic, narrow scope)
        System.Diagnostics.Debug.WriteLine("[TextInjector] Clipboard path failed — trying ValuePattern");
        var focusedElement = _uia.GetFocusedElement();
        if (focusedElement is not null && _uia.TrySetValue(focusedElement, candidate))
        {
            System.Diagnostics.Debug.WriteLine("[TextInjector] ✓ ValuePattern path");
        }
        else
        {
            System.Diagnostics.Debug.WriteLine("[TextInjector] All injection paths exhausted");
        }
    }

    // MARK: - Step 1: Real VK_BACK key events

    private static void DeleteLatinBuffer(int count)
    {
        var inputs = new INPUT[count * 2];
        for (var i = 0; i < count; i++)
        {
            inputs[i * 2] = new INPUT
            {
                type = INPUT_KEYBOARD,
                ki = new KEYBDINPUT { wVk = (ushort)VK_BACK, dwFlags = 0 }
            };
            inputs[i * 2 + 1] = new INPUT
            {
                type = INPUT_KEYBOARD,
                ki = new KEYBDINPUT { wVk = (ushort)VK_BACK, dwFlags = KEYEVENTF_KEYUP }
            };
        }
        SendInput((uint)(count * 2), inputs, Marshal.SizeOf<INPUT>());
    }

    // MARK: - Step 2: SendInput KEYEVENTF_UNICODE

    private static bool InjectViaSendInput(string candidate)
    {
        if (string.IsNullOrEmpty(candidate)) return true;

        try
        {
            // Each UTF-16 code unit needs a key-down + key-up pair.
            // Surrogate pairs are two code units → two pairs each.
            var utf16 = candidate.ToCharArray();
            var inputs = new INPUT[utf16.Length * 2];

            for (var i = 0; i < utf16.Length; i++)
            {
                var scan = (ushort)utf16[i];
                inputs[i * 2] = new INPUT
                {
                    type = INPUT_KEYBOARD,
                    ki = new KEYBDINPUT
                    {
                        wVk    = 0,
                        wScan  = scan,
                        dwFlags = KEYEVENTF_UNICODE
                    }
                };
                inputs[i * 2 + 1] = new INPUT
                {
                    type = INPUT_KEYBOARD,
                    ki = new KEYBDINPUT
                    {
                        wVk    = 0,
                        wScan  = scan,
                        dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP
                    }
                };
            }

            var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
            return sent == (uint)inputs.Length;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[TextInjector] SendInput exception: {ex.Message}");
            return false;
        }
    }

    // MARK: - Step 3: Clipboard paste (Ctrl+V)

    private static async Task<bool> InjectViaClipboardAsync(string candidate)
    {
        try
        {
            // Write our candidate to the clipboard
            var dataPackage = new DataPackage();
            dataPackage.SetText(candidate);
            Clipboard.SetContent(dataPackage);

            // Post synthetic Ctrl+V
            var ctrlDown = new INPUT
            {
                type = INPUT_KEYBOARD,
                ki = new KEYBDINPUT { wVk = (ushort)VK_CONTROL, dwFlags = 0 }
            };
            var vDown = new INPUT
            {
                type = INPUT_KEYBOARD,
                ki = new KEYBDINPUT { wVk = 0x56 /* V */, dwFlags = 0 }  // VK_V = 0x56
            };
            var vUp = new INPUT
            {
                type = INPUT_KEYBOARD,
                ki = new KEYBDINPUT { wVk = 0x56, dwFlags = KEYEVENTF_KEYUP }
            };
            var ctrlUp = new INPUT
            {
                type = INPUT_KEYBOARD,
                ki = new KEYBDINPUT { wVk = (ushort)VK_CONTROL, dwFlags = KEYEVENTF_KEYUP }
            };

            SendInput(4, [ctrlDown, vDown, vUp, ctrlUp], Marshal.SizeOf<INPUT>());

            // Restore original clipboard after enough time for the target app to consume the paste.
            // 400ms matches the macOS clipboard fallback delay.
            // Note: Clipboard.GetContent() returns DataPackageView (read-only).
            // WinUI has no API to copy DataPackageView back to a new DataPackage for all formats.
            // We intentionally leave the clipboard with the candidate text — matching typical IME behavior.
            // (Most IMEs also leave clipboard contents after paste.)
            await Task.Delay(400);

            return true;
        }
        catch (Exception ex)
        {
            System.Diagnostics.Debug.WriteLine($"[TextInjector] Clipboard paste exception: {ex.Message}");
            return false;
        }
    }
}
