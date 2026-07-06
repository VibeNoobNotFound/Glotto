import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers

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
    @State private var draggedEntry: ProviderEntry?

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
                Text("Drag rows by their handles or use arrow buttons to prioritize transliteration engines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(displayedProviders.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 10) {
                        // Up / Down click fallbacks for accessibility and ease of use on macOS
                        VStack(spacing: 1) {
                            Button(action: { moveUp(index) }) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(index == 0 ? Color.secondary.opacity(0.2) : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)

                            Button(action: { moveDown(index) }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(index == displayedProviders.count - 1 ? Color.secondary.opacity(0.2) : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(index == displayedProviders.count - 1)
                        }
                        .frame(width: 14)

                        // Drag handle
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .onHover { hovering in
                                if hovering { NSCursor.closedHand.push() } else { NSCursor.pop() }
                            }

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
                    .background(Color.clear) // Helps drop targets identify clicks
                    .onDrag {
                        self.draggedEntry = entry
                        return NSItemProvider(object: entry.id as NSString)
                    }
                    .onDrop(of: [.text], delegate: ProviderDropDelegate(
                        item: entry,
                        draggedItem: $draggedEntry,
                        list: $displayedProviders,
                        rawOrder: $providerOrderRaw
                    ))
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

    private func moveUp(_ index: Int) {
        guard index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            displayedProviders.swapAt(index, index - 1)
        }
        providerOrderRaw = displayedProviders.map(\.id).joined(separator: ",")
    }

    private func moveDown(_ index: Int) {
        guard index < displayedProviders.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            displayedProviders.swapAt(index, index + 1)
        }
        providerOrderRaw = displayedProviders.map(\.id).joined(separator: ",")
    }
}

// MARK: - Drop Delegate

private struct ProviderDropDelegate: DropDelegate {
    let item: ProviderEntry
    @Binding var draggedItem: ProviderEntry?
    @Binding var list: [ProviderEntry]
    @Binding var rawOrder: String

    func performDrop(info: DropInfo) -> Bool {
        self.draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem else { return }
        if draggedItem.id != item.id {
            guard let from = list.firstIndex(where: { $0.id == draggedItem.id }),
                  let to = list.firstIndex(where: { $0.id == item.id })
            else { return }

            withAnimation(.easeInOut(duration: 0.15)) {
                list.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
            rawOrder = list.map(\.id).joined(separator: ",")
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environmentObject(PermissionManager())
}
#endif
