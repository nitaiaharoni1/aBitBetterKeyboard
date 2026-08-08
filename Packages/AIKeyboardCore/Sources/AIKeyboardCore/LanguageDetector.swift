import Foundation
import NaturalLanguage

/// The half of `LanguageDetector` that needs `NaturalLanguage`.
///
/// The enum and `scripts(in:)` live in `AIKeyboardShared`, because the screen
/// reader calls them and the screen reader now runs inside the broadcast upload
/// extension. This stayed here so that process does not link a framework nothing
/// in it asks for.
extension LanguageDetector {

    /// The dominant natural language as a BCP-47 tag, or nil when the text has
    /// too few letters to tell. Used to pick a prompt, never to route.
    public static func dominantLanguageTag(in text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }
}
