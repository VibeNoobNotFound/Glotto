import AppKit
import ApplicationServices

/// Reads AX information from the currently focused UI element in any application.
///
/// Rewritten caret resolution strategy (was: single AXBoundsForRange call, no
/// validation, single-screen coordinate flip). Now uses a tiered
/// exact -> derived -> estimated resolver with rect validation against the
/// element's own frame, a deep-traversal fallback for Chromium/Electron apps
/// whose AXBoundsForRange frequently returns stale/zero rects, and a proper
/// per-display CoreGraphics -> AppKit coordinate conversion so multi-monitor
/// setups (mixed resolution, vertical arrangement, secondary-taller-than-primary)
/// resolve correctly instead of assuming `NSScreen.screens.first` is both the
/// primary display and the tallest one.
enum AccessibilityBridge {

    // MARK: - Result type

    /// A resolved caret rect plus how confident we are in it. Callers that only
    /// need "give me a rect" can keep using `caretScreenRect(in:)`; callers that
    /// want to make quality-based decisions (e.g. AppCompatibility overrides)
    /// can use `resolveCaretGeometry(in:)`.
    enum CaretQuality: Int, Comparable {
        case estimated = 0
        case derived = 1
        case exact = 2
        static func < (lhs: CaretQuality, rhs: CaretQuality) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    struct CaretGeometry {
        let rect: NSRect       // already in AppKit (bottom-left origin) coordinates
        let source: String     // for debugging/logging
        let quality: CaretQuality
    }

    // MARK: - Focused element

    /// Returns the AX element that currently has keyboard focus, or nil on failure.
    static func focusedElement() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let element = value else { return nil }
        return (element as! AXUIElement)
    }

    /// Returns the process ID owning `element`, if resolvable.
    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    // MARK: - Caret / selection rect (public entry point, used by CandidateOverlayController)

    /// Returns the best available screen rectangle for the insertion point in
    /// the focused element, or nil if nothing usable could be resolved at all.
    /// This is a thin wrapper over `resolveCaretGeometry` that most callers want.
    static func caretScreenRect(in element: AXUIElement? = nil) -> NSRect? {
        resolveCaretGeometry(in: element)?.rect
    }

