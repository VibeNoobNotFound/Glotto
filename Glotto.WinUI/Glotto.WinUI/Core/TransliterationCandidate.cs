// TransliterationCandidate.cs
// Port of TransliterationCandidate in TransliterationProvider.swift

namespace Glotto.WinUI.Core;

/// <summary>
/// A single ranked transliteration candidate.
/// Rank 0 = best match, ascending.
/// Using the text as the logical ID is safe — candidates for a given buffer are always unique strings.
/// </summary>
public sealed record TransliterationCandidate(string Text, int Rank);
