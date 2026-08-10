import CoreGraphics
import Foundation

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

    // MARK: Letter layout model

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
    struct LetterLayout {
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
    static func alternates(_ table: [String: String]) -> [String: [String]] {
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
            if index == 2, layout.hasCase { keys.append(KeySpec(.shift, width: .pinned)) }
            keys += chars(layout.rows[index], alternates: layout.alternates)
            if index == 2 { keys.append(KeySpec(.backspace, width: .pinned)) }
            return KeyRow(
                id: index,
                keys: keys,
                // The delete row carries no side inset: with pinned ends, an
                // inset only shrinks the letters between them and used to leave
                // Arabic's delete inland while Hebrew's sat on the edge.
                sideInsetUnits: index == 2
                    ? 0
                    : max(0, (columns - CGFloat(layout.rows[index].count)) / 2))
        }
    }

    /// How wide shift and delete want to be when the row has room to spare.
    /// Matches what they work out to on the English layout, where the row is full.
    static let functionKeyUnits: CGFloat = 1.5

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
    static func latin(_ extra: [String: String] = [:]) -> [String: [String]] {
        alternates(latinAlternates.merging(extra) { shared, extra in shared + extra })
    }

    /// **Split into four literals rather than one.** Sixty-four entries in a
    /// single dictionary literal is the shape that makes Swift's type checker
    /// give up; four named groups compile in seconds and read as the four
    /// families they are.
    static let letterLayouts: [KeyboardLanguage: LetterLayout] =
        originalLayouts
        .merging(latinLayouts) { first, _ in first }
        .merging(cyrillicLayouts) { first, _ in first }
        .merging(otherScriptLayouts) { first, _ in first }

}
