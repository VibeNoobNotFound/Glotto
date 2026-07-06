# Glotto

Glotto is a lightweight macOS utility that lets you type phonetically in Latin characters into **any text field in any application** (Safari, MS Word, Pages, Slack, Xcode, terminal, etc.) and instantly commit the correct transliterated script candidates. 

It acts as a floating IME (Input Method Editor) helper without requiring complex setup in System Settings → Keyboard → Input Sources.

---

## Key Features

- 🔠 **Phonetic Transliteration:** Type words phonetically (e.g., type `ammawarun` to get `අම්මාවරුන්` in Sinhala).
- 🪄 **Vibrant Liquid Glass UI:** A modern floating panel next to your cursor with:
  - Specular borders and dynamic dark-mode background tinting.
  - Snappy pop-up and exit animations matching the macOS Quick Lookup/Spotlight feel.
- ⚡ **Seamless Insertion:** Cleans up the phonetic Latin input and inserts the chosen script candidate at the insertion point.
- 🎛️ **Pluggable & Reorderable Providers:** Prioritize between different transliteration engines (currently supports Google Input Tools, with architecture ready for offline/rule-based modules).
- 🎹 **Keyboard & Click Navigation:** 
  - Arrow keys or number keys `1`–`5` to navigate and commit candidates.
  - Direct mouse clicks on candidate rows.
  - Esc or navigating away with Left/Right arrows cancels composition safely.
- 🔊 **Sound Feedback:** Select system sound effects (or "None") to notify you when Glotto is armed or disarmed.
- ⚙️ **Custom Shortcut:** Configure a global hotkey via KeyboardShortcuts to quickly toggle Glotto's arming state.

---

## How It Works Under the Hood

Glotto bypasses the complex macOS Input Method Kit infrastructure to remain lightweight and portable:
1. **Accessibility Event Tap:** Uses a session-level global event tap (`.cgSessionEventTap`) that monitors keystrokes system-wide *only* when armed.
2. **Buffer Interception:** When you start typing Latin letters, Glotto swallows the keystrokes and routes them to its buffer. It queries the active transliteration providers in your priority order.
3. **Cursor Tracking:** Utilizes the macOS Accessibility (AX) API to locate the text field's caret bounds and position the panel immediately below the insertion point.
4. **Text Injection:** When a candidate is committed, Glotto performs a zero-length AX selection write (`kAXSelectedTextAttribute`) to insert the text, falling back to a clipboard-paste mechanism if the target application is non-AX compliant.

---

## Build Requirements

- macOS 26 or later
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
   - Press `Cmd + R` in Xcode.
   - Upon first launch, Glotto will request **Accessibility permissions** (required to intercept shortcut keys, determine cursor positioning, and inject text).
   - If you rebuild the app binary later, you may need to toggle the permission Off and On in System Settings → Privacy & Security → Accessibility due to macOS binary-signature caching.
