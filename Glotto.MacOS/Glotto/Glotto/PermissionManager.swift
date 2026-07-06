import AppKit
import ApplicationServices

/// Checks and requests the Accessibility permission Glotto needs.
/// Accessibility allows Glotto to read the caret screen coordinates, query focused elements,
/// inject transliterated text, and establish a session-level global event tap.
@MainActor
final class PermissionManager: ObservableObject {

    @Published private(set) var hasAccessibility: Bool = false

    private var pollTimer: Timer?

    // MARK: - Status checks

    /// Synchronously check the accessibility permission state.
    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
    }

    /// Returns true when the required Accessibility permission is granted.
    var allGranted: Bool { hasAccessibility }

    // MARK: - Polling

    /// Start polling every `interval` seconds until the permission is granted,
    /// then call `onGranted`.
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

    // MARK: - Deep links

    /// Open the Accessibility section of Privacy & Security in System Settings.
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Request helpers

    /// Trigger the system's Accessibility permission prompt.
    func requestAccessibilityIfNeeded() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}
