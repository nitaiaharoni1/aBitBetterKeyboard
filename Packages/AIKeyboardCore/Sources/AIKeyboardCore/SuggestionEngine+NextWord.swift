import Foundation

extension SuggestionEngine {

    // MARK: Prediction of the next word
    //
    // Next-word-suggestions is the case documented at the top of the main file
    // as genuinely unavailable: no public on-device API predicts a word from
    // nothing typed. This table is deliberately small — the handful of openers
    // a chat keyboard sees constantly — and is disclosed as a table, not
    // presented as prediction.

    private static let englishNextWord: [String: [String]] = [
        "i": ["think", "would", "will"],
        "to": ["know", "see", "make"],
        "would": ["like", "be", "you"],
        "like": ["to", "this", "that"],
        "we": ["should", "can", "need"],
        "should": ["be", "do", "have"],
        "can": ["you", "we", "be"],
        "you": ["can", "want", "know"],
        "the": ["team", "meeting", "same"],
        "is": ["not", "the", "a"],
        "it": ["is", "was", "would"],
        "for": ["the", "you", "me"],
        "this": ["is", "one", "week"],
        "let": ["me", "us", "them"],
        "thanks": ["for", "a", "so"]
    ]

    private static let hebrewNextWord: [String: [String]] = [
        "אני": ["חושב", "רוצה", "אשלח"],
        "אנחנו": ["צריכים", "נדבר", "יכולים"],
        "צריך": ["לבדוק", "לשלוח", "להיות"],
        "רוצה": ["לדבר", "לשאול", "לבדוק"],
        "יש": ["לי", "לנו", "משהו"],
        "מה": ["קורה", "השעה", "נשמע"],
        "את": ["ה", "זה", "כל"],
        "לא": ["בטוח", "נכון", "יודע"],
        "תודה": ["רבה", "לך", "על"],
        "אפשר": ["לבדוק", "לדבר", "מחר"],
        "בוא": ["נדבר", "נעשה", "נבדוק"]
    ]

    private static let defaultEnglish = ["I", "The", "We"]
    private static let defaultHebrew = ["אני", "מה", "תודה"]

    /// The two languages this table was written for. It is a hand-written table,
    /// not a model, so the honest thing to do for the twelve languages it does
    /// not cover is to offer nothing rather than to offer English words under a
    /// Greek keyboard.
    private static let nextWordTables: [KeyboardLanguage: [String: [String]]] = [
        .english: englishNextWord,
        .hebrew: hebrewNextWord
    ]

    private static let nextWordDefaults: [KeyboardLanguage: [String]] = [
        .english: defaultEnglish,
        .hebrew: defaultHebrew
    ]

    static func nextWordSuggestions(
        context: String,
        contextLanguage: KeyboardLanguage
    ) -> [Suggestion] {
        guard let table = nextWordTables[contextLanguage],
            let defaults = nextWordDefaults[contextLanguage]
        else { return [] }

        let words =
            context
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard let last = words.last?.trimmingCharacters(in: .punctuationCharacters).lowercased(),
            !last.isEmpty, let hits = table[last]
        else {
            return defaults.map { Suggestion(text: $0, language: contextLanguage) }
        }
        return hits.map { Suggestion(text: $0, language: contextLanguage) }
    }
}
