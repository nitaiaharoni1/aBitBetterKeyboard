import Foundation

// MARK: - Suggestions
//
// Stands in for the local typing + prediction engines described in the plan.
// Deterministic, no network, no model. Good enough to judge the interaction;
// nothing here should survive into the real product.

public enum MockSuggestionEngine {

    private static let englishVocabulary: [String] = [
        "about", "after", "again", "already", "always", "another", "answer", "anything",
        "back", "because", "before", "believe", "better", "between", "bring",
        "call", "check", "come", "confirm", "could", "course",
        "deadline", "decide", "design", "different", "discuss", "does", "done", "down",
        "each", "early", "enough", "even", "every", "everything", "exactly",
        "feedback", "find", "first", "follow", "friday", "from",
        "give", "going", "good", "great",
        "handle", "happy", "have", "here", "however",
        "idea", "into", "issue",
        "just",
        "keep", "kind", "know",
        "last", "later", "leave", "let", "like", "look",
        "made", "make", "maybe", "mean", "meet", "meeting", "mention", "might", "monday",
        "morning", "most", "move", "much", "must",
        "need", "never", "next", "nice", "night", "nothing", "now",
        "office", "only", "other", "over",
        "people", "perfect", "person", "place", "please", "point", "possible", "presentation",
        "probably", "problem", "project",
        "question", "quick",
        "ready", "really", "reason", "remember", "review", "right",
        "same", "schedule", "send", "should", "since", "some", "something", "soon",
        "sorry", "sounds", "sprint", "start", "still", "sure",
        "take", "talk", "team", "than", "thanks", "that", "their", "them", "then",
        "there", "these", "they", "thing", "think", "this", "those", "though",
        "through", "time", "today", "together", "tomorrow", "tonight", "true", "try",
        "understand", "until", "update", "used",
        "very",
        "wait", "want", "week", "well", "were", "what", "when", "where", "which",
        "while", "will", "with", "work", "would", "write",
        "year", "yesterday", "your"
    ]

    private static let hebrewVocabulary: [String] = [
        "אבל", "אולי", "אוקיי", "אחר", "אחרי", "איזה", "איך", "אין", "אישור", "אליך",
        "אמרתי", "אנחנו", "אני", "אפשר", "אתה", "אתמול",
        "באמת", "בבקשה", "בוקר", "ביום", "בכל", "בסדר", "בערב", "בקרוב", "בשביל",
        "גם", "גמר",
        "דבר", "דוגמה", "דחוף",
        "היום", "הכל", "הרבה", "השבוע",
        "ואז", "ולא",
        "זה", "זמן",
        "חושב", "חושבת", "חוזר", "חייב", "חשוב",
        "יודע", "יודעת", "יום", "יותר", "ישיבה",
        "כאן", "כבר", "כדי", "כותב", "כלום", "כמה", "כן",
        "לא", "לבדוק", "לדבר", "להיות", "להגיד", "לוקח", "לך", "למה", "לפני", "לשלוח",
        "מה", "מחר", "מישהו", "מצוין", "מקווה", "משהו",
        "נהדר", "נכון", "נשמע",
        "סבבה", "סליחה",
        "עדיין", "עובד", "עוד", "עכשיו", "ערב",
        "פגישה", "פשוט",
        "צריך", "צריכה",
        "קצת",
        "רגע", "רוצה", "רק",
        "שאלה", "שבוע", "שוב", "שולח", "שיהיה", "שלום", "שלח", "שלי", "שלך",
        "תודה", "תזכורת", "תשובה"
    ]

    /// English words Israelis type inside Hebrew sentences without thinking about it.
    /// These are the reason a single-language prediction engine feels broken here.
    private static let codeSwitchVocabulary: [String] = [
        "backlog", "brief", "call", "deadline", "demo", "design", "document", "feedback",
        "follow-up", "invite", "meeting", "presentation", "product", "review", "roadmap",
        "scope", "slack", "sprint", "standup", "sync", "template", "ticket", "update"
    ]

    /// Next-word predictions with nothing typed yet. Keyed by the last word.
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

