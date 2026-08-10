import CoreGraphics
import Foundation

// MARK: - Key model

public enum KeyCap: Equatable, Sendable {
    case character(String)
    case shift
    case backspace
    /// Switches to another plane. The label is what the key shows now, not where it goes.
    case plane(KeyboardPlane, label: String)
    case globe
    case space
    case ret
    case dictation
    /// The three controls that used to exist only as chrome in the suggestion
    /// bar, plus the three the layout editor adds.
    ///
    /// They are caps rather than special-cased views because the point of the
    /// editor is that a user can move them into the grid, and a grid key is a
    /// `KeySpec`. Drawing them here also means one implementation: a control
    /// cannot behave differently depending on which of the two places it was put.
    case emoji
    case aiMenu
    case quickTone
    case cursorLeft
    case cursorRight
    case hideKeyboard
    /// Reply and Fix, run straight from a key.
    ///
    /// **They exist because the action row made them destinations rather than
    /// menu items.** `aiMenu` opens a panel that lists four actions and costs a
    /// tap to reach any of them; with a row of actions under the keys, the two
    /// that need no further choice run outright. Rewrite keeps needing one — a
    /// register — so it stays `quickTone`, which runs the default and holds the
    /// rest behind a long press.
    ///
    /// Fix is deliberately not folded into `quickTone`. `KeyboardController`
    /// `runDefaultTone` carries the reason the one-tap button is Rewrite and not
    /// Fix: `Prompts.fix` keeps the writer's register on purpose and `EditScope`
    /// undoes any change the model cannot name as a mistake, so a tone pointed at
    /// Fix would have nothing to do.
    case aiReply
    case aiFix

    public var isFunctionKey: Bool {
        switch self {
        case .character: return false
        case .space: return false
        default: return true
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .character(let value): return value
        case .shift: return "Shift"
        case .backspace: return "Delete"
        case .plane(_, let label): return label
        case .globe: return "Next keyboard"
        case .space: return "Space"
        case .ret: return "Return"
        case .dictation: return "Dictate"
        case .emoji: return "Emoji"
        case .aiMenu: return "AI actions"
        case .quickTone: return "One-tap rewrite"
        case .cursorLeft: return "Cursor left"
        case .cursorRight: return "Cursor right"
        case .hideKeyboard: return "Hide keyboard"
        // The action's own title, so the key and the row label cannot drift.
        case .aiReply: return AIAction.reply.title
        case .aiFix: return AIAction.fix.title
        }
    }
}

/// How wide a key is, in multiples of the standard letter key.
public enum KeyWidth: Equatable, Sendable {
    case unit(CGFloat)
    /// Splits whatever is left over in the row between all keys marked flexible.
    case flexible
    /// Shift and delete share the space the letters do not use, the way iOS does it.
    case remainderShare
}

public struct KeySpec: Identifiable, Equatable, Sendable {
    public let id: String
    public let cap: KeyCap
    public let width: KeyWidth

    /// What a long press on this key offers instead.
    ///
    /// This is where every accent, hamza form and InScript shifted consonant
    /// lives. Without it a keyboard with three rows and no popup has to choose
    /// between an unfaithful layout and an unreachable letter: Apple's own
    /// Arabic layout has no key for أ, its Greek layout has no key for ά, and its
    /// Hindi layout puts half the consonants behind shift. Empty for most keys.
    public let alternates: [String]

    public init(
        _ cap: KeyCap, width: KeyWidth = .unit(1), id: String? = nil, alternates: [String] = []
    ) {
        self.cap = cap
        self.width = width
        self.alternates = alternates
        self.id = id ?? KeySpec.identifier(for: cap)
    }

    /// The id without the uniquing suffix a compiled custom key carries.
    ///
    /// `char-,#a1b2c3d4` addresses as `char-,`. Every key that is not compiled
    /// from a `SlotSpec` has no suffix and answers itself. This is what
    /// `KeyView`'s accessibility identifier is built from, so `key-space` finds
    /// the space bar whether it came from `bottomRow` or from a custom layout.
    public var addressableID: String {
        id.split(separator: "#", maxSplits: 1).first.map(String.init) ?? id
    }

    private static func identifier(for cap: KeyCap) -> String {
        switch cap {
        case .character(let value): return "char-\(value)"
        case .shift: return "shift"
        case .backspace: return "backspace"
        case .plane(_, let label): return "plane-\(label)"
        case .globe: return "globe"
        case .space: return "space"
        case .ret: return "return"
        case .dictation: return "dictation"
        case .emoji: return "emoji"
        case .aiMenu: return "ai-menu"
        case .quickTone: return "quick-tone"
        case .cursorLeft: return "cursor-left"
        case .cursorRight: return "cursor-right"
        case .hideKeyboard: return "hide-keyboard"
        // Kebab-case like their neighbours, because these reach a UI test and a
        // screen reader through `addressableID`: `key-ai-reply` is what a test
        // addresses, and it must not change once anything is written against it.
        case .aiReply: return "ai-reply"
        case .aiFix: return "ai-fix"
        }
    }
}

