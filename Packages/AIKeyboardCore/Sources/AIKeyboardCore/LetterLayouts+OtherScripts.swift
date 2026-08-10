import Foundation

extension KeyboardLayout {

    /// The scripts with one keyboard each.
    static let otherScriptLayouts: [KeyboardLanguage: LetterLayout] = [
        // Apple's `Urdu`: 12 / 9 / 7 on the desktop, and two of those twelve keys
        // are bare harakat that Urdu does not write, so they are dropped and the
        // row is ten. Everything on the shift plane is a long press.
        .urdu: LetterLayout(
            ["قوعرتےئیہپ", "اسدفگھجکل", "زشچطبنم"],
            hasCase: false,
            alternates: alternates([
                "ا": "آ", "ت": "ٹ", "ج": "ض", "د": "ڈ", "ر": "ڑ", "ز": "ذ", "س": "ص", "ش": "ژ",
                "ط": "ظ", "ع": "\u{0651}", "ق": "\u{0652}", "ن": "ں", "و": "ؤ", "ئ": "ء",
                "پ": "\u{0657}", "چ": "ث", "ک": "خ", "گ": "غ", "ھ": "ح", "ہ": "ۂ",
                "ی": "\u{0670}", "ے": "\u{0656}"
            ])),

        // Apple's `Afghan Pashto`: Persian's arrangement plus the retroflex and
        // palatal letters Pashto adds, with the rest of its shift plane as long
        // presses.
        .pashto: LetterLayout(
            ["ضصثقفغعهخحجچ", "شسیبلاتنمکګ", "ۍېزرذدړوږ"],
            hasCase: false,
            alternates: alternates([
                "ا": "آ", "ب": "پ", "ت": "ټ", "ث": "\u{064D}", "ح": "څ", "خ": "ځ", "د": "ډ",
                "ر": "ء", "ز": "ژ", "س": "ئ", "ش": "ښ", "ص": "\u{064C}", "ض": "\u{0652}",
                "ع": "\u{064E}", "غ": "\u{0650}", "ف": "\u{064F}", "ق": "\u{064B}", "ل": "أ",
                "م": "ة", "ن": "ڼ", "ه": "\u{0651}", "ړ": "ؤ", "ګ": "گ", "ی": "ي", "ۍ": "ظ",
                "ې": "ط"
            ])),

        // Apple's `Georgian – QWERTY`. Georgian is unicameral — Mtavruli is for
        // headings, not for sentences — so there is no shift key and the seven
        // letters on Apple's shift plane are long presses.
        .georgian: LetterLayout(
            ["ქწერტყუიოპ", "ასდფგჰჯკლ", "ზხცვბნმ"],
            hasCase: false,
            alternates: alternates([
                "ზ": "ძ", "რ": "ღ", "ს": "შ", "ტ": "თ", "ც": "ჩ", "წ": "ჭ", "ჯ": "ჟ"
            ])),

        // Apple's `Dhivehi`. Thaana is right to left and writes its vowels as
        // marks, so six of the twenty-six keys are combining marks — which is why
        // the rows are written key by key: `އ` followed by `ެ` is one `Character`,
        // and as a string those two keys would silently become one.
        .dhivehi: LetterLayout(
            keys: [
                [
                    "\u{07B0}", "އ", "\u{07AC}", "ރ", "ތ", "ޔ", "\u{07AA}", "\u{07A8}",
                    "\u{07AE}", "ޕ"
                ],
                ["\u{07A6}", "ސ", "ދ", "ފ", "ގ", "ހ", "ޖ", "ކ", "ލ"],
                ["ޒ", "ޱ", "ޗ", "ވ", "ބ", "ނ", "މ"]
            ],
            hasCase: false,
            alternates: alternates([
                "ހ": "ޙ", "ނ": "ޞ", "ރ": "ޜ", "ބ": "ޝ", "ކ": "ޚ", "އ": "ޢ", "ވ": "ޥ", "މ": "ޏ",
                "ފ": "ޛ", "ދ": "ޑ", "ތ": "ޓ", "ލ": "ޅ", "ގ": "ޣ", "ސ": "ށ", "ޒ": "ޡ", "ޖ": "ޟ",
                "ޗ": "ޘ", "ޱ": "ޠ", "\u{07A6}": "\u{07A7}", "\u{07A8}": "\u{07A9}",
                "\u{07AA}": "\u{07AB}", "\u{07AC}": "\u{07AD}", "\u{07AE}": "\u{07AF}",
                "\u{07B0}": "ޤ"
            ])),

        // Apple's `Tamil99`, which is Tamil's own arrangement rather than a
        // transliteration: the vowels lead the rows and the pulli ் is a key.
        // Written key by key, and its alternates written out as arrays, for the
        // Devanagari reason — `ஸ` followed by `ா` is one `Character`, so
        // `"ஸா"` as an alternates string would offer one option, not two.
        .tamil: LetterLayout(
            keys: [
                ["ஆ", "ஈ", "ஊ", "ஐ", "ஏ", "ள", "ற", "ன", "ட", "ண", "ச", "ஞ"],
                ["அ", "இ", "உ", "\u{0BCD}", "எ", "க", "ப", "ம", "த", "ந", "ய"],
                ["ஔ", "ஓ", "ஒ", "வ", "ங", "ல", "ர", "ழ"]
            ],
            hasCase: false,
            alternates: [
                "ஆ": ["ஸ", "\u{0BBE}"], "இ": ["\u{0BBF}"], "ஈ": ["ஷ", "\u{0BC0}"],
                "உ": ["\u{0BC1}"], "ஊ": ["ஜ", "\u{0BC2}"], "எ": ["\u{0BC6}"],
                "ஏ": ["\u{0BC7}"], "ஐ": ["ஹ", "\u{0BC8}"], "ஒ": ["\u{0BCA}"],
                "ஓ": ["\u{0BCB}"], "ஔ": ["\u{0BCC}"], "ற": ["ஶ"], "\u{0BCD}": ["ஃ"]
            ])
    ]
}
