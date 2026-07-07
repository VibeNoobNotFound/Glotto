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
    private let panelWidth: CGFloat = 320
    private let panelPadding: CGFloat = 4   // gap between caret bottom and panel top

    /// Set by CompositionController. Called when the user clicks a candidate row.
    var onCandidateSelected: ((Int) -> Void)?

    private var isPresented = false
    private var lastSession: CompositionSession?

    /// Reactively repositions the panel on selection/window/focus changes that
    /// don't come from a keystroke (scrolling, window drag, click elsewhere in
    /// the same field). Started/stopped alongside the composition session.
    private let caretObserver = CaretChangeObserver()

    init() {
        caretObserver.onCaretMoved = { [weak self] in
            guard let self, self.isPresented else { return }
            self.reposition()
        }
    }

    // MARK: - Show / update / hide

    func showOrUpdate(session: CompositionSession) {
        self.isPresented = true
        self.lastSession = session
        let isFirstShow = (panel == nil)
        if panel == nil {
            createPanel(session: session)
            panel?.alphaValue = 0 // start fully transparent for fade-in
        } else {
            update(session: session)
        }
        reposition()
        startObservingCaretIfNeeded()

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

    /// Updates the panel's content. `reposition: true` should be passed whenever
    /// the update can change the panel's size (e.g. loading placeholder -> real
    /// candidate list) so it doesn't drift away from the caret; keystroke-driven
    /// callers that immediately call `reposition()` themselves can pass `false`
    /// to avoid doing the layout pass twice.
    func update(session: CompositionSession, reposition shouldReposition: Bool = false) {
        hostingView?.rootView = makePanelView(session: session)
        if shouldReposition {
            reposition()
        }
    }

    func hide() {
        caretObserver.stop()
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
            guard let self else { return }
            // Only orderOut and clean up if it was not shown again during the fadeout
            if !self.isPresented {
                panel.orderOut(nil)
                // Clear references so the next creation triggers onAppear cleanly
                self.panel = nil
                self.hostingView = nil
            }
        })
    }

    /// Starts the AXObserver-based reactive repositioning against whatever
    /// element currently has focus. Called once per show — re-focusing the
    /// same field mid-session is cheap to re-arm and keeps the observer
    /// pointed at the right element if focus moved within the same app.
    private func startObservingCaretIfNeeded() {
        guard let focused = AccessibilityBridge.focusedElement() else { return }
        caretObserver.start(observing: focused)
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

        // Fallback chain, in order of trustworthiness:
        //   1. AccessibilityBridge's tiered resolver (exact/derived/estimated,
        //      cross-validated against real window bounds).
        //   2. Last mouse-click location in the current app — doesn't depend on
        //      AX at all, so it's a reliable anchor for apps with poor/custom
        //      text accessibility (e.g. Pages' canvas-based text engine).
        //   3. The focused element's own frame — anchored near its TOP edge.
        //      (Previously anchored to `.minY`, which in AppKit's bottom-left
        //      coordinate space is the *bottom* of the rect — for apps whose
        //      focused element is the entire document view, e.g. Word/Pages,
        //      that put the panel at the literal bottom of the window.)
        //   4. Current mouse cursor position — final catch-all.
        let origin: NSPoint
        if let caretGeometry = AccessibilityBridge.resolveCaretGeometry() {
            let caretRect = caretGeometry.rect
            origin = NSPoint(
                x: caretRect.minX,
                y: caretRect.minY - panelSize.height - panelPadding
            )
        } else if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                  let clickLocation = MouseClickTracker.shared.recentClickLocation(forPID: pid) {
            origin = NSPoint(
                x: clickLocation.x,
                y: clickLocation.y - panelSize.height - panelPadding - 20 // clear the clicked line itself
            )
        } else if let focused = AccessibilityBridge.focusedElement(),
                  let elementFrame = AccessibilityBridge.elementFrame(in: focused) {
            // Fallback 3: near the TOP of the focused text area/field, not the
            // bottom — for a large multi-line container (MS Word, Pages,
            // Electron apps whose editable area spans the whole window) the
            // insertion point is essentially never at the frame's bottom edge.
            let lineHeightGuess: CGFloat = 20
            origin = NSPoint(
                x: elementFrame.minX,
                y: elementFrame.maxY - lineHeightGuess - panelSize.height - panelPadding
            )
        } else {
            // Fallback 4: bottom-right of the current mouse cursor location
            let mouseLoc = NSEvent.mouseLocation
            origin = NSPoint(
                x: mouseLoc.x + 10,
                y: mouseLoc.y - panelSize.height - 10
            )
        }

        let clampedOrigin = clamp(origin: origin, panelSize: panelSize)
        panel.setFrameOrigin(clampedOrigin)
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
