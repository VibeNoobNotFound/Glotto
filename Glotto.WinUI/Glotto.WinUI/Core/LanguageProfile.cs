// LanguageProfile.cs
// Port of LanguageProfile.swift — language-agnostic configuration unit.
// Nothing in Glotto should hardcode "Sinhala"; consume a LanguageProfile instead.

using System.Collections.Generic;

namespace Glotto.WinUI.Core;

public enum ScriptDirection
{
    LeftToRight,
    RightToLeft
}

/// <summary>
/// A language profile is the single unit of configuration that makes Glotto language-agnostic.
/// Every data-model and service tempted to hardcode "Sinhala" should reference a profile value instead.
/// </summary>
public sealed record LanguageProfile
{
    /// <summary>Stable identifier used as a storage/dictionary key (e.g. "si").</summary>
    public required string Id { get; init; }

    /// <summary>Human-readable display name shown in UI (e.g. "Sinhala").</summary>
    public required string DisplayName { get; init; }

    /// <summary>The `itc` parameter value for Google Input Tools (e.g. "si-t-i0-und").</summary>
    public required string GoogleInputToolsCode { get; init; }

    /// <summary>Script directionality — used for panel text alignment and future RTL support.</summary>
    public ScriptDirection ScriptDirection { get; init; } = ScriptDirection.LeftToRight;

    /// <summary>
    /// Characters that terminate a word and should trigger an auto-commit.
    /// Defaults to whitespace + common punctuation.
    /// </summary>
    public HashSet<char> WordBoundaryCharacters { get; init; } = DefaultWordBoundaries;

    /// <summary>Whether this profile is active in composition mode.</summary>
    public bool IsEnabled { get; init; } = true;

    // MARK: - Default word boundaries

    private static readonly HashSet<char> DefaultWordBoundaries =
    [
        ' ', '\t', '\r', '\n',
        '.', ',', ';', ':', '!', '?',
        '"', '\'', '(', ')', '[', ']', '{', '}'
    ];

    // MARK: - Built-in profiles

    /// <summary>The only shipped profile in Phase 1. Data is language-specific; code is not.</summary>
    public static readonly LanguageProfile Sinhala = new()
    {
        Id = "si",
        DisplayName = "Sinhala",
        GoogleInputToolsCode = "si-t-i0-und",
        ScriptDirection = ScriptDirection.LeftToRight
    };

    /// <summary>All profiles Glotto ships with. Phase 1: one item. Phase N: this list grows without code changes.</summary>
    public static readonly IReadOnlyList<LanguageProfile> BuiltIn = [Sinhala];
}
