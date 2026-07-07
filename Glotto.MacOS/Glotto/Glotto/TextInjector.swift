import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os.log

private let logger = Logger(subsystem: "dev.noobnotfound.glotto", category: "TextInjector")

/// Commits a transliterated candidate into the focused text field.
///
/// Design (rewritten): deletion and insertion are now fully decoupled, and AX's
/// reported success is verified rather than trusted.
///
///   Step 1 — ALWAYS remove the buffered Latin characters via real synthetic
///   backspace key events. This is indistinguishable from real typing, so it
///   works identically in every app regardless of AX support quality.
///
///   Step 2 — Insert `candidate` at the now-collapsed cursor. Try the AX fast
///   path first, but VERIFY it actually happened: Microsoft's own support docs
///   confirm AXUIElementSetAttributeValue can return `.success` on Word without
///   changing anything, and the same false-success behavior is documented for
///   several AX roles (combo boxes, some scroll areas) in Safari/Xcode/Pages too.
///   If the cursor didn't move the way a real insertion would move it, the
///   "success" is treated as a lie and we fall through.
///
///   Step 3 — Clipboard paste (⌘V). Universal fallback. No deletion needed here
///   anymore since Step 1 already handled it via real key events.
///
///   Step 4 — Synthetic Unicode keystroke. Last-resort fallback for the rare app
///   that doesn't respond to paste either.
@MainActor
final class TextInjector {

    // MARK: - Main entry point

    /// Removes `latinCharCount` characters before the cursor, inserts `candidate`,
    /// then appends `suffix`. By default `suffix` is embedded directly in the same
    /// insertion (one atomic AX-set or one ⌘V payload) — the only exception is a
    /// space suffix in an app registered with `pasteTrimsTrailingWhitespace`
    /// (Word), which needs a real, separate `kVK_Space` keystroke to survive.
    ///
    /// Embedding is the default, not the exception, because firing a *second*,
    /// independent synthetic keystroke immediately after an AX-set/paste races
    /// the target's own handling of that first mutation. This is reliably
    /// reproducible in Safari (and other React-controlled web fields): typing
    /// candidate+space in quick succession can land the follow-up Space keydown
    /// before the browser has actually committed the pasted text to the field's
    /// value, so the two edits interleave instead of applying in order and the
    /// trailing space silently disappears. Embedding sidesteps the race entirely
    /// since there's nothing left to reorder.
    func inject(candidate: String, deletingLatinChars latinCharCount: Int, suffix: String = "") async {
        // Step 1: always delete via real key events.
        if latinCharCount > 0 {
            removeLatinBuffer(count: latinCharCount)
            // Give the target app's event loop a moment to process the backspaces
            // before we query/mutate its AX state.
            try? await Task.sleep(nanoseconds: 15_000_000) // 15ms
        }

        let quirks = AppCompatibility.quirksForFrontmostApp()
        let mustSendSpaceAsKeystroke = suffix == " " && quirks.pasteTrimsTrailingWhitespace
        let textToInsert = mustSendSpaceAsKeystroke ? candidate : candidate + suffix
        let keystrokeSuffix = mustSendSpaceAsKeystroke ? suffix : ""

        // Step 2: AX fast path, with verification — only attempted, never trusted blindly.
        if let element = AccessibilityBridge.focusedElement(),
           tryVerifiedAXInsertion(candidate: textToInsert, into: element) {
            logger.debug("AX path verified")
            // Fire space immediately — no clipboard restore delay to wait for.
            if !keystrokeSuffix.isEmpty { postKeyEvent(keyCode: UInt16(kVK_Space), flags: []) }
            return
        }

        // Step 3: clipboard paste fallback.
        logger.debug("AX path unavailable/unverified — using clipboard paste")
        if await injectViaClipboard(candidate: textToInsert, suffix: keystrokeSuffix) {
            logger.debug("Clipboard paste path succeeded")
            return
        }

        // Step 4: last resort synthetic keystroke — include suffix directly in the string.
        logger.debug("Clipboard path failed — using synthetic Unicode keystroke")
        injectViaKeystrokes(textToInsert + keystrokeSuffix)
    }

