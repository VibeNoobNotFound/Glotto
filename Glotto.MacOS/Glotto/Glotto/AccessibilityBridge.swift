import AppKit
import ApplicationServices

struct CaretGeometryResult {
    let rect: NSRect
    let source: String
}

/// Reads AX information from the currently focused UI element in any application.
/// Caret geometry uses a tiered resolver inspired by KeyType: exact AX bounds,
/// text-marker bounds, previous-character derivation, child text runs, then estimate.
enum AccessibilityBridge {

    // MARK: - Focused element

    static func focusedElement() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        if let focused = focusedElement(on: systemElement) {
            return focused
        }

        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return focusedElement(on: AXUIElementCreateApplication(app.processIdentifier))
    }

    private static func focusedElement(on element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttributeValue(kAXFocusedUIElementAttribute as CFString, on: element),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }

        return unsafeBitCast(value, to: AXUIElement.self)
    }

    // MARK: - Caret / selection rect

    static func caretScreenRect(in element: AXUIElement? = nil) -> NSRect? {
        caretGeometry(in: element)?.rect
    }

    static func caretGeometry(in element: AXUIElement? = nil) -> CaretGeometryResult? {
        guard let target = element ?? focusedElement() else { return nil }
        wakeEnhancedAccessibilityIfNeeded()

        let anchorFrame = elementFrame(in: target)
        let preferDerivedFirst = AppCompatibility.current.prefersDerivedCaretGeometry

        if !preferDerivedFirst,
           let exact = exactBoundsForSelection(in: target, anchorFrame: anchorFrame) {
            return exact
        }

        if let marker = textMarkerCaretRect(in: target, anchorFrame: anchorFrame) {
            return marker
        }

        if let derived = previousCharacterCaretRect(in: target, anchorFrame: anchorFrame) {
            return derived
        }

        if let deep = deepChildTextRunCaretRect(in: target, anchorFrame: anchorFrame) {
            return deep
        }

        if preferDerivedFirst,
           let exact = exactBoundsForSelection(in: target, anchorFrame: anchorFrame) {
            return exact
        }

        if let estimate = estimatedCaretRect(in: target, anchorFrame: anchorFrame) {
            return estimate
        }

        return nil
    }

    /// Returns focused element frame. Used only as last-resort overlay anchor.
    static func elementFrame(in element: AXUIElement) -> NSRect? {
        if let rect = rectValue(for: "AXFrame" as CFString, on: element), !rect.isEmpty {
            return cocoaRect(fromAccessibilityRect: rect)
        }

        var posValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let posValue,
              let sizeValue
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        return cocoaRect(fromAccessibilityRect: CGRect(origin: position, size: size))
    }

    // MARK: - Text range helpers

    static func selectedRange(in element: AXUIElement) -> CFRange? {
        guard let value = copyAttributeValue(kAXSelectedTextRangeAttribute as CFString, on: element) else {
            return nil
        }

        var range = CFRange()
        guard CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetValue(value as! AXValue, .cfRange, &range)
        else { return nil }

        return range
    }

    static func stringValue(of element: AXUIElement) -> String? {
        stringValue(for: kAXValueAttribute as CFString, on: element)
    }

    // MARK: - Resolver strategies

    private static func exactBoundsForSelection(
        in element: AXUIElement,
        anchorFrame: NSRect?
    ) -> CaretGeometryResult? {
        guard supportsParameterizedAttribute(kAXBoundsForRangeParameterizedAttribute as String, on: element),
              let selection = selectedRange(in: element),
              let rawRect = parameterizedRectValue(
                for: kAXBoundsForRangeParameterizedAttribute as CFString,
                range: CFRange(location: selection.location, length: 0),
                on: element
              ),
              !rawRect.isEmpty
        else { return nil }

        let rect = validatedCocoaTextRect(fromAccessibilityRect: rawRect, anchorFrame: anchorFrame)
        guard rectIsUsableCaretRect(rect, anchor: anchorFrame) else { return nil }

        return CaretGeometryResult(rect: normalizedCaretRect(rect), source: "AXBoundsForRange")
    }

    private static func textMarkerCaretRect(
        in element: AXUIElement,
        anchorFrame: NSRect?
    ) -> CaretGeometryResult? {
        guard let rawRect = textMarkerRawCaretRect(on: element), !rawRect.isEmpty else { return nil }

        let rect = validatedCocoaTextRect(fromAccessibilityRect: rawRect, anchorFrame: anchorFrame)
        guard rectIsUsableCaretRect(rect, anchor: anchorFrame) else { return nil }

        return CaretGeometryResult(rect: normalizedCaretRect(rect), source: "AXTextMarker")
    }

    private static func previousCharacterCaretRect(
        in element: AXUIElement,
        anchorFrame: NSRect?
    ) -> CaretGeometryResult? {
        guard supportsParameterizedAttribute(kAXBoundsForRangeParameterizedAttribute as String, on: element),
              let selection = selectedRange(in: element),
              selection.location > 0,
              let rawRect = parameterizedRectValue(
                for: kAXBoundsForRangeParameterizedAttribute as CFString,
                range: CFRange(location: selection.location - 1, length: 1),
                on: element
              ),
              !rawRect.isEmpty
        else { return nil }

        let rect = validatedCocoaTextRect(fromAccessibilityRect: rawRect, anchorFrame: anchorFrame)
        guard rectIsUsableCaretRect(rect, anchor: anchorFrame) else { return nil }

        return CaretGeometryResult(
            rect: NSRect(x: rect.maxX, y: rect.minY, width: 2, height: rect.height),
            source: "AXBoundsForPreviousCharacter"
        )
    }

    private static func deepChildTextRunCaretRect(
        in element: AXUIElement,
        anchorFrame: NSRect?
    ) -> CaretGeometryResult? {
        guard let selection = selectedRange(in: element),
              let textValue = stringValue(of: element),
              !textValue.isEmpty
        else { return nil }

        if let result = caretFromChildTextRuns(
            root: element,
            parentSelection: selection,
            parentText: textValue,
            anchorFrame: anchorFrame
        ) {
            return result
        }

        var current = element
        for _ in 0..<2 {
            guard let parent = parentElement(of: current) else { break }
            if let result = caretFromChildTextRuns(
                root: parent,
                parentSelection: selection,
                parentText: textValue,
                anchorFrame: anchorFrame
            ) {
                return result
            }
            current = parent
        }

        return nil
    }

    private static func estimatedCaretRect(
        in element: AXUIElement,
        anchorFrame: NSRect?
    ) -> CaretGeometryResult? {
        guard let selection = selectedRange(in: element),
              let text = stringValue(of: element),
              let anchorFrame,
              anchorFrame.width > 10,
              anchorFrame.height > 0
        else { return nil }

        return CaretGeometryResult(
            rect: conservativeEstimatedCaretRect(in: anchorFrame, text: text, selection: selection),
            source: "AXFrameEstimate"
        )
    }

    private static func caretFromChildTextRuns(
        root: AXUIElement,
        parentSelection: CFRange,
        parentText: String,
        anchorFrame: NSRect?
    ) -> CaretGeometryResult? {
        let parentLength = (parentText as NSString).length
        guard parentSelection.location <= parentLength else { return nil }

        let runs = collectStaticTextRuns(from: root)
        guard !runs.isEmpty else { return nil }

        let caretOffset = parentSelection.location
        var cumulative = 0
        for run in runs {
            let runLength = (run.text as NSString).length
            if caretOffset <= cumulative + runLength {
                let localOffset = caretOffset - cumulative
                let fraction = runLength > 0 ? CGFloat(localOffset) / CGFloat(runLength) : 1
                let frame = cocoaRect(fromAccessibilityRect: run.frame)
                let rect = NSRect(
                    x: frame.minX + fraction * frame.width,
                    y: frame.minY,
                    width: 2,
                    height: frame.height
                )
                guard rectIsNearAnchor(rect, anchor: anchorFrame) else { return nil }
                return CaretGeometryResult(rect: rect, source: "AXStaticTextRuns")
            }
            cumulative += runLength
        }

        guard let lastFrame = runs.last?.frame else { return nil }
        let frame = cocoaRect(fromAccessibilityRect: lastFrame)
        let rect = NSRect(x: frame.maxX, y: frame.minY, width: 2, height: frame.height)
        guard rectIsNearAnchor(rect, anchor: anchorFrame) else { return nil }
        return CaretGeometryResult(rect: rect, source: "AXStaticTextRunsTrailingEdge")
    }

    private static func collectStaticTextRuns(from root: AXUIElement) -> [(text: String, frame: CGRect)] {
        let maxDepth = 8
        let maxNodes = 250
        var visited = 0
        var seen = Set<String>()
        var runs: [(text: String, frame: CGRect)] = []

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= maxDepth, visited < maxNodes else { return }
            let identity = elementIdentity(for: element)
            guard seen.insert(identity).inserted else { return }
            visited += 1

            let role = stringValue(for: kAXRoleAttribute as CFString, on: element)
            if role == kAXStaticTextRole as String,
               let text = stringValue(for: kAXValueAttribute as CFString, on: element),
               !text.isEmpty,
               let frame = rectValue(for: "AXFrame" as CFString, on: element),
               !frame.isEmpty {
                runs.append((text, frame))
            }

            guard depth < maxDepth else { return }
            for child in childElements(of: element) {
                walk(child, depth: depth + 1)
            }
        }

        walk(root, depth: 0)
        return runs
    }

    // MARK: - AX helpers

    static func wakeEnhancedAccessibilityIfNeeded() {
        guard AppCompatibility.current.shouldEnableEnhancedAccessibility,
              let app = NSWorkspace.shared.frontmostApplication
        else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )
    }

    private static func copyAttributeValue(_ attribute: CFString, on element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value
    }

    private static func stringValue(for attribute: CFString, on element: AXUIElement) -> String? {
        copyAttributeValue(attribute, on: element) as? String
    }

    private static func rectValue(for attribute: CFString, on element: AXUIElement) -> CGRect? {
        guard let value = copyAttributeValue(attribute, on: element),
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func parameterizedRectValue(
        for attribute: CFString,
        range: CFRange,
        on element: AXUIElement
    ) -> CGRect? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute, rangeValue, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func supportsParameterizedAttribute(_ attribute: String, on element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success,
              let names = names as? [String]
        else { return true }
        return names.contains(attribute)
    }

    private static func textMarkerRawCaretRect(on element: AXUIElement) -> CGRect? {
        guard let selectedMarkerRange = copyAttributeValue("AXSelectedTextMarkerRange" as CFString, on: element) else {
            return nil
        }

        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            selectedMarkerRange,
            &value
        ) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    private static func childElements(of element: AXUIElement) -> [AXUIElement] {
        guard let value = copyAttributeValue(kAXChildrenAttribute as CFString, on: element),
              CFGetTypeID(value) == CFArrayGetTypeID(),
              let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private static func parentElement(of element: AXUIElement) -> AXUIElement? {
        guard let value = copyAttributeValue(kAXParentAttribute as CFString, on: element),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func elementIdentity(for element: AXUIElement) -> String {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return "\(pid)-\(CFHash(element))"
    }

    // MARK: - Validation and estimation

    private static func normalizedCaretRect(_ rect: NSRect) -> NSRect {
        guard !rect.isEmpty else { return rect }
        return NSRect(x: rect.minX, y: rect.minY, width: max(2, min(rect.width, 3)), height: rect.height)
    }

    private static func rectIsUsableCaretRect(_ rect: NSRect, anchor: NSRect?) -> Bool {
        guard rect.width.isFinite,
              rect.height.isFinite,
              rect.height > 0,
              rect.height < 200,
              rectIsNearAnchor(rect, anchor: anchor)
        else { return false }

        guard let anchor, !anchor.isEmpty else { return true }
        if anchor.height >= 40, rect.height >= anchor.height * 0.65 { return false }
        if anchor.width >= 80, rect.width >= anchor.width * 0.5 { return false }
        return true
    }

    private static func rectIsNearAnchor(_ rect: NSRect, anchor: NSRect?) -> Bool {
        guard let anchor, !anchor.isEmpty else { return true }
        let tolerance: CGFloat = 100
        return anchor.insetBy(dx: -tolerance, dy: -tolerance).contains(
            NSPoint(x: rect.midX, y: rect.midY)
        )
    }

    private static func conservativeEstimatedCaretRect(
        in frame: NSRect,
        text: String,
        selection: CFRange
    ) -> NSRect {
        let font = NSFont.systemFont(ofSize: 15)
        let lineHeight = min(max(font.boundingRectForFont.height, 18), 24)
        let height = min(frame.height, lineHeight)
        let nsText = text as NSString
        let safeLocation = min(max(selection.location, 0), nsText.length)
        let prefix = nsText.substring(to: safeLocation)
        let logicalLines = prefix.components(separatedBy: .newlines)
        let currentLine = logicalLines.last ?? prefix
        let measuredWidth = (currentLine as NSString).size(withAttributes: [.font: font]).width
        let x = min(frame.minX + max(0, measuredWidth * 0.95), frame.maxX)

        if frame.height <= lineHeight * 2 {
            return NSRect(x: x, y: frame.minY, width: 2, height: height)
        }

        let lineIndex = max(0, logicalLines.count - 1)
        let y = max(frame.minY, frame.maxY - 2 - CGFloat(lineIndex + 1) * lineHeight)
        return NSRect(x: x, y: y, width: 2, height: height)
    }

    // MARK: - Coordinate conversion

    static func flipToAppKitCoordinates(_ rect: CGRect) -> NSRect {
        cocoaRect(fromAccessibilityRect: rect)
    }

    private static func validatedCocoaTextRect(fromAccessibilityRect rect: CGRect, anchorFrame: NSRect?) -> NSRect {
        let flipped = cocoaRect(fromAccessibilityRect: rect)
        guard let anchorFrame, !anchorFrame.isEmpty else { return flipped }
        if rectIsNearAnchor(flipped, anchor: anchorFrame) {
            return flipped
        }

        for scaled in appKitRectsFromPixelRect(rect) where rectIsNearAnchor(scaled, anchor: anchorFrame) {
            return scaled
        }

        return flipped
    }

    private static func cocoaRect(fromAccessibilityRect rect: CGRect) -> NSRect {
        guard !rect.isNull, rect != .zero else { return rect }

        if let display = bestDisplay(for: rect, using: \.coreGraphicsBounds) {
            return appKitRect(fromCoreGraphicsRect: rect, on: display)
        }

        let desktopBounds = NSScreen.screens.map(\.frame).reduce(into: CGRect.null) {
            $0 = $0.union($1)
        }
        guard !desktopBounds.isNull else { return rect }

        return NSRect(
            x: rect.origin.x,
            y: desktopBounds.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func appKitRectsFromPixelRect(_ rect: CGRect) -> [NSRect] {
        displayGeometries().compactMap { display in
            guard display.backingScaleFactor > 0 else { return nil }
            let pixelBounds = CGRect(
                x: display.coreGraphicsBounds.minX * display.backingScaleFactor,
                y: display.coreGraphicsBounds.minY * display.backingScaleFactor,
                width: display.coreGraphicsBounds.width * display.backingScaleFactor,
                height: display.coreGraphicsBounds.height * display.backingScaleFactor
            )
            guard pixelBounds.intersects(rect) || pixelBounds.contains(CGPoint(x: rect.midX, y: rect.midY)) else {
                return nil
            }

            let pointRect = CGRect(
                x: display.coreGraphicsBounds.minX + (rect.minX - pixelBounds.minX) / display.backingScaleFactor,
                y: display.coreGraphicsBounds.minY + (rect.minY - pixelBounds.minY) / display.backingScaleFactor,
                width: rect.width / display.backingScaleFactor,
                height: rect.height / display.backingScaleFactor
            )
            return appKitRect(fromCoreGraphicsRect: pointRect, on: display)
        }
    }

    private static func appKitRect(fromCoreGraphicsRect rect: CGRect, on display: DisplayGeometry) -> NSRect {
        let localX = rect.minX - display.coreGraphicsBounds.minX
        let localY = rect.minY - display.coreGraphicsBounds.minY
        return NSRect(
            x: display.appKitFrame.minX + localX,
            y: display.appKitFrame.maxY - localY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private static func bestDisplay(
        for rect: CGRect,
        using keyPath: KeyPath<DisplayGeometry, CGRect>
    ) -> DisplayGeometry? {
        let displays = displayGeometries()
        let midpoint = CGPoint(x: rect.midX, y: rect.midY)
        if let containing = displays.first(where: { $0[keyPath: keyPath].contains(midpoint) }) {
            return containing
        }

        return displays
            .map { ($0, $0[keyPath: keyPath].intersection(rect).area) }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    private static func displayGeometries() -> [DisplayGeometry] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let displayID = CGDirectDisplayID(number.uint32Value)
            return DisplayGeometry(
                appKitFrame: screen.frame,
                coreGraphicsBounds: CGDisplayBounds(displayID),
                backingScaleFactor: screen.backingScaleFactor
            )
        }
    }
}

private struct DisplayGeometry {
    let appKitFrame: CGRect
    let coreGraphicsBounds: CGRect
    let backingScaleFactor: CGFloat
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
