import Foundation

/// The instructions behind the four actions, in two authored sets and a line.
///
/// They are split by language rather than parameterised because a single merged
/// prompt is measurably unsafe: adding Hebrew examples to an otherwise English
/// prompt made the model translate every English input into Hebrew. The Hebrew
/// set is written in Hebrew for the same reason in reverse — the language the
/// instructions are written in is the strongest signal the model has for which
/// language to answer in, stronger than any sentence telling it not to translate.
///
/// **The keyboard now draws fourteen languages and there are still two prompt
/// sets, which is a deliberate stop rather than an oversight.** The two that
/// exist are scored against `Bar/ai-text`; a third written blind would be an
/// unmeasured artifact wearing the same clothes. What the other twelve get is
/// `scriptDirective`: one English sentence naming the script the message is in,
/// appended to the English set. That is not the merge the measurement warned
/// about — no foreign-language example is added, and the English and Hebrew
/// paths come out byte for byte as before — and it addresses the one failure
/// that matters here, a model answering an Arabic message in English or
/// transliterating a Greek one into Latin letters.
enum Prompts {

    /// Hebrew if there is any Hebrew in the text at all, not if it dominates.
    /// The sentences this keyboard exists for are often mostly Latin with the
    /// Hebrew carrying the error.
    static func isHebrew(_ text: String) -> Bool {
        LanguageDetector.scripts(in: text).contains(.hebrew)
    }

    /// One sentence naming the script, or nothing at all.
    ///
    /// Nothing for Latin, because the English instructions already cover it and
    /// the corpus is measured with them exactly as they are. Nothing for `.other`
    /// either: the honest sentence about a script we could not name is no
    /// sentence, and "the This language script" is what naming it would produce.
    /// Sorted rather than taken off a `Set`, so a message carrying two scripts
    /// produces the same prompt twice running.
    static func scriptDirective(for text: String) -> String {
        guard
            let script = LanguageDetector.scripts(in: text)
                .subtracting([.latin, .other])
                .sorted(by: { $0.rawValue < $1.rawValue })
                .first
        else { return "" }
        return """


            The message is written in the \(script.displayName) script. Answer in the same \
            language and the same script. Never translate it into English, and never \
            transliterate it into Latin letters.
            """
    }
}
