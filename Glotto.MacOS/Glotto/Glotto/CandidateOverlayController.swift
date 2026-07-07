import AppKit
import SwiftUI

/// Owns the floating NSPanel that shows transliteration candidates.
///
/// The panel uses `.nonactivatingPanel` so it never steals keyboard focus from the
/// target application's text field — the whole point is the user keeps typing there.
@MainActor
final class CandidateOverlayController {

    private var panel: NSPanel?
    private var hostingView: NSHostingView<CandidatePanelView>?
    private let caretObserver = CaretChangeObserver()
    private let panelWidth: CGFloat = 320
    private let panelPadding: CGFloat = 4   // gap between caret bottom and panel top

    /// Set by CompositionController. Called when the user clicks a candidate row.
    var onCandidateSelected: ((Int) -> Void)?

    private var isPresented = false
    private var lastSession: CompositionSession?

    // MARK: - Show / update / hide

    func showOrUpdate(session: CompositionSession) {
        self.isPresented = true
        self.lastSession = session
        startCaretObservation()
        let isFirstShow = (panel == nil)
        if panel == nil {
            createPanel(session: session)
            panel?.alphaValue = 0 // start fully transparent for fade-in
        } else {
            update(session: session)
        }
        reposition()
        
        if isFirstShow || panel?.alphaValue == 0 {
            panel?.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel?.animator().alphaValue = 1.0
            }
        } else {
            panel?.orderFrontRegardless()
        }
    }

    func update(session: CompositionSession) {
        hostingView?.rootView = makePanelView(session: session)
        if isPresented {
            reposition()
        }
    }

    func hide() {
        guard let panel, isPresented else { return }
        self.isPresented = false
        
        // Notify SwiftUI view to start its scale-down / slide-down animation
        if let lastSession {
            update(session: lastSession)
        }
        
        NSAnimationContext.runAnimationGroup({ context in
            // Keep window animation synchronized with the SwiftUI spring animation duration
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only orderOut and clean up if it was not shown again during the fadeout
                if !self.isPresented {
                    panel.orderOut(nil)
                    // Clear references so the next creation triggers onAppear cleanly
                    self.panel = nil
                    self.hostingView = nil
                    self.caretObserver.stop()
                }
            }
        })
    }

    // MARK: - Panel creation

    private func createPanel(session: CompositionSession) {
        let view = makePanelView(session: session)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 200)

        let newPanel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = hosting
        newPanel.backgroundColor = .clear
        newPanel.isOpaque = false
        // Disable OS shadow to prevent the thin black border around rounded transparent windows.
        // SwiftUI view containers handle shadow rendering natively.
        newPanel.hasShadow = false
        newPanel.level = .floating
        // The panel must not become key or main — it should never pull focus.
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        panel = newPanel
        hostingView = hosting
    }

    // MARK: - Positioning

    /// Position the panel just below the caret rect from AccessibilityBridge.
    /// Falls back to focused control frame, then to mouse cursor if no bounds found.
    /// Clamps to screen bounds so the panel is never partially off-screen.
    func reposition() {
        guard let panel else { return }

        // Fit the panel to its SwiftUI content size.
        if let idealSize = hostingView?.fittingSize {
            let clampedWidth = min(max(idealSize.width, 200), panelWidth)
            let height = min(idealSize.height, 300)
            panel.setContentSize(NSSize(width: clampedWidth, height: height))
        }

        let panelSize = panel.frame.size

        // Try to get the caret rect and place the panel just below it.
        let origin: NSPoint
        if let caretGeometry = AccessibilityBridge.caretGeometry() {
            let caretRect = caretGeometry.rect
            origin = NSPoint(
                x: caretRect.minX,
                y: caretRect.minY - panelSize.height - panelPadding
            )
        } else if let focused = AccessibilityBridge.focusedElement(),
                  let elementFrame = AccessibilityBridge.elementFrame(in: focused) {
            // Fallback 1: bottom-left of the focused text area/field (MS Word, Pages, Electron)
            origin = NSPoint(
                x: elementFrame.minX,
                y: elementFrame.minY - panelSize.height - panelPadding
            )
        } else {
            // Fallback 2: bottom-right of the current mouse cursor location
            let mouseLoc = NSEvent.mouseLocation
            origin = NSPoint(
                x: mouseLoc.x + 10,
                y: mouseLoc.y - panelSize.height - 10
            )
        }

        let clampedOrigin = clamp(origin: origin, panelSize: panelSize)
        panel.setFrameOrigin(clampedOrigin)
    }

    private func startCaretObservation() {
        caretObserver.onCaretChanged = { [weak self] in
            self?.reposition()
        }
        caretObserver.start()
    }

    /// Keep the panel fully on-screen across multiple monitors.
    private func clamp(origin: NSPoint, panelSize: NSSize) -> NSPoint {
        // Find the screen that best contains the desired origin.
        let targetRect = NSRect(origin: origin, size: panelSize)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(targetRect) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        let bounds = screen.visibleFrame
        let x = min(max(origin.x, bounds.minX), bounds.maxX - panelSize.width)
        let y = min(max(origin.y, bounds.minY), bounds.maxY - panelSize.height)
        return NSPoint(x: x, y: y)
    }
    /// Constructs a CandidatePanelView wired to the click callback.
    private func makePanelView(session: CompositionSession) -> CandidatePanelView {
        CandidatePanelView(session: session, isPresented: isPresented, onSelect: onCandidateSelected)
    }
}
