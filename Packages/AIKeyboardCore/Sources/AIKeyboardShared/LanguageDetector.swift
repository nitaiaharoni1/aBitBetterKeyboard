import Foundation

/// The writing systems one message can be in.
///
/// The raw values are ISO 15924 codes, which is not decoration: Apple reports a
/// `Locale.Language.script` with the same identifiers, so
/// `FoundationModelsEngine` maps its supported-language list into this enum by
/// `init(rawValue:)` rather than by a hand-written table that would go stale.
///
/// `other` is deliberately coarse and deliberately *not* treated as supported
/// anywhere: a script we cannot name is a script we cannot promise to preserve,
/// so it routes to the cloud the same way Hebrew does. That is the whole reason
/// the shipped scripts are named individually. When only Latin and Hebrew had
/// names, every other script in the world collapsed into `other` — and because
/// Apple's on-device list contains Japanese, Korean and Chinese, whose scripts
/// also had no name here, `other` ended up *inside* the supported set and
/// Cyrillic, Greek, Arabic and Devanagari all routed on-device to a model with
/// no word of any of them.
public enum TextScript: String, Sendable, Hashable, CaseIterable {
    case latin = "Latn"
    case hebrew = "Hebr"
    case arabic = "Arab"
    case cyrillic = "Cyrl"
    case greek = "Grek"
    case devanagari = "Deva"
    case georgian = "Geor"
    case tamil = "Taml"
    case thaana = "Thaa"
    case other = "Zzzz"

    /// Whether text in this script runs right to left.
    ///
    /// The one place this is decided. `KeyboardLanguage.isRightToLeft` reads it,
    /// so Persian is right-to-left because it is written in the Arabic script,
    /// not because anybody remembered to add it to a list. Thaana is here for
    /// the same reason and is not Arabic: Dhivehi is written right to left in an
    /// alphabet of its own.
    public var isRightToLeft: Bool {
        switch self {
        case .hebrew, .arabic, .thaana: return true
        case .latin, .cyrillic, .greek, .devanagari, .georgian, .tamil, .other: return false
        }
    }

    /// How to name this script to the user. `other` has no name on purpose —
    /// the honest thing to say about a script we did not recognise is nothing.
    public var displayName: String {
        switch self {
        case .latin: return "Latin"
        case .hebrew: return "Hebrew"
        case .arabic: return "Arabic"
        case .cyrillic: return "Cyrillic"
        case .greek: return "Greek"
        case .devanagari: return "Devanagari"
        case .georgian: return "Georgian"
        case .tamil: return "Tamil"
        case .thaana: return "Thaana"
        case .other: return "This language"
        }
    }

    /// The first three letters of this script, which is how iOS labels the key
    /// back to the letters plane. A property of the script rather than of the
    /// language: every Cyrillic keyboard says АБВ. `KeyboardLanguage` overrides
    /// it only where a language spells its own alphabet differently, as Persian
    /// does with ابپ.
    public var lettersPlaneLabel: String {
        switch self {
        case .latin, .other: return "ABC"
        case .hebrew: return "אבג"
        case .arabic: return "ابج"
        case .cyrillic: return "АБВ"
        case .greek: return "ΑΒΓ"
        case .devanagari: return "अआइ"
        case .georgian: return "აბგ"
        case .tamil: return "அஆஇ"
        case .thaana: return "ހށނ"
        }
    }
}

/// Language and script detection shared by the AI engines and the dictation panel.
///
/// Deliberately separate from `SuggestionEngine.dominantLanguage`, which
/// answers a narrower question — which of the two keyboard layouts a run of
/// characters belongs to — and is still what the suggestion bar wants.
///
/// **The `NaturalLanguage` half stayed in `AIKeyboardCore`.** `scripts(in:)` is
/// pure `CharacterSet` arithmetic and the screen reader calls it, so it has to
/// be reachable from the broadcast upload extension; `dominantLanguageTag(in:)`
/// needs `NLLanguageRecognizer` and nothing in the capture process asks for it.
/// Splitting the enum keeps one more framework out of a process capped at
/// ~50 MB, and costs one `extension` in `AIKeyboardCore/LanguageDetector.swift`.
public enum LanguageDetector {

