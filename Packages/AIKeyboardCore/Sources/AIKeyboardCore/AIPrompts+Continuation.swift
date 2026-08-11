import Foundation

extension Prompts {

    /// Instructions for the three words a suggestion bar offers next.
    ///
    /// **Written against the one thing that makes this different from every other
    /// action here: the answer goes above a keyboard, not into the field.** The
    /// model is not writing the message, it is guessing the next word or two, and
    /// the failure mode is a model that helpfully composes a whole sentence and
    /// gets it drawn as a three-word bar it does not fit in.
    ///
    /// Two prompts, never merged, for the reason the whole `Prompts` enum is split
    /// that way: a prompt carrying Hebrew examples translated all ten English test
    /// inputs into Hebrew, and the same prompt in reverse translates Hebrew into
    /// English. There is no single prompt that is safe for both.
    static func continuation(for text: String, replyingTo context: ScreenContext?) -> String {
        let hebrew = isHebrew(text) || context.map { isHebrew($0.message) } == true
        let base = hebrew ? hebrewContinuation : englishContinuation
        guard context != nil else { return base }
        return base + (hebrew ? hebrewReplyNote : englishReplyNote)
    }

    private static let englishContinuation = """
        You are the predictive text bar above a phone keyboard. You are given the \
        start of a message somebody is typing and you return the three most likely \
        next words.

        Rules that decide whether your answer is usable at all:
        - Each answer is ONE word. Two only when the pair is inseparable, like \
        "you too".
        - Continue the sentence. Do not rewrite it, do not correct it, do not \
        finish it, and never repeat a word that is already there.
        - Three genuinely different continuations, not one word and two \
        variations of it. If the sentence could go three ways, offer three ways.
        - Match the register of what is already typed. Someone writing "yeah ok \
        so" is not about to write "furthermore".
        - Answer in the language the message is written in.
        - If the message reads as finished, offer the words that would start the \
        next sentence.
        """

    private static let hebrewContinuation = """
        אתה שורת הניחושים שמעל מקלדת של טלפון. מקבלים ממך את תחילת ההודעה שמישהו \
        מקליד, ואתה מחזיר את שלוש המילים הבאות הסבירות ביותר.

        כללים שקובעים אם התשובה בכלל שמישה:
        - כל תשובה היא מילה אחת. שתיים רק כשהצירוף בלתי נפרד, כמו "בוקר טוב".
        - המשך את המשפט. אל תנסח אותו מחדש, אל תתקן אותו, אל תסיים אותו, ולעולם \
        אל תחזור על מילה שכבר כתובה בו.
        - שלושה המשכים שונים באמת, לא מילה אחת ועוד שתי הטיות שלה.
        - שמור על המשלב של מה שכבר הוקלד.
        - ענה בעברית.
        - אם ההודעה נקראת כמשפט שנגמר, הצע את המילים שיפתחו את המשפט הבא.
        """

    /// Added only when a screen reading is live.
    ///
    /// **The message on screen is context for the reply, never the thing being
    /// continued**, and saying so is the whole note: given a message and a
    /// half-typed answer, a model will happily start predicting the *message*
    /// back at the user.
    private static let englishReplyNote = """

        The user is replying to a message they can see on screen. It is given to \
        you as context so your guesses fit the answer they are writing. Continue \
        THEIR reply. Never continue or echo the message they received.
        """

    private static let hebrewReplyNote = """

        המשתמש עונה להודעה שהוא רואה על המסך. ההודעה ניתנת לך כהקשר בלבד, כדי \
        שהניחושים יתאימו לתשובה שהוא כותב. המשך את התשובה שלו. לעולם אל תמשיך או \
        תחזור על ההודעה שקיבל.
        """
}
