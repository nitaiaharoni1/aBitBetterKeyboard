import Foundation

// MARK: - Letter layout data
//
// The layout dictionaries that `KeyboardLayout.letterLayouts` merges.
// Kept in separate files so `KeyboardLayout.swift` stays focused on
// width-solving and row-building logic.
//
// originalLayouts and devanagariInScript: this file.
// latinLayouts and cyrillicLayouts:       LetterLayouts+Latin.swift
// otherScriptLayouts:                     LetterLayouts+OtherScripts.swift

extension KeyboardLayout {

    static let originalLayouts: [KeyboardLanguage: LetterLayout] = [
        .english: LetterLayout(
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),

        // 22 letters plus 5 final forms across 8 / 10 / 9 keys, and no case, so no
        // shift key. The short top row carries delete, matching Apple's Hebrew
        // keyboard.
        //
        // The long presses are `hebrewMarks` rather than a shift plane: a script
        // with no case usually spends its alternates on the letters Apple hid
        // behind shift, and Hebrew hides none.
        .hebrew: LetterLayout(hebrewRows, hasCase: false, alternates: hebrewMarks),

        // Apple's `Arabic`: 12 / 10 / 7. أ إ آ ء ؤ ئ ى are on its shift plane,
        // and Arabic has no case, so they are long presses here.
        .arabic: LetterLayout(
            ["ضصثقفغعهخحجة", "شسيبلاتنمك", "ظطذدزرو"],
            hasCase: false,
            alternates: alternates(["ا": "أإآء", "و": "ؤ", "ي": "ئى", "ة": "ه"])),

        // Apple's `Persian – Standard`: 12 / 11 / 8. ژ and the hamza forms are on
        // its shift plane, and `persianHalfSpace` rides on every letter beside
        // them.
        .persian: LetterLayout(
            persianRows,
            hasCase: false,
            alternates: alternates([
                "ا": "آأإء", "و": "ؤ", "ی": "يئى", "ک": "ك", "ز": "ژ", "ه": "ة"
            ]).merging(persianHalfSpace) { letters, half in letters + half }),

        // Apple's `Russian`: 12 / 11 / 9. ё is on the bracket key, which a phone
        // does not have, so it is the long press of е — as it is on iOS.
        .russian: LetterLayout(
            ["йцукенгшщзхъ", "фывапролджэ", "ячсмитьбю"],
            alternates: alternates(["е": "ё"])),

        // Apple's `Ukrainian`: 12 / 11 / 9, with ґ on a key a phone does not have.
        //
        // The apostrophe ʼ closes the home row, where Apple's own layout puts it —
        // the key beside `'` on an ISO keyboard. CLDR lists it as a letter of the
        // Ukrainian alphabet because it is one (`з'їзд`), and without it the only
        // thing to reach for was the ASCII `'` on the numbers plane.
        .ukrainian: LetterLayout(
            ["йцукенгшщзхї", "фівапролджєʼ", "ячсмитьбю"],
            alternates: alternates(["г": "ґ", "и": "і"])),

        // Apple's `Greek`: 9 / 9 / 7, the ; at the q position dropped. Every
        // accented vowel is a dead key there and a long press here.
        .greek: LetterLayout(
            ["ςερτυθιοπ", "ασδφγηξκλ", "ζχψωβνμ"],
            alternates: alternates([
                "α": "ά", "ε": "έ", "η": "ή", "ι": "ίϊΐ", "ο": "ό", "υ": "ύϋΰ", "ω": "ώ"
            ])),

        // Apple's `Turkish Q`: 12 / 11 / 9. ı and i are separate keys, as they are
        // separate letters.
        .turkish: LetterLayout(
            ["qwertyuıopğü", "asdfghjklşi", "zxcvbnmöç"], alternates: latin()),

        .french: LetterLayout(
            ["azertyuiop", "qsdfghjklm", "wxcvbn"], alternates: latin()),

        .german: LetterLayout(
            ["qwertzuiopü", "asdfghjklöä", "yxcvbnm"], alternates: latin()),

        .spanish: LetterLayout(
            ["qwertyuiop", "asdfghjklñ", "zxcvbnm"], alternates: latin()),

        .portuguese: LetterLayout(
            ["qwertyuiop", "asdfghjklç", "zxcvbnm"], alternates: latin()),

        .italian: LetterLayout(
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),

        // Apple's `Hindi – InScript`, whose whole shifted plane becomes long
        // presses: Devanagari has no case, so a shift key would have nothing to
        // do, and half the consonants live up there. ञ rides on ज and ष on स,
        // because the phone rows are one key shorter than the desktop ones, and
        // the nukta forms ride on the letters they are formed from.
        //
        // ृ earns a key of its own rather than a long press: it is the vowel in
        // कृपया, and InScript puts it on `=`, a key a phone does not have. ऋ is
        // its shifted partner and rides on it; the visarga ः joins ं and ँ,
        // which are the other two marks of its kind.
        .hindi: devanagariInScript,

        // Marathi and Nepali are written in the same script on the same layout:
        // `Marathi – InScript` and `Nepali – InScript` extract to exactly the
        // rows and shifted plane `Hindi – InScript` does, key for key.
        .marathi: devanagariInScript,
        .nepali: devanagariInScript
    ]

    /// Hebrew's three rows, named rather than written inline above so the geresh
    /// table below is derived from the same twenty-seven keys instead of
    /// restating them.
    static let hebrewRows = ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"]

