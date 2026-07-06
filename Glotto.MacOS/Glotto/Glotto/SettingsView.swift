import SwiftUI
import KeyboardShortcuts

// MARK: - Shortcut name extension

extension KeyboardShortcuts.Name {
    /// The global toggle shortcut for arming/disarming Glotto composition mode.
    static let toggleCompositionMode = Self("toggleCompositionMode")
}

/// Main settings window — shown from the menu bar "Settings…" item.
struct SettingsView: View {

    @EnvironmentObject private var permissionManager: PermissionManager
    @AppStorage("activeProfileID") private var activeProfileID: String = LanguageProfile.sinhala.id

    // In Phase 1 there's exactly one built-in profile. The list is already the right structure
    // for when Phase N adds more — no UI change needed, just more items in `LanguageProfile.builtIn`.
    private let profiles = LanguageProfile.builtIn

    var body: some View {
        Form {
            // MARK: Hotkey
            Section("Global Shortcut") {
                HStack {
                    Label("Toggle Glotto", systemImage: "keyboard")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .toggleCompositionMode)
                }
                Text("Press this shortcut in any app to arm or disarm transliteration mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Language profiles
            Section("Language") {
                Picker("Active Profile", selection: $activeProfileID) {
                    ForEach(profiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
            }

            // MARK: Permissions
            Section("Permissions") {
                permissionRow(
                    title: "Accessibility",
                    detail: "Required to read cursor position, toggle global hotkey, and inject text.",
                    icon: "hand.tap",
                    granted: permissionManager.hasAccessibility,
                    action: { permissionManager.openAccessibilitySettings() }
                )
            }

            // MARK: About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                Link("Send Feedback", destination: URL(string: "https://github.com")!)
                    .font(.body)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear { permissionManager.refresh() }
    }

    // MARK: - Helpers

    private func permissionRow(
        title: String,
        detail: String,
        icon: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18))
                    .foregroundStyle(.green)
            } else {
                Button("Open Settings", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(PermissionManager())
}
#endif
