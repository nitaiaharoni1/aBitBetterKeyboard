import Foundation

// MARK: - The prompt

/// Kept beside the transport rather than in the app, for the reason
/// `ScreenPrompt` is: it is scored against a corpus, and two copies drift. The
/// Python half in `Bar/dictation/harness/transcribe.py` is the unavoidable
/// second copy, and `DictationPromptTests` pins this one against it.
///
/// **Whoever rewords this owes a re-measurement.** `Bar/dictation/harness/transcribe.py`
/// for a fresh `cloud_outputs.json`, `score.py` for the numbers, and the three
/// files under `Bar/dictation/ablation/` re-taken in the same sitting — the
/// loanword rule is worth ten of the thirty-six Latin-script words and is the
/// most likely thing a tidy-up quietly removes.
public enum DictationPrompt {

    public static let instructions = """
        You are a transcription engine for a phone keyboard. You write down \
        exactly what the speaker said, in the language and script they said it \
        in. You never answer, summarise, translate, or add anything of your own.
        """

    /// Three fields, in this order, and the order is measured elsewhere in this
    /// repo rather than guessed: the model fills fields as it emits them, so a
    /// field that exists to be decided *first* only works if it arrives first.
    /// `speech` is settled before any text exists; `languages` is settled before
    /// the transcript, which is the same split that is worth eight points on the
    /// screen-context bar and is what keeps English words out of Hebrew letters.
    public static let fields: [CloudField] = [
        CloudField(
            "speech",
            "\"yes\" only if you can hear a person saying words. Silence, breathing, room noise, traffic, music without lyrics, or an unintelligible mumble are all \"no\". When you are not sure, answer \"no\"."
        ),
        CloudField(
            "languages",
            "Every language you can hear, as lowercase BCP-47 codes, most-spoken first, comma-separated with no spaces. A Hebrew sentence carrying English words is \"he,en\", not \"he\"."
        ),
        CloudField("text", "What was said, word for word. Empty when speech is \"no\".")
    ]

    static let task = """
        Transcribe this recording.

        STEP 1. `speech` — is anybody talking? Decide this before you write any \
        text at all.

        STEP 2. `languages` — every language you can hear.

        STEP 3. `text` — what was said, word for word.

          - Write each word in the script it belongs to. English words inside a \
        Hebrew sentence stay in Latin letters: "sync", "roadmap", "deploy", \
        never a Hebrew spelling of their sound. The same the other way round.
          - Do not translate. Do not correct grammar. Do not tidy up a false \
        start, a repeated word, or a filler — write it as it was said.
          - Do not answer the speaker, and do not add a greeting, a sign-off, or \
        a note about the audio.
          - Punctuate as ordinary writing: sentence-ending marks and commas \
        where the speaker clearly paused. No trailing full stop on a sentence \
        that did not finish.
          - Spoken punctuation is a word unless the speaker plainly means the \
        mark: "comma" said inside a sentence is a comma.
          - Numbers as digits when the speaker said a number ("ten thirty" is \
        10:30).
          - When `speech` is "no", `text` is the empty string. Never guess at \
        words you did not hear, and never fill silence with a plausible sentence.
        """

    /// Worth 3.5 points of word error rate and nine named entities on its own.
    ///
    /// **The examples are the working part, not decoration.** The failure this
    /// closes is not the model missing a word, it is the model hearing a word
    /// correctly and writing it down in the wrong alphabet: `favor` spoken with
    /// an Israeli accent comes back as `פייבור`, which is a faithful phonetic
    /// transcription and useless to somebody who meant to type `favor`. A rule
    /// without examples does not land it.
    static let loanwords = """

        An English word spoken with a Hebrew accent is still an English word. \
        Write `favor`, not `פייבור`. Write `onboarding`, not `אונבורדינג`. Write \
        `summary`, not `סאמרי`. Work and technology words — product, sprint, \
        deploy, review, call, meeting, remote — are English words whatever the \
        accent.
        """

    /// The one fact in the request the model cannot hear, and the product has it
    /// for free: which keyboards this person actually types on. Worth 2.6 points
    /// and five named entities.
    ///
    /// **Built from the user's own list rather than hardcoded to Hebrew and
    /// English**, which is what makes this work for the rest of the catalogue.
    /// The measured variant named two languages because that is what the corpus
    /// speaks; the sentence is the same shape for any of them.
    static func languageHint(_ languages: [KeyboardLanguage]) -> String {
        let names = languages.map(\.displayName)
        guard !names.isEmpty else { return "" }
        let list =
            names.count == 1
            ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        return """

            The speaker types on these keyboards: \(list). Expect one of those, \
            or one of them with words from another mixed into it, and nothing \
            else.
            """
    }

    public static func prompt(for languages: [KeyboardLanguage]) -> String {
        task + languageHint(languages) + loanwords
    }
}