    /// Tiered caret resolution:
    ///   1. Exact — AXBoundsForRange on a zero-length range at the selection start.
    ///   2. Exact (Chromium fallback) — deep child text-run traversal, for apps
    ///      where the standard AX bounds call returns stale/zero rects (Chrome,
    ///      Slack, Discord, VS Code, and other Electron/CEF-based apps).
    ///   3. Derived — bounds of the character immediately before the caret,
    ///      offset to its trailing edge. Works when zero-length ranges return
    ///      garbage but 1-length ranges don't (common Chromium quirk).
    ///   4. Estimated — approximate position within the element's own AXFrame,
    ///      proportional to selection offset within the text. Last resort.
    /// Every non-final candidate is validated against the element's AXFrame
    /// before being trusted — a rect miles away from the element's own bounds
    /// is treated as bogus rather than used verbatim.
    static func resolveCaretGeometry(in element: AXUIElement? = nil) -> CaretGeometry? {
        guard let target = element ?? focusedElement() else { return nil }

        let anchorFrame = rawElementFrame(target)
        let quirks = AppCompatibility.quirks(forPID: pid(of: target))

        // Ground truth independent of anything the target app itself reports:
        // the window server's own record of this app's window bounds. AX-frame
        // tolerance checks alone (below) rejected valid rects too eagerly the
        // moment a window wasn't near-fullscreen, because some apps' own
        // reported AXFrame doesn't perfectly track their real on-screen bounds
        // (e.g. a title/tab bar whose height isn't reflected in AXFrame). A rect
        // is trusted if it's plausible against *either* check.
        let windowFrame = pid(of: target).flatMap(WindowGeometry.mainWindowFrame(forPID:))

        // --- 1. Exact: zero-length range at selection start ---
        // Skipped for apps known to lie about AXBoundsForRange on the
        // top-level element (Chromium/Electron) — go straight to deep traversal.
        if let selection = selectedRange(in: target) {
            if !quirks.preferDeepTraversal,
               let rawRect = boundsForRange(CFRange(location: selection.location, length: 0), in: target),
               !rawRect.isEmpty || (rawRect.origin.x != 0 || rawRect.origin.y != 0) {
                let cocoaRect = flipToAppKitCoordinates(rawRect)
                if isUsableCaretRect(cocoaRect, anchor: anchorFrame, windowFrame: windowFrame) {
                    return CaretGeometry(rect: cocoaRect, source: "AXBoundsForRange", quality: .exact)
                }
            }

            // --- 2. Exact (Chromium/Electron deep traversal) ---
            if let deep = deepChromiumCaretRect(root: target, selection: selection, anchorFrame: anchorFrame, windowFrame: windowFrame) {
                return deep
            }

            // --- 3. Derived: bounds of the previous character, offset to trailing edge ---
            if selection.location > 0,
               let prevRaw = boundsForRange(CFRange(location: selection.location - 1, length: 1), in: target),
               !(prevRaw.width == 0 && prevRaw.height == 0) {
                let prevCocoa = flipToAppKitCoordinates(prevRaw)
                if isUsableCaretRect(prevCocoa, anchor: anchorFrame, windowFrame: windowFrame) {
                    let derivedRect = NSRect(x: prevCocoa.maxX, y: prevCocoa.minY, width: 2, height: prevCocoa.height)
                    return CaretGeometry(rect: derivedRect, source: "AXBoundsForPreviousCharacter", quality: .derived)
                }
            }
        }

        // --- 4. Estimated: proportional position within the element's own frame ---
        // Only attempted when we have a real selection offset to place it with —
        // without one, "somewhere inside this element's frame" degenerates to a
        // corner of the frame (often the bottom, for apps whose focused element
        // is the entire document view), which is worse than letting the caller's
        // own fallback chain (last click location, etc.) take over instead.
        if let anchorFrame, anchorFrame.width > 4, anchorFrame.height > 0,
           let selection = selectedRange(in: target), selection.location > 0 {
            let text = stringValue(of: target) ?? ""
            guard !text.isEmpty else { return nil }
            let estimate = estimatedCaretRect(in: anchorFrame, text: text, selection: selection)
            return CaretGeometry(rect: estimate, source: "AXFrameEstimate", quality: .estimated)
        }

        return nil
    }

    /// Returns the frontmost window frame for `pid` in AppKit (bottom-left
    /// origin) coordinates, or nil if it couldn't be resolved. Ground truth
    /// from the window server, independent of the target app's own AX
    /// reporting — useful as a last-resort anchor when AX-based caret
    /// resolution fails entirely.
    static func mainWindowFrame(forPID pid: pid_t) -> NSRect? {
        WindowGeometry.mainWindowFrame(forPID: pid).map(flipToAppKitCoordinates)
    }

    /// Returns the screen rectangle of the focused AX element itself, or nil on failure.
    /// Used as a fallback location for overlay positioning in Electron / MS Word / Pages.
    static func elementFrame(in element: AXUIElement) -> NSRect? {
        rawElementFrame(element).map(flipToAppKitCoordinates)
    }

    // MARK: - Text range helpers

