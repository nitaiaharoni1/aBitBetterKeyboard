import CoreGraphics
import Foundation

extension KeyboardLayout {

    // MARK: Numbers and symbols

    /// SwiftKey's four-row numbers page: digits, brackets, connectors, then the
    /// `#+=` punctuation row. The three-row iOS page this replaced hid the
    /// brackets behind `#+=`; putting them here is the whole change, and it is
    /// why both planes grew a row rather than trading characters.
    static func numbers(for language: KeyboardLanguage) -> [KeyRow] {
        [
            KeyRow(id: 0, keys: chars(language.digits)),
            KeyRow(id: 1, keys: chars(Self.brackets)),
            KeyRow(
                id: RowID.extraSymbols,
                keys: chars(connectors(for: language))
                    + [KeySpec(.character(language.currency))]
                    + chars("&@\"", alternates: quoteAlternates)),
            punctuationRow(
                plane: .symbols, label: "#+=", language: language)
        ]
    }

    /// SwiftKey's four-row symbols page: the same digits and brackets as
    /// numbers, then the remaining marks. Digits stay on this page so `#+=`
    /// does not drop a row the thumb had just learned.
    static func symbols(for language: KeyboardLanguage) -> [KeyRow] {
        // SwiftKey's extras are $ € £ ·. The language's own currency leads, and
        // the three that are not it follow, so no row ever carries the same sign
        // twice — two keys with one id is a `ForEach` with duplicate identity.
        // ¥ and • used to sit where £ and · sit now; they ride as long presses
        // so a language that is not English does not lose them.
        let others = Self.currencyExtras.filter { $0 != language.currency }.prefix(3)
        return [
            KeyRow(id: 0, keys: chars(language.digits)),
            KeyRow(id: 1, keys: chars(Self.brackets)),
            KeyRow(
                id: RowID.extraSymbols,
                keys: chars("_\\|~<>")
                    + [currencyKey(language.currency)]
                    + others.map { currencyKey($0) }),
            punctuationRow(
                plane: .numbers, label: "123", language: language)
        ]
    }

    /// The brackets row SwiftKey prints on both symbol pages.
    private static let brackets = "[]{}#%^*+="

    /// SwiftKey's four trailing marks on the symbols page, after `_\\|~<>`.
    private static let currencyExtras = ["$", "€", "£", "·"]

    /// The two marks this keyboard used to print where SwiftKey prints £ and ·.
    private static let currencyExtraAlternates: [String: [String]] = [
        "£": ["¥"], "·": ["•"]
    ]

    private static func currencyKey(_ mark: String) -> KeySpec {
        KeySpec(.character(mark), alternates: currencyExtraAlternates[mark] ?? [])
    }

    private static func punctuationRow(
        plane: KeyboardPlane, label: String, language: KeyboardLanguage
    ) -> KeyRow {
        KeyRow(
            id: 2,
            keys: [KeySpec(.plane(plane, label: label), width: .pinned)]
                + punctuation(for: language)
                + [KeySpec(.backspace, width: .pinned)],
            sideInsetUnits: 0
        )
    }

    /// The run of connectors on the numbers plane's third row.
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
        return chars(
            punctuationMarks(for: language),
            alternates: extras.merging(quoteAlternates) { script, quotes in script + quotes })
    }

    /// The curved quotation marks, behind the two straight ones.
    ///
    /// **Measured rather than assumed, and the apostrophe is the one that
    /// matters.** `UIKeyboardNonstopPunctuationCharacters` in each
    /// `InputMode_<tag>.plist` is Apple's own list of the marks that appear
    /// *inside* a word, and ten of the languages this keyboard ships — Danish,
    /// Icelandic, both Norwegians, Portuguese, Romanian, Russian, Swedish,
    /// Ukrainian, Indonesian — name U+2019 among them. It was reachable on no
    /// plane, so a word written with the typographic apostrophe could not be
    /// typed at all. The same key in the Hebrew and Persian files is what
    /// `hebrewMarks` and `persianHalfSpace` answer.
    ///
    /// The guillemets ride on `"` because they are the primary quotation marks
    /// of Russian, Ukrainian, Persian, Greek, French and Spanish, and iOS offers
    /// them from the same key. Both entries are safe through `alternates(_:)`:
    /// every one of these marks is a single `Character`.
    private static let quoteAlternates: [String: [String]] = alternates([
        "'": "’‘", "\"": "“”«»"
    ])

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

    /// Sparkle, emoji and dictation live in the action row, so this row stays
    /// close to the system layout: plane switch, globe, space, punctuation,
    /// return. Widths here are what `KeyboardCustomization.default.bottomRow`
    /// copies — keep the two lists the same shape.
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
        // On every plane: the numbers plane already draws these five marks one
        // row up, and that is not a reason to move the one key a thumb finds
        // without looking. The ids do not collide — this one is `punctuation`.
        keys.append(punctuationKey(for: language))
        // Match Backspace in the row above. Both are trailing function keys.
        keys.append(KeySpec(.ret, width: .unit(functionKeyUnits)))
        return KeyRow(id: 3, keys: keys)
    }

    /// The bottom row's punctuation key: a full stop on the cap, the other four
    /// marks of the script behind a long press.
    ///
    /// **Drawn on every plane, and its identity is its own.** The numbers plane
    /// already carries the same five marks on the row above as `char-.` and
    /// friends; this key answers to `punctuationKeyID` so the two never share a
    /// `ForEach` identity. That is what lets it stay under the thumb on 123 and
    /// #+= rather than vanishing when the plane switches.
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

    // MARK: Helpers

    static func chars(_ string: String, alternates: [String: [String]] = [:]) -> [KeySpec] {
        chars(string.map(String.init), alternates: alternates)
    }

    static func chars(_ keys: [String], alternates: [String: [String]] = [:]) -> [KeySpec] {
        keys.map { key in
            KeySpec(.character(key), alternates: alternates[key] ?? [])
        }
    }
}
