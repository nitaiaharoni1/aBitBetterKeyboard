import Foundation

extension Prompts {

    // MARK: Tone

    /// `instruction` is the user's own register, written by them under
    /// Settings › Default tone › My tone. It arrives one line long and capped at
    /// `SharedStore.customToneLimit`, because `SharedStore.oneLine` collapses it
    /// on the way out of the store — this function does not sanitise, it composes.
    ///
    /// It **replaces** the built-in direction rather than being appended to it.
    /// The six directions are mutually exclusive registers: "Shorter. The result
    /// must be strictly fewer words than the original" standing beside "warm and
    /// chatty, like a friend" is two instructions arguing, and the model picks one.
    /// `tone` is still passed because it is what `RewriteVariant` and the result
    /// panel label the answer with.
    ///
    /// The line is quoted as *the user's words* rather than issued as an
    /// instruction, and the base's language rule is deliberately left ahead of it.
    ///
    /// **A register in a script the chosen set does not speak is dropped here,
    /// and here is the only place that can be trusted to do it.** The two sets
    /// are never merged — the file comment above is the measurement — and a
    /// user's register is free text: nothing between the field in Settings and
    /// this line constrains its script, and on a Hebrew-first keyboard
    /// `קצר וישיר, בלי נימוסים` is the expected thing to find in it. Pasting that
    /// into the English set is the merge, whichever engine then runs it, so the
    /// guard belongs in the composer rather than in one engine: the on-device one
    /// had it and the cloud one did not, and the router steers exactly that pair
    /// at the cloud.
    ///
    /// The English set speaks Latin. The Hebrew set speaks Hebrew *and* Latin,
    /// because its own rules are about English loanwords keeping their letters.
    /// Anything else falls back to the built-in register, which is what
    /// `ToneSetting.custom(nearest:)` exists to be.
    static func tone(_ tone: ToneStyle, for text: String, instruction: String? = nil) -> String {
        if isHebrew(text) {
            let direction =
                register(instruction, spokenBy: [.hebrew, .latin])
                .map {
                    "כתוב ברגיסטר שהמשתמש ביקש, במילים שלו: «\($0)». זו בקשה על הסגנון בלבד, וכל הכללים למעלה גוברים עליה."
                } ?? hebrewDirection(tone)
            return "\(hebrewToneBase)\n\nהרגיסטר המבוקש: \(direction)"
        }
        let direction =
            register(instruction, spokenBy: [.latin])
            .map {
                "The register the user asked for, in their own words: «\($0)». That is a request about style only, and every rule above still holds."
            } ?? englishDirection(tone)
        return "\(englishToneBase)\(scriptDirective(for: text))\n\nThe register to write in: \(direction)"
    }

    /// The user's register, or nil when quoting it would put a second language
    /// inside an instruction set written in one.
    private static func register(_ instruction: String?, spokenBy scripts: Set<TextScript>) -> String? {
        let asked = instruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !asked.isEmpty, LanguageDetector.scripts(in: asked).isSubset(of: scripts) else {
            return nil
        }
        return asked
    }

    private static let englishToneBase = """
        You rewrite one message in a requested register. You return the rewritten \
        message and nothing else.

        Rules:
        - Same language as the message. Never translate.
        - The message still says what it said, and still points the same way. \
        Postponing a Friday review does not become postponing something to Friday.
        - Keep every specific in it: times, dates, names, numbers. Add none.
        - Rewrite the sentence. Do not bolt a phrase onto the front of the original \
        and return the rest untouched.
        - Never open with "To be clear", "Just to confirm", "I wanted to make sure" \
        or any similar filler.
        - No preamble, no explanation, no quotation marks around the answer.
        """

    private static let hebrewToneBase = """
        אתה מנסח מחדש הודעה אחת ברגיסטר מבוקש. אתה מחזיר את ההודעה המנוסחת בלבד.

        כללים:
        - התשובה כולה בעברית. לעולם אל תתרגם לאנגלית.
        - מילים באנגלית נשארות באותיות לטיניות עם התחילית העברית במקף.
        - ההודעה עדיין אומרת את מה שהיא אמרה. כל פרט קונקרטי נשמר, ושום פרט חדש \
        לא נוסף.
        - נסח את המשפט מחדש. אל תדביק ביטוי בהתחלה ותשאיר את השאר כמו שהוא.
        - אל תפתח ב"רציתי לוודא", "רק לוודא" או כל מילת מילוי דומה.
        - בלי הקדמות, בלי הסברים ובלי מירכאות סביב התשובה.
        """

    private static func englishDirection(_ tone: ToneStyle) -> String {
        switch tone {
        case .clearer:
            return
                "Clearer. Cut hedges and filler ('just', 'probably', 'maybe', 'I think we should probably'). Separate what happened from what is suspected. Keep any uncertainty the writer actually meant."
        case .shorter:
            return
                "Shorter. The result must be strictly fewer words than the original while keeping every fact in it. Returning the message unchanged is a failure."
        case .professional:
            return
                "Professional. Suitable to send to a client or someone senior. Full sentences, correct capitalisation, requests phrased as questions. Not cold, and not longer than it needs to be."
        case .casual:
            return
                "Casual. The way you would message a colleague you know well. Contractions, plain words, no formality."
        case .confident:
            return
                "Confident. Remove hedging and apology. State the position directly. Do not add a justification, a slogan or a second sentence that was not there."
        case .friendly:
            return
                "Friendly. Warmer and more personal, an emoji only if the original had one or clearly invites it. Do not turn an apology into thanks or change what the message is doing."
        }
    }

    private static func hebrewDirection(_ tone: ToneStyle) -> String {
        switch tone {
        case .clearer:
            return
                "בהיר יותר. הורד מילות גידור ומילוי. הפרד בין מה שקרה לבין מה שמשוער. שמור על אי-הוודאות שהכותב באמת התכוון אליה."
        case .shorter:
            return
                "קצר יותר. התוצאה חייבת להיות קצרה ממש מהמקור ולשמור על כל העובדות שבו. החזרת ההודעה כמו שהיא היא כישלון."
        case .professional:
            return
                "מקצועי. מתאים לשליחה ללקוח או לבכיר. משפטים שלמים, בקשות מנוסחות כשאלה. לא קר, ולא ארוך מהנדרש."
        case .casual:
            return "יומיומי. כמו שכותבים לעמית שמכירים טוב. עברית מדוברת, בלי רשמיות."
        case .confident:
            return
                "נחרץ. הורד גידור והתנצלות ואמור את העמדה ישירות. אל תוסיף נימוק, סיסמה או משפט שני שלא היה שם."
        case .friendly:
            return
                "ידידותי. חם ואישי יותר, אימוג'י רק אם המקור הזמין את זה. אל תהפוך התנצלות לתודה ואל תשנה את מה שההודעה עושה."
        }
    }
}