    // MARK: - Step 1: real backspace key events

    private func removeLatinBuffer(count: Int) {
        for _ in 0..<count {
            postKeyEvent(keyCode: UInt16(kVK_Delete), flags: [])
        }
    }

    // MARK: - Step 2: AX insertion, verified

    private func tryVerifiedAXInsertion(candidate: String, into element: AXUIElement) -> Bool {
        // Only attempt this when we have a clean, zero-length caret. If there's an
        // active selection here, we don't have the guarantee the verification math
        // below depends on — skip straight to clipboard rather than guess.
        guard let before = AccessibilityBridge.selectedRange(in: element), before.length == 0 else {
            return false
        }

        guard AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, candidate as CFTypeRef
        ) == .success else { return false }

        // Verification: a real insertion moves the cursor forward by the inserted
        // length. If the app silently no-op'd (the documented Word/Xcode/Safari
        // behavior), the cursor won't have moved — treat that as failure.
        guard let after = AccessibilityBridge.selectedRange(in: element) else { return false }
        let expectedLocation = before.location + (candidate as NSString).length
        return after.location == expectedLocation
    }

    /// Clipboard paste (⌘V) — insertion only, no deletion.
    /// If `suffix` is a space, fires `kVK_Space` immediately after the paste keystroke
    /// (before the clipboard-restore wait) so it appears with no perceptible delay.
    /// Word silently trims trailing whitespace from ⌘V payload; a real Space keypress bypasses that.
    @discardableResult
    private func injectViaClipboard(candidate: String, suffix: String = "") async -> Bool {
        let pasteboard = NSPasteboard.general
        let savedItems: [(types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data])] =
            (pasteboard.pasteboardItems ?? []).map { item in
                let dataMap = item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { acc, ptype in
                    if let d = item.data(forType: ptype) { acc[ptype] = d }
                }
                return (types: item.types, data: dataMap)
            }

        pasteboard.clearContents()
        pasteboard.setString(candidate, forType: .string)
        // Snapshot the change count right after our own write — if it differs when
        // the restore timer fires, something else (the user copying elsewhere,
        // another app) wrote to the pasteboard in the meantime, and restoring our
        // saved snapshot would silently clobber that newer content.
        let changeCountAfterOurWrite = pasteboard.changeCount

        postKeyEvent(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)

        // Fire space immediately after ⌘V — before the clipboard-restore wait.
        // This avoids the 400ms delay that would occur if we fired it after the sleep.
        if suffix == " " {
            postKeyEvent(keyCode: UInt16(kVK_Space), flags: [])
        }

        // Restore the original clipboard after enough time for the app to consume the paste.
        try? await Task.sleep(nanoseconds: 400_000_000) // 400ms

        guard pasteboard.changeCount == changeCountAfterOurWrite else {
            logger.debug("Clipboard changed during paste window — skipping restore to avoid clobbering newer content")
            return true
        }

        pasteboard.clearContents()
        for item in savedItems {
            let newItem = NSPasteboardItem()
            for (type, data) in item.data {
                newItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([newItem])
        }

        return true // NSPasteboard/CGEvent posting doesn't give us a real success signal here;
                    // this path is treated as "best effort universal," not verified like Step 2.
    }

    // MARK: - Step 4: synthetic Unicode CGEvent (last resort)

    private func injectViaKeystrokes(_ text: String) {
        let scalars = Array(text.utf16)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return }

        scalars.withUnsafeBufferPointer { buf in
            event.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        event.post(tap: .cghidEventTap)

        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }

        logger.debug("Synthetic keystroke path")
    }

    // MARK: - Helpers

    private func postKeyEvent(keyCode: UInt16, flags: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags   = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
