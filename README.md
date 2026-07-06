# Glotto

Glotto is a lightweight macOS utility that lets you type phonetically in Latin characters into any text field (in Safari, MS Word, Pages, terminal, etc.) and commit transliterated script candidates. 

It acts as a helper panel next to your cursor without requiring any keyboard input source configuration in System Settings.

---

## Features

- **Phonetic Transliteration:** Type words phonetically (e.g., type `amma` to get `අම්ම` or `ammaa` to get `අම්මා` in Sinhala).
- **Transliteration Data Providers:** Candidates are retrieved in real-time from active transliteration providers.
  - Google Input Tools API: Online engine querying `inputtools.google.com/request` to fetch candidates based on phonetic strings and language codes.
  - Sinhala Local Rules: Offline engine containing precompiled rules mapping Singlish strings directly to Sinhala Unicode locally.
- **Priority Reordering:** Customize the priority order of transliteration engines from the settings panel. Reordering can be done by dragging rows via their handle or by clicking the up and down chevron buttons next to each item.
- **Vibrant Overlay UI:** A floating candidate panel positioned right at your text cursor with rounded corners, specular glow borders, and support for macOS system dark mode.
- **Snappy Animations:** Snappy pop-up and fade-out spring animations style-modeled after macOS Quick Lookup.
- **Keyboard and Click Control:** Use arrow keys or numbers 1 to 5 to commit candidates, or click directly on candidate rows.
- **Sound Feedback:** Audio alerts play when toggling Glotto on or off, with configurable sound options in Settings.
- **Global Shortcut:** Customize the hotkey to quickly enable or disable phonetic typing.

---

## How It Works

1. **Accessibility Event Tap:** While armed, Glotto monitors keystrokes globally using a session-level event tap.
2. **Buffer Interception:** Glotto swallows Latin keystrokes and appends them to a local buffer.
3. **Data Fetching:** The buffer is sent to the active provider fallback chain (ordered by your priority list) to fetch matching candidate suggestions.
4. **Insertion:** When you select a candidate, Glotto erases the Latin text and injects the committed characters at your cursor via the Accessibility API (with copy/paste fallback for non-compliant apps).

---

## Build Requirements

- macOS 26 or later (supporting Sequoia SwiftUI enhancements)
- Xcode 15.0 or later
- Swift 5.9+

---

## Getting Started

1. **Clone the repository:**
   ```bash
   git clone https://github.com/VibeNoobNotFound/Glotto.git
   cd Glotto
   ```
2. **Open the project:**
   Open `Glotto.MacOS/Glotto/Glotto.xcodeproj` in Xcode.
3. **Build and Run:**
   - Press Cmd + R in Xcode.
   - Glotto requires Accessibility permissions to capture keys and insert text.
   - Note: If you rebuild the app binary later, you may need to toggle the permission Off and On in System Settings to refresh macOS binary-signature caching.
