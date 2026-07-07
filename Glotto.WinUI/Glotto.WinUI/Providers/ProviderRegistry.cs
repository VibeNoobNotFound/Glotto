// ProviderRegistry.cs
// Port of ProviderRegistry.swift.
//
// Central registry of every transliteration provider Glotto knows about.
//
// Adding a new provider in a future phase:
//   1. Implement ITransliterationProvider.
//   2. Add one ProviderEntry to AllProviders below.
//   3. Done — the Settings UI, priority ordering, and service fallback chain update automatically.

using Glotto.WinUI.Core;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Glotto.WinUI.Providers;

/// <summary>Static description of a registered transliteration provider.</summary>
/// <param name="Id">Stable key stored in LocalSettings.</param>
/// <param name="DisplayName">Short name shown in Settings.</param>
/// <param name="Subtitle">One-line description shown in Settings.</param>
/// <param name="Icon">Segoe Fluent Icons character or tag string for the UI.</param>
/// <param name="MakeProvider">Factory called fresh each time the service builds its provider list.</param>
public sealed record ProviderEntry(
    string Id,
    string DisplayName,
    string Subtitle,
    string Icon,
    Func<ITransliterationProvider> MakeProvider);

public static class ProviderRegistry
{
    public static readonly IReadOnlyList<ProviderEntry> AllProviders =
    [
        new ProviderEntry(
            Id: "google.inputtools",
            DisplayName: "Google Input Tools",
            Subtitle: "Online — high accuracy for most scripts via Google's transliteration API.",
            Icon: "\uE909",   // Segoe Fluent Icons: Globe
            MakeProvider: static () => new GoogleTransliterationProvider()
        ),
        new ProviderEntry(
            Id: "local.rules",
            DisplayName: "Sinhala (Local Rules)",
            Subtitle: "Offline — rule-based phonetic transliteration.",
            Icon: "\uE92E",   // Segoe Fluent Icons: Keyboard
            MakeProvider: static () => new LocalRuleTransliterationProvider()
        )
    ];

    /// <summary>Default provider order — the natural registration order of <see cref="AllProviders"/>.</summary>
    public static string DefaultOrder =>
        string.Join(",", AllProviders.Select(p => p.Id));

    /// <summary>
    /// Returns <see cref="ProviderEntry"/> objects ordered by the comma-separated ID string.
    /// IDs not found in the registry are silently dropped.
    /// Registered providers missing from the saved list are appended at the end.
    /// </summary>
    public static IReadOnlyList<ProviderEntry> OrderedEntries(string rawOrder)
    {
        var savedIds = rawOrder
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        var byId = AllProviders.ToDictionary(p => p.Id);
        var seen = new HashSet<string>(savedIds.Length);
        var result = new List<ProviderEntry>(AllProviders.Count);

        // 1. Providers in the user's saved order
        foreach (var id in savedIds)
        {
            if (byId.TryGetValue(id, out var entry) && seen.Add(id))
                result.Add(entry);
        }

        // 2. Any newly registered providers not yet in the saved list
        foreach (var entry in AllProviders.Where(p => !seen.Contains(p.Id)))
            result.Add(entry);

        return result;
    }

    /// <summary>Instantiates live provider objects in the order dictated by <paramref name="rawOrder"/>.</summary>
    public static IReadOnlyList<ITransliterationProvider> OrderedProviders(string rawOrder) =>
        OrderedEntries(rawOrder).Select(e => e.MakeProvider()).ToList();
}