public struct KeyRow: Identifiable, Sendable {
    public let id: Int
    public let keys: [KeySpec]
    /// Extra inset on both sides, in units, for rows with fewer keys than the top row.
    public let sideInsetUnits: CGFloat

    public init(id: Int, keys: [KeySpec], sideInsetUnits: CGFloat = 0) {
        self.id = id
        self.keys = keys
        self.sideInsetUnits = sideInsetUnits
    }
}

// MARK: - Layouts

public enum KeyboardLayout {

    /// The rows for a language and plane. Row 4 is appended by `bottomRow`.
    public static func rows(for language: KeyboardLanguage, plane: KeyboardPlane) -> [KeyRow] {
        switch plane {
        case .letters:
            return letters(for: language)
        case .numbers:
            return numbers(for: language)
        case .symbols:
            return symbols(for: language)
        }
    }

    /// How many standard-width keys fit across, which sets the unit every row is
    /// measured in.
    ///
    /// Ten for Latin and Hebrew, and not ten for everything: Apple's own Russian,
    /// Turkish, Arabic and Persian layouts are twelve keys wide, and forcing them
    /// into ten either drops letters or overflows the screen. Never fewer than
    /// ten, so the nine-key Greek rows keep the same key size as English and
    /// centre instead of growing.
    ///
    /// **Shift and delete count against the budget, and for a year nothing said
    /// so.** The widest row alone is the right answer only while the bottom row
    /// is the short one, which it is in every layout that shipped first. Apple's
    /// Bulgarian puts *ten* letters on the bottom row beside eleven on the
    /// middle, so a budget of eleven left shift and delete nothing to stand in
    /// and the row ran 45pt off the side of an iPhone 17 Pro — a whole key and a
    /// half, not a rounding error. Belarusian overran by 9pt and Tongan by 10pt
    /// the same way. Reserving `functionKeyUnits` per stretcher fixes all three
    /// and moves no layout that was already correct: English needs 7 + 3 = 10,
    /// which is the ten it already had. The budget is asked of every row rather
    /// than of the bottom one alone, because a row that is not the bottom one can
    /// still be the widest.
    public static func columns(for language: KeyboardLanguage, plane: KeyboardPlane) -> Int {
        guard plane == .letters, let layout = letterLayouts[language] else { return 10 }
        let needed = layout.rows.indices.map { index in
            layout.rows[index].count + Int(stretchUnits(of: layout, row: index))
        }
        return max(10, needed.max() ?? 10)
    }

    /// How much of a row is taken by the function keys standing in it. Shift and
    /// delete both stand on the bottom row, in every language.
    private static func stretchUnits(of layout: LetterLayout, row index: Int) -> CGFloat {
        guard index == 2 else { return 0 }
        return layout.hasCase ? functionKeyUnits * 2 : functionKeyUnits
    }

    // MARK: Letters

