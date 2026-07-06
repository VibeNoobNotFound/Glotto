import Foundation

/// Direction the script flows — used to mirror the panel layout for RTL scripts (Arabic, Hebrew, etc.)
enum ScriptDirection: String, Codable, Sendable {
    case leftToRight
    case rightToLeft
}

/// A language profile is the single unit of configuration that makes Glotto language-agnostic.
/// Every data-model and service that is tempted to hardcode "Sinhala" should reference a profile value instead.
struct LanguageProfile: Identifiable, Codable, Equatable, Sendable {
    /// Stable identifier used as a storage/dictionary key (e.g. "si").
    let id: String

    /// Human-readable display name shown in UI (e.g. "Sinhala").
    let displayName: String

    /// The `itc` parameter value for Google Input Tools (e.g. "si-t-i0-und").
    let googleInputToolsCode: String

    /// Script directionality — used for panel text alignment and future RTL support.
    let scriptDirection: ScriptDirection

    /// Characters that terminate a word and should trigger a commit.
    /// Defaults to `.whitespacesAndNewlines` plus common punctuation.
    let wordBoundaryCharacters: CharacterSet

    /// Whether this profile is active in composition mode.
    var isEnabled: Bool

    // MARK: - Codable

    // CharacterSet is not Codable by default, so we persist it as a comma-separated
    // list of Unicode scalar values. For the built-in profiles this is irrelevant
    // (they're never decoded from JSON in Phase 1), but the Codable conformance
    // keeps the Settings persistence path clean for future custom profiles.
    enum CodingKeys: String, CodingKey {
        case id, displayName, googleInputToolsCode, scriptDirection, isEnabled
        case wordBoundaryScalars
    }

    init(
        id: String,
        displayName: String,
        googleInputToolsCode: String,
        scriptDirection: ScriptDirection = .leftToRight,
        wordBoundaryCharacters: CharacterSet = .defaultWordBoundaries,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.googleInputToolsCode = googleInputToolsCode
        self.scriptDirection = scriptDirection
        self.wordBoundaryCharacters = wordBoundaryCharacters
        self.isEnabled = isEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        googleInputToolsCode = try c.decode(String.self, forKey: .googleInputToolsCode)
        scriptDirection = try c.decode(ScriptDirection.self, forKey: .scriptDirection)
        isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        let scalars = try c.decode([UInt32].self, forKey: .wordBoundaryScalars)
        var cs = CharacterSet()
        for v in scalars {
            if let scalar = Unicode.Scalar(v) { cs.insert(scalar) }
        }
        wordBoundaryCharacters = cs
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(googleInputToolsCode, forKey: .googleInputToolsCode)
        try c.encode(scriptDirection, forKey: .scriptDirection)
        try c.encode(isEnabled, forKey: .isEnabled)
        var scalars: [UInt32] = []
        for plane: UInt8 in 0...16 {
            for code in UInt32(plane) << 16 ..< (UInt32(plane) << 16) + 0xFFFF {
                if let s = Unicode.Scalar(code), wordBoundaryCharacters.contains(s) {
                    scalars.append(code)
                }
            }
        }
        try c.encode(scalars, forKey: .wordBoundaryScalars)
    }
}

extension CharacterSet {
    /// Word boundary = whitespace/newline + common punctuation that ends a word mid-sentence.
    static let defaultWordBoundaries: CharacterSet = {
        var cs = CharacterSet.whitespacesAndNewlines
        cs.formUnion(CharacterSet(charactersIn: ".,;:!?\"'()[]{}"))
        return cs
    }()
}

// MARK: - Built-in profiles

extension LanguageProfile {
    /// The only shipped profile in Phase 1.
    /// Data is language-specific; code that consumes it is not.
    static let sinhala = LanguageProfile(
        id: "si",
        displayName: "Sinhala",
        googleInputToolsCode: "si-t-i0-und",
        scriptDirection: .leftToRight
    )

    /// All profiles Glotto ships with. Phase 1: one item. Phase N: this list grows without code changes.
    static let builtIn: [LanguageProfile] = [.sinhala]
}
