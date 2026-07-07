import AppKit
import Carbon.HIToolbox
import os

/// Owns the CGEventTap that intercepts keystrokes system-wide while composition mode is armed.
///
/// Design constraints from §6.1 of the implementation plan:
///  - CGEventTapCallBack is a C function pointer — cannot capture Swift context.
///    We bridge via `Unmanaged<EventTapManager>` passed through the refcon parameter.
///  - The callback must return *fast*. All real work is handed off to the MainActor via Task.
///  - The tap is created on arm and destroyed on disarm, not left passively installed.
///    This is polite to the system (battery/CPU) and the right model for an opt-in utility.
@MainActor
final class EventTapManager {

    weak var compositionController: CompositionController?
    private let logger = Logger(subsystem: "dev.noobnotfound.glotto", category: "EventTap")

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isArmed: Bool = false

    // MARK: - Arm / disarm

    func arm() {
        guard !isArmed else { return }
        guard installTap() else {
            logger.error("Failed to install CGEventTap. Accessibility/Input Monitoring may be missing.")
            return
        }
        isArmed = true
        logger.info("Event tap armed.")
    }

    func disarm() {
        guard isArmed else { return }
        removeTap()
        compositionController?.cancelComposition()
        isArmed = false
        logger.info("Event tap disarmed.")
    }

    func toggle() {
        isArmed ? disarm() : arm()
    }

    // MARK: - Tap installation

    private func installTap() -> Bool {
        let eventsOfInterest = CGEventMask(1 << CGEventType.keyDown.rawValue)

        // Pass `self` via refcon — unretained because EventTapManager is long-lived
        // (owned by the app delegate) and we manually manage the tap lifetime.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        tap = newTap
        runLoopSource = source
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling (called from the C callback, on the main thread)

    /// Returns nil to swallow the event, or the original event to pass it through.
    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags   = event.flags

        // --- Special keys while composing ---
        if let controller = compositionController, !controller.session.isEmpty {
            switch Int(keyCode) {
            case kVK_UpArrow:
                dispatch { controller.handleSpecialKey(.arrowUp) }
                return nil  // swallow

            case kVK_DownArrow:
                dispatch { controller.handleSpecialKey(.arrowDown) }
                return nil

            case kVK_LeftArrow, kVK_RightArrow:
                // If they navigate away, cancel the composition but let the arrow key through
                dispatch { controller.cancelComposition() }
                return Unmanaged.passUnretained(event)

            case kVK_Return, kVK_ANSI_KeypadEnter:
                dispatch { controller.handleSpecialKey(.commit) }
                return nil

            case kVK_Space:
                // Swallow space and trigger commit. Commit will append a space itself!
                dispatch { _ = controller.handleSpecialKey(.space) }
                return nil

            case kVK_Escape:
                dispatch { controller.handleSpecialKey(.escape) }
                return nil

            case kVK_Delete:
                dispatch { controller.handleBackspace() }
                // Swallow: the buffer pop is all that's needed; nothing is in the text field.
                return nil

            // Number keys 1–5 for direct candidate selection (only when Shift is not pressed)
            case kVK_ANSI_1 where !flags.contains(.maskShift): dispatch { controller.handleSpecialKey(.numberSelect(1)) }; return nil
            case kVK_ANSI_2 where !flags.contains(.maskShift): dispatch { controller.handleSpecialKey(.numberSelect(2)) }; return nil
            case kVK_ANSI_3 where !flags.contains(.maskShift): dispatch { controller.handleSpecialKey(.numberSelect(3)) }; return nil
            case kVK_ANSI_4 where !flags.contains(.maskShift): dispatch { controller.handleSpecialKey(.numberSelect(4)) }; return nil
            case kVK_ANSI_5 where !flags.contains(.maskShift): dispatch { controller.handleSpecialKey(.numberSelect(5)) }; return nil

            default:
                break
            }
        }

        // --- Standard Latin character ---
        // Ignore modifier-key combinations (⌘, ⌃, ⌥) — those are app shortcuts, not typing.
        let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        guard flags.intersection(modifiers).isEmpty else {
            // User pressed a shortcut — cancel composition cleanly.
            if let controller = compositionController, !controller.session.isEmpty {
                dispatch { controller.cancelComposition() }
            }
            return Unmanaged.passUnretained(event)
        }

        // Extract the character from the event.
        guard let character = extractCharacter(from: event) else {
            return Unmanaged.passUnretained(event)
        }

        if character.isASCII && character.isLetter {
            dispatch { self.compositionController?.receive(character: character) }
            // Swallow: Latin characters never appear in the target field.
            // The overlay header shows the buffer; the app receives only the committed script text.
            return nil
        }

        // If we are currently composing and type a non-letter (punctuation, numbers, special characters),
        // we automatically commit the active composition and append this typed character.
        if let controller = compositionController, !controller.session.isEmpty {
            let suffix = String(character)
            dispatch {
                controller.commitSelected(appending: suffix)
            }
            // Swallow the event because the custom character is appended inside commitSelected() and injected.
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Helpers

    /// Hops to the MainActor to run composition logic — keeps the callback itself lightweight.
    private func dispatch(_ block: @escaping @MainActor () -> Void) {
        Task { @MainActor in block() }
    }

    private func extractCharacter(from event: CGEvent) -> Character? {
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }

        var chars = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(
            maxStringLength: length,
            actualStringLength: &length,
            unicodeString: &chars
        )
        guard let scalar = Unicode.Scalar(chars[0]) else { return nil }
        return Character(scalar)
    }
}

// MARK: - C callback (must be a free function / global closure)

/// The C-compatible callback bridged back into EventTapManager via refcon.
/// Returns nil to swallow the event or the original event pointer to pass through.
private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(proxy: proxy, type: type, event: event)
}