    /// The three letter rows of one language.
    ///
    /// **Every row here was read out of Apple's own keyboard layout data**, not
    /// remembered: `TISCreateInputSourceList` plus `UCKeyTranslate` over the
    /// virtual key codes of the three letter rows, for the macOS input source of
    /// the same name (`Arabic`, `Persian – Standard`, `Russian`, `Ukrainian`,
    /// `Greek`, `Turkish Q`, `Hindi – InScript`, `French`, `German`, `Spanish`,
    /// `Portuguese`, `Italian`, and one per language for the fifty added since —
    /// `Bulgarian – Standard`, `Tamil99`, `Georgian – QWERTY`, `Dhivehi`, and so
    /// on, named in the comment above each group). Where Apple's layout puts a
    /// character behind shift or a dead key and the script has no case for a
    /// shift key to serve, it moves into `alternates` rather than being dropped.
    ///
    /// **The rule that turns a desktop layout into a phone one is four lines and
    /// it reproduces the twelve that were written first, key for key.** Take the
    /// base layer of the three letter rows and keep the keys that produce a
    /// letter, which is how a desktop 12 / 11 / 10 becomes English's 10 / 9 / 7
    /// without anybody choosing what to drop. For a script with no case, the
    /// shift layer of the same key becomes its long presses. Anything in the
    /// language's own CLDR alphabet that is still unreachable is placed by
    /// Unicode's own data — the same letter under the option layer, the
    /// diacritic-folded base, or the letter Unicode's character name says it is
    /// built from ("CYRILLIC SMALL LETTER GHE WITH STROKE" is a long press of
    /// ghe) — and a letter Apple puts on the key beside the home row lands at the
    /// end of the home row, where the hardware key sits. `LanguageCatalogueTests`
    /// checks the result rather than the recipe: every letter of the alphabet
    /// reachable, no two keys with one identity, nothing wider than the screen.
    ///
    /// **What was left out, and why, so nobody re-derives it.** Vietnamese, Thai,
    /// Lao, Khmer, Burmese, Tibetan, Amharic and Cherokee do not fit: their
    /// macOS layouts put letters the alphabet needs on the number row or behind
    /// dead keys, so three rows cannot hold them. Kazakh and Mongolian fail the
    /// same way, on nine and two letters. Bengali, Gujarati, Gurmukhi, Kannada,
    /// Malayalam, Odia, Telugu and Sinhala need the hand-tuning Devanagari got —
    /// their InScript layouts hide letters on keys a phone does not have — and
    /// that work is not done. Yiddish is the one dropped for a reason of its own:
    /// Apple's macOS layout emits Hebrew *presentation forms* (U+FB2E and
    /// friends) rather than the letter-plus-point sequences Yiddish is stored in,
    /// and it puts ק on two keys, which is two keys with one identity.
    private struct LetterLayout {
        /// Exactly three rows, top to bottom, **left to right on screen**. One
        /// entry per key.
        ///
        /// Left to right for every script, including the six that are written
        /// right to left, because that is what the source these rows come from
        /// says: `UCKeyTranslate` is asked for the virtual key codes of the three
        /// letter rows in physical order, and Apple's own iOS keyboard draws
        /// Hebrew and Arabic on those same physical keys — ק at the left of the
        /// top row, ض at the left of the Arabic one. Reading these as *logical*
        /// order and mirroring them is what shipped all six right-to-left
        /// keyboards backwards. `Bar/layouts/stock-rendered-rows.json` is Apple's
        /// keyboard measured on screen; `RenderedRowOrderTests` compares this
        /// keyboard's own rendering against it.
        let rows: [[String]]
        /// Whether the script has upper and lower case, and so a shift key.
        let hasCase: Bool
        /// Long-press alternates, keyed by the character on the key.
        let alternates: [String: [String]]

        /// Rows written as strings, one character per key.
        init(
            _ rows: [String], hasCase: Bool = true,
            alternates: [String: [String]] = [:]
        ) {
            self.init(
                keys: rows.map { $0.map(String.init) }, hasCase: hasCase,
                alternates: alternates)
        }

        /// Rows written key by key.
        ///
        /// **Devanagari has to use this one**, and the reason is a trap worth
        /// naming: a Devanagari row is mostly combining marks, and a run of
        /// combining marks in a Swift `String` is *one* `Character`. Written as a
        /// string, InScript's top row `ौैाीूबहगदजड` measures 7 rather than 11 —
        /// the five leading matras fuse into a single grapheme cluster and the
        /// keyboard silently draws four keys too few.
        init(
            keys rows: [[String]], hasCase: Bool = true,
            alternates: [String: [String]] = [:]
        ) {
            self.rows = rows
            self.hasCase = hasCase
            self.alternates = alternates
        }
    }

    /// Alternates written as a string, one character per alternate.
    ///
    /// **Safe for every script whose alternates are letters, and not safe for
    /// Devanagari**, which is why the alternates are arrays and this is only a
    /// convenience over them. It is the same trap as the rows: `"ँः"` — the
    /// candrabindu followed by the visarga — is *one* `Character`, so written as a
    /// string those two alternates silently become one, and the visarga becomes
    /// untypeable without any of it failing to compile. Anything with two
    /// combining marks beside each other has to be written out.
    private static func alternates(_ table: [String: String]) -> [String: [String]] {
        table.mapValues { $0.map(String.init) }
    }

