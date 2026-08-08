import Foundation

/// The writing systems one message can be in. `other` is deliberately coarse:
/// a script we cannot name is a script we cannot promise to preserve, so it
/// routes the same way Hebrew does.
public enum TextScript: String, Sendable, Hashable {
    case latin = "Latn"
    case hebrew = "Hebr"
    case other = "Zzzz"
}

/// Language and script detection shared by the AI engines and the dictation panel.
///
/// Deliberately separate from `MockSuggestionEngine.dominantLanguage`, which
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
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            found.insert(script(of: scalar))
        }
        return found
    }

    private static func script(of scalar: Unicode.Scalar) -> TextScript {
        switch scalar.value {
        // Hebrew, plus the alphabetic presentation forms block that holds the
        // ligatures some keyboards emit.
        case 0x0590...0x05FF, 0xFB1D...0xFB4F:
            return .hebrew
        // Basic Latin through Latin Extended-B, Latin Extended Additional.
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F, 0x1E00...0x1EFF:
            return .latin
        default:
            return .other
        }
    }
}
