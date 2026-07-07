import AppKit
import ApplicationServices

/// Watches the focused application's accessibility tree for events that should
/// trigger an overlay reposition *without* a keystroke: text selection moving
/// (e.g. the user clicks elsewhere in the same field), the focused element
/// changing, or the window being moved/resized. Previously Glotto's panel only
/// repositioned inside `CompositionController`'s keystroke handlers, so
/// scrolling, dragging the window, or the field autoresizing mid-composition
/// left the panel visibly detached from the caret until the next character.
///
/// Lifecycle: started when a composition session becomes non-empty, stopped
/// when it's cancelled/committed. Scoped to the single frontmost process for
/// the lifetime of one composition — cheap, and avoids the overhead of
/// system-wide observation when the user isn't actively composing.
@MainActor
final class CaretChangeObserver {

    /// Called on the main actor whenever a watched AX notification fires.
    /// The caller (CandidateOverlayController) should call `reposition()`.
    var onCaretMoved: (() -> Void)?

    private var axObserver: AXObserver?
    private var observedElement: AXUIElement?
    private var observedPID: pid_t?

    private static let notifications: [CFString] = [
        kAXSelectedTextChangedNotification as CFString,
        kAXFocusedUIElementChangedNotification as CFString,
        kAXMovedNotification as CFString,
        kAXResizedNotification as CFString,
    ]

    // MARK: - Start / stop

    /// Begins observing AX notifications for the process that owns `element`.
    /// Safe to call repeatedly — if we're already observing this exact element,
    /// this is a no-op rather than tearing down and rebuilding the AXObserver.
    ///
    /// This matters because `CandidateOverlayController` calls this on every
    /// `showOrUpdate`, which fires on every keystroke while composing. Without
    /// this guard, every character typed would tear down and recreate a real
    /// AXObserver — an XPC round-trip to the Accessibility server plus six
    /// `AXObserverAddNotification` calls — instead of only doing that once per
    /// composition session (or when focus genuinely moves to a new element).
    func start(observing element: AXUIElement) {
        if axObserver != nil, let observedElement, CFEqual(observedElement, element) {
            return
        }
        stop()

        guard let pid = AccessibilityBridge.pid(of: element) else { return }

        var observerRef: AXObserver?
        let createResult = AXObserverCreate(pid, axObserverCallback, &observerRef)
        guard createResult == .success, let observer = observerRef else { return }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        for notification in Self.notifications {
            // Some roles/apps don't support every notification — failures here
            // are expected and non-fatal, so we don't bail out on the first one.
            AXObserverAddNotification(observer, element, notification, refcon)
        }

        // Also observe the application element itself for window move/resize,
        // since those notifications are commonly posted on the app or window
        // element rather than the focused text field.
        let appElement = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, appElement, kAXMovedNotification as CFString, refcon)
        AXObserverAddNotification(observer, appElement, kAXResizedNotification as CFString, refcon)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        axObserver = observer
        observedElement = element
        observedPID = pid
    }

    func stop() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = nil
        observedElement = nil
        observedPID = nil
    }

    // MARK: - Callback bridge

    fileprivate func handleNotification() {
        onCaretMoved?()
    }
}

/// C-compatible AXObserver callback. Bridges back into `CaretChangeObserver`
/// via the refcon pointer, matching the same pattern EventTapManager uses for
/// its CGEventTap callback (AX/CG callbacks can't capture Swift context).
private let axObserverCallback: AXObserverCallback = { _, _, _, refcon in
    guard let refcon else { return }
    let observer = Unmanaged<CaretChangeObserver>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in
        observer.handleNotification()
    }
}
