// Just enough of the app for `GroupedKeys.swift` and `GroupedDecoder.swift` to
// compile on their own.
//
// **Nothing here is under test and nothing here is guessed.** The rows come from
// `Bar/grouped/data/rows.json`, which `make-rows.py` extracts from
// `LetterLayouts.swift` and fails loudly if the Swift moved — so the letters this
// harness groups are the letters the keyboard ships. Everything else is glue that
// the two files touch but the algorithm does not depend on: a fold, a language
// tag, an absent resource.
//
// The alternative was copying `KeyboardLayout.swift`, which pulls in `SharedStore`,
// `Theme`, `KeySpec` and most of the package to check a partition function.

import Foundation

public enum KeyboardLanguage: String {
    case english, hebrew
    public var languageTag: String { self == .english ? "en" : "he" }
    public func uppercased(_ value: String) -> String { value.uppercased() }
}

public enum KeyboardLayout {
    public struct LetterLayout {
        public let rows: [[String]]
        public let hasCase: Bool
        public let alternates: [String: [String]]
        public init(keys rows: [[String]], hasCase: Bool = true, alternates: [String: [String]] = [:]) {
            self.rows = rows
            self.hasCase = hasCase
            self.alternates = alternates
        }
    }

    /// Filled from `data/rows.json` at start-up by `main.swift`.
    public static var letterLayouts: [KeyboardLanguage: LetterLayout] = [:]
}

enum SeedLanguageModel {
    static func fold(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "־", with: "-")
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }
    static func allWords(in language: KeyboardLanguage) -> [String] { [] }
}

enum GroupedLexiconResource {
    static func words(for language: KeyboardLanguage) -> [String] { [] }
    /// Nothing is bundled here, which is the truthful answer: this harness reads
    /// its lexicon from `data/`, and the generated resource is gitignored.
    static func isBundled(_ language: KeyboardLanguage) -> Bool { false }
}
