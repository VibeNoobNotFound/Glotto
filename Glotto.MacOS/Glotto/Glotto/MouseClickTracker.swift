import AppKit

/// Tracks the location and target app of the user's most recent mouse click,
/// system-wide. This is a deliberately dumb, AX-independent anchor: an
/// `NSEvent`'s `mouseLocation` is always correct AppKit screen-space
/// (bottom-left origin), no matter what quirks the frontmost app has in its
/// own accessibility reporting. When accessibility-based caret resolution
/// fails or produces something implausible (custom-drawn text engines like
/// Pages' canvas-based text view, apps with incomplete AX support), "roughly
/// where the user last clicked in this app" is a far better guess than the
/// bottom or top-left corner of the entire focused element.
///
/// Does not require Accessibility or Input Monitoring permission — global
/// mouse-click monitoring via `NSEvent` is unrestricted; only keyboard
/// monitoring needs those. Safe to run for the app's entire lifetime.
@MainActor
final class MouseClickTracker {

    static let shared = MouseClickTracker()

    private(set) var lastClickLocation: NSPoint?
    private(set) var lastClickPID: pid_t?
    private var lastClickTime: Date?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    func start() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor in self?.record(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.record(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func record(_ event: NSEvent) {
        lastClickLocation = NSEvent.mouseLocation
        lastClickPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        lastClickTime = Date()
    }

    /// Returns the last click location only if it happened recently and in
    /// the currently-frontmost app — a click from 10 minutes ago, or in an
    /// app the user has since switched away from, isn't a useful anchor.
    func recentClickLocation(maxAge: TimeInterval = 30, forPID pid: pid_t?) -> NSPoint? {
        guard let lastClickLocation, let lastClickTime, let pid,
              lastClickPID == pid,
              Date().timeIntervalSince(lastClickTime) <= maxAge
        else { return nil }
        return lastClickLocation
    }
}