    /// Three candidates for the suggestion bar.
    ///
    /// - Parameters:
    ///   - prefix: the word currently being typed, may be empty
    ///   - context: everything before the current word
    ///   - languages: the languages the user turned on, in priority order
    public static func suggestions(
        prefix: String,
        context: String,
        languages: [KeyboardLanguage]
    ) -> [Suggestion] {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextLanguage = dominantLanguage(in: context) ?? languages.first ?? .english

        if trimmedPrefix.isEmpty {
            let results = nextWordSuggestions(
                context: context, contextLanguage: contextLanguage, languages: languages)
            // Nothing is being typed, so nothing is at risk of being replaced;
            // highlight the middle candidate the way the system keyboard does.
            return markDefault(results, at: min(1, results.count - 1))
        }

        let results = completions(for: trimmedPrefix, contextLanguage: contextLanguage, languages: languages)
        return markDefault(results, at: shouldAutocorrect(trimmedPrefix, results: results) ? 1 : 0)
    }

    /// Whether pressing space should replace what was typed.
    ///
    /// Defaulting to "yes" is how autocorrect earns its reputation: one letter in,
    /// and `I` turns into `idea`. Only override the user when there is a real
    /// reason to think they mis-typed.
    private static func shouldAutocorrect(_ prefix: String, results: [Suggestion]) -> Bool {
        guard results.count > 1 else { return false }
        let lower = prefix.lowercased()

        // A missing apostrophe is unambiguous, so correct it at any length.
        if contractions[lower] != nil { return true }

        // Otherwise wait until enough letters are in to be confident, and never
        // correct something that is already a word.
        return prefix.count >= 4 && !isKnownWord(lower)
    }

    private static func isKnownWord(_ lower: String) -> Bool {
        englishVocabulary.contains(lower)
            || hebrewVocabulary.contains(lower)
            || codeSwitchVocabulary.contains(lower)
    }

    // MARK: Completion of the word being typed

    private static func completions(
        for prefix: String,
        contextLanguage: KeyboardLanguage,
        languages: [KeyboardLanguage]
    ) -> [Suggestion] {
        let typedLanguage = script(of: prefix) ?? contextLanguage
        let lower = prefix.lowercased()
        var out: [Suggestion] = []

        // The literal keystrokes always stay available, so the engine can never
        // trap the user into a word they did not want.
        out.append(Suggestion(text: prefix, language: typedLanguage))

        // A dropped apostrophe is the most common thing worth fixing, and it
        // should sit directly next to what was typed.
        if let contraction = contractions[lower] {
            out.append(Suggestion(text: matchCase(of: prefix, applyingTo: contraction), language: .english))
        }

        if typedLanguage == .hebrew {
            out +=
                hebrewVocabulary
                .filter { $0.hasPrefix(prefix) && $0 != prefix }
                .prefix(2)
                .map { Suggestion(text: $0, language: .hebrew) }
        } else {
            // Latin letters typed inside a Hebrew sentence: the loanword list goes
            // first, because that is almost always what is happening.
            if contextLanguage == .hebrew && languages.contains(.hebrew) {
                out +=
                    codeSwitchVocabulary
                    .filter { $0.hasPrefix(lower) && $0 != lower }
                    .prefix(2)
                    .map { Suggestion(text: $0, language: .english) }
            }
            out +=
                englishVocabulary
                .filter { $0.hasPrefix(lower) && $0 != lower }
                .prefix(3)
                .map { Suggestion(text: matchCase(of: prefix, applyingTo: $0), language: .english) }
        }

        return dedupe(out, limit: 3)
    }

    // MARK: Prediction of the next word

    private static func nextWordSuggestions(
        context: String,
        contextLanguage: KeyboardLanguage,
        languages: [KeyboardLanguage]
    ) -> [Suggestion] {
        let words =
            context
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard let last = words.last?.trimmingCharacters(in: .punctuationCharacters).lowercased(),
            !last.isEmpty
        else {
            let defaults = contextLanguage == .hebrew ? defaultHebrew : defaultEnglish
            return defaults.map { Suggestion(text: $0, language: contextLanguage) }
        }

        let table = contextLanguage == .hebrew ? hebrewNextWord : englishNextWord
        if let hits = table[last] {
            return hits.map { Suggestion(text: $0, language: contextLanguage) }
        }

        let defaults = contextLanguage == .hebrew ? defaultHebrew : defaultEnglish
        return defaults.map { Suggestion(text: $0, language: contextLanguage) }
    }

    // MARK: Script detection

