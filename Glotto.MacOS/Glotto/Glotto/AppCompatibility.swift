import AppKit

struct AppCompatibility {
    let prefersDerivedCaretGeometry: Bool
    let shouldEnableEnhancedAccessibility: Bool

    static var current: AppCompatibility {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""

        let webBackedBundles: Set<String> = [
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.tinyspeck.slackmacgap",
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "com.hnc.Discord",
            "notion.id"
        ]

        let derivedFirstBundles: Set<String> = [
            "com.google.Chrome",
            "com.microsoft.edgemac",
            "com.brave.Browser",
            "com.tinyspeck.slackmacgap",
            "com.microsoft.VSCode",
            "com.microsoft.VSCodeInsiders",
            "notion.id"
        ]

        return AppCompatibility(
            prefersDerivedCaretGeometry: derivedFirstBundles.contains(bundleID),
            shouldEnableEnhancedAccessibility: webBackedBundles.contains(bundleID)
        )
    }
}
