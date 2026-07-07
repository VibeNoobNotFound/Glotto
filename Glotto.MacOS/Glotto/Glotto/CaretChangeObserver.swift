import AppKit
import ApplicationServices

@MainActor
final class CaretChangeObserver: NSObject {
    var onCaretChanged: (() -> Void)?

    private let systemElement = AXUIElementCreateSystemWide()
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedFocusedElement: AXUIElement?
    private var pendingRefresh: DispatchWorkItem?
    private var isRunning = false

    func start() {
        guard !isRunning else { return }
        isRunning = true

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        retargetObserver()
        scheduleRefresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pendingRefresh?.cancel()
        pendingRefresh = nil
        tearDownObserver()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc
    private func frontmostAppChanged(_ note: Notification) {
        Task { @MainActor [weak self] in
            self?.retargetObserver()
            self?.scheduleRefresh()
        }
    }

    private func retargetObserver() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            tearDownObserver()
            return
        }

        if observedPID == app.processIdentifier, observer != nil {
            refreshFocusedElementObservation()
            return
        }

        tearDownObserver()

        var newObserver: AXObserver?
        guard AXObserverCreate(app.processIdentifier, CaretChangeObserver.observerCallback, &newObserver) == .success,
              let newObserver
        else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AccessibilityBridge.wakeEnhancedAccessibilityIfNeeded()

        addNotification(kAXFocusedUIElementChangedNotification, on: appElement, observer: newObserver)
        addNotification(kAXFocusedWindowChangedNotification, on: appElement, observer: newObserver)
        addNotification(kAXWindowMovedNotification, on: appElement, observer: newObserver)
        addNotification(kAXWindowResizedNotification, on: appElement, observer: newObserver)
        addNotification(kAXUIElementDestroyedNotification, on: appElement, observer: newObserver)

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)

        observer = newObserver
        observedPID = app.processIdentifier
        refreshFocusedElementObservation()
    }

    private func refreshFocusedElementObservation() {
        guard let observer else { return }

        if let previous = observedFocusedElement {
            removeNotification(kAXSelectedTextChangedNotification, on: previous, observer: observer)
            removeNotification(kAXValueChangedNotification, on: previous, observer: observer)
            removeNotification(kAXMovedNotification, on: previous, observer: observer)
            removeNotification(kAXResizedNotification, on: previous, observer: observer)
            removeNotification(kAXUIElementDestroyedNotification, on: previous, observer: observer)
        }

        observedFocusedElement = AccessibilityBridge.focusedElement()

        if let focused = observedFocusedElement {
            addNotification(kAXSelectedTextChangedNotification, on: focused, observer: observer)
            addNotification(kAXValueChangedNotification, on: focused, observer: observer)
            addNotification(kAXMovedNotification, on: focused, observer: observer)
            addNotification(kAXResizedNotification, on: focused, observer: observer)
            addNotification(kAXUIElementDestroyedNotification, on: focused, observer: observer)
        }
    }

    private func tearDownObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedPID = nil
        observedFocusedElement = nil
    }

    private func addNotification(_ name: String, on element: AXUIElement, observer: AXObserver) {
        let context = Unmanaged.passUnretained(self).toOpaque()
        _ = AXObserverAddNotification(observer, element, name as CFString, context)
    }

    private func removeNotification(_ name: String, on element: AXUIElement, observer: AXObserver) {
        _ = AXObserverRemoveNotification(observer, element, name as CFString)
    }

    private static let observerCallback: AXObserverCallback = { _, _, name, refcon in
        guard let refcon else { return }
        let owner = Unmanaged<CaretChangeObserver>.fromOpaque(refcon).takeUnretainedValue()
        let notification = name as String
        Task { @MainActor in
            owner.handleNotification(notification)
        }
    }

    private func handleNotification(_ name: String) {
        if name == kAXFocusedUIElementChangedNotification
            || name == kAXFocusedWindowChangedNotification
            || name == kAXUIElementDestroyedNotification {
            refreshFocusedElementObservation()
        }

        scheduleRefresh()
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.onCaretChanged?()
            }
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
    }
}
