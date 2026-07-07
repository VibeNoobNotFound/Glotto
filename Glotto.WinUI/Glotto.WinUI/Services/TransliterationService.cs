// TransliterationService.cs
// Port of TransliterationService.swift (actor → thread-safe singleton-ish service).
//
// Owns the priority-ordered list of transliteration providers and falls through them in order.
// Provider priority is read from LocalSettings on every query via ProviderRegistry,
// so a reorder made in Settings takes effect on the next keystroke — no restart required.

using Glotto.WinUI.Core;
using Glotto.WinUI.Providers;
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Windows.Storage;

namespace Glotto.WinUI.Services;

public sealed class TransliterationService
{
    private const string ProviderOrderKey = "providerOrder";

    /// <summary>
    /// Try each provider in priority order; return the first non-empty result.
    /// Returns [] if all providers fail or return empty — callers should treat [] as "nothing to show."
    /// </summary>
    public async Task<IReadOnlyList<TransliterationCandidate>> GetCandidatesAsync(
        string text,
        LanguageProfile profile,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrEmpty(text)) return [];

        foreach (var provider in CurrentProviders())
        {
            try
            {
                var result = await provider.GetCandidatesAsync(text, profile, cancellationToken);
                if (result.Count > 0) return result;
                // Provider returned empty — fall through to next
            }
            catch (OperationCanceledException)
            {
                // Task was cancelled — stop trying further providers
                return [];
            }
            catch (Exception ex)
            {
                // Network failure, decode error, etc. — log and try the next provider
                System.Diagnostics.Debug.WriteLine(
                    $"[TransliterationService] Provider {provider.GetType().Name} failed: {ex.Message}");
            }
        }

        return [];
    }

    // MARK: - Private

    /// <summary>
    /// Builds the provider list from the user's current priority order in LocalSettings.
    /// Provider construction is cheap (stateless objects) so doing it per-query is fine.
    /// </summary>
    private static IReadOnlyList<ITransliterationProvider> CurrentProviders()
    {
        var raw = SettingsStorage.GetString(ProviderOrderKey, ProviderRegistry.DefaultOrder)!;
        return ProviderRegistry.OrderedProviders(raw);
    }
}
