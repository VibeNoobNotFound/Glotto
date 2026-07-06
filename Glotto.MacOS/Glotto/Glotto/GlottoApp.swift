import SwiftUI
import KeyboardShortcuts

// MARK: - App entry point

@main
struct GlottoApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window opened from the menu bar.
        Settings {
            SettingsView()
                .environmentObject(appDelegate.permissionManager)
        }
    }
}

// MARK: - App Delegate

/// Owns the top-level controller graph and the NSStatusItem.
/// We use NSApplicationDelegate because:
///  - We need `.accessory` activation policy (no Dock icon) which must be set early.
///  - We need to wire up the status item and the global hotkey before the app finishes launching.
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Controllers

    let permissionManager = PermissionManager()
    private let overlayController = CandidateOverlayController()
    private lazy var compositionController = CompositionController(
        service: TransliterationService(),
        textInjector: TextInjector(),
        overlayController: overlayController
    )
    private lazy var eventTapManager: EventTapManager = {
        let m = EventTapManager()
        m.compositionController = compositionController
        return m
    }()

    // MARK: Status item

    private var statusItem: NSStatusItem?
    private var onboardingWindow: NSWindow?
    private var settingsWindow: NSWindow?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as an accessory (menu-bar only) — no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)

        buildStatusItem()
        registerHotkey()

        // Show onboarding if either permission is missing.
        permissionManager.refresh()
        if !permissionManager.allGranted {
            showOnboarding()
        }

        // Observe focus loss — if the user Cmd-Tabs away mid-composition, cancel cleanly.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    // MARK: - Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(armed: false)

        let menu = NSMenu()
        
        let toggleItem = menu.addItem(withTitle: "Toggle Composition Mode", action: #selector(toggleComposition), keyEquivalent: "")
        toggleItem.target = self
        
        menu.addItem(.separator())
        
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        
        menu.addItem(.separator())
        
        let quitItem = menu.addItem(withTitle: "Quit Glotto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp

        statusItem?.menu = menu
    }

    private func updateStatusIcon(armed: Bool) {
        let symbolName = armed ? "character.cursor.ibeam" : "character.bubble"
        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: armed ? "Glotto: Armed" : "Glotto: Idle"
        )
        image?.isTemplate = true
        statusItem?.button?.image = image
        statusItem?.button?.toolTip = armed
            ? "Glotto is armed — type phonetically"
            : "Glotto is idle — click to arm"
    }

    // MARK: - Hotkey

    private func registerHotkey() {
        KeyboardShortcuts.onKeyUp(for: .toggleCompositionMode) { [weak self] in
            self?.toggleComposition()
        }
    }

    @objc private func toggleComposition() {
        guard permissionManager.allGranted else {
            showOnboarding()
            return
        }
        eventTapManager.toggle()
        let armed = eventTapManager.isArmed
        updateStatusIcon(armed: armed)
        
        // Retrieve and play selected sound
        let soundKey = armed ? "enableSound" : "disableSound"
        let defaultSound = armed ? "Tink" : "Blow"
        let soundName = UserDefaults.standard.string(forKey: soundKey) ?? defaultSound
        if soundName != "None" {
            NSSound(named: NSSound.Name(soundName))?.play()
        }
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SettingsView()
            .environmentObject(permissionManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 440, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Glotto Settings"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    // MARK: - Onboarding

    private func showOnboarding() {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = PermissionOnboardingView(onAllGranted: { [weak self] in
            self?.onboardingWindow?.close()
        })
        .environmentObject(permissionManager)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 480, height: 350)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Glotto — Setup"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    // MARK: - Focus change

    @objc private func activeAppChanged(_ notification: Notification) {
        // If the user switches apps while composing, cancel the session so the floating
        // panel doesn't remain over whatever app they've switched to.
        Task { @MainActor in
            if self.eventTapManager.isArmed {
                self.compositionController.cancelComposition()
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window == settingsWindow {
                settingsWindow = nil
            } else if window == onboardingWindow {
                onboardingWindow = nil
            }
        }
    }
}
