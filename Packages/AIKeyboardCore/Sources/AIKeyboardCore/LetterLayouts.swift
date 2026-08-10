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
        // shift key. Apple puts delete at the end of the short *top* row here;
        // this keyboard keeps it on the bottom row with every other language, for
        // the reason `letters(for:)` gives — the language changes under the user's
        // thumb, so the keys around it must not.
        .hebrew: LetterLayout(
            ["קראטוןםפ", "שדגכעיחלךף", "זסבהנמצתץ"], hasCase: false),

        // Apple's `Arabic`: 12 / 10 / 7. أ إ آ ء ؤ ئ ى are on its shift plane,
        // and Arabic has no case, so they are long presses here.
        .arabic: LetterLayout(
            ["ضصثقفغعهخحجة", "شسيبلاتنمك", "ظطذدزرو"],
            hasCase: false,
            alternates: alternates(["ا": "أإآء", "و": "ؤ", "ي": "ئى", "ة": "ه"])),

        // Apple's `Persian – Standard`: 12 / 11 / 8. ژ and the hamza forms are on
        // its shift plane.
        .persian: LetterLayout(
            ["ضصثقفغعهخحجچ", "شسیبلاتنمکگ", "ظطزرذدپو"],
            hasCase: false,
            alternates: alternates([
                "ا": "آأإء", "و": "ؤ", "ی": "يئى", "ک": "ك", "ز": "ژ", "ه": "ة"
            ])),

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
