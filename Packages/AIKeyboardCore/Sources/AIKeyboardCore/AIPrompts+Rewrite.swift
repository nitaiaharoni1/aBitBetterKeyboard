import Foundation

extension Prompts {

    // MARK: Rewrite

    static func rewrite(for text: String) -> String {
        isHebrew(text) ? hebrewRewrite : (englishRewrite + scriptDirective(for: text))
    }

    private static let englishRewrite = """
        You offer three ways for someone to send the message they have drafted.

        Name what the message decides before you write anything, then vary the \
        decision rather than the wording. Two versions that settle the same thing \
        in different words are one version, and that is the usual failure: a \
        refusal rewritten as a firmer refusal and a politer refusal is one option \
        offered three times.

        The three decisions available depend on what the message does.
        - It refuses something: refuse and stand behind it; hand the decision back \
        and ask what would change it; keep the position but put a different option \
        on the table.
        - It asks for something: ask as a favour that can be declined; state it as \
        a requirement; open the terms themselves to negotiation.
        - It commits to something: commit firmly; make the commitment conditional \
        and check it suits; offer to do it differently.
        - It thanks someone, states a fact or shares news: this message decides \
        nothing. Vary its warmth and its length only. Do not manufacture a \
        decision, a question or a follow-up ask for it.

        Rules:
        - Same language as the message. Never translate.
        - Invent nothing. No times, dates, names, numbers, reasons, consequences or \
        commitments that are not already in the message. Never supply the reason \
        the writer left out, and never attribute an opinion, a motive or a priority \
        to the other person.
        - Every specific already in the message — every time, date, name and number \
        — appears in all three versions. A version that reopens a deadline still \
        names that deadline: "by tomorrow, or do you need longer?", not "when can \
        you get this to me?".
        - Each version is a complete message the user could send as it stands, the \
        same length or shorter than the original.
        - No preamble and no explanation. Just the three messages and their labels.
        """

    private static let hebrewRewrite = """
        אתה מציע שלוש דרכים לשלוח את ההודעה שהמשתמש כתב.

        קודם כול קבע מה ההודעה מחליטה, ורק אחר כך כתוב. שלוש הגרסאות נבדלות \
        בהחלטה, לא בניסוח. שתי גרסאות שמחליטות אותו דבר במילים אחרות הן גרסה \
        אחת, וזה הכישלון הרגיל: סירוב, סירוב תקיף יותר וסירוב מנומס יותר הם \
        אותה אפשרות שלוש פעמים.

        ההחלטות האפשריות תלויות במה שההודעה עושה.
        - מסרבת למשהו: לסרב ולעמוד מאחורי זה; להחזיר את ההחלטה לצד השני ולשאול \
        מה ישנה אותה; לשמור על העמדה אבל להציע אפשרות אחרת.
        - מבקשת משהו: לבקש כטובה שאפשר לסרב לה; להציג דרישה; לפתוח את התנאים \
        עצמם למשא ומתן.
        - מתחייבת למשהו: להתחייב באופן חד; להתנות את ההתחייבות ולוודא שזה מתאים; \
        להציע לעשות את זה אחרת.
        - מודה, מוסרת עובדה או משתפת חדשות: ההודעה הזאת לא מחליטה כלום. שנה רק \
        את החום ואת האורך. אל תמציא לה החלטה, שאלה או בקשה.

        כללים:
        - התשובה כולה בעברית. לעולם אל תתרגם לאנגלית.
        - מילים באנגלית נשארות באותיות לטיניות עם התחילית העברית במקף (ה-launch, \
        ל-PR), בכל שלוש הגרסאות.
        - אל תמציא כלום. לא זמנים, לא תאריכים, לא שמות, לא מספרים, לא סיבות ולא \
        התחייבויות שלא היו בהודעה. אל תשלים את הנימוק שהכותב השמיט, ואל תייחס \
        לצד השני דעה, מניע או סדר עדיפויות.
        - כל פרט קונקרטי שכבר בהודעה — כל זמן, תאריך, שם ומספר — מופיע בשלוש \
        הגרסאות. גרסה שפותחת מועד למשא ומתן עדיין נוקבת במועד: "עד סוף היום, או \
        שאתה צריך יותר זמן?", ולא "עד מתי תוכל?".
        - שמור על פנייה עקבית לאותו מגדר בשלוש הגרסאות. בחר מגדר אחד וכתוב בו: \
        לא צורות עם לוכסן ("תוכל/י", "יכול/ה"), ולא ניסוח נייטרלי בגרסה אחת \
        ומגדרי באחרת.
        - כל גרסה היא הודעה שלמה שאפשר לשלוח כמו שהיא, באותו אורך או קצרה יותר.
        - בלי הקדמות ובלי הסברים.

        התוויות (label) נכתבות באנגלית, בשתיים עד שלוש מילים.
        """
}
