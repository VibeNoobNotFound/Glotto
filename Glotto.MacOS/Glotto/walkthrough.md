# Glotto Phase 1 — Walkthrough Update

## ✅ Build Status: SUCCEEDED

---

## Changes Implemented

### 1. Resizable Settings and Onboarding Windows
- **Fix**: Added the `.resizable` option to the `styleMask` configuration in both the **Settings Window** and the **Onboarding (Setup) Window** inside `GlottoApp.swift`.
- **Safeguard**: Programmed minimum window size bounds (`window.minSize`) to guarantee layout contents remain perfectly structured:
  - Settings: minimum bounds at `440 x 350`
  - Onboarding: minimum bounds at `480 x 350`

### 2. Premium Liquid Glass Upgrades
- **Corner Radius**: Increased from `12` to `18` on both the glass panels and content clipping layers.
- **Dark Mode Prominence**: Overlayed a subtle dynamic translucency tint (`Color.black.opacity(0.35)`) active specifically in dark mode to darken the material.
- **Inner Glow Border Stroke**: Outlined the glass panel with a thin (1pt) top-leading-to-bottom-trailing gradient frame. This adds a native specular reflective edge (glow border) that adapts automatically between light and dark modes.

### 3. Snappy macOS Quick Lookup Transition (Appear & Disappear)
- **Problem**: Previously, because the hosting view was reused instead of recreated, SwiftUI's `onAppear` would only trigger the animation the very first time. Furthermore, hiding the panel immediately cut off any disappear animation.
- **Fix**:
  - Added an `isPresented` state flow managed by `CandidateOverlayController` that cache-updates the SwiftUI view structure.
  - Added a `.animation(.spring(...), value: isPresented)` modifier to the view's layout scaling/translation modifiers.
  - **Appear**: Instantly scales from `0.88` to `1.0` with a slide offset on a snappy spring (`response: 0.22`, `dampingFraction: 0.65`).
  - **Disappear**: When hidden, `isPresented` is toggled to `false`, sliding and scaling the UI down to its initial position. The AppKit window uses an `alphaValue` animation context for `0.18s` matching the duration, ordering out and tearing down panel references only once the transition finishes. This enables clean, repeated transition cycles.
