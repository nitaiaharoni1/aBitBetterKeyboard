import Foundation

/// One word the keyboard has seen this person type, with how often.
public struct LearnedWord: Identifiable, Equatable, Sendable {
    public let word: String
    public let count: Int
    public let language: KeyboardLanguage
    public var id: String { "\(language.languageTag)\u{1F}\(word)" }
}

enum PersonalStoreCodingKeys: String, CodingKey { case unigrams, bigrams, selected, automatic, rejected, tokens }
enum PersonalStoreLegacyCodingKeys: String, CodingKey { case phones }

extension PersonalLanguageModel {
    enum LearningSource: Sendable { case typed, selectedSuggestion, automatic }
    struct VerbatimToken: Codable {
        var kind: PersonalToken.Kind
        var text: String
        var count: Int
        var languageTag: String
    }
    struct LegacyPhone: Decodable {
        var text: String
        var count: Int
        var languageTag: String
    }
    struct FileStamp: Equatable {
        let modified: Date
        let size: Int
    }

    public func learnedWords() -> [LearnedWord] {
        var out: [LearnedWord] = []
        for (tag, counts) in store.unigrams {
            guard let language = KeyboardLanguage(languageTag: tag) else { continue }
            for (word, count) in counts {
                out.append(LearnedWord(word: word, count: count, language: language))
            }
        }
        out += store.tokens.values.compactMap { token in
            guard let language = KeyboardLanguage(languageTag: token.languageTag) else { return nil }
            return LearnedWord(word: token.text, count: token.count, language: language)
        }
        return out.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.language.displayName != $1.language.displayName {
                return $0.language.displayName < $1.language.displayName
            }
            return $0.word < $1.word
        }
    }

    func allWords(in language: KeyboardLanguage) -> [String] {
        guard let counts = store.unigrams[language.languageTag] else { return [] }
        return counts.filter { isReadable($0.key, count: $0.value, in: language) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
    }
}
