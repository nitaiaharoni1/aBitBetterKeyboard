import Foundation

extension SuggestionEngine {

    // MARK: Prediction of the next word
    //
    // No public on-device API predicts a word from nothing typed — that is
    // QuickType's job and QuickType is `UIKitCore`-private. So this is built out
    // of four things the keyboard *can* see, asked in order of how much they
    // know about the person holding it:
    //
    //   1. what this user writes after this word,
    //   2. what followed this word earlier in this field,
    //   3. what people generally write after this word,
    //   4. the openers a message starts with.
    //
    // The fourth used to be the whole mechanism. A 26-key table answered `i` and
    // `to` and `אני`, and every other sentence in both languages fell through to
    // the same three words — which is why the corpus caught the bar showing
    // `I · The · We` after "Happy" and `אני · מה · תודה` after "בוקר". The
    // second used to be missing entirely: `previousWords` stops at a full stop,
    // so a name two sentences back was invisible.

    /// Openers, for a field with nothing in it at all.
    ///
    /// Not predictions and never presented as such: with no previous word there is
    /// nothing to predict from, and these are the words a message most often
    /// starts with. Two languages, because a hand-written list for a language
    /// nobody here writes would be worse than the empty bar the other twelve get.
    private static let openers: [KeyboardLanguage: [String]] = [
        .english: ["I", "Thanks", "Hi"],
        .hebrew: ["אני", "תודה", "היי"]
    ]

    /// Three words to follow what has been typed so far.
    ///
    /// - Parameters:
    ///   - context: everything committed before the cursor.
    ///   - contextLanguage: the language that text is written in.
    ///   - personal: what this user's own typing has taught the keyboard. Asked
    ///     first, and this is the whole point of it: after `אני` the table says
    ///     `חושב`, but somebody who writes `אני מגיע` nine times a week should be
    ///     offered `מגיע`.
    @MainActor
    static func nextWordSuggestions(
        context: String,
        contextLanguage: KeyboardLanguage,
        personal: PersonalLanguageModel
    ) -> [Suggestion] {
        nextWordTrace(context: context, contextLanguage: contextLanguage, personal: personal)
            .ranked
    }

    @MainActor
    static func nextWordTrace(
        context: String,
        contextLanguage: KeyboardLanguage,
        personal: PersonalLanguageModel
    ) -> (generated: [Candidate], ranked: [Suggestion]) {
        // Empty when the sentence ended: a full stop closes the thought, and
        // predicting `much` after `Thank you so much.` would read across a
        // boundary the writer just drew. The openers answer instead, which is
        // right — the next word really is the start of something.
        //
        // The whole current sentence, not the last two tokens. Seed lookup
        // still prefers the longest key at the end (`see you` beats `you`);
        // earlier pairs in this sentence are how `the quick` still predicts
        // `response` after two more words have landed. Earlier *sentences*
        // stay out — that is `documentFollowers`'s job, and only for the
        // last token, so a name two sentences back can return and a closed
        // thought cannot.
        let sentence = previousWords(in: context, limit: Int.max)
        let last = sentence.last ?? ""

        var out: [Candidate] = []
        if !last.isEmpty {
            out +=
                personal.followers(mentionedIn: sentence, in: contextLanguage, limit: 3)
                .enumerated()
                .map {
                    Candidate(
                        text: $0.element, language: contextLanguage, source: .learned,
                        ordinal: $0.offset)
                }
            out +=
                documentFollowers(after: last, in: context, limit: 3)
                .enumerated()
                .map {
                    Candidate(
                        text: $0.element, language: contextLanguage, source: .document,
                        ordinal: $0.offset)
                }
            let seedFollowers = SeedLanguageModel.followers(
                mentionedIn: sentence, in: contextLanguage)
            out +=
                seedFollowers
                .prefix(3)
                .enumerated()
                .map {
                    Candidate(
                        text: $0.element, language: contextLanguage, source: .seed,
                        ordinal: $0.offset)
                }
            if contextLanguage.script == .hebrew, seedFollowers.isEmpty {
                out +=
                    ConversationalHebrewModel.followers(after: sentence, limit: 3)
                    .enumerated()
                    .map {
                        Candidate(
                            text: $0.element, language: .hebrew, source: .conversational,
                            ordinal: $0.offset)
                    }
            }
        }
        // Only when nothing above answered. An opener after a real word is not a
        // prediction, it is the bar giving up in a way that looks like an answer —
        // which is exactly what `I · The · We` after "Happy" was.
        if out.isEmpty, let words = openers[contextLanguage] {
            out +=
                words.enumerated()
                .map {
                    Candidate(
                        text: $0.element, language: contextLanguage, source: .seed,
                        ordinal: $0.offset)
                }
        }

        // Capitalised at the start of a message, because that is where the word is
        // going and the shift key has already decided the same thing.
        let atStart = context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        stampPersonalCounts(&out, personal: personal)
        // Exactly what the bar draws, not one more: there is no typed word here
        // for `SuggestionBar.centeredSlots` to filter out.
        let ranked = rank(out, limit: barSlots).map { candidate -> Suggestion in
            guard atStart else {
                return Suggestion(text: candidate.text, language: candidate.language)
            }
            return Suggestion(
                text: contextLanguage.uppercased(String(candidate.text.prefix(1)))
                    + candidate.text.dropFirst(),
                language: candidate.language)
        }
        return (out, ranked)
    }
}
