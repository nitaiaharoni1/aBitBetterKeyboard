import Foundation

/// The last check before a generated message reaches the user.
///
/// Reply and Rewrite are the two actions that write rather than correct, and
/// both put their output in the user's voice: a Reply is sent to someone else as
/// the user, and a Rewrite replaces what the user actually typed. When either
/// adds a fact the conversation never contained — a number, a day, a promise
/// about when something will be done — the user taps a suggestion and ships a
/// commitment they never made. That is worse than an action that admits it could
/// not answer, so nothing here is repaired or softened: a candidate that added
/// something is dropped, and if every candidate added something the action fails.
///
/// The rules are deliberately narrow. Each is a closed set that cannot appear in
/// an honest answer unless the message put it there, and the set was checked
/// against all 58 reference answers in `Bar/ai-text/reference.json` — the ones a
/// good writer produced — with nothing flagged. A broader rule rejects good
/// writing: the reference answer to the corpus's own hallucination probe declines
/// with "it won't be today", so a rule against every time word would throw away
/// the model answer we are aiming for. Judging *which* invented sentence is
/// harmful is the prompt's job; this catches the ones that always are.
public enum OutputGuard {

    // MARK: Filtering

    /// The candidates worth showing, in the order they were generated.
    ///
    /// Drops a candidate that repeats one already kept, that names a number or a
    /// day the message did not, or that promises when something will happen when
    /// the message named no time. `mustAsk` additionally drops any candidate that
    /// does not ask something, for the messages that cannot be agreed to as they
    /// stand — a reply that accepts an unnamed task has invented the task.
    public static func keep(
        _ candidates: [(label: String, text: String)],
        groundedIn source: String,
        mustAsk: Bool = false
    ) -> [(label: String, text: String)] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { return nil }
            guard addedSpecifics(in: text, notIn: source).isEmpty else { return nil }
            guard !mustAsk || asks(text) else { return nil }
            return (label: candidate.label, text: text)
        }
    }

    // MARK: Checks

    /// Every specific in `candidate` that `source` never contained, named so a
    /// test and a log line can both say what was wrong.
    public static func addedSpecifics(in candidate: String, notIn source: String) -> [String] {
        let text = candidate.lowercased()
        let original = source.lowercased()
        var added: [String] = []

        // Digits carry the times, dates, prices and counts, in both languages
        // and without a word list.
        added += numbers(in: text).subtracting(numbers(in: original)).sorted()
        // A day the sender never named is always the engine's invention.
        added += weekdays.filter { contains($0, in: text) && !contains($0, in: original) }
        // "As soon as I can" is a delivery date with no number in it.
        added += promises.filter { contains($0, in: text) && !contains($0, in: original) }
        return added
    }

    /// Whether the candidate asks the recipient anything. A reply to a message
    /// that cannot be answered has to, and both languages mark it the same way.
    public static func asks(_ candidate: String) -> Bool {
        candidate.contains("?")
    }

    // MARK: Word lists

    /// Full names only. The abbreviations collide with ordinary words in both
    /// languages, and a day is rare enough in a two-sentence reply that catching
    /// "Tuesday" and missing "Tue" is the right trade.
    private static let weekdays = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "יום ראשון", "יום שני", "יום שלישי", "יום רביעי", "יום חמישי", "יום שישי", "שבת"
    ]

    /// Phrases that are a commitment about timing whatever else the sentence
    /// says. Bare time words are not here on purpose: "it won't be today" is a
    /// limit rather than a promise, and refusing it would reject good answers.
    private static let promises = [
        "as soon as i can", "as soon as possible", "asap", "right away", "straight away",
        "first thing", "by end of day", "by the end of the day", "shortly", "in a bit",
        "הקדם", "מיד", "תכף", "תיכף", "בקרוב"
    ]

    // MARK: Matching

    /// Hebrew attaches its prepositions and its definite article to the front of
    /// the word, so "בשבת" is "on Saturday" and has to count as the same word.
    private static let hebrewPrefixes: Set<Character> = ["ב", "ה", "ל", "מ", "ו", "ש", "כ"]

    private static func numbers(in text: String) -> Set<String> {
        Set(
            text.split(whereSeparator: { !$0.isNumber })
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    /// Whole-word containment, with one Hebrew prefix letter allowed in front.
    private static func contains(_ phrase: String, in text: String) -> Bool {
        var from = text.startIndex
        while let range = text.range(of: phrase, range: from..<text.endIndex) {
            from = range.upperBound
            let followedByWord =
                range.upperBound < text.endIndex && isWordCharacter(text[range.upperBound])
            if !followedByWord, startsWord(at: range.lowerBound, in: text) { return true }
        }
        return false
    }

    private static func startsWord(at index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let prefix = text.index(before: index)
        guard isWordCharacter(text[prefix]) else { return true }
        // A single Hebrew prefix letter is part of the word, not a word of its
        // own — but only when it is itself at the start of the word, so "יושבת"
        // does not read as Saturday.
        guard hebrewPrefixes.contains(text[prefix]) else { return false }
        guard prefix > text.startIndex else { return true }
        return !isWordCharacter(text[text.index(before: prefix)])
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

// MARK: - Vetted results

// Both engines fill the same slots from the same prompts, so both assemble their
// results here rather than twice. The distinction the two `guard`s draw is the
// point: a model that returned nothing has failed, and a model whose every answer
// invented something has failed differently, in the way the user most needs to be
// told about.

extension RewriteVariant {
    static func vetted(
        _ drafts: [(label: String, text: String)],
        against source: String
    ) throws -> [RewriteVariant] {
        guard drafts.contains(where: { !$0.text.isEmpty }) else { throw AIEngineError.empty }
        let kept = OutputGuard.keep(drafts, groundedIn: source)
        guard !kept.isEmpty else { throw AIEngineError.invented }
        return kept.map {
            RewriteVariant(tone: .clearer, label: $0.label.isEmpty ? nil : $0.label, text: $0.text)
        }
    }
}

extension ReplyOption {
    /// `unnamed` is what the model reported the message points at but never
    /// names. When it reported something, a reply that does not ask about it has
    /// accepted a task nobody described, and it is dropped however well written
    /// it is.
    static func vetted(
        accept: String,
        pushBack: String,
        ask: String,
        against source: String,
        unnamed: String
    ) throws -> [ReplyOption] {
        let drafts = [
            (label: "Accept", text: accept),
            (label: "Push back", text: pushBack),
            (label: "Ask", text: ask)
        ]
        guard drafts.contains(where: { !$0.text.isEmpty }) else { throw AIEngineError.empty }

        // The field is required, so a model with nothing to report writes a
        // placeholder rather than leaving it blank. Reading "none" as "something
        // is unnamed" would silently drop two thirds of every reply set.
        let missing = unnamed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unanswerable = !missing.isEmpty && !["none", "n/a", "na", "null", "-"].contains(missing)

        let kept = OutputGuard.keep(drafts, groundedIn: source, mustAsk: unanswerable)
        guard !kept.isEmpty else { throw AIEngineError.invented }

        let icons = ["Accept": "checkmark", "Push back": "hand.raised", "Ask": "questionmark"]
        return kept.map {
            ReplyOption(intent: $0.label, icon: icons[$0.label] ?? "questionmark", text: $0.text)
        }
    }
}
