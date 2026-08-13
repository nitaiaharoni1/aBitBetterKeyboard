import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Generated shapes

/// One field, unlike the cloud engine's two.
///
/// The cloud model is asked to list every mistake before it writes the corrected
/// message, which is what lets `EditScope` hold it to that list. This model was
/// asked the same and got worse at the job it was already doing: over the ten
/// English Fix entries in `Bar/ai-text` it began dropping words from the message
/// — "can you send me the id" came back as "you send me the id" — and correcting
/// things it had corrected properly before. Its context is small and its
/// attention is finite; a second field spends both. So it is asked for the
/// message alone, and `EditScope.repaired` cleans up after it without a list.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct FixDraft {
    @Guide(
        description:
            "The whole message with spelling and grammar corrected, in the same language and script it arrived in. Return every sentence, never a fragment. A missing apostrophe is a typo (`dont -> don't`). Words stuck together with no space are a mistake (`hellothere -> hello there`). A word that is already right, slang, an abbreviation, and an already-correct contraction stay as they are."
    )
    var text: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct ToneDraft {
    @Guide(description: "The message rewritten in the requested register, in its original language.")
    var text: String
}

/// Flat rather than an array of a nested `@Generable`, because three named
/// slots with their own guides is what stops the model from returning one
/// answer reworded three times.
///
/// `decision` and `specifics` come first because the fields are filled in the
/// order they are declared, so anything written down here is available to the
/// three versions below it. Both were added against measured failures: asked
/// straight out for three versions, the model produced three phrasings of one
/// refusal, and its negotiating version dropped the deadline the message was
/// about. Naming the decision once and listing the specifics once fixes both
/// without a second round trip.
///
/// The guides carry no worked examples on purpose. An earlier version offered
/// 'Direct no' and 'Counter-proposal' as illustrations, and the model copied
/// them verbatim into every result — including onto a thank-you note, which it
/// then rewrote as declining an offer that did not exist.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct RewriteDraft {
    @Guide(
        description:
            "What the message decides or asks for, in a few words. Write 'nothing' when it only thanks, informs or shares news."
    )
    var decision: String
    @Guide(
        description:
            "Every time, date, name and number in the message, comma separated. Write 'none' if it has none. Each one has to appear in all three versions below."
    )
    var specifics: String
    @Guide(description: "Two or three words in English naming what this version commits to.")
    var firstLabel: String
    @Guide(
        description:
            "The whole message, rewritten to take that decision as directly as it can be taken. It is still a rewrite: when the message already says it directly, tighten it. Returning the message word for word is not a version. Use only facts already in the message."
    )
    var firstText: String
    @Guide(description: "Two or three words in English naming a different decision this version takes.")
    var secondLabel: String
    @Guide(
        description:
            "The whole message, rewritten to hand the decision back rather than settle it: it asks the other person for what would settle it. When the message decides nothing, this is the same message, shorter and plainer."
    )
    var secondText: String
    @Guide(description: "Two or three words in English naming a third decision this version takes.")
    var thirdLabel: String
    @Guide(
        description:
            "The whole message, rewritten to keep the position but put a different option on the table. When the message decides nothing, this is the same message, warmer — and no longer than the original. Invent no times, names or numbers."
    )
    var thirdText: String
}

/// `unnamed` is first for the same reason `decision` is: the model has to
/// establish whether the message can be agreed to before it writes something
/// that agrees to it. Measured — asked for an accept/push back/ask set on "can
/// you look at this when you get a chance?", the model accepted a task nobody
/// had described and promised when it would be done.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct ReplyDraft {
    @Guide(
        description:
            "The task, file or item the sender refers to but never identifies — 'this', 'it' — when agreeing would mean taking on something the user cannot see. Empty when the message says what it is about, and empty when it only asks for time or attention: agreeing to talk hides nothing."
    )
    var unnamed: String
    @Guide(
        description:
            "The grammatical gender to address the sender in, worked out from their name: 'feminine' or 'masculine'. 'none' when the reply is in a language that does not inflect for it."
    )
    var addressee: String
    @Guide(
        description:
            "A reply that agrees or accepts. Use only times and dates the message already named. If something is unnamed above, this reply still asks what it is. Address the sender in the gender named above, never with a slash form."
    )
    var accept: String
    @Guide(
        description:
            "A reply that declines, disagrees or negotiates. Do not offer a different time; if one is needed, ask for it. If something is unnamed above, this reply refuses to commit until it knows what it is, and asks. Same gender as above."
    )
    var pushBack: String
    @Guide(
        description:
            "A reply that asks the one question needed before answering, addressing the sender in the gender named above."
    )
    var ask: String
}

#endif
