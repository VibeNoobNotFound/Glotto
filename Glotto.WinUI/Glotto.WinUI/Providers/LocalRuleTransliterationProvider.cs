// LocalRuleTransliterationProvider.cs
// Port of LocalRuleTransliterationProvider.swift.
//
// Offline, rule-based transliterator mapping phonetic Singlish to Sinhala Unicode.
// Contains the exact same character tables as the Swift version.
// Longest-match-first algorithm: rules sorted descending by latin length at construction time.

using Glotto.WinUI.Core;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Glotto.WinUI.Providers;

public sealed class LocalRuleTransliterationProvider : ITransliterationProvider
{
    private const string HalKirima = "්";
    private const char ZeroWidthJoiner = '\u200D';

    // MARK: - Rule types

    private readonly record struct VowelRule(string Latin, string Independent, string Modifier);
    private readonly record struct ConsonantRule(string Latin, string Uni);
    private readonly record struct LiteralRule(string Latin, string Uni);
    private readonly record struct GayanukittaRule(string Latin, string Uni);

    // MARK: - Rule tables (identical characters to LocalRuleTransliterationProvider.swift)

    private static readonly VowelRule[] s_vowels =
    [
        new("aa", "ආ", "ා"),
        new("a)", "ආ", "ා"),
        new("Aa", "ඈ", "ෑ"),
        new("A)", "ඈ", "ෑ"),
        new("ae", "ඈ", "ෑ"),
        new("ii", "ඊ", "ී"),
        new("i)", "ඊ", "ී"),
        new("ie", "ඊ", "ී"),
        new("ee", "ඊ", "ී"),
        new("ea", "ඒ", "ේ"),
        new("e)", "ඒ", "ේ"),
        new("ei", "ඒ", "ේ"),
        new("oo", "ඌ", "ූ"),
        new("uu", "ඌ", "ූ"),
        new("u)", "ඌ", "ූ"),
        new("au", "ඖ", "ෞ"),
        new("a",  "අ", ""),
        new("A",  "ඇ", "ැ"),
        new("i",  "ඉ", "ි"),
        new("e",  "එ", "ෙ"),
        new("u",  "උ", "ු"),
        new("o",  "ඔ", "ො"),
        new("I",  "ඓ", "ෛ")
    ];

    private static readonly ConsonantRule[] s_consonants =
    [
        // Prenasalized (longer patterns must come before shorter ones)
        new("nng", "ඟ"),
        new("nd",  "ඳ"),
        new("nND", "ඬ"),
        new("mb",  "ඹ"),

        // Velar
        new("k",  "ක"),
        new("kh", "ඛ"),
        new("g",  "ග"),
        new("gh", "ඝ"),

        // Palatal
        new("ch", "ච"),
        new("Ch", "ඡ"),
        new("j",  "ජ"),
        new("q",  "ඣ"),
        new("GN", "ඥ"),
        new("KN", "ඤ"),

        // Retroflex
        new("T",  "ට"),
        new("Th", "ඨ"),
        new("D",  "ඩ"),
        new("Dh", "ඪ"),
        new("N",  "ණ"),

        // Dental
        new("t",  "ත"),
        new("th", "ථ"),
        new("d",  "ද"),
        new("dh", "ධ"),
        new("n",  "න"),

        // Labial
        new("p",  "ප"),
        new("ph", "ඵ"),
        new("b",  "බ"),
        new("bh", "භ"),
        new("m",  "ම"),

        // Semivowels
        new("Y",  "ය"),
        new("y",  "ය"),
        new("r",  "ර"),
        new("l",  "ල"),
        new("L",  "ළ"),
        new("Lu", "ළු"),
        new("v",  "ව"),
        new("w",  "ව"),

        // Sibilants / glottal
        new("sh", "ශ"),
        new("Sh", "ෂ"),
        new("s",  "ස"),
        new("h",  "හ"),
        new("f",  "ෆ")
    ];

    private static readonly LiteralRule[] s_literals =
    [
        new(@"\n", "ං"),
        new(@"\h", "ඃ"),
        new(@"\N", "ඞ"),
        new(@"\R", "ඍ"),
        new(@"\r", "ර්" + ZeroWidthJoiner),
        new("R",   "ර්" + ZeroWidthJoiner),
        new(@"\y", "ය")
    ];

    private static readonly GayanukittaRule[] s_gayanukitta =
    [
        new("ruu", "ෲ"),
        new("ru",  "ෘ")
    ];

    // MARK: - Pre-sorted rule arrays (longest-match-first — critical correctness guarantee)

    private readonly VowelRule[]       _vowelsByLength;
    private readonly ConsonantRule[]   _consonantsByLength;
    private readonly LiteralRule[]     _literalsByLength;
    private readonly GayanukittaRule[] _gayanukittaByLength;

    public LocalRuleTransliterationProvider()
    {
        _vowelsByLength      = [.. s_vowels.OrderByDescending(r => r.Latin.Length)];
        _consonantsByLength  = [.. s_consonants.OrderByDescending(r => r.Latin.Length)];
        _literalsByLength    = [.. s_literals.OrderByDescending(r => r.Latin.Length)];
        _gayanukittaByLength = [.. s_gayanukitta.OrderByDescending(r => r.Latin.Length)];
    }

