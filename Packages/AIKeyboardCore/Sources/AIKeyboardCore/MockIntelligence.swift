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
            let results = nextWordSuggestions(context: context, contextLanguage: contextLanguage, languages: languages)
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
        if MockAI.contractions[lower] != nil { return true }

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
        if let contraction = MockAI.contractions[lower] {
            out.append(Suggestion(text: matchCase(of: prefix, applyingTo: contraction), language: .english))
        }

        if typedLanguage == .hebrew {
            out += hebrewVocabulary
                .filter { $0.hasPrefix(prefix) && $0 != prefix }
                .prefix(2)
                .map { Suggestion(text: $0, language: .hebrew) }
        } else {
            // Latin letters typed inside a Hebrew sentence: the loanword list goes
            // first, because that is almost always what is happening.
            if contextLanguage == .hebrew && languages.contains(.hebrew) {
                out += codeSwitchVocabulary
                    .filter { $0.hasPrefix(lower) && $0 != lower }
                    .prefix(2)
                    .map { Suggestion(text: $0, language: .english) }
            }
            out += englishVocabulary
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
        let words = context
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        guard let last = words.last?.trimmingCharacters(in: .punctuationCharacters).lowercased(),
              !last.isEmpty else {
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
            if (0x0590...0x05FF).contains(scalar.value) { hebrew += 1 }
            else if CharacterSet.letters.contains(scalar) { latin += 1 }
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
}

// MARK: - AI
//
// Stands in for Foundation Models on device / the cloud LLM behind the backend.
// Rule-based so that whatever the user types during a demo comes back changed
// in a way they can recognise, instead of an empty response.

public enum MockAI {

    /// Rough time the real thing would take, so the loading state gets exercised.
    public static let simulatedLatency: Duration = .milliseconds(650)

    /// Shared with the suggestion engine, which offers these as autocorrections.
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

    private static let hebrewTypos: [String: String] = [
        "בבקשא": "בבקשה", "תודא": "תודה", "שלוםם": "שלום", "אנחנוו": "אנחנו",
        "מחרר": "מחר", "אנני": "אני", "צריח": "צריך", "יכל": "יכול"
    ]

    private static let fillerWords: Set<String> = [
        "just", "really", "actually", "basically", "very", "quite", "kind", "sort",
        "maybe", "perhaps", "somewhat", "literally", "definitely"
    ]

    // MARK: Fix

    /// Grammar and spelling only. Meaning, tone and language stay put.
    public static func fix(_ input: String) -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        if MockSuggestionEngine.dominantLanguage(in: text) == .hebrew {
            return fixHebrew(text)
        }
        return fixEnglish(text)
    }

    private static func fixEnglish(_ text: String) -> String {
        var words = text.components(separatedBy: " ")

        for index in words.indices {
            let word = words[index]
            let core = word.trimmingCharacters(in: .punctuationCharacters)
            guard !core.isEmpty else { continue }
            let trailing = String(word.dropFirst(core.count))

            if let fixed = contractions[core.lowercased()] {
                words[index] = preserveCapitalisation(of: core, in: fixed) + trailing
            } else if core == "i" {
                words[index] = "I" + trailing
            }
        }

        var result = words.joined(separator: " ")

        // "its not make sense" is a real pattern in the plan's example, and it needs
        // more than a contraction swap to read correctly.
        result = result.replacingOccurrences(of: "it's not make sense", with: "it doesn't make sense")
        result = result.replacingOccurrences(of: "It's not make sense", with: "It doesn't make sense")

        result = collapseSpaces(result)
        result = capitaliseFirstLetter(result)
        result = ensureTerminalPunctuation(result)
        return result
    }

    private static func fixHebrew(_ text: String) -> String {
        var words = text.components(separatedBy: " ")
        for index in words.indices {
            let core = words[index].trimmingCharacters(in: .punctuationCharacters)
            if let fixed = hebrewTypos[core] {
                words[index] = words[index].replacingOccurrences(of: core, with: fixed)
            }
        }
        var result = collapseSpaces(words.joined(separator: " "))
        result = ensureTerminalPunctuation(result)
        return result
    }

    // MARK: Rewrite

    public static func variants(for input: String, tone: ToneStyle? = nil) -> [RewriteVariant] {
        let base = fix(input)
        guard !base.isEmpty else { return [] }

        let tones: [ToneStyle] = tone.map { [$0] } ?? [.clearer, .shorter, .professional]
        let candidates = tones.map { RewriteVariant(tone: $0, text: rewrite(base, as: $0)) }

        // An explicitly requested tone is always shown, even if it changed
        // nothing. In the three-up list, an option that returns the text
        // unchanged is a promise the UI did not keep, so it is dropped.
        guard tone == nil else { return candidates }

        var seen: Set<String> = [base.lowercased()]
        return candidates.filter { variant in
            let key = variant.text.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    /// Phrases that carry no more meaning than their replacement. Cutting these
    /// is most of what "make it shorter" actually means in practice.
    private static let compressions: [String: String] = [
        "due to the fact that": "because",
        "in the event that": "if",
        "at this point in time": "now",
        "in order to": "to",
        "a large number of": "many",
        "a lot of": "many",
        "as well as": "and",
        "would like to": "want to",
        "are able to": "can",
        "is able to": "can",
        "with regard to": "about",
        "in spite of": "despite",
        "prior to": "before",
        "subsequent to": "after",
        "i don't think": "i doubt",
        "i do not think": "i doubt",
        "because it doesn't": ", it doesn't",
        "because it does not": ", it doesn't",
        "because it isn't": ", it isn't"
    ]

    private static let hebrewCompressions: [String: String] = [
        "בגלל העובדה ש": "כי",
        "בגלל ש": "כי",
        "על מנת ל": "כדי ל",
        "אני לא חושב ש": "אני בספק ש",
        "בנקודת הזמן הזאת": "עכשיו",
        "וגם כן": "וגם"
    ]

    public static func shorten(_ input: String) -> String {
        let base = fix(input)
        let isHebrew = MockSuggestionEngine.dominantLanguage(in: base) == .hebrew
        var result = base

        for (verbose, terse) in (isHebrew ? hebrewCompressions : compressions) {
            result = result.replacingOccurrences(
                of: verbose,
                with: terse,
                options: [.caseInsensitive]
            )
        }

        if !isHebrew {
            let kept = result.components(separatedBy: " ").filter { word in
                let core = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
                return !fillerWords.contains(core)
            }
            if !kept.isEmpty { result = kept.joined(separator: " ") }
        }

        return ensureTerminalPunctuation(capitaliseFirstLetter(collapseSpaces(result)))
    }

    private static func rewrite(_ text: String, as tone: ToneStyle) -> String {
        let isHebrew = MockSuggestionEngine.dominantLanguage(in: text) == .hebrew
        let body = stripTerminalPunctuation(text)
        let lowerBody = isHebrew ? body : lowercaseFirstLetter(body)

        switch tone {
        case .clearer:
            return isHebrew
                ? ensureTerminalPunctuation("רציתי לוודא: \(lowerBody)")
                : ensureTerminalPunctuation("To be clear, \(lowerBody)")
        case .shorter:
            return shorten(text)
        case .professional:
            return isHebrew
                ? ensureTerminalPunctuation("אשמח אם נוכל להתייחס לכך: \(lowerBody)")
                : ensureTerminalPunctuation("Could you please make sure that \(lowerBody)")
        case .casual:
            return isHebrew
                ? ensureTerminalPunctuation("היי, \(lowerBody)")
                : ensureTerminalPunctuation("Hey, \(lowerBody)")
        case .confident:
            return isHebrew
                ? ensureTerminalPunctuation("\(body). זה מה שצריך לקרות")
                : ensureTerminalPunctuation("\(capitaliseFirstLetter(body)). Let's move on that")
        case .friendly:
            return isHebrew
                ? ensureTerminalPunctuation("תודה מראש! \(lowerBody)")
                : ensureTerminalPunctuation("Thanks in advance. \(lowerBody)")
        }
    }

    // MARK: String helpers

    private static func collapseSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ([,.!?])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func capitaliseFirstLetter(_ text: String) -> String {
        guard let first = text.first, first.isLowercase else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func lowercaseFirstLetter(_ text: String) -> String {
        guard let first = text.first, first.isUppercase, text != "I", !text.hasPrefix("I ") else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func ensureTerminalPunctuation(_ text: String) -> String {
        guard let last = text.last else { return text }
        if ".!?".contains(last) { return text }
        return text + "."
    }

    private static func stripTerminalPunctuation(_ text: String) -> String {
        var out = text
        while let last = out.last, ".!?,".contains(last) {
            out.removeLast()
        }
        return out
    }

    private static func preserveCapitalisation(of source: String, in replacement: String) -> String {
        guard let first = source.first, first.isUppercase else { return replacement }
        return replacement.prefix(1).uppercased() + replacement.dropFirst()
    }
}

// MARK: - Screen context
//
// Stands in for the ScreenCaptureKit session that runs in the main app and hands
// frames to the keyboard through the App Group. Nothing here captures anything;
// these are the messages a session would have read off the screen.

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

public extension MockAI {

    /// Three answers that differ in what they decide, not in how they phrase it.
    /// Picking between "yes", "no" and "ask" is the actual decision; wording is
    /// the easy part and the one the model should own.
    static func replies(to context: ScreenContext) -> [ReplyOption] {
        switch context.language {
        case .hebrew:
            return [
                ReplyOption(
                    intent: "מאשר",
                    icon: "checkmark",
                    text: hebrewAccept(for: context)
                ),
                ReplyOption(
                    intent: "דוחה",
                    icon: "clock",
                    text: hebrewDefer(for: context)
                ),
                ReplyOption(
                    intent: "שואל",
                    icon: "questionmark",
                    text: hebrewAsk(for: context)
                )
            ]
        case .english:
            return [
                ReplyOption(
                    intent: "Accept",
                    icon: "checkmark",
                    text: englishAccept(for: context)
                ),
                ReplyOption(
                    intent: "Push back",
                    icon: "clock",
                    text: englishDefer(for: context)
                ),
                ReplyOption(
                    intent: "Ask first",
                    icon: "questionmark",
                    text: englishAsk(for: context)
                )
            ]
        }
    }

    private static func hebrewAccept(for context: ScreenContext) -> String {
        "כן, פנוי. באיזו שעה נוח לך?"
    }

    private static func hebrewDefer(for context: ScreenContext) -> String {
        "הערב קצת צפוף לי, אפשר לדחות למחר?"
    }

    private static func hebrewAsk(for context: ScreenContext) -> String {
        "נשמע טוב. איפה בדיוק ובאיזו שעה?"
    }

    private static func englishAccept(for context: ScreenContext) -> String {
        "Sure, I can take it. I'll run standup at 9."
    }

    private static func englishDefer(for context: ScreenContext) -> String {
        "I have something at 9 too. Can we move it to 10?"
    }

    private static func englishAsk(for context: ScreenContext) -> String {
        "Probably yes. Anything specific you want covered?"
    }
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
