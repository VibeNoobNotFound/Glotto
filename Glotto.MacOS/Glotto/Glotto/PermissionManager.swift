import AppKit
import ApplicationServices
import IOKit.hid

/// Checks and requests the macOS privacy permissions Glotto depends on.
///
/// - Accessibility is **required**: gates AX-based caret/text-field capture and
///   synthetic keystroke injection.
/// - Input Monitoring is **required**: the global session-level CGEventTap that
///   intercepts key-downs is gated by Input Monitoring (kIOHIDRequestTypeListenEvent)
///   separately from Accessibility on modern macOS.
@MainActor
final class PermissionManager: ObservableObject {

    @Published private(set) var hasAccessibility: Bool = false
    @Published private(set) var hasInputMonitoring: Bool = false

    private var pollTimer: Timer?

    // MARK: - Status checks

    /// Synchronously refresh both permission states.
    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
        hasInputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// True when every permission Glotto requires to function is granted.
    var allGranted: Bool { hasAccessibility && hasInputMonitoring }

    // MARK: - Polling

    /// Polls every `interval` seconds. Calls `onGranted` once both permissions are satisfied.
    func startPolling(interval: TimeInterval = 1.0, onGranted: @escaping () -> Void) {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.refresh()
                if self.allGranted {
                    self.stopPolling()
                    onGranted()
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Request helpers

    /// Triggers the system Accessibility prompt (deep-links to System Settings).
    func requestAccessibilityIfNeeded() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Triggers the system Input Monitoring consent prompt.
    func requestInputMonitoringIfNeeded() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refresh()
    }

    // MARK: - Deep links

    /// Open Accessibility in Privacy & Security.
    func openAccessibilitySettings() {
        open(pane: "Privacy_Accessibility")
    }

    /// Open Input Monitoring in Privacy & Security.
    func openInputMonitoringSettings() {
        open(pane: "Privacy_ListenEvent")
    }

    // MARK: - Private

    private func open(pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
}
