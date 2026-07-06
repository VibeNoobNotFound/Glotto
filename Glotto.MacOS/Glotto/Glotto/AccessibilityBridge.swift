import AppKit
import ApplicationServices

/// Reads AX information from the currently focused UI element in any application.
/// This is intentionally a stateless utility namespace — no stored state here.
/// All results are Optional because AX calls can fail on any app at any time (§2, principle 4).
enum AccessibilityBridge {

    // MARK: - Focused element

    /// Returns the AX element that currently has keyboard focus, or nil on failure.
    /// Uses the system-wide focused element rather than targeting a specific PID,
    /// so it works regardless of which app the user is in.
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

    // MARK: - Caret / selection rect

    /// Returns the screen rectangle of the insertion point in the focused element, or nil.
    /// Used to position the candidate overlay panel directly beneath the cursor.
    ///
    /// Sequence:
    ///  1. Read the selected text range (kAXSelectedTextRangeAttribute).
    ///  2. Pass it to the parameterised bounds query (kAXBoundsForRangeParameterizedAttribute).
    ///  3. Convert the AXValue CGRect to screen coordinates (AX uses flipped coordinates on macOS).
    static func caretScreenRect(in element: AXUIElement? = nil) -> NSRect? {
        let target = element ?? focusedElement()
        guard let target else { return nil }

        // Step 1: selected text range
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue
        else { return nil }

        // Step 2: bounds for that range
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            target,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success,
              let boundsValue
        else { return nil }

        // Step 3: extract CGRect from AXValue
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else { return nil }

        // AX coordinates are in screen space with top-left origin (same as NSScreen.main).
        // Convert to AppKit's bottom-left-origin coordinate system.
        return flipToAppKitCoordinates(rect)
    }

    /// Returns the screen rectangle of the focused AX element itself, or nil on failure.
    /// Used as a fallback location for overlay positioning in Electron / MS Word / Pages.
    static func elementFrame(in element: AXUIElement) -> NSRect? {
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
        
        let rect = CGRect(origin: position, size: size)
        return flipToAppKitCoordinates(rect)
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

    // MARK: - Coordinate flip

    /// AX returns rects in a coordinate system with the origin at the top-left of the primary screen.
    /// AppKit / NSWindow positioning uses bottom-left origin. This converts between them.
    static func flipToAppKitCoordinates(_ rect: CGRect) -> NSRect {
        guard let screenHeight = NSScreen.screens.first?.frame.height else {
            return NSRect(origin: rect.origin, size: rect.size)
        }
        return NSRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}
