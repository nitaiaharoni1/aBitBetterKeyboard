import Foundation

/// One keyboard the user can switch to: its identity, its script, and everything
/// about it that is not a key layout.
///
/// **A struct over a catalogue, not an enum.** It was a two-case enum and every
/// property was a `switch` with two arms, which is fine for two languages and
/// unmaintainable for sixty-four: adding one meant editing seven switches and the
/// compiler only caught the ones that were exhaustive. The identity is a stable
/// string, the rest is a row in `Definition.all`, and adding a language is one
/// row plus one layout in `KeyboardLayout`.
///
/// **The raw values did not change, and that is deliberate.** `english` and
/// `hebrew` are what `SharedStore.enabledLanguages` has been writing into the App
/// Group plist since the first build, and what `ScreenReadingRecord.language`
/// carries between two processes. Keeping them means an existing install needs no
/// migration: it reads back exactly what it wrote. `init?(rawValue:)` returns nil
/// for anything not in the catalogue, and `SharedStore.load` already
/// `compactMap`s, so a language written by a newer build and read by an older one
/// is dropped rather than crashing the decode of the settings beside it.
///
/// **In `AIKeyboardShared` because the capture process needs it.** A screen
/// reading carries the language to reply in, and the read happens inside the
/// broadcast upload extension, which must never link `AIKeyboardCore`. Only the
/// SwiftUI half stayed behind: `layoutDirection` is an extension in
/// `Models.swift`, which is the whole reason that file imports SwiftUI.
public struct KeyboardLanguage: RawRepresentable, Hashable, Identifiable, Codable, Sendable,
    CaseIterable
{

    private let definition: Definition

    /// Internal so `KeyboardLanguage+Named` can build the static catalogue entries
    /// from the same file-split Definitions without re-exporting the type.
    init(_ definition: Definition) {
        self.definition = definition
    }

    /// Fails for an identifier this build does not know, which is what lets a
    /// stored list survive a downgrade: the unknown entries drop out and the rest
    /// still load.
    public init?(rawValue: String) {
        guard let definition = Definition.byID[rawValue] else { return nil }
        self.definition = definition
    }

    /// Stable and persisted. Never derive it from a display name.
    public var rawValue: String { definition.id }
    public var id: String { definition.id }

    // MARK: Identity

    /// Shown on the globe key, on the space bar and beside a suggestion that came
    /// from a language other than the one being typed in.
    public var shortName: String { definition.shortName }

    /// The English name, for a UI whose chrome is in English.
    public var displayName: String { definition.displayName }

    /// The name in the language itself, which is what a speaker of it looks for.
    public var nativeName: String { definition.nativeName }

    public var flag: String { definition.flag }

    /// BCP-47. Used to look this language up in Apple's own tables rather than to
    /// route anything.
    public var languageTag: String { definition.tag }

    /// The catalogue language for a BCP-47 tag, or nil.
    ///
    /// **The one caller is dictation, and the reason is a defect worth naming.**
    /// A transcript's direction was being decided by counting letters
    /// (`SuggestionEngine.languages(in:)`), and on the sentence this product
    /// exists for that counts wrong: `בוא נעשה sync על ה-roadmap` is ten Hebrew
    /// letters against eleven Latin ones, so a Hebrew sentence with two English
    /// words in it was laid out left to right. The transcriber already reports
    /// what it *heard*, most-spoken first, which is a better answer than any
    /// count of glyphs — this is what turns that report into a language.
    ///
    /// Matched on the primary subtag, so `he-IL`, `he` and `HE` all land on
    /// Hebrew and a region nobody has a keyboard for cannot miss.
    public init?(languageTag: String) {
        let primary = languageTag.split(separator: "-").first?.lowercased() ?? ""
        guard !primary.isEmpty,
            let match = KeyboardLanguage.allCases.first(where: { $0.languageTag.lowercased() == primary })
        else { return nil }
        self = match
    }

    /// Upper case by this language's own rules.
    ///
    /// **Turkish is why this exists and why `String.uppercased()` is not enough.**
    /// Turkish has two i's, dotted and dotless, and they are different letters:
    /// `i` upper-cases to `İ` and `ı` to `I`. Unicode's default casing knows
    /// nothing about that and turns both into `I`, so a Turkish keyboard that
    /// shifts with the default rule silently merges two letters — `İstanbul`
    /// becomes `Istanbul`, which is a spelling error in every word it lands in.
    /// Every place that shifts a character has to go through here: the document,
    /// the key cap, the callout and the long-press popup, or the key shows one
    /// letter and types another.
    public func uppercased(_ text: String) -> String {
        text.uppercased(with: definition.locale)
    }

    // MARK: Script

    public var script: TextScript { definition.script }

    /// Follows from the script, so Persian is right-to-left because it is written
    /// in the Arabic script. Nothing anywhere compares a language against a
    /// hardcoded pair to answer this.
    public var isRightToLeft: Bool { definition.script.isRightToLeft }

    // MARK: Spelling

    /// The identifier `UITextChecker` knows this language by, or nil when Apple
    /// ships no checker for it.
    ///
    /// **Read off `UITextChecker.availableLanguages` on the iOS 26.2 Simulator,
    /// not guessed.** That list has 42 entries and its shape is its own: `he_IL`
    /// and `de_DE` carry a region, `ar` and `hi` do not, and Persian is absent
    /// altogether. `SuggestionEngine` degrades to no completions rather than to
    /// another language's completions when this is nil — offering English words
    /// under a Persian keyboard is worse than offering nothing.
    /// `SuggestionLanguageTests` pins every value here against the live list.
    public var spellCheckerLocale: String? { definition.spellChecker }

    // MARK: Key captions

    /// The digits on the top row of the numbers plane.
    ///
    /// Almost always Latin, and the exception is measured rather than assumed:
    /// `Locale(identifier: "fa").numberingSystem` is `arabext`, so Persian gets
    /// Persian digits. Arabic does **not** — Apple's own bare `ar` locale reports
    /// `latn`, and only some regions of it (`ar_EG`, `ar_SA`) report `arab` while
    /// others (`ar_MA`, `ar_AE`) report `latn`. This catalogue has one entry for
    /// Arabic rather than one per region, so it follows the bare locale. Hindi
    /// likewise: `hi_IN` reports `latn`, and Devanagari digits belong to `ne_NP`.
    public var digits: String { definition.digits }

    /// The currency sign that earns a place on the numbers plane, where the
    /// dollar sits for English.
    public var currency: String { definition.currency }

    /// What the key back to the letters plane says — "ABC" in Latin, "אבג" in
    /// Hebrew, and so on. Three letters of the script, which is how iOS labels it.
    public var lettersPlaneLabel: String { definition.lettersLabel ?? definition.script.lettersPlaneLabel }

    /// What the space bar says.
    ///
    /// **Read out of Apple's own localisation, not translated.**
    /// `UIKitCore.framework/<lang>.lproj/Localizable.strings` carries the key
    /// `Space` in 53 languages, and that string is what a new entry uses
    /// verbatim. It also settles the fourteen that were here first: every one of
    /// them matches Apple's word, case-insensitively, except Persian, which has
    /// no `fa.lproj` in that framework at all. The casing differs because iOS
    /// draws this cap in lower case in most languages and Apple's table is
    /// title case; the shipped fourteen keep the casing they were written with.
    ///
    /// Apple has no localisation for 33 of the languages here, and rather than
    /// invent one the bar shows the language's own name — which is what Gboard
    /// does on every keyboard, and is the same string a space-bar swipe already
    /// puts there.
    public var spaceLabel: String { definition.spaceLabel ?? nativeName }

    // There is no `returnLabel`, and the search for one is worth recording so
    // nobody runs it twice. Apple's resources do not answer it: the only
    // per-language "return" string on this machine is
    // `AccessibilitySharedSupport.framework/<lang>.lproj/iOS.strings`, and it is
    // VoiceOver's phrasing rather than a key cap — Spanish "Volver", Hindi
    // "वापस जाएँ", Russian "Клавиша «Ввод»" — while `KBLayouts_iPhone.dat` holds
    // `return` as an untranslated internal key id. Fourteen languages did carry
    // an unverified word here; `KeyView` now draws the glyph for all of them,
    // which is right in every language and needs no translation.

    // MARK: The catalogue

    public static let allCases: [KeyboardLanguage] = Definition.all.map(KeyboardLanguage.init)

    // `next()` used to live here, wrapping to the next row of the catalogue, and
    // it is deleted rather than fixed. Its one caller was the dictation panel's
    // mixed-language badge, which wanted *the other language in this sentence* and
    // got *catalogue index + 1* — harmless while the catalogue was English and
    // Hebrew, and wrong the day it grew to fourteen: Hebrew's neighbour is Arabic,
    // so a Hebrew transcript carrying English loanwords was badged `עב ⟷ ع`. The
    // question it was standing in for is answered by counting the scripts actually
    // present, which is `SuggestionEngine.languages(in:)`.

    // MARK: Conformances

    public static func == (lhs: KeyboardLanguage, rhs: KeyboardLanguage) -> Bool {
        lhs.definition.id == rhs.definition.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(definition.id)
    }

    /// Spelled out rather than left to the compiler, so the wire format is one
    /// string and stays one string. A synthesised `Codable` over the stored
    /// definition would write the whole row and would change the moment a field
    /// is added here.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let language = KeyboardLanguage(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "\(raw) is not a keyboard language this build ships")
        }
        self = language
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// Named language constants are in KeyboardLanguage+Named.swift.
