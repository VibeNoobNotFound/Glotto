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
    @AppStorage("enableSound")     private var enableSound: String = "Tink"
    @AppStorage("disableSound")    private var disableSound: String = "Blow"
    /// Comma-separated provider IDs in priority order, persisted across launches.
    @AppStorage("providerOrder")   private var providerOrderRaw: String = ProviderRegistry.defaultOrder

    /// Live-ordered entries derived from `providerOrderRaw`; mutated by drag-to-reorder.
    @State private var displayedProviders: [ProviderEntry] = []

    private let profiles     = LanguageProfile.builtIn
    private let soundOptions = ["None", "Tink", "Blow", "Pop", "Submarine", "Glass", "Bottle", "Funk", "Ping", "Hero"]

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

            // MARK: Providers
            Section("Transliteration Providers") {
                Text("Drag to reorder priority. Each provider is tried in order; the first with results is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(displayedProviders.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 10) {
                        // Drag handle — visual cue for reorderability
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)

                        Image(systemName: entry.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.displayName)
                                .font(.body)
                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("#\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(.vertical, 3)
                }
                .onMove { from, to in
                    displayedProviders.move(fromOffsets: from, toOffset: to)
                    providerOrderRaw = displayedProviders.map(\.id).joined(separator: ",")
                }
            }

            // MARK: Sound Feedback
            Section("Sound Effects") {
                Picker("Armed Sound", selection: $enableSound) {
                    ForEach(soundOptions, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .onChange(of: enableSound) { _, newValue in
                    previewSound(newValue)
                }

                Picker("Disarmed Sound", selection: $disableSound) {
                    ForEach(soundOptions, id: \.self) { sound in
                        Text(sound).tag(sound)
                    }
                }
                .onChange(of: disableSound) { _, newValue in
                    previewSound(newValue)
                }
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
        .onAppear {
            permissionManager.refresh()
            // Populate displayedProviders from stored order (or default if first launch).
            displayedProviders = ProviderRegistry.orderedEntries(from: providerOrderRaw)
        }
        // Keep displayedProviders in sync if providerOrderRaw is changed externally.
        .onChange(of: providerOrderRaw) { _, newValue in
            let fresh = ProviderRegistry.orderedEntries(from: newValue)
            if fresh.map(\.id) != displayedProviders.map(\.id) {
                displayedProviders = fresh
            }
        }
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

    private func previewSound(_ name: String) {
        guard name != "None" else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(PermissionManager())
}
#endif
