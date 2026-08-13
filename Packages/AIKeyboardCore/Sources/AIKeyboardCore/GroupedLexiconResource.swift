import Foundation
import os

/// The bundled word list `GroupedDecoder` indexes by keystroke.
///
/// One word per line, **descending frequency**, so the line number is the rank
/// and no count has to be stored. Plain text rather than JSON because it is tens
/// of thousands of lines: splitting on newlines is a single pass, where
/// `JSONDecoder` over the same data builds an array of boxed strings and costs
/// several times as much on a keyboard's first keystroke.
///
/// Built by `Scripts/generate-grouped-lexicon.py` from the Leipzig Corpora
/// Collection (CC BY 4.0). Attribution is `GroupedLexicon-NOTICE.txt`. When a
/// list is missing, `GroupedDecoder` falls back to `SeedLanguageModel` and
/// reports `.seedOnly`.
enum GroupedLexiconResource {

    static func words(for language: KeyboardLanguage) -> [String] {
        cache.withLock { store in
            if let known = store[language.languageTag] { return known }
            let loaded = load(language)
            store[language.languageTag] = loaded
            return loaded
        }
    }

    /// Whether a real list is bundled for this language. Read by Settings so the
    /// screen can say the feature is running on the fallback instead of letting
    /// somebody discover it by typing.
    static func isBundled(_ language: KeyboardLanguage) -> Bool {
        !words(for: language).isEmpty
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [String: [String]]())

    private static let logger = Logger(
        subsystem: "com.nitai.aikeyboard", category: "GroupedLexicon")

    private static func load(_ language: KeyboardLanguage) -> [String] {
        guard
            let url = Bundle.module.url(
                forResource: "GroupedLexicon-\(language.languageTag)", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            logger.notice(
                """
                GroupedLexicon-\(language.languageTag, privacy: .public).txt absent — \
                grouped keys will decode from the seed list only. Run \
                Scripts/generate-grouped-lexicon.py.
                """)
            return []
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }
}
