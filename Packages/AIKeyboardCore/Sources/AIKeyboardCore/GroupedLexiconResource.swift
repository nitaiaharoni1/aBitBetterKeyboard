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
    /// somebody discover it by typing. URL only: loading the list just to
    /// decide whether to hide a warning is a hitch on a screen that is not typing.
    static func isBundled(_ language: KeyboardLanguage) -> Bool {
        resourceURL(for: language) != nil
    }

    /// The head of the list, uncached, for a reader that only needs the commonest
    /// few thousand rather than every rank.
    ///
    /// **Deliberately outside `cache`.** That cache exists to hold the full
    /// 50,000-entry list for grouped-key decoding, which needs every rank.
    /// `TypoLexicon` only ever wants the commonest `depth` words for a
    /// keystroke-time typo search, and routing that through `cache` would pull
    /// 50,000 boxed strings into a keyboard extension to serve a caller that
    /// asked for a few thousand. This re-reads and re-splits the file on every
    /// call; `TypoLexicon` is the one caller and it loads once, lazily, and
    /// holds its own compact form afterwards.
    static func head(for language: KeyboardLanguage, limit: Int) -> [String] {
        Array(uncachedWords(for: language).prefix(limit))
    }

    /// Every form in the list, uncached, for a reader that needs the whole thing
    /// once and holds its own derived form afterwards.
    ///
    /// Same reason as `head(for:limit:)` for staying outside `cache`: that cache
    /// hands back 50,000 boxed strings and keeps them for the life of the
    /// process, which is the right trade for grouped keys, which index them on
    /// every keystroke, and the wrong one for a caller that reads the list once
    /// at load and wants a `Set` out of it.
    static func uncachedWords(for language: KeyboardLanguage) -> [String] {
        load(language)
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [String: [String]]())

    private static let logger = Logger(
        subsystem: "com.nitai.aikeyboard", category: "GroupedLexicon")

    private static func load(_ language: KeyboardLanguage) -> [String] {
        guard
            let url = resourceURL(for: language),
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

    private static func resourceURL(for language: KeyboardLanguage) -> URL? {
        #if HARNESS
        // `Bundle.module` is synthesised by SwiftPM and does not exist when
        // Bar/typing/harness/run.sh compiles these files loose against the
        // simulator SDK. The harness passes the directory holding the two
        // `.txt` files instead, the same shape `SeedLanguageModel.payloadData()`
        // already takes for `LanguageModel.json`.
        guard let directory = ProcessInfo.processInfo.environment["GROUPED_LEXICON_DIR"] else {
            return nil
        }
        return URL(fileURLWithPath: directory)
            .appendingPathComponent("GroupedLexicon-\(language.languageTag).txt")
        #else
        return Bundle.module.url(
            forResource: "GroupedLexicon-\(language.languageTag)", withExtension: "txt")
        #endif
    }
}