    /// The two marks Hebrew writes *inside* a word, on every letter: hold צ and
    /// the popup offers צ, then צ׳, then צ״.
    ///
    /// **Neither is reachable any other way, and that is measured rather than
    /// assumed.** Sweeping Apple's own macOS Hebrew layout for the characters it
    /// produces that this keyboard cannot type leaves the geresh U+05F3, the
    /// gershayim U+05F4, the maqaf U+05BE and the niqqud. The first two are here.
    /// The geresh carries the borrowed consonants of loanwords (ג׳ירפה, צ׳יפס),
    /// ends an abbreviation (עמ׳) and marks a letter standing in for a number
    /// (א׳ ב׳ ג׳); the gershayim sits before the last letter of an acronym, which
    /// is how Hebrew writes most institutions and half its everyday nouns —
    /// צה״ל, ארה״ב, דו״ח — so it can follow any letter of the alphabet too.
    ///
    /// **The whole alphabet, not the handful that conventionally take one.**
    /// ג׳ ז׳ צ׳ ד׳ ת׳ are the list somebody would sit down and write for the
    /// geresh, and the acronym rule alone already reaches every letter. A key
    /// whose hold does something on some letters and nothing on others is a key
    /// nobody learns to hold. It costs two entries each and no screen space: the
    /// popup only exists under a finger that is already down.
    ///
    /// **Written as arrays because `alternates(_:)` would split each one in
    /// half.** That helper takes one alternate per `Character`, which is right for
    /// the accents it was built for and wrong here: U+05F3 and U+05F4 are spacing
    /// punctuation rather than combining marks, so `"צ׳"` is two `Character`s and
    /// the helper would offer צ and a bare ׳ as two separate long presses — the
    /// same trap `devanagariInScript` hits from the other side, where two marks
    /// that should have been separate fuse into one.
    static let hebrewMarks: [String: [String]] = Dictionary(
        uniqueKeysWithValues: hebrewRows.joined().map {
            (String($0), [String($0) + "\u{05F3}", String($0) + "\u{05F4}"])
        })

    /// Persian's rows, named for the same reason Hebrew's are: the table below is
    /// derived from them rather than restating them.
    static let persianRows = ["ضصثقفغعهخحجچ", "شسیبلاتنمکگ", "ظطزرذدپو"]

    /// The half-space, نیم‌فاصله, on every Persian letter: hold ی and the popup
    /// offers ی then ی␣.
    ///
    /// **Persian is misspelled without it, and it is the one mark Apple's own
    /// iOS Persian keyboard declares.** `InputMode_fa.plist` in the simulator
    /// runtime lists `UIKeyboardNonstopPunctuationCharacters = "\u{200C}"` and
    /// nothing else — the same key in `InputMode_he.plist` lists exactly the
    /// geresh and the gershayim, which is what `hebrewMarks` carries. U+200C
    /// separates a prefix or a suffix from its stem without breaking the word:
    /// `می‌روم`, `کتاب‌ها`. Written `میروم` it is a spelling mistake, and this
    /// keyboard could not type it at all.
    ///
    /// **It is the only alternate that draws nothing**, which is why
    /// `KeyView.displayLabel` exists: `ی` and `ی‌` are the same picture in a
    /// popup, since a zero-width character has no width and the letter before it
    /// is isolated either way. The popup draws the half-space as `␣` and inserts
    /// the real character.
    static let persianHalfSpace: [String: [String]] = Dictionary(
        uniqueKeysWithValues: persianRows.joined().map {
            (String($0), [String($0) + "\u{200C}"])
        })

    static let devanagariInScript = LetterLayout(
        keys: [
            ["ौ", "ै", "ा", "ी", "ू", "ब", "ह", "ग", "द", "ज", "ड"],
            ["ो", "े", "्", "ि", "ु", "प", "र", "क", "त", "च", "ट"],
            ["ॉ", "ं", "म", "न", "व", "ल", "स", "य", "ृ"]
        ],
        hasCase: false,
        alternates: alternates([
            "ौ": "औ", "ै": "ऐ", "ा": "आ", "ी": "ई", "ू": "ऊ", "ब": "भ", "ह": "ङ",
            "ग": "घग़", "द": "ध", "ज": "झञज़", "ड": "ढड़ढ़",
            "ो": "ओ", "े": "ए", "्": "अ", "ि": "इ", "ु": "उ", "प": "फफ़", "र": "ऱ",
            "क": "खक़", "त": "थ", "च": "छ", "ट": "ठ",
            "ॉ": "ऑ", "म": "ण", "न": "ऩ", "व": "ऴ", "ल": "ळ", "स": "शष",
            "य": "य़।", "ृ": "ऋ"
        ]).merging(
            // Written out because `"ँः"` is one `Character`: two combining
            // marks in a row fuse, and as a string these two alternates would
            // silently become one. The nukta ़ is here for the same reason —
            // appended to `"ढड़ढ़"` it would fuse with the ढ़ before it — and it is
            // here at all because Apple's own InScript gives it a key at the end
            // of the top row, which is one key longer than a phone's. It sits
            // with the two letters formed from it that this key already offers.
            [
                "ं": ["ँ", "ः"],
                "ड": ["ढ", "ड़", "ढ़", "\u{093C}"]
            ], uniquingKeysWith: { _, explicit in explicit }))
}
