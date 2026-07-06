import Foundation

// MARK: - Rule Protocols and Models

private protocol TransliterationRule {
    var latin: String { get }
    var uni: String { get }
}

private struct ConsonantRule: TransliterationRule {
    let latin: String
    let uni: String
}

private struct VowelRule: TransliterationRule {
    let latin: String
    let independent: String
    let modifier: String
    var uni: String { independent }
}

private struct LiteralRule: TransliterationRule {
    let latin: String
    let uni: String
}

private struct GayanukittaRule: TransliterationRule {
    let latin: String
    let uni: String
}

// MARK: - Local Rule Transliteration Provider

/// An offline, rule-based transliterator mapping phonetic Singlish to Sinhala Unicode.
/// Conforms to `TransliterationProvider`.
final class LocalRuleTransliterationProvider: TransliterationProvider, @unchecked Sendable {

    private static let HAL_KIRIMA = "්"

    // MARK: - Static Rule Databases

    private static let VOWELS: [VowelRule] = [
        VowelRule(latin: "aa", independent: "ආ", modifier: "ා"),
        VowelRule(latin: "a)", independent: "ආ", modifier: "ා"),
        VowelRule(latin: "Aa", independent: "ඈ", modifier: "ෑ"),
        VowelRule(latin: "A)", independent: "ඈ", modifier: "ෑ"),
        VowelRule(latin: "ae", independent: "ඈ", modifier: "ෑ"),
        VowelRule(latin: "ii", independent: "ඊ", modifier: "ී"),
        VowelRule(latin: "i)", independent: "ඊ", modifier: "ී"),
        VowelRule(latin: "ie", independent: "ඊ", modifier: "ී"),
        VowelRule(latin: "ee", independent: "ඊ", modifier: "ී"),
        VowelRule(latin: "ea", independent: "ඒ", modifier: "ේ"),
        VowelRule(latin: "e)", independent: "ඒ", modifier: "ේ"),
        VowelRule(latin: "ei", independent: "ඒ", modifier: "ේ"),
        VowelRule(latin: "oo", independent: "ඌ", modifier: "ූ"),
        VowelRule(latin: "uu", independent: "ඌ", modifier: "ූ"),
        VowelRule(latin: "u)", independent: "ඌ", modifier: "ූ"),
        VowelRule(latin: "au", independent: "ඖ", modifier: "ෞ"),
        VowelRule(latin: "a", independent: "අ", modifier: ""),
        VowelRule(latin: "A", independent: "ඇ", modifier: "ැ"),
        VowelRule(latin: "i", independent: "ඉ", modifier: "ි"),
        VowelRule(latin: "e", independent: "එ", modifier: "ෙ"),
        VowelRule(latin: "u", independent: "උ", modifier: "ු"),
        VowelRule(latin: "o", independent: "ඔ", modifier: "ො"),
        VowelRule(latin: "I", independent: "ඓ", modifier: "ෛ")
    ]

    private static let CONSONANTS: [ConsonantRule] = [
        ConsonantRule(latin: "nng", uni: "ඟ"),
        ConsonantRule(latin: "nd", uni: "ඳ"),
        ConsonantRule(latin: "nND", uni: "ඬ"),
        ConsonantRule(latin: "mb", uni: "ඹ"),

        // velar
        ConsonantRule(latin: "k", uni: "ක"),
        ConsonantRule(latin: "kh", uni: "ඛ"),
        ConsonantRule(latin: "g", uni: "ග"),
        ConsonantRule(latin: "gh", uni: "ඝ"),

        // palatal
        ConsonantRule(latin: "ch", uni: "ච"),
        ConsonantRule(latin: "Ch", uni: "ඡ"),
        ConsonantRule(latin: "j", uni: "ජ"),
        ConsonantRule(latin: "q", uni: "ඣ"),
        ConsonantRule(latin: "GN", uni: "ඥ"),
        ConsonantRule(latin: "KN", uni: "ඤ"),

        // retroflex
        ConsonantRule(latin: "T", uni: "ට"),
        ConsonantRule(latin: "Th", uni: "ඨ"),
        ConsonantRule(latin: "D", uni: "ඩ"),
        ConsonantRule(latin: "Dh", uni: "ඪ"),
        ConsonantRule(latin: "N", uni: "ණ"),

        // dental
        ConsonantRule(latin: "t", uni: "ත"),
        ConsonantRule(latin: "th", uni: "ථ"),
        ConsonantRule(latin: "d", uni: "ද"),
        ConsonantRule(latin: "dh", uni: "ධ"),
        ConsonantRule(latin: "n", uni: "න"),

        // labial
        ConsonantRule(latin: "p", uni: "ප"),
        ConsonantRule(latin: "ph", uni: "ඵ"),
        ConsonantRule(latin: "b", uni: "බ"),
        ConsonantRule(latin: "bh", uni: "භ"),
        ConsonantRule(latin: "m", uni: "ම"),

        // semivowels
        ConsonantRule(latin: "Y", uni: "ය"),
        ConsonantRule(latin: "y", uni: "ය"),
        ConsonantRule(latin: "r", uni: "ර"),
        ConsonantRule(latin: "l", uni: "ල"),
        ConsonantRule(latin: "L", uni: "ළ"),
        ConsonantRule(latin: "Lu", uni: "ළු"),
        ConsonantRule(latin: "v", uni: "ව"),
        ConsonantRule(latin: "w", uni: "ව"),

        // sibilants / glottal
        ConsonantRule(latin: "sh", uni: "ශ"),
        ConsonantRule(latin: "Sh", uni: "ෂ"),
        ConsonantRule(latin: "s", uni: "ස"),
        ConsonantRule(latin: "h", uni: "හ"),
        ConsonantRule(latin: "f", uni: "ෆ")
    ]

