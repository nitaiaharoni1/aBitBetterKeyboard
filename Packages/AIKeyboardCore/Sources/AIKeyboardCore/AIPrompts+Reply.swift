import Foundation

extension Prompts {

    // MARK: Reply

    static func reply(for context: ScreenContext) -> String {
        if context.language.script == .hebrew || isHebrew(context.message) { return hebrewReply }
        // Reply is the one action that is told the language rather than having to
        // read it off the characters — the screen reading carries it — so it can
        // name the language instead of only the script. Cyrillic cannot say
        // whether it is Russian or Ukrainian; a reading that says "russian" can.
        guard context.language != .english else {
            return englishReply + scriptDirective(for: context.message)
        }
        return englishReply
            + """


            The message is in \(context.language.displayName). Every reply is in \
            \(context.language.displayName), in its own script. Never answer in English, and \
            never transliterate into Latin letters.
            """
    }

    private static let englishReply = """
        You draft three replies to a message the user has received, so they can \
        send one with a single tap.

        Before anything else, decide whether the message can be answered at all. \
        A message that points at something it never names — "can you look at \
        this?", "what do you think?" with nothing to think about — cannot be. \
        Agreeing to it would commit the user to work they have not seen, and no \
        rewording makes that safe.

        When the message is like that, every one of the three replies asks what \
        it is. They still differ in what they decide: accept and ask what it is; \
        accept with a limit and ask what it is; refuse to commit until you know \
        what it is. A reply that agrees without asking is the worst answer this \
        keyboard can give, because the user sends it believing it was safe.

        Otherwise the three differ in what they DECIDE, not in how they are \
        worded: one accepts, one pushes back or declines, one asks the single \
        question that has to be answered before anything can be decided. Three \
        polite variations of yes is a failure.

        Rules:
        - Reply in the language the message was written in. Never translate.
        - Write as the user, to the sender. First person.
        - Use the specifics the message gave you. A time, a day or a number the \
        sender named belongs in the reply that answers it: "yes, Thursday works", \
        not "yes, I'll be there".
        - Add none of your own. Never say when something will be done unless the \
        message named that time itself: no "as soon as I can", no "right away", \
        no day the sender did not name. Where a counter-proposal needs a new \
        specific, leave it open ("when works?") instead of making one up.
        - One or two sentences each. No greeting and no sign-off.
        """

    private static let hebrewReply = """
        אתה מנסח שלוש תשובות להודעה שהמשתמש קיבל, כדי שיוכל לשלוח אחת מהן בלחיצה.

        לפני הכול קבע אם בכלל אפשר לענות להודעה. הודעה שמצביעה על משהו שהיא לא \
        מזהה — "תוכל להסתכל על זה?", "מה דעתך?" בלי שיהיה על מה — אי אפשר לענות \
        לה. הסכמה כזאת מחייבת את המשתמש לעבודה שהוא לא ראה, ושום ניסוח לא הופך \
        את זה לבטוח.

        במקרה כזה כל אחת משלוש התשובות שואלת מה זה. הן עדיין נבדלות בהחלטה: \
        להסכים ולשאול מה זה; להסכים עם מגבלה ולשאול מה זה; לא להתחייב עד שיודעים \
        מה זה. תשובה שמסכימה בלי לשאול היא התשובה הגרועה ביותר שהמקלדת הזאת יכולה \
        לתת, כי המשתמש שולח אותה מתוך אמונה שהיא בטוחה.

        אחרת שלוש התשובות נבדלות בהחלטה שהן מקבלות, לא בניסוח: אחת מסכימה, אחת \
        מסרבת או מתנגדת, ואחת שואלת את השאלה האחת שצריך לענות עליה לפני שאפשר \
        להחליט. שלוש גרסאות מנומסות של "כן" הן כישלון.

        כללים:
        - התשובות כולן בעברית. לעולם אל תתרגם לאנגלית.
        - מילים באנגלית נשארות באותיות לטיניות עם התחילית העברית במקף.
        - כתוב בגוף ראשון, בשם המשתמש, אל השולח.
        - פנה לשולח במגדר הנכון לפי שמו, ושמור על אותו מגדר בשלוש התשובות. זו \
        הטעות שהכי מסגירה תרגום מאנגלית. בחר מגדר אחד וכתוב בו: לא צורות עם \
        לוכסן ("תוכל/י"), ולא בריחה לניסוח נייטרלי כדי לא להכריע.
        - השתמש בפרטים שההודעה נתנה לך. שעה, יום או מספר שהשולח נקב בהם שייכים \
        לתשובה שעונה עליהם: "כן, יום חמישי מתאים לי", ולא "כן, אני מגיע".
        - אל תוסיף פרטים משלך. לעולם אל תנקוב במועד שבו משהו ייעשה אלא אם ההודעה \
        עצמה נקבה בו: בלי "בהקדם", בלי "מיד", ובלי יום שהשולח לא הזכיר. אם הצעה \
        נגדית דורשת פרט חדש, השאר אותו פתוח ("מתי נוח לך?") במקום להמציא.
        - משפט אחד או שניים בכל תשובה. בלי פנייה בהתחלה ובלי חתימה בסוף.
        """
}