    /// Returns the value of kAXSelectedTextRangeAttribute as a CFRange, or nil.
    static func selectedRange(in element: AXUIElement) -> CFRange? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Returns the full string value of an AX text element, or nil.
    static func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let str = value as? String
        else { return nil }
        return str
    }

    // MARK: - Private: raw AX reads (still in AX/CG top-left coordinate space)

    private static func boundsForRange(_ range: CFRange, in element: AXUIElement) -> CGRect? {
        var rangeValue = range
        guard let axRange = AXValueCreate(.cfRange, &rangeValue) else { return nil }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &boundsValue
        ) == .success,
              let boundsValue
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func rawElementFrame(_ element: AXUIElement) -> CGRect? {
        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue, let sizeValue
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: position, size: size)
    }

    /// True if `rect` is plausible either against the anchor element's own
    /// frame, or against the target app's real on-screen window bounds
    /// (from `WindowGeometry`, ground truth independent of the app's own AX
    /// reporting quirks). Accepting on *either* check — rather than requiring
    /// both — is what fixes rejecting genuinely-correct rects the moment a
    /// window isn't near-fullscreen: some apps' AXFrame for the focused
    /// element doesn't perfectly track their true on-screen position (a
    /// title/tab bar height discrepancy is a common cause), so the tighter
    /// anchor check alone was too eager to reject valid results.
    private static func isUsableCaretRect(_ rect: NSRect, anchor: CGRect?, windowFrame: CGRect? = nil) -> Bool {
        guard rect.width.isFinite, rect.height.isFinite, rect.origin.x.isFinite, rect.origin.y.isFinite else {
            return false
        }
        if anchor == nil, windowFrame == nil { return true }

        if let anchor {
            let anchorCocoa = flipToAppKitCoordinates(anchor)
            let tolerance: CGFloat = 80
            let expanded = anchorCocoa.insetBy(dx: -tolerance, dy: -tolerance)
            if expanded.contains(CGPoint(x: rect.midX, y: rect.midY)) { return true }
        }

        if let windowFrame {
            // Window bounds are a much harder constraint than the element's own
            // frame — the caret genuinely cannot be outside the window that
            // contains it — but allow generous slack for title/tab bar chrome
            // whose height varies by app and window state.
            let windowCocoa = flipToAppKitCoordinates(windowFrame)
            let chromeTolerance: CGFloat = 120
            let expanded = windowCocoa.insetBy(dx: -20, dy: -chromeTolerance)
            if expanded.contains(CGPoint(x: rect.midX, y: rect.midY)) { return true }
        }

        return false
    }

    /// Estimates a caret rect proportionally within `anchorFrame` (still CG
    /// top-left space, converted at the end) based on how far through `text`
    /// the selection is. Only called when we have a real, non-zero selection
    /// offset — callers no longer fall into this for a bare "no idea" guess,
    /// since anchoring blind to a corner of a possibly-huge element frame
    /// (e.g. an entire document view) is worse than deferring to the caller's
    /// own AX-independent fallbacks (last click location, etc).
    private static func estimatedCaretRect(in anchorFrame: CGRect, text: String, selection: CFRange) -> NSRect {
        let cocoaAnchor = flipToAppKitCoordinates(anchorFrame)
        // Rough single-line proportional estimate. Multi-line text makes this
        // approximate at best, which is why it's ranked `.estimated`.
        let fraction = min(1.0, CGFloat(selection.location) / CGFloat(max(text.utf16.count, 1)))
        let lineHeight = min(cocoaAnchor.height, 20)
        let x = cocoaAnchor.minX + fraction * cocoaAnchor.width
        // Anchor near the TOP of the frame, not the bottom — for large
        // multi-line containers (the exact case that broke Word/Pages) the
        // insertion point is virtually never at the frame's bottom edge, and
        // "somewhere along the top row" is a much safer default guess.
        return NSRect(x: x, y: cocoaAnchor.maxY - lineHeight, width: 2, height: lineHeight)
    }

    // MARK: - Private: Chromium/Electron deep text-run traversal

    /// Chromium's AX tree exposes the actual caret geometry on nested
    /// AXStaticText / AXInlineTextBox children rather than reliably on the
    /// focused text field's own AXBoundsForRange. Walk one or two levels of
    /// children looking for a text-role node whose own selection/bounds are
    /// usable. This mirrors the class of fix KeyType applies for exactly the
    /// same class of app.
    private static func deepChromiumCaretRect(
        root: AXUIElement,
        selection: CFRange,
        anchorFrame: CGRect?,
        windowFrame: CGRect? = nil
    ) -> CaretGeometry? {
        for child in children(of: root, maxDepth: 2) {
            var roleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String
            else { continue }

            guard role == "AXStaticText" || role == "AXTextField" || role == "AXTextArea" else { continue }

            // Try the child's own selection range first, then fall back to a
            // full-range bounds query (index 0, length 0) which some Chromium
            // text-run nodes support even without a live selection.
            let childSelection = selectedRange(in: child) ?? CFRange(location: 0, length: 0)
            guard let rawRect = boundsForRange(childSelection, in: child), !rawRect.isEmpty else { continue }

            let cocoaRect = flipToAppKitCoordinates(rawRect)
            if isUsableCaretRect(cocoaRect, anchor: anchorFrame, windowFrame: windowFrame) {
                return CaretGeometry(rect: cocoaRect, source: "DeepChromiumTextRun", quality: .exact)
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement, maxDepth: Int) -> [AXUIElement] {
        guard maxDepth > 0 else { return [] }
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let rawChildren = childrenValue as? [AXUIElement]
        else { return [] }

        var result = rawChildren
        for child in rawChildren {
            result.append(contentsOf: children(of: child, maxDepth: maxDepth - 1))
        }
        return result
    }

    // MARK: - Coordinate conversion (multi-display aware)

    /// A pure snapshot of one display's geometry in both coordinate spaces.
    private struct DisplayGeometry {
        let appKitFrame: CGRect       // bottom-left origin, global desktop space
        let coreGraphicsBounds: CGRect // top-left origin, global desktop space (what AX gives us)
    }

    private static func currentDisplayGeometries() -> [DisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return DisplayGeometry(appKitFrame: screen.frame, coreGraphicsBounds: CGDisplayBounds(displayID))
        }
    }

    /// AX/CoreGraphics rects use a top-left origin *per the global desktop
    /// bounding box*, not "the primary screen's height". The previous
    /// implementation used `NSScreen.screens.first?.frame.height` for every
    /// conversion, which:
    ///   - assumed `.screens.first` is the primary/menu-bar display (not
    ///     guaranteed by AppKit),
    ///   - assumed every display shares that height (breaks the moment a
    ///     secondary monitor has a different resolution or is offset
    ///     vertically, e.g. a monitor mounted lower or a portrait display).
    ///
    /// This finds the specific display that actually contains the rect and
    /// converts using that display's own CG bounds / AppKit frame pair, which
    /// is correct for arbitrary multi-monitor arrangements. Falls back to a
    /// desktop-union flip only if no display geometry could be resolved.
    static func flipToAppKitCoordinates(_ rect: CGRect) -> NSRect {
        let displays = currentDisplayGeometries()
        guard !displays.isEmpty else {
            // No screen info at all (extremely unlikely) — return as-is rather than crash.
            return NSRect(origin: rect.origin, size: rect.size)
        }

        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        let display = displays.first(where: { $0.coreGraphicsBounds.contains(midpoint) })
            ?? displays.max(by: { intersectionArea($0.coreGraphicsBounds, rect) < intersectionArea($1.coreGraphicsBounds, rect) })
            ?? displays[0]

        // Only trust the "best match" if it actually overlaps the rect; otherwise
        // fall back to the desktop-union flip below (e.g. rect from a display
        // that's since been disconnected).
        guard display.coreGraphicsBounds.intersects(rect) || display.coreGraphicsBounds.contains(midpoint) else {
            return legacyDesktopUnionFlip(rect, displays: displays)
        }

        let localX = rect.minX - display.coreGraphicsBounds.minX
        let localY = rect.minY - display.coreGraphicsBounds.minY

        return NSRect(
            x: display.appKitFrame.minX + localX,
            y: display.appKitFrame.maxY - localY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private static func legacyDesktopUnionFlip(_ rect: CGRect, displays: [DisplayGeometry]) -> NSRect {
        let desktopBounds = displays.map(\.appKitFrame).reduce(into: CGRect.null) { $0 = $0.union($1) }
        guard !desktopBounds.isNull else { return NSRect(origin: rect.origin, size: rect.size) }
        return NSRect(
            x: rect.origin.x,
            y: desktopBounds.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
