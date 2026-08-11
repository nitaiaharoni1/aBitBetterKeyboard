import Foundation

extension KeyboardLayout {

    /// **Thirty-seven Latin keyboards, each Apple's own arrangement for that
    /// language.** The macOS input source is named beside every group that is
    /// not the plain `ABC`, and the rows are what `UCKeyTranslate` prints for its
    /// three letter rows with the punctuation keys dropped — which is exactly how
    /// English comes out 10 / 9 / 7 from a desktop 12 / 11 / 10.
    static let latinLayouts: [KeyboardLanguage: LetterLayout] = [
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
        //
        // **`l` carries the punt volat, and it is the one thing in this file that
        // is not a letter.** `l·l` is a distinct sound from `ll` in Catalan and
        // spelling it `ll` is an error, not a shortcut — `col·legi`, `paral·lel`,
        // `il·lusió`. The interpunt is on Apple's own Spanish layout and on none
        // of the three planes this keyboard draws, so before this it could not be
        // typed at all. The alternate is `l·` rather than a bare `·` for the same
        // reason Hebrew's is `צ׳` rather than `׳`: picking it replaces the letter
        // the key already inserted, so the mark has to arrive with its letter.
        //
        // Merged as an array because `latin(_:)` concatenates strings and splits
        // per `Character`, which would turn `l·` into `l` and `·`.
        .catalan: LetterLayout(
            ["qwertyuiop", "asdfghjklñ", "zxcvbnm"],
            alternates: latin().merging(["l": ["ł", "l·"]]) { _, explicit in explicit }),

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
        .maltese: LetterLayout(
            ["qwertyuiopġħ", "asdfghjkl", "zxcvbnm"], alternates: latin(["c": "ċ"])),

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
    static let cyrillicLayouts: [KeyboardLanguage: LetterLayout] = [
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
}