    // MARK: - ITransliterationProvider

    public Task<IReadOnlyList<TransliterationCandidate>> GetCandidatesAsync(
        string text,
        LanguageProfile profile,
        CancellationToken cancellationToken)
    {
        // This local provider strictly supports Sinhala transliteration.
        if (profile.Id != "si" || string.IsNullOrEmpty(text))
            return Task.FromResult<IReadOnlyList<TransliterationCandidate>>([]);

        var converted = Convert(text);
        return Task.FromResult<IReadOnlyList<TransliterationCandidate>>(
        [
            new TransliterationCandidate(converted, 0)
        ]);
    }

    // MARK: - Core conversion logic

    private string Convert(string text)
    {
        // Split by hyphen to support disambiguation boundaries (same as Swift implementation).
        var segments = text.Split('-');
        return string.Concat(segments.Select(ConvertSegment));
    }

    private string ConvertSegment(string segment)
    {
        var sb = new System.Text.StringBuilder(segment.Length * 2);
        var i = 0;

        while (i < segment.Length)
        {
            // 1. Literal escapes (anusvara, visarga, repaya, yansaya, ...)
            if (MatchLiteral(segment, i) is { } lit)
            {
                sb.Append(lit.Uni);
                i += lit.Latin.Length;
                continue;
            }

            // 2. Consonant-led tokens
            if (MatchConsonant(segment, i) is { } cons)
            {
                var after = i + cons.Latin.Length;

                // 2a. consonant + gayanukitta (ru / ruu) → vocalic-r vowel signs
                if (MatchGayanukitta(segment, after) is { } gaya)
                {
                    sb.Append(cons.Uni).Append(gaya.Uni);
                    i = after + gaya.Latin.Length;
                    continue;
                }

                // 2b. consonant + "r" (+ optional vowel) → rakaransaya cluster (ක්ර)
                if (after < segment.Length && segment[after] == 'r')
                {
                    var next = after + 1;
                    if (MatchVowel(segment, next) is { } vowelAfterR)
                    {
                        sb.Append(cons.Uni).Append(HalKirima).Append(ZeroWidthJoiner).Append('ර').Append(vowelAfterR.Modifier);
                        i = next + vowelAfterR.Latin.Length;
                    }
                    else
                    {
                        sb.Append(cons.Uni).Append(HalKirima).Append(ZeroWidthJoiner).Append('ර');
                        i = next;
                    }
                    continue;
                }

                // 2c. consonant + vowel
                if (MatchVowel(segment, after) is { } vowel)
                {
                    sb.Append(cons.Uni).Append(vowel.Modifier);
                    i = after + vowel.Latin.Length;
                    continue;
                }

                // 2d. bare consonant, no vowel follows → hal kirima (vowel-killer)
                sb.Append(cons.Uni).Append(HalKirima);
                i = after;
                continue;
            }

            // 3. Standalone vowel (syllable-initial, no preceding consonant)
            if (MatchVowel(segment, i) is { } standaloneVowel)
            {
                sb.Append(standaloneVowel.Independent);
                i += standaloneVowel.Latin.Length;
                continue;
            }

            // 4. Fallback: already-Sinhala characters, punctuation, spaces, etc.
            sb.Append(segment[i]);
            i++;
        }

        return sb.ToString();
    }

    // MARK: - Typed match helpers (avoids boxing/reflection)

    private VowelRule? MatchVowel(string text, int index)
    {
        foreach (ref readonly var rule in _vowelsByLength.AsSpan())
        {
            if (index + rule.Latin.Length <= text.Length &&
                text.AsSpan(index, rule.Latin.Length).SequenceEqual(rule.Latin.AsSpan()))
                return rule;
        }
        return null;
    }

    private ConsonantRule? MatchConsonant(string text, int index)
    {
        foreach (ref readonly var rule in _consonantsByLength.AsSpan())
        {
            if (index + rule.Latin.Length <= text.Length &&
                text.AsSpan(index, rule.Latin.Length).SequenceEqual(rule.Latin.AsSpan()))
                return rule;
        }
        return null;
    }

    private LiteralRule? MatchLiteral(string text, int index)
    {
        foreach (ref readonly var rule in _literalsByLength.AsSpan())
        {
            if (index + rule.Latin.Length <= text.Length &&
                text.AsSpan(index, rule.Latin.Length).SequenceEqual(rule.Latin.AsSpan()))
                return rule;
        }
        return null;
    }

    private GayanukittaRule? MatchGayanukitta(string text, int index)
    {
        foreach (ref readonly var rule in _gayanukittaByLength.AsSpan())
        {
            if (index + rule.Latin.Length <= text.Length &&
                text.AsSpan(index, rule.Latin.Length).SequenceEqual(rule.Latin.AsSpan()))
                return rule;
        }
        return null;
    }
}