    /// Every script present in the text, ignoring digits, punctuation and emoji.
    ///
    /// Routing reads this rather than a single dominant language, because the
    /// mixed sentences this product exists for are usually mostly Latin with the
    /// error in the Hebrew: "Can you check the deployment on staging, אני חושב
    /// שיש שם באג בבקשא" is four fifths Latin characters and the typo is Hebrew.
    /// A router that picked one winner would hand that to an English-only model.
    public static func scripts(in text: String) -> Set<TextScript> {
        var found: Set<TextScript> = []
        for scalar in text.unicodeScalars where isScriptBearing(scalar) {
            found.insert(script(of: scalar))
        }
        return found
    }

    /// Whether this character says anything about which script the text is in.
    ///
    /// **The spacing modifier letters are the exception, and they are the whole
    /// reason this is a function.** `ʻ` (U+02BB) and `ʼ` (U+02BC) are `Lm`, so
    /// `CharacterSet.letters` contains them, and they are letters — the ʻokina is
    /// a consonant of Hawaiian, Samoan and Tongan, and `ʼ` is a letter of the
    /// Ukrainian alphabet (`зʼїзд`). But the same code point serves all four, so
    /// counting it as Latin makes every Ukrainian word carrying one look like a
    /// code-switched sentence, and counting it as Cyrillic does the same to
    /// Hawaiian. It belongs to whatever it is written beside, which for a
    /// detector means it belongs to nothing.
    private static func isScriptBearing(_ scalar: Unicode.Scalar) -> Bool {
        guard CharacterSet.letters.contains(scalar) else { return false }
        return !(0x02B0...0x02FF).contains(scalar.value)
    }

    /// The script one character belongs to, or nil when it is not a letter.
    ///
    /// Exposed because `SuggestionEngine` needs the *count* per script rather
    /// than the set — which language a run of text is mostly in is a different
    /// question from which languages appear in it — and counting through
    /// `scripts(in:)` would mean a `Set` allocation per character on a path that
    /// runs on every keystroke.
    public static func script(ofLetter scalar: Unicode.Scalar) -> TextScript? {
        guard isScriptBearing(scalar) else { return nil }
        return script(of: scalar)
    }

    private static func script(of scalar: Unicode.Scalar) -> TextScript {
        switch scalar.value {
        // Hebrew, plus the alphabetic presentation forms block that holds the
        // ligatures some keyboards emit.
        case 0x0590...0x05FF, 0xFB1D...0xFB4F:
            return .hebrew
        // Basic Latin through Latin Extended-B, then IPA Extensions and Latin
        // Extended Additional. IPA Extensions is not a phonetician's block here:
        // it is where the letters West African orthographies use live, and
        // without it Hausa's ɓ and ɗ, Azerbaijani's ə and Yoruba's ɛ and ɔ are
        // all reported as a script this keyboard cannot name.
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F, 0x0250...0x02AF,
            0x1E00...0x1EFF:
            return .latin
        // Greek and Coptic, then Greek Extended — which sits *above* Latin
        // Extended Additional, so the two ranges must stay in this order.
        case 0x0370...0x03FF, 0x1F00...0x1FFF:
            return .greek
        // Cyrillic, its supplement, and the two historic extensions.
        case 0x0400...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
            return .cyrillic
        // Arabic, Arabic Supplement, Arabic Extended-A and B, and both
        // presentation-form blocks. Persian, Urdu and Pashto all live in here:
        // this is a script, not a language.
        case 0x0600...0x06FF, 0x0750...0x077F, 0x0870...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return .arabic
        // Devanagari and its extended block.
        case 0x0900...0x097F, 0xA8E0...0xA8FF:
            return .devanagari
        // Thaana, which Dhivehi is written in. Above the Arabic ranges rather
        // than inside them: it is a right-to-left alphabet of its own, and the
        // Dhivehi keyboard's own vowels live here.
        case 0x0780...0x07BF:
            return .thaana
        // Tamil, plus the supplement block that holds its fractions and symbols.
        case 0x0B80...0x0BFF, 0x11FC0...0x11FFF:
            return .tamil
        // Georgian: Mkhedruli and Asomtavruli, then Mtavruli — which sits in a
        // separate block a long way above, so both ranges are needed.
        case 0x10A0...0x10FF, 0x1C90...0x1CBF, 0x2D00...0x2D2F:
            return .georgian
        default:
            return .other
        }
    }
}