    /// Which language a run of text is written in, ignoring digits and punctuation.
    public static func dominantLanguage(in text: String) -> KeyboardLanguage? {
        var hebrew = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if (0x0590...0x05FF).contains(scalar.value) {
                hebrew += 1
            } else if CharacterSet.letters.contains(scalar) {
                latin += 1
            }
        }
        if hebrew == 0 && latin == 0 { return nil }
        return hebrew >= latin ? .hebrew : .english
    }

    private static func script(of word: String) -> KeyboardLanguage? {
        dominantLanguage(in: word)
    }

    private static func matchCase(of source: String, applyingTo candidate: String) -> String {
        guard let first = source.first, first.isUppercase else { return candidate }
        return candidate.prefix(1).uppercased() + candidate.dropFirst()
    }

    private static func dedupe(_ items: [Suggestion], limit: Int) -> [Suggestion] {
        var seen = Set<String>()
        var out: [Suggestion] = []
        for item in items where !seen.contains(item.text.lowercased()) {
            seen.insert(item.text.lowercased())
            out.append(item)
            if out.count == limit { break }
        }
        return out
    }

    private static func markDefault(_ items: [Suggestion], at defaultIndex: Int) -> [Suggestion] {
        guard !items.isEmpty else { return items }
        let index = max(0, min(defaultIndex, items.count - 1))
        return items.enumerated().map { position, item in
            Suggestion(text: item.text, language: item.language, isDefault: position == index)
        }
    }

    /// Offered as autocorrections in the suggestion bar.
    static let contractions: [String: String] = [
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "cant": "can't",
        "wont": "won't", "isnt": "isn't", "wasnt": "wasn't", "arent": "aren't",
        "werent": "weren't", "couldnt": "couldn't", "shouldnt": "shouldn't",
        "wouldnt": "wouldn't", "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't",
        "im": "I'm", "ive": "I've", "ill": "I'll", "id": "I'd",
        "youre": "you're", "youve": "you've", "youll": "you'll",
        "theyre": "they're", "theyve": "they've", "thats": "that's",
        "whats": "what's", "hes": "he's", "shes": "she's", "lets": "let's",
        "its": "it's", "theres": "there's", "heres": "here's"
    ]
}

// MARK: - Screen context
//
// Stands in for the ReplayKit broadcast session that runs in the main app and
// hands OCR'd text to the keyboard through the App Group. Nothing here captures
// anything; these are the messages a session would have read off the screen.
// (Capture API depends on deployment target: ReplayKit on iOS <=26, reportedly
// ScreenCaptureKit on iOS 27+. See ScreenContextSession.swift.)

public enum MockScreenContext {

    private static let samples: [ScreenContext] = [
        ScreenContext(
            appName: "WhatsApp",
            appIcon: "message.fill",
            sender: "שרה",
            message: "היי, אתה פנוי לארוחת ערב הערב? חשבתי על המקום החדש ביפו",
            language: .hebrew
        ),
        ScreenContext(
            appName: "Slack",
            appIcon: "number",
            sender: "Daniel",
            message: "Can you take the standup tomorrow? I have a conflict at 9.",
            language: .english
        ),
        ScreenContext(
            appName: "Messages",
            appIcon: "bubble.left.fill",
            sender: "Maya",
            message: "שלחתי לך את ה-deck, אפשר feedback עד מחר בצהריים?",
            language: .hebrew
        )
    ]

    public static func sample(at index: Int) -> ScreenContext {
        samples[index % samples.count]
    }

    public static var sampleCount: Int { samples.count }

    /// How long the picker plus stream start-up takes before frames arrive.
    public static let startupDelay: Duration = .milliseconds(900)
    /// How long the session watches before it reads something repliable.
    public static let firstReadDelay: Duration = .milliseconds(1400)
}

// MARK: - Dictation
//
// A scripted transcript that streams in word by word. The real thing lives in the
// main app behind AVAudioSession; nothing here touches the microphone.

public enum MockDictation {

    public struct Script: Sendable {
        public let words: [String]
        public let isRightToLeft: Bool
    }

    private static let scripts: [Script] = [
        Script(
            words: ["אני", "אשלח", "לך", "את", "ה-document", "מחר", "בבוקר,", "אחרי", "ה-standup"],
            isRightToLeft: true
        ),
        Script(
            words: ["Can", "you", "review", "the", "deck", "before", "the", "meeting", "tomorrow?"],
            isRightToLeft: false
        ),
        Script(
            words: ["בוא", "נעשה", "sync", "קצר", "על", "ה-roadmap", "של", "Q3"],
            isRightToLeft: true
        )
    ]

    public static func script(at index: Int) -> Script {
        scripts[index % scripts.count]
    }

    public static var scriptCount: Int { scripts.count }

    /// Gap between words while streaming. Uneven on purpose; a metronome reads as fake.
    public static func delay(forWordAt index: Int) -> Duration {
        let pattern: [Int] = [220, 180, 300, 160, 260, 200, 340, 190]
        return .milliseconds(pattern[index % pattern.count])
    }
}