    private static func letters(for language: KeyboardLanguage) -> [KeyRow] {
        guard let layout = letterLayouts[language] else { return letters(for: .english) }
        let columns = CGFloat(columns(for: language, plane: .letters))

        // Shift opens the bottom row when the script has case, and delete closes
        // that same row in every language. Both take whatever the letters leave;
        // the inset stops that being a half-row-wide delete key on a layout whose
        // row is short, as Arabic's seven-letter bottom one is against twelve
        // columns.
        //
        // **Delete stands in the same place in all sixty-four, and that is a
        // product decision over a fidelity one.** Apple's Hebrew keyboard puts it
        // at the end of the *top* row — `Bar/layouts/stock/he_IL.png` is the
        // photograph — but this keyboard changes language on a swipe along the
        // space bar, so following Apple made delete jump rows mid-sentence under
        // a thumb that was already reaching for it. Nothing else in the keyboard
        // moves when the language does; delete does not either.
        return layout.rows.indices.map { index in
            var keys: [KeySpec] = []
            if index == 2, layout.hasCase { keys.append(KeySpec(.shift, width: .remainderShare)) }
            keys += chars(layout.rows[index], alternates: layout.alternates)
            if index == 2 { keys.append(KeySpec(.backspace, width: .remainderShare)) }
            return KeyRow(
                id: index,
                keys: keys,
                sideInsetUnits: max(
                    0,
                    (columns - CGFloat(layout.rows[index].count)
                        - stretchUnits(of: layout, row: index)) / 2))
        }
    }

    /// How wide shift and delete want to be when the row has room to spare.
    /// Matches what they work out to on the English layout, where the row is full.
    private static let functionKeyUnits: CGFloat = 1.5

    /// Long-press alternates shared by every Latin layout: the accented forms
    /// iOS offers on its English keyboard. A superset of what French, German,
    /// Spanish, Portuguese, Italian and Turkish each need, and none of them needs
    /// a different set — an à is an à.
    private static let latinAlternates: [String: String] = [
        "a": "àáâäæãåā", "c": "çćč", "e": "èéêëēėę", "i": "îïíīįì",
        "l": "ł", "n": "ñńň", "o": "ôöòóœøōõ", "s": "ßśš", "u": "ûüùúū",
        "y": "ÿý", "z": "žźż"
    ]

    /// The shared Latin long presses plus whatever one language needs on top.
    ///
    /// **The extras are a measured delta, not a wish list.** Each one is a letter
    /// in the language's own CLDR alphabet (`NSLocale.exemplarCharacterSet`) that
    /// neither its three letter rows nor the shared set above can reach: Polish
    /// needs ą because the shared `a` stops at ā, Welsh needs ŵ ẁ ẃ ẅ, and
    /// Croatian needs nothing at all because š đ č ć are keys on its rows.
    private static func latin(_ extra: [String: String] = [:]) -> [String: [String]] {
        alternates(latinAlternates.merging(extra) { shared, extra in shared + extra })
    }

    /// **Split into four literals rather than one.** Sixty-four entries in a
    /// single dictionary literal is the shape that makes Swift's type checker
    /// give up; four named groups compile in seconds and read as the four
    /// families they are.
    private static let letterLayouts: [KeyboardLanguage: LetterLayout] =
        originalLayouts
        .merging(latinLayouts) { first, _ in first }
        .merging(cyrillicLayouts) { first, _ in first }
        .merging(otherScriptLayouts) { first, _ in first }

    private static let originalLayouts: [KeyboardLanguage: LetterLayout] = [
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
            alternates: alternates(["ا": "آأإء", "و": "ؤ", "ی": "يئى", "ک": "ك", "ز": "ژ", "ه": "ة"])),

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

