# Glotto

Glotto is a lightweight utility for Windows and MacOS that lets you type phonetically in Latin characters into any text field (in Google Chrome, MS Word, Pages, terminal, etc.) and commit transliterated script candidates. 

It acts as a helper panel next to your cursor without requiring any keyboard input source configuration in System Settings.
## Demo
<table>
  <tr>
    <td>
      <video src="https://github.com/user-attachments/assets/f0d31240-dae9-4e1c-b627-4748a4c313b8" width="400" controls></video>
    </td>
    <td>
      <video src="https://github.com/user-attachments/assets/6f114704-cc01-4a6a-9ab3-662835f781ae" width="400" controls></video>
    </td>
  </tr>
  <tr>
    <td><b>MacOS @v1.0b1</b></td>
    <td><b>Windows @v1.0b1</b></td>
  </tr>
</table>

## Download

Glotto is available for Windows & MacOS. 
You can download the latest stable release from [GitHub Releases](https://github.com/VibeNoobNotFound/Glotto/releases). See the Installation instructions below for platform-specific setup.

### Windows
> [!IMPORTANT]
> Glotto is distributed as a signed MSIX package. If this is your **first time** installing Glotto, you **must** trust the signing certificate:
1. Download the `.cer` certificate file from the release assets, If not available. Right Click -> Go to properties of your instllation file -> Security -> Signing & Certificates .
2. Right-click the `.cer` file and select **Install Certificate**.
3. Choose **Local Machine**, place it in **Trusted People** (If installation didnt work then try **Trusted Root Certification Authorities** ), and confirm.
4. Once trusted, you can download and run the `.appinstaller` file for automatic updates, or download the offline `.msix`/`.appxbundle` for your specific architecture.

### macOS
> [!IMPORTANT]
> The macOS build is currently **not notarized**. Gatekeeper will block it by default. To run Glotto, you must remove the quarantine attribute for every new binary you download. Open Terminal and run:
```bash
xattr -cr /path/to/Glotto.app
```

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

## How It Works

1. **Accessibility Event Tap:** While armed, Glotto monitors keystrokes globally using a session-level event tap.
2. **Buffer Interception:** Glotto swallows Latin keystrokes and appends them to a local buffer.
3. **Data Fetching:** The buffer is sent to the active provider fallback chain (ordered by your priority list) to fetch matching candidate suggestions.
4. **Insertion:** When you select a candidate, Glotto erases the Latin text and injects the committed characters at your cursor via the Accessibility API (with copy/paste fallback for non-compliant apps).


## Building From Source


### Requirements

#### MacOS
- macOS 26 or later (supporting Sequoia SwiftUI enhancements)
- Xcode 26.0 or later
#### Windows
- Windows 11
- Visual Studio with WinUI workload
---
1. **Clone the repository:**
   ```bash
   git clone https://github.com/VibeNoobNotFound/Glotto.git
   cd Glotto
   ```
2. **Open the project:**
   Open `Glotto.MacOS/Glotto/Glotto/Glotto.xcodeproj` in Xcode. Or open `Glotto.WinUI\Glotto.WinUI.slnx` in Visual Studio.
3. **Build and Run:**
   Press Cmd + R to run.

   
> [!NOTE]  
> In MacOS Glotto requires Accessibility permissions to capture keys and insert text.  
> If you rebuild the app binary later, you may need to toggle the permission Off and On in System Settings to refresh macOS binary-signature caching.
