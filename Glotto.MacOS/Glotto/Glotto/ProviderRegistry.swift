import Foundation

// MARK: - ProviderEntry

/// Static description of a registered transliteration provider.
///
/// The factory closure is called fresh each time the service builds its provider list.
/// Providers are intentionally stateless, so construction is cheap.
struct ProviderEntry: Identifiable {
    let id: String                                      // Stable key stored in UserDefaults
    let displayName: String                             // Short name shown in Settings
    let subtitle: String                                // One-line description shown in Settings
    let icon: String                                    // SF Symbol name
    let makeProvider: @Sendable () -> any TransliterationProvider
}

// MARK: - ProviderRegistry

/// Central registry of every transliteration provider Glotto knows about.
///
/// **Adding a new provider in a future phase:**
///   1. Implement `TransliterationProvider`.
///   2. Add one `ProviderEntry` to `allProviders` below.
///   3. Done — the Settings UI, priority ordering, and service fallback chain update automatically.
enum ProviderRegistry {

    static let allProviders: [ProviderEntry] = [
        ProviderEntry(
            id: "google.inputtools",
            displayName: "Google Input Tools",
            subtitle: "Online — high accuracy for most scripts via Google's transliteration API.",
            icon: "globe",
            makeProvider: { GoogleTransliterationProvider() }
        ),
        ProviderEntry(
            id: "local.rules",
            displayName: "Sinhala (Local Rules)",
            subtitle: "Offline — rule-based phonetic transliteration.",
            icon: "keyboard",
            makeProvider: { LocalRuleTransliterationProvider() }
        )
    ]

    // MARK: - Helpers

    /// Default provider order — the natural registration order of `allProviders`.
    static var defaultOrder: String {
        allProviders.map(\.id).joined(separator: ",")
    }

    /// Returns `ProviderEntry` objects ordered by the comma-separated ID string stored in
    /// UserDefaults.
    ///
    /// - IDs not found in the registry are silently dropped (e.g., a provider was removed).
    /// - Registered providers missing from the saved list are appended at the end, so newly
    ///   installed providers are always visible even after an app update.
    static func orderedEntries(from rawOrder: String) -> [ProviderEntry] {
        let savedIDs = rawOrder
            .split(separator: ",")
            .map(String.init)
            .filter { !$0.isEmpty }

        let byID = Dictionary(uniqueKeysWithValues: allProviders.map { ($0.id, $0) })
        var seen   = Set<String>()
        var result = [ProviderEntry]()

        // 1. Providers in the user's saved order
        for id in savedIDs {
            guard let entry = byID[id], !seen.contains(id) else { continue }
            result.append(entry)
            seen.insert(id)
        }
        // 2. Any newly registered providers not yet in the saved list
        for entry in allProviders where !seen.contains(entry.id) {
            result.append(entry)
        }
        return result
    }

    /// Instantiates live provider objects in the order dictated by `rawOrder`.
    static func orderedProviders(from rawOrder: String) -> [any TransliterationProvider] {
        orderedEntries(from: rawOrder).map { $0.makeProvider() }
    }
}