    private static let devanagariInScript = LetterLayout(
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

    /// **Thirty-seven Latin keyboards, each Apple's own arrangement for that
    /// language.** The macOS input source is named beside every group that is
    /// not the plain `ABC`, and the rows are what `UCKeyTranslate` prints for its
    /// three letter rows with the punctuation keys dropped — which is exactly how
    /// English comes out 10 / 9 / 7 from a desktop 12 / 11 / 10.
    private static let latinLayouts: [KeyboardLanguage: LetterLayout] = [
        // Apple's `ABC`, the US arrangement, for the languages whose alphabet is
        // the plain Latin one. What differs between them is which accented forms
        // the long presses have to reach, and that comes from each language's own
        // CLDR alphabet rather than from a shared guess.
        .dutch: LetterLayout(["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),
        .filipino: LetterLayout(["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),
        .indonesian: LetterLayout(["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),
        .irish: LetterLayout(["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),
        .malay: LetterLayout(["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),
        .maori: LetterLayout(["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),
        .swahili: LetterLayout(["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin()),

        .latvian: LetterLayout(
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"],
            alternates: latin(["g": "ģ", "k": "ķ", "l": "ļ", "n": "ņ"])),
        .lithuanian: LetterLayout(
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin(["a": "ą", "u": "ų"])),
        .polish: LetterLayout(
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin(["a": "ą"])),
        .welsh: LetterLayout(
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"], alternates: latin(["w": "ŵẁẃẅ", "y": "ŷỳ"])),
        .igbo: LetterLayout(
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"],
            alternates: latin(["i": "ị", "n": "ṅ", "o": "ọ", "u": "ụ"])),
        .yoruba: LetterLayout(
            ["qwertyuiop", "asdfghjkl", "zxcvbnm"],
            alternates: latin(["e": "ẹ", "m": "ḿ", "n": "ǹ", "o": "ọ", "s": "ṣ"])),

        // Apple's `Hausa`, `Hawaiian` and `Samoan` each put one more letter at the
        // end of the home row — the glottal stop for the Polynesian pair, the
        // apostrophe for Hausa — and Apple's `Tongan` puts its at the start of the
        // bottom row, where the hardware key sits.
        .hausa: LetterLayout(
            ["qwertyuiop", "asdfghjklʼ", "zxcvbnm"],
            alternates: latin(["b": "ɓ", "d": "ɗ", "k": "ƙ", "y": "ƴ"])),
        .hawaiian: LetterLayout(["qwertyuiop", "asdfghjklʻ", "zxcvbnm"], alternates: latin()),
        .samoan: LetterLayout(["qwertyuiop", "asdfghjklʻ", "zxcvbnm"], alternates: latin()),
        .tongan: LetterLayout(["qwertyuiop", "asdfghjkl", "ʻzxcvbnm"], alternates: latin()),

        // Apple's `Haitian Creole` replaces q with ò and x with è, because
        // Haitian Creole has neither letter and needs both accents.
        .haitian: LetterLayout(["òwertyuiop", "asdfghjkl", "zècvbnm"], alternates: latin()),

        // Apple's `Spanish`, shared by the three languages of Spain it also
        // serves. Catalan's ç and the accented vowels are long presses.
        .catalan: LetterLayout(["qwertyuiop", "asdfghjklñ", "zxcvbnm"], alternates: latin()),

        // The Nordic layouts: å at the end of the top row, and the other two
        // vowels in the order that country writes them.
        .danish: LetterLayout(["qwertyuiopå", "asdfghjklæø", "zxcvbnm"], alternates: latin()),
        .norwegian: LetterLayout(["qwertyuiopå", "asdfghjkløæ", "zxcvbnm"], alternates: latin()),
        .swedish: LetterLayout(["qwertyuiopå", "asdfghjklöä", "zxcvbnm"], alternates: latin()),
        .finnish: LetterLayout(["qwertyuiopå", "asdfghjklöä", "zxcvbnm"], alternates: latin()),
        .faroese: LetterLayout(["qwertyuiopåð", "asdfghjklæø", "zxcvbnm"], alternates: latin()),
        .icelandic: LetterLayout(["qwertyuiopð", "asdfghjklæ", "zxcvbnmþ"], alternates: latin()),

        // **Central Europe is QWERTZ, and getting that wrong is not cosmetic.**
        // This machine ships `Czech` *and* `Czech – QWERTY`, `Slovak` and
        // `Slovak – QWERTY`, `Hungarian` and `Hungarian – QWERTY`. These three
        // rows were first taken from the `– QWERTY` half of each pair: a real
        // Apple layout, and the wrong one. y and z came out transposed, so a
        // Czech speaker typing `zítra` got `yítra`, and `byl`, `jazyk` and
        // `dobrý` all gained a z — roughly every second word, before anything
        // else in this product runs.
        //
        // Three of Apple's own sources agree on QWERTZ: the unqualified macOS
        // input source, `SWLayouts` in `InputMode_cs/sk/hu.plist` (`Czech-Slovak`
        // and `QWERTZ` respectively, ahead of the QWERTY variants), and
        // `VOTKeyboardMap-Czech.plist` and its siblings, which map y→z and z→y
        // while the `-QWERTY` files beside them do not. `LayoutProvenanceTests`
        // now diffs every row against `Bar/layouts/apple-layouts.json` position
        // by position, because no reachability check can see a transposition:
        // both letters are on the keyboard either way.
        //
        // The carons stay long presses because Apple's own layouts put them on
        // the number row, which a phone does not have.
        .czech: LetterLayout(
            ["qwertzuiopú", "asdfghjklů", "yxcvbnm"],
            alternates: latin(["d": "ď", "e": "ě", "r": "ř", "t": "ť"])),
        .slovak: LetterLayout(
            ["qwertzuiopúä", "asdfghjklô", "yxcvbnm"],
            alternates: latin(["d": "ď", "l": "ĺľ", "r": "ŕ", "t": "ť"])),
        .hungarian: LetterLayout(
            ["qwertzuiopőú", "asdfghjkléá", "yxcvbnm"], alternates: latin(["u": "ű"])),
        .estonian: LetterLayout(["qwertyuiopüõ", "asdfghjklöä", "zxcvbnm"], alternates: latin()),
        .romanian: LetterLayout(["qwertyuiopăî", "asdfghjklșț", "zxcvbnm"], alternates: latin()),

        // The former Yugoslav layout. Croatian and Slovene take it as QWERTZ,
        // Serbian in Latin script as QWERTY — and that split is Apple's, not a
        // guess: `InputMode_sr.plist` gives `sr_Latn` `SWLayouts[0] = "QWERTY"`.
        //
        // **Slovene is the one place Apple's two sources genuinely disagree, and
        // the file that disagrees says both halves out loud.**
        // `InputMode_sl.plist` carries `Hardware.Layout = "Slovenian"` — the
        // macOS input source, which is QWERTY — and `SWLayouts = ["QWERTZ", …]`
        // beside it, with `SWLayouts-iPadExtra` naming that first entry
        // `QWERTZ-Croatian`. Apple ships Slovene a QWERTY *hardware* layout and
        // a QWERTZ *software* one. This is a software keyboard, so the software
        // layout wins, and it is Croatian's arrangement key for key.
        .croatian: LetterLayout(["qwertzuiopšđ", "asdfghjklčć", "yxcvbnm"], alternates: latin()),
        .slovenian: LetterLayout(["qwertzuiopšđ", "asdfghjklčć", "yxcvbnm"], alternates: latin()),
        .serbianLatin: LetterLayout(
            ["qwertyuiopšđ", "asdfghjklčć", "zxcvbnm"], alternates: latin()),

        .albanian: LetterLayout(["qwertzuiopç", "asdfghjklë", "yxcvbnm"], alternates: latin()),
        .maltese: LetterLayout(["qwertyuiopġħ", "asdfghjkl", "zxcvbnm"], alternates: latin(["c": "ċ"])),

        // Apple's `Azeri` and `Turkmen`. Azerbaijani has Turkish's two i's and
        // the schwa ə on its own key; Turkmen puts ä where q would be and moves
        // q, x, c and v onto long presses of the letters that replaced them.
        .azerbaijani: LetterLayout(
            ["qüertyuiopöğ", "asdfghjklıə", "zxcvbnmçş"], alternates: latin()),
        .turkmen: LetterLayout(
            ["äwertyuiopňö", "asdfghjkl", "züçýbnm"], alternates: latin(["s": "ş"]))
    ]

    /// Six Cyrillic keyboards. Bulgarian is the odd one: its national layout is
    /// not a rearranged QWERTY at all, and Apple's `Bulgarian – Standard` is what
    /// this is.
    private static let cyrillicLayouts: [KeyboardLanguage: LetterLayout] = [
        .bulgarian: LetterLayout(["уеишщксдзц", "ьяаожгтнвмч", "юйъэфхпрлб"]),

        .belarusian: LetterLayout(
            ["йцукенгшўзх", "фывапролджэ", "ячсмітьбю"], alternates: alternates(["е": "ё"])),

        // Apple's `Kyrgyz` is Russian's layout, with the three letters Kyrgyz adds
        // on the option layer of the vowels they are formed from — which is where
        // this puts them too.
        .kyrgyz: LetterLayout(
            ["йцукенгшщзхъ", "фывапролджэ", "ячсмитьбю"],
            alternates: alternates(["е": "ё", "н": "ң", "о": "ө", "у": "ү"])),

        // Apple's `Tajik (Cyrillic)`: қ ҳ ҷ ӣ are keys, ғ and ӯ are not — Unicode
        // calls them "ghe with stroke" and "u with macron", so they long-press
        // from г and у.
        .tajik: LetterLayout(
            ["йқукенгшҳзхъ", "фҷвапролджэ", "ячсмитӣбю"],
            alternates: alternates(["г": "ғ", "е": "ё", "у": "ӯ"])),

        // Apple's `Serbian` and `Macedonian`, the former Yugoslav arrangement.
        // ж is on the key beside the home row on an ISO keyboard, so it lands at
        // the end of the home row here.
        .serbian: LetterLayout(["љњертзуиопшђ", "асдфгхјклчћж", "ѕџцвбнм"]),
        .macedonian: LetterLayout(["љњертѕуиопшѓ", "асдфгхјклчќж", "зџцвбнм"])
    ]

    /// The scripts with one keyboard each.
    private static let otherScriptLayouts: [KeyboardLanguage: LetterLayout] = [
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
                ["\u{07B0}", "އ", "\u{07AC}", "ރ", "ތ", "ޔ", "\u{07AA}", "\u{07A8}", "\u{07AE}", "ޕ"],
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

    // MARK: Numbers and symbols

    private static func numbers(for language: KeyboardLanguage) -> [KeyRow] {
        [
            KeyRow(id: 0, keys: chars(language.digits)),
            KeyRow(
                id: 1,
                keys: chars(connectors(for: language))
                    + [KeySpec(.character(language.currency))] + chars("&@\"")),
            KeyRow(
                id: 2,
                keys: [KeySpec(.plane(.symbols, label: "#+="), width: .remainderShare)]
                    + punctuation(for: language)
                    + [KeySpec(.backspace, width: .remainderShare)],
                sideInsetUnits: 0
            )
        ]
    }

    private static func symbols(for language: KeyboardLanguage) -> [KeyRow] {
        // The language's own currency leads, and the three that are not it follow,
        // so no row ever carries the same sign twice — two keys with one id is a
        // `ForEach` with duplicate identity.
        let others = ["$", "€", "¥", "•"].filter { $0 != language.currency }.prefix(3)
        return [
            KeyRow(id: 0, keys: chars("[]{}#%^*+=")),
            KeyRow(
                id: 1,
                keys: chars("_\\|~<>") + [KeySpec(.character(language.currency))]
                    + others.map { KeySpec(.character($0)) }),
            KeyRow(
                id: 2,
                keys: [KeySpec(.plane(.numbers, label: "123"), width: .remainderShare)]
                    + punctuation(for: language)
                    + [KeySpec(.backspace, width: .remainderShare)],
                sideInsetUnits: 0
            )
        ]
    }

    /// The run of connectors that opens the numbers plane's middle row.
    ///
    /// The semicolon is the one that moves. Greek writes its question mark as a
    /// semicolon, so its semicolon is the ano teleia — and leaving `;` in both
    /// rows put two keys with the same identity on one plane, which is a `ForEach`
    /// with duplicate identity and undefined behaviour, not a cosmetic clash.
    private static func connectors(for language: KeyboardLanguage) -> String {
        switch language.script {
        case .greek: return "-/:·()"
        case .arabic: return "-/:؛()"
        default: return "-/:;()"
        }
    }

    /// The five punctuation keys, which are not the same five in every script.
    ///
    /// Arabic and Persian write the comma and the question mark as ، and ؟, and
    /// Greek writes the question mark as a semicolon — U+037E, the "Greek question
    /// mark", is canonically equivalent to it and Unicode says to use U+003B. The
    /// Latin forms stay reachable as long presses, so nothing is lost.
    ///
    /// Spanish keeps the Latin five and gains the two marks that open a sentence:
    /// Apple's own Spanish layout puts ¡ and ¿ on one key, and a phone has no room
    /// for it, so they are the long presses of the marks that close the sentence.
    private static func punctuation(for language: KeyboardLanguage) -> [KeySpec] {
        let extras: [String: [String]]
        switch language.script {
        case .arabic: extras = alternates(["،": ",", "؟": "?"])
        case .greek: extras = alternates([";": "?"])
        default: extras = openingMarks[language] ?? [:]
        }
        return chars(punctuationMarks(for: language), alternates: extras)
    }

    /// The five marks themselves, in the order the numbers plane prints them.
    ///
    /// The bottom row's punctuation key offers the same five, so the two cannot
    /// drift: a script that writes its question mark as ؟ has to get ؟ in both
    /// places or the letters plane types a mark the language does not use.
    public static func punctuationMarks(for language: KeyboardLanguage) -> String {
        switch language.script {
        case .arabic: return ".،؟!'"
        case .greek: return ".,;!'"
        default: return ".,?!'"
        }
    }

    /// The inverted marks Spanish opens a question or an exclamation with. A
    /// dictionary rather than a `case` because it is data about one language, not
    /// a property of its script — nothing else in Latin script uses them.
    private static let openingMarks: [KeyboardLanguage: [String: [String]]] = [
        .spanish: alternates(["?": "¿", "!": "¡"])
    ]

    // MARK: Bottom row

    /// Sparkle and emoji live in the suggestion bar, so this row stays close to
    /// the system layout: plane switch, globe, space, dictation, punctuation,
    /// return.
    public static func bottomRow(
        for language: KeyboardLanguage, plane: KeyboardPlane, showsGlobe: Bool
    ) -> KeyRow {
        let planeKey: KeySpec =
            plane == .letters
            ? KeySpec(.plane(.numbers, label: "123"), width: .unit(1.3))
            : KeySpec(
                .plane(.letters, label: language.lettersPlaneLabel), width: .unit(1.3))

        var keys: [KeySpec] = [planeKey]
        if showsGlobe { keys.append(KeySpec(.globe, width: .unit(1.0))) }
        keys.append(KeySpec(.space, width: .flexible))
        keys.append(KeySpec(.dictation, width: .unit(1.0)))
        if plane == .letters { keys.append(punctuationKey(for: language)) }
        keys.append(KeySpec(.ret, width: .unit(2.2)))
        return KeyRow(id: 3, keys: keys)
    }

    /// The letters plane's one punctuation key: a full stop on the cap, the other
    /// four marks of the script behind a long press.
    ///
    /// **Letters plane only, and its identity is its own.** On the numbers and
    /// symbols planes all five marks are already on the row above, so a sixth way
    /// to type a full stop would only cost the space bar a unit — and it would put
    /// two keys with the id `char-.` on one plane, which is a `ForEach` with
    /// duplicate identity rather than a cosmetic clash. Hence the explicit id;
    /// `LanguageCatalogueTests` fails if it is dropped.
    /// Internal rather than private so `CustomLayoutCompiler` can build the same
    /// key for a custom row. A second spelling of it there would be a copy that
    /// loses the alternates the first time somebody changes one of them.
    static func punctuationKey(for language: KeyboardLanguage) -> KeySpec {
        let marks = punctuationMarks(for: language).map(String.init)
        return KeySpec(
            .character(marks[0]),
            width: .unit(1.0),
            id: punctuationKeyID,
            alternates: Array(marks.dropFirst()))
    }

    /// Read by `KeyView`, which draws this one key's long presses in miniature
    /// above the mark it types.
    public static let punctuationKeyID = "punctuation"

    // MARK: Width solving

    /// Resolved widths for one row, given the space available.
    ///
    /// The top row of equal keys sets the unit; everything else is expressed
    /// in that unit so the columns line up down the whole keyboard.
    public static func widths(
        for row: KeyRow,
        totalWidth: CGFloat,
        unitWidth: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        let count = CGFloat(row.keys.count)
        guard count > 0 else { return [] }

        let gaps = spacing * (count - 1)
        let inset = row.sideInsetUnits * (unitWidth + spacing) * 2
        let available = max(0, totalWidth - gaps - inset)

        let fixedTotal = row.keys.reduce(CGFloat(0)) { partial, key in
            switch key.width {
            case .unit(let multiple): return partial + unitWidth * multiple
            case .flexible, .remainderShare: return partial
            }
        }

        // Flexible and remainder-share keys both mean "take what the fixed keys
        // left behind", so they split the leftover evenly.
        //
        // **The floor keeps shift and delete tappable on a narrow screen, and it
        // is the only thing here that can push a row past the keyboard's width**,
        // so it is asked only where it is needed: when the even share is already
        // a full letter key wide, the key is tappable and widening it just runs
        // off the side. Hebrew is the layout that shows it — nine letters plus
        // delete divide out at exactly one unit, and floored to 1.15 the row ran
        // 5.1pt off an iPhone 17 Pro.
        let stretchCount = row.keys.filter { $0.width == .flexible || $0.width == .remainderShare }.count
        let leftover = max(0, available - fixedTotal)
        let share = stretchCount > 0 ? leftover / CGFloat(stretchCount) : 0
        let stretchWidth = share < unitWidth ? max(unitWidth * 1.15, share) : share

        return row.keys.map { key in
            switch key.width {
            case .unit(let multiple): return unitWidth * multiple
            case .flexible, .remainderShare: return stretchWidth
            }
        }
    }

    /// Width of a standard letter key for a keyboard of this width.
    ///
    /// **The floor here is a guard against a degenerate width, not a minimum key
    /// size, and it used to be both.** At `max(20, …)` a thirteen-column layout on
    /// a 320pt screen — which is what Display Zoom gives a modern iPhone — asked
    /// for 20pt keys where there was room for 18.6, and Bulgarian's top two rows
    /// ran 18pt off the side. A key that is a little narrow is worse than a key
    /// the right size and better than a key that is not on the screen, so the
    /// division wins and the floor only stops a zero-width `GeometryReader` pass
    /// producing zero or negative frames.
    public static func unitWidth(
        totalWidth: CGFloat, spacing: CGFloat, sideInset: CGFloat, columns: Int = 10
    ) -> CGFloat {
        let columns = CGFloat(max(1, columns))
        let usable = totalWidth - sideInset * 2 - spacing * (columns - 1)
        return max(1, usable / columns)
    }

    // MARK: Helpers

    private static func chars(_ string: String, alternates: [String: [String]] = [:]) -> [KeySpec] {
        chars(string.map(String.init), alternates: alternates)
    }

    private static func chars(_ keys: [String], alternates: [String: [String]] = [:]) -> [KeySpec] {
        keys.map { key in
            KeySpec(.character(key), alternates: alternates[key] ?? [])
        }
    }
}
