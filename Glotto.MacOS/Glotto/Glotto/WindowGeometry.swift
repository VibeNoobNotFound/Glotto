import AppKit

/// Resolves a target app's actual on-screen window bounds via `CGWindowList`
/// rather than accessibility APIs. This exists as ground truth to validate
/// against: AX-reported rects (from AccessibilityBridge) can be subtly wrong
/// in app-specific ways — e.g. some apps' reported bounds don't correctly
/// account for a variable-height title/tab bar — but the window's actual
/// on-screen frame as tracked by the window server is always correct
/// regardless of what the app itself reports. `CGWindowList` bounds are in
/// the same top-left-origin global coordinate space that AX rects use, so
/// no extra conversion is needed to compare them directly.
enum WindowGeometry {

    /// The frame (CG top-left global coordinates) of the largest on-screen,
    /// normal-layer window owned by `pid`, or nil if none is found.
    static func mainWindowFrame(forPID pid: pid_t) -> CGRect? {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: AnyObject]] else { return nil }

        // Layer 0 = normal application windows (excludes menu bar, dock, etc).
        let candidates = infoList.filter { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid &&
            (info[kCGWindowLayer as String] as? Int) == 0
        }

        guard let best = candidates.max(by: { area(of: $0) < area(of: $1) }),
              let boundsDict = best[kCGWindowBounds as String] as? [String: CGFloat]
        else { return nil }

        return CGRect(
            x: boundsDict["X"] ?? 0,
            y: boundsDict["Y"] ?? 0,
            width: boundsDict["Width"] ?? 0,
            height: boundsDict["Height"] ?? 0
        )
    }

    private static func area(of info: [String: AnyObject]) -> CGFloat {
        guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { return 0 }
        return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
    }
}
