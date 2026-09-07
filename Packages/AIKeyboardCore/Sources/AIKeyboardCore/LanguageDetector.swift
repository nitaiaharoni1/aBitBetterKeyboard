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
    /// too few letters to tell. Used to pick a prompt.
    public static func dominantLanguageTag(in text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    private struct SuggestionLanguageKey: Hashable {
        let context: String
        let candidates: [KeyboardLanguage]
    }

    private struct SuggestionLanguageResult {
        let language: KeyboardLanguage?
    }

    @MainActor private static var suggestionCache: [SuggestionLanguageKey: SuggestionLanguageResult] = [:]
    @MainActor private static var suggestionCacheOrder: [SuggestionLanguageKey] = []

    @MainActor
    static func suggestionLanguage(
        in context: String, among candidates: [KeyboardLanguage]
    ) -> KeyboardLanguage? {
        guard candidates.count > 1 else { return candidates.first }
        let bounded = String(context.suffix(240))
        let key = SuggestionLanguageKey(context: bounded, candidates: candidates)
        if let cached = suggestionCache[key] { return cached.language }
        let script = candidates[0].script
        var words: [String] = []
        for token in bounded.split(whereSeparator: \.isWhitespace).reversed() {
            let scripts = scripts(in: String(token))
            guard scripts.isEmpty || scripts == [script] else { break }
            if !scripts.isEmpty { words.append(String(token)) }
            if words.count == 8 { break }
        }
        let sample = words.reversed().joined(separator: " ")
        var detected: KeyboardLanguage?
        if words.count >= 3 && sample.filter(\.isLetter).count >= 12 {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = candidates.map { NLLanguage(rawValue: $0.languageTag) }
            recognizer.processString(sample)
            let hypotheses = recognizer.languageHypotheses(withMaximum: candidates.count)
                .sorted {
                    $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value
                }
            if let best = hypotheses.first, best.value >= 0.8,
                best.value - (hypotheses.dropFirst().first?.value ?? 0) >= 0.2
            {
                detected = candidates.first { $0.languageTag == best.key.rawValue }
            }
        }
        if suggestionCacheOrder.count == 16 {
            suggestionCache.removeValue(forKey: suggestionCacheOrder.removeFirst())
        }
        suggestionCacheOrder.append(key)
        suggestionCache[key] = SuggestionLanguageResult(language: detected)
        return detected
    }
}
