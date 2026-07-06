# Glotto Phase 1 — Walkthrough Update

## ✅ Build Status: SUCCEEDED

All fixes build and link successfully.

---

## Final Fixes Applied

### 1. Settings Page Not Opening (Target Routing)
- **Issue**: In AppKit, creating `NSMenuItem` instances with a `nil` target prompts AppKit to search the responder chain starting from the key focused window. Since Glotto runs as a background/accessory status item without key window focus, the actions were never routed to the `AppDelegate`. The menu items appeared greyed-out or non-responsive.
- **Fix**: Explicitly set the `target = self` on custom actions ("Settings...", "Toggle Composition Mode") in `GlottoApp.swift`'s `buildStatusItem()` method. This targets the `AppDelegate` directly, activating and opening the settings panel.

### 2. Repeated Permission Request Prompt
- **Issue**: Glotto previously requested both **Accessibility** and **Input Monitoring** permissions. Input Monitoring has no public checking API, and the passive event tap test method was prone to false negatives. Furthermore, a session-level global event tap (`.cgSessionEventTap`) is fully authorized by Accessibility permissions alone; Input Monitoring is not required for accessibility-trusted processes.
- **Fix**: 
  - Simplified `PermissionManager` to check and request only **Accessibility** (`AXIsProcessTrusted()`), removing the buggy Input Monitoring checks.
  - Simplified `PermissionOnboardingView` and `SettingsView` to present only the Accessibility permission block.
  - Added a developer tip explaining the macOS TCC caching bug: if a rebuilt local binary loses system trust, toggling the Accessibility checkbox off and back on in System Settings will re-establish permissions.

---

## Verification Steps

1. **Launch App**: Open the `.app` bundle from your build directory.
2. **Menu Interaction**: Click the menu bar item. The "Settings..." option is now active and clickable, launching the direct settings window.
3. **Permissions Onboarding**: The app only asks for Accessibility permission. Once checked in System Settings, it registers immediately and launches.
