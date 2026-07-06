import Foundation

/// Owns the priority-ordered list of transliteration providers and falls through them in order.
///
/// Provider priority is read from UserDefaults on every query via `ProviderRegistry`, so a
/// reorder made in Settings takes effect on the next keystroke — no restart required.
///
/// Using an `actor` ensures that any future provider that caches mutable state is thread-safe
/// without explicit locking.
actor TransliterationService {

    /// Try each provider in priority order; return the first non-empty result.
    /// Returns [] if all providers fail or return empty — callers should treat [] as "nothing to show."
    func candidates(for text: String, profile: LanguageProfile) async -> [TransliterationCandidate] {
        guard !text.isEmpty else { return [] }

        for provider in currentProviders() {
            do {
                let result = try await provider.candidates(for: text, profile: profile)
                if !result.isEmpty { return result }
                // Provider returned empty — fall through to next
            } catch TransliterationError.cancelled {
                // Task was cancelled — stop trying further providers
                return []
            } catch {
                // Network failure, decode error, etc. — log and try the next provider
                print("[TransliterationService] Provider \(type(of: provider)) failed: \(error)")
            }
        }

        return []
    }

    // MARK: - Private

    /// Builds the provider list from the user's current priority order in UserDefaults.
    /// Provider construction is cheap (stateless objects) so doing it per-query is fine.
    private func currentProviders() -> [any TransliterationProvider] {
        let raw = UserDefaults.standard.string(forKey: "providerOrder")
                  ?? ProviderRegistry.defaultOrder
        return ProviderRegistry.orderedProviders(from: raw)
    }
}
