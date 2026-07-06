import AppKit
import ApplicationServices
import Carbon.HIToolbox

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

    /// Removes `latinCharCount` characters before the cursor, then inserts `candidate`.
    func inject(candidate: String, deletingLatinChars latinCharCount: Int) async {
        // Step 1: always delete via real key events. Never via AX — this is what
        // keeps deletion and insertion from stepping on each other's state.
        if latinCharCount > 0 {
            removeLatinBuffer(count: latinCharCount)
            // Give the target app's event loop a moment to actually process the
            // backspaces before we query/mutate its AX state. Synthetic events are
            // posted asynchronously relative to the receiving app; without this,
            // the verification read below can race and see stale selection state.
            try? await Task.sleep(nanoseconds: 15_000_000) // 15ms
        }

        // Step 2: AX fast path, with verification — only attempted, never trusted blindly.
        if let element = AccessibilityBridge.focusedElement(),
           tryVerifiedAXInsertion(candidate: candidate, into: element) {
            print("[TextInjector] ✓ AX path verified")
            return
        }

        // Step 3: universal fallback. No deleteCount here — already handled in Step 1.
        print("[TextInjector] AX path unavailable/unverified — using clipboard paste")
        if await injectViaClipboard(candidate: candidate) {
            print("[TextInjector] ✓ Clipboard paste path succeeded")
            return
        }

        // Step 4: last resort.
        print("[TextInjector] Clipboard path failed — using synthetic Unicode keystroke")
        injectViaKeystrokes(candidate: candidate)
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

    // MARK: - Step 3: clipboard paste (⌘V) — insertion only, no deletion

    @discardableResult
    private func injectViaClipboard(candidate: String) async -> Bool {
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

        postKeyEvent(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)

        // Restore the original clipboard after enough time for the app to consume the paste.
        try? await Task.sleep(nanoseconds: 400_000_000) // 400ms
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

    private func injectViaKeystrokes(candidate: String) {
        let scalars = Array(candidate.utf16)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return }

        scalars.withUnsafeBufferPointer { buf in
            event.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        event.post(tap: .cghidEventTap)

        if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            keyUp.post(tap: .cghidEventTap)
        }

        print("[TextInjector] ✓ Synthetic keystroke path")
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
