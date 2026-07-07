import AppKit

/// Bundle-ID-keyed table of known AX quirks in specific apps, modeled after
/// KeyType's `AppCompatibility` package. Glotto's overlay positioning logic
/// consults this to know when to skip straight to a cheaper/more reliable
/// strategy instead of trusting a given app's AX responses.
///
/// This is intentionally small and additive — it never blocks composition,
/// it only tunes *how* AccessibilityBridge resolves the caret rect for a
/// given frontmost app.
enum AppCompatibility {

    struct Quirks {
        /// If true, skip the exact `AXBoundsForRange` call entirely and go
        /// straight to the deep Chromium child-traversal strategy, since this
        /// app is known to return stale/incorrect bounds on the top-level element.
        var preferDeepTraversal: Bool = false

        /// If true, Glotto should not arm composition mode at all in this app
        /// (e.g. system password fields, Terminal in some configurations where
        /// injected paste could clobber a shell command usage).
        var disableComposition: Bool = false

        /// If true, this app is known to trim trailing whitespace from
        /// programmatically-set/pasted text, so a trailing space suffix must be
        /// fired as a separate, real `kVK_Space` keystroke rather than embedded
        /// directly in the inserted string. This is the *exception*, not the
        /// default: embedding the suffix in the same set/paste operation is
        /// strictly safer everywhere else, since it avoids racing a second,
        /// independent synthetic keystroke against the target's own (often
        /// async) handling of the first mutation — see `TextInjector`.
        var pasteTrimsTrailingWhitespace: Bool = false
    }

    /// Known bundle IDs with special handling. Chromium/Electron-based apps
    /// are the biggest offenders for stale/zero AXBoundsForRange results.
    private static let overrides: [String: Quirks] = [
        "com.google.Chrome": Quirks(preferDeepTraversal: true),
        "com.microsoft.edgemac": Quirks(preferDeepTraversal: true),
        "com.brave.Browser": Quirks(preferDeepTraversal: true),
        "com.tinyspeck.slackmacgap": Quirks(preferDeepTraversal: true),
        "com.hnc.Discord": Quirks(preferDeepTraversal: true),
        "com.microsoft.VSCode": Quirks(preferDeepTraversal: true),
        "com.figma.Desktop": Quirks(preferDeepTraversal: true),
        "notion.id": Quirks(preferDeepTraversal: true),

        // Password managers / secure fields: never arm composition here.
        "com.agilebits.onepassword7": Quirks(disableComposition: true),
        "com.1password.1password": Quirks(disableComposition: true),
        "com.apple.SecurityAgent": Quirks(disableComposition: true),

        // Word trims trailing whitespace from ⌘V/AX-set payloads, so it needs
        // the trailing space fired as a real, separate keystroke instead.
        "com.microsoft.Word": Quirks(pasteTrimsTrailingWhitespace: true),
    ]

    /// Returns quirks for the frontmost application, or default (empty) quirks
    /// if the app isn't in the table.
    static func quirks(forBundleID bundleID: String?) -> Quirks {
        guard let bundleID else { return Quirks() }
        return overrides[bundleID] ?? Quirks()
    }

    /// Convenience: quirks for whatever app currently owns the given PID.
    static func quirks(forPID pid: pid_t?) -> Quirks {
        guard let pid,
              let app = NSRunningApplication(processIdentifier: pid),
              let bundleID = app.bundleIdentifier
        else { return Quirks() }
        return quirks(forBundleID: bundleID)
    }

    /// Convenience: quirks for the current frontmost application.
    static func quirksForFrontmostApp() -> Quirks {
        quirks(forBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
