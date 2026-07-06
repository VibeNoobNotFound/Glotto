import Foundation

/// Owns the priority-ordered list of transliteration providers and falls through them in order.
///
/// Phase 1: providers = [GoogleTransliterationProvider()]
/// Phase 2: providers = [LocalRuleBasedProvider(), GoogleTransliterationProvider()]
///   — the loop already handles this correctly; only the initialiser changes.
///
/// Using an `actor` ensures that provider state mutations (if any future provider caches data)
/// are thread-safe without explicit locking.
actor TransliterationService {

    private let providers: [any TransliterationProvider]

    init(providers: [any TransliterationProvider] = [GoogleTransliterationProvider()]) {
        self.providers = providers
    }

    /// Try each provider in order; return the first non-empty result.
    /// Returns [] if all providers fail or return empty — callers should treat [] as "nothing to show."
    func candidates(for text: String, profile: LanguageProfile) async -> [TransliterationCandidate] {
        guard !text.isEmpty else { return [] }

        for provider in providers {
            do {
                let result = try await provider.candidates(for: text, profile: profile)
                if !result.isEmpty {
                    return result
                }
                // Provider returned empty — try the next one (fall-through behaviour)
            } catch TransliterationError.cancelled {
                // Task was cancelled — stop trying further providers and bail
                return []
            } catch {
                // Network failure, decode error, etc. — log and try the next provider
                print("[TransliterationService] Provider \(type(of: provider)) failed: \(error)")
            }
        }

        return []
    }
}