    private static let LITERALS: [LiteralRule] = [
        LiteralRule(latin: "\\n", uni: "ං"),
        LiteralRule(latin: "\\h", uni: "ඃ"),
        LiteralRule(latin: "\\N", uni: "ඞ"),
        LiteralRule(latin: "\\R", uni: "ඍ"),
        LiteralRule(latin: "\\r", uni: "ර්" + "\u{200D}"),
        LiteralRule(latin: "R", uni: "ර්" + "\u{200D}"),
        LiteralRule(latin: "\\y", uni: "ය")
    ]

    private static let GAYANUKITTA: [GayanukittaRule] = [
        GayanukittaRule(latin: "ruu", uni: "ෲ"),
        GayanukittaRule(latin: "ru", uni: "ෘ")
    ]

    // MARK: - Sorted Rules (Precomputed on demand)

    private let vowelsByLength: [VowelRule]
    private let consonantsByLength: [ConsonantRule]
    private let literalsByLength: [LiteralRule]
    private let gayanukittaByLength: [GayanukittaRule]

    // MARK: - Init

    init() {
        self.vowelsByLength = Self.VOWELS.sorted { $0.latin.count > $1.latin.count }
        self.consonantsByLength = Self.CONSONANTS.sorted { $0.latin.count > $1.latin.count }
        self.literalsByLength = Self.LITERALS.sorted { $0.latin.count > $1.latin.count }
        self.gayanukittaByLength = Self.GAYANUKITTA.sorted { $0.latin.count > $1.latin.count }
    }

    // MARK: - TransliterationProvider Interface

    func candidates(for text: String, profile: LanguageProfile) async throws -> [TransliterationCandidate] {
        // This local provider strictly supports Sinhala transliteration.
        guard profile.id == "si", !text.isEmpty else { return [] }

        let converted = convert(text: text)
        return [TransliterationCandidate(text: converted, rank: 0)]
    }

    // MARK: - Core Conversion Logic

    private func convert(text: String) -> String {
        // Split by hyphen to support disambiguation boundaries.
        let segments = text.components(separatedBy: "-")
        return segments.map(convertSegment).joined()
    }

    private func convertSegment(_ segment: String) -> String {
        var out = ""
        var i = segment.startIndex

        while i < segment.endIndex {
            // 1. Literal escapes (anusvara, visarga, repaya, yansaya escape, ...)
            if let lit = matchAt(rules: literalsByLength, text: segment, index: i) {
                out.append(lit.uni)
                i = segment.index(i, offsetBy: lit.latin.count)
                continue
            }

            // 2. Consonant-led tokens
            if let cons = matchAt(rules: consonantsByLength, text: segment, index: i) {
                let after = segment.index(i, offsetBy: cons.latin.count)

                // 2a. consonant + gayanukitta (ru / ruu) -> vocalic-r vowel signs
                if let gaya = matchAt(rules: gayanukittaByLength, text: segment, index: after) {
                    out.append(cons.uni + gaya.uni)
                    i = segment.index(after, offsetBy: gaya.latin.count)
                    continue
                }

                // 2b. consonant + "r" (+ optional vowel) -> rakaransaya cluster (ක්ර)
                if after < segment.endIndex && segment[after] == "r" {
                    let next = segment.index(after, offsetBy: 1)
                    if let vowel = matchAt(rules: vowelsByLength, text: segment, index: next) {
                        out.append(cons.uni + Self.HAL_KIRIMA + "\u{200D}" + "ර" + vowel.modifier)
                        i = segment.index(next, offsetBy: vowel.latin.count)
                    } else {
                        out.append(cons.uni + Self.HAL_KIRIMA + "\u{200D}" + "ර")
                        i = next
                    }
                    continue
                }

                // 2c. consonant + vowel
                if let vowel = matchAt(rules: vowelsByLength, text: segment, index: after) {
                    out.append(cons.uni + vowel.modifier)
                    i = segment.index(after, offsetBy: vowel.latin.count)
                    continue
                }

                // 2d. bare consonant, no vowel follows -> hal kirima (vowel-killer)
                out.append(cons.uni + Self.HAL_KIRIMA)
                i = after
                continue
            }

            // 3. Standalone vowel (syllable-initial, no preceding consonant)
            if let vowel = matchAt(rules: vowelsByLength, text: segment, index: i) {
                out.append(vowel.independent)
                i = segment.index(i, offsetBy: vowel.latin.count)
                continue
            }

            // 4. Fallback: already-Sinhala characters, punctuation, spaces, etc.
            out.append(segment[i])
            i = segment.index(after: i)
        }

        return out
    }

    // MARK: - Substring Matching Helper

    private func matchAt<T: TransliterationRule>(rules: [T], text: String, index: String.Index) -> T? {
        for rule in rules {
            if let limit = text.index(index, offsetBy: rule.latin.count, limitedBy: text.endIndex),
               text[index..<limit] == rule.latin {
                return rule
            }
        }
        return nil
    }
}
