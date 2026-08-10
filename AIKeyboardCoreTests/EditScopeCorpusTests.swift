import XCTest

@testable import AIKeyboardCore

/// Corpus-table tests extracted from `EditScopeTests`.
final class EditScopeCorpusTests: XCTestCase {

    // MARK: The corpus, as a table

    /// Every Fix entry in `Bar/ai-text`, as `(what the user typed, what a good
    /// writer produces, the corrections that names)`. Applying the scope check to
    /// a reference answer has to give that answer back: if it does not, the rule
    /// is undoing a correction the product is measured on.
    func testTheScopeCheckNeverUndoesACorrectionTheReferenceAnswersMake() {
        let corpus = [
            (
                "I dont think we should do it because its not make sense",
                "I don't think we should do it because it doesn't make sense.",
                "dont -> don't, its not -> it doesn't, sense -> sense."
            ),
            (
                "Sounds good, I'll send you the deck tonight.",
                "Sounds good, I'll send you the deck tonight.",
                "none"
            ),
            (
                "The onboarding is good but its flow breaks on the last screen",
                "The onboarding is good but its flow breaks on the last screen",
                "none"
            ),
            (
                "can you send me the id for the sprint ticket",
                "Can you send me the ID for the sprint ticket?",
                "can -> Can, id -> ID, ticket -> ticket?"
            ),
            (
                "sorry i was ill last week and didnt see your message",
                "Sorry, I was ill last week and didn't see your message",
                "sorry i -> Sorry, I, didnt -> didn't"
            ),
            (
                "he said \"i dont know\" and left it there",
                "He said \"I don't know\" and left it there.",
                "he -> He, \"i dont -> \"I don't, there -> there."
            ),
            (
                "omg that meeting was sooo long 😅 im gonna need coffee",
                "omg that meeting was sooo long 😅 I'm gonna need coffee",
                "im -> I'm"
            ),
            (
                "Ill sedn you teh updated presentaion after the standup tommorow",
                "I'll send you the updated presentation after the standup tomorrow.",
                "Ill sedn -> I'll send, teh -> the, presentaion -> presentation, tommorow -> tomorrow."
            ),
            (
                "the numbers from last week doesnt match what the dashboard show",
                "The numbers from last week don't match what the dashboard shows.",
                "the -> The, doesnt -> don't, show -> shows."
            ),
            (
                "Please dont forget to send the invoice before the 15th, otherwise finance wont process it this month.",
                "Please don't forget to send the invoice before the 15th, otherwise finance won't process it this month.",
                "dont -> don't, wont -> won't"
            ),
            (
                "היי, אני חושב שאנחנו צריכים לדבר על זה מחרר בבקשא",
                "היי, אני חושב שאנחנו צריכים לדבר על זה מחר בבקשה",
                "מחרר בבקשא -> מחר בבקשה"
            ),
            (
                "אני יבדוק את זה ואחזור אליך",
                "אני אבדוק את זה ואחזור אליך",
                "יבדוק -> אבדוק"
            ),
            (
                "תודה רבה, קיבלתי. אני עובר על זה עכשיו ומעדכן.",
                "תודה רבה, קיבלתי. אני עובר על זה עכשיו ומעדכן.",
                "none"
            ),
            (
                "מעולה, נתראה מחר בבוקר",
                "מעולה, נתראה מחר בבוקר",
                "none"
            ),
            (
                "אתה יכול להעביר לי את הקובץ של אתמול",
                "אתה יכול להעביר לי את הקובץ של אתמול?",
                "אתמול -> אתמול?"
            ),
            (
                "יאללה סבבה, נדבר אח\"כ",
                "יאללה סבבה, נדבר אח\"כ",
                "none"
            ),
            (
                "שלחתי לך את הקובץ אתמול בערב, תגדי לי אם קיבלת",
                "שלחתי לך את הקובץ אתמול בערב, תגיד לי אם קיבלת",
                "תגדי -> תגיד"
            ),
            (
                "מה קורה אני מנסה להתקשר אליך כל הבוקר",
                "מה קורה? אני מנסה להתקשר אליך כל הבוקר",
                "קורה -> קורה?"
            ),
            (
                "אני אשלח לך את ה-document מחר אחרי ה-standup",
                "אני אשלח לך את ה-document מחר אחרי ה-standup",
                "none"
            ),
            (
                "העליתי את התיקון ל-staging והכל עובד, its fine",
                "העליתי את התיקון ל-staging והכל עובד, it's fine",
                "its -> it's"
            ),
            (
                "Can you check the deployment on staging, אני חושב שיש שם באג בבקשא",
                "Can you check the deployment on staging? אני חושב שיש שם באג, בבקשה",
                "staging, -> staging?, באג בבקשא -> באג, בבקשה"
            ),
            (
                "בוא נעשה sync קצר על ה-roadmap של Q3",
                "בוא נעשה sync קצר על ה-roadmap של Q3",
                "none"
            ),
            (
                "אנני צריך את ה-API key בשביל ה-demo של מחר",
                "אני צריך את ה-API key בשביל ה-demo של מחר",
                "אנני -> אני"
            ),
            (
                "צריך לעשות refactor ל-service הזה לפני ה-release",
                "צריך לעשות refactor ל-service הזה לפני ה-release",
                "none"
            )
        ]
        for (source, reference, corrections) in corpus {
            XCTAssertEqual(
                EditScope.applied(reference, to: source, corrections: corrections),
                reference,
                "the scope check changed the reference answer for \(source.debugDescription)"
            )
        }
    }
}
