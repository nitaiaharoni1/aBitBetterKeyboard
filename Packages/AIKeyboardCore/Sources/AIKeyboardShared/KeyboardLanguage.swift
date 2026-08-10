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

    private init(_ definition: Definition) {
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

// MARK: - Named languages

extension KeyboardLanguage {
    public static let english = KeyboardLanguage(Definition.english)
    public static let hebrew = KeyboardLanguage(Definition.hebrew)
    public static let albanian = KeyboardLanguage(Definition.albanian)
    public static let arabic = KeyboardLanguage(Definition.arabic)
    public static let azerbaijani = KeyboardLanguage(Definition.azerbaijani)
    public static let belarusian = KeyboardLanguage(Definition.belarusian)
    public static let bulgarian = KeyboardLanguage(Definition.bulgarian)
    public static let catalan = KeyboardLanguage(Definition.catalan)
    public static let croatian = KeyboardLanguage(Definition.croatian)
    public static let czech = KeyboardLanguage(Definition.czech)
    public static let danish = KeyboardLanguage(Definition.danish)
    public static let dhivehi = KeyboardLanguage(Definition.dhivehi)
    public static let dutch = KeyboardLanguage(Definition.dutch)
    public static let estonian = KeyboardLanguage(Definition.estonian)
    public static let faroese = KeyboardLanguage(Definition.faroese)
    public static let filipino = KeyboardLanguage(Definition.filipino)
    public static let finnish = KeyboardLanguage(Definition.finnish)
    public static let french = KeyboardLanguage(Definition.french)
    public static let georgian = KeyboardLanguage(Definition.georgian)
    public static let german = KeyboardLanguage(Definition.german)
    public static let greek = KeyboardLanguage(Definition.greek)
    public static let haitian = KeyboardLanguage(Definition.haitian)
    public static let hausa = KeyboardLanguage(Definition.hausa)
    public static let hawaiian = KeyboardLanguage(Definition.hawaiian)
    public static let hindi = KeyboardLanguage(Definition.hindi)
    public static let hungarian = KeyboardLanguage(Definition.hungarian)
    public static let icelandic = KeyboardLanguage(Definition.icelandic)
    public static let igbo = KeyboardLanguage(Definition.igbo)
    public static let indonesian = KeyboardLanguage(Definition.indonesian)
    public static let irish = KeyboardLanguage(Definition.irish)
    public static let italian = KeyboardLanguage(Definition.italian)
    public static let kyrgyz = KeyboardLanguage(Definition.kyrgyz)
    public static let latvian = KeyboardLanguage(Definition.latvian)
    public static let lithuanian = KeyboardLanguage(Definition.lithuanian)
    public static let macedonian = KeyboardLanguage(Definition.macedonian)
    public static let malay = KeyboardLanguage(Definition.malay)
    public static let maltese = KeyboardLanguage(Definition.maltese)
    public static let maori = KeyboardLanguage(Definition.maori)
    public static let marathi = KeyboardLanguage(Definition.marathi)
    public static let nepali = KeyboardLanguage(Definition.nepali)
    public static let norwegian = KeyboardLanguage(Definition.norwegian)
    public static let pashto = KeyboardLanguage(Definition.pashto)
    public static let persian = KeyboardLanguage(Definition.persian)
    public static let polish = KeyboardLanguage(Definition.polish)
    public static let portuguese = KeyboardLanguage(Definition.portuguese)
    public static let romanian = KeyboardLanguage(Definition.romanian)
    public static let russian = KeyboardLanguage(Definition.russian)
    public static let samoan = KeyboardLanguage(Definition.samoan)
    public static let serbian = KeyboardLanguage(Definition.serbian)
    public static let serbianLatin = KeyboardLanguage(Definition.serbianLatin)
    public static let slovak = KeyboardLanguage(Definition.slovak)
    public static let slovenian = KeyboardLanguage(Definition.slovenian)
    public static let spanish = KeyboardLanguage(Definition.spanish)
    public static let swahili = KeyboardLanguage(Definition.swahili)
    public static let swedish = KeyboardLanguage(Definition.swedish)
    public static let tajik = KeyboardLanguage(Definition.tajik)
    public static let tamil = KeyboardLanguage(Definition.tamil)
    public static let tongan = KeyboardLanguage(Definition.tongan)
    public static let turkish = KeyboardLanguage(Definition.turkish)
    public static let turkmen = KeyboardLanguage(Definition.turkmen)
    public static let ukrainian = KeyboardLanguage(Definition.ukrainian)
    public static let urdu = KeyboardLanguage(Definition.urdu)
    public static let welsh = KeyboardLanguage(Definition.welsh)
    public static let yoruba = KeyboardLanguage(Definition.yoruba)
}

// MARK: - Catalogue rows

/// One row of the language catalogue. Everything a keyboard needs to know about a
/// language except the arrangement of its keys, which is `KeyboardLayout`'s.
private struct Definition: Sendable {
    let id: String
    let tag: String
    /// Built once from `tag`, because casing runs on every shifted keystroke and
    /// on every key cap the keyboard draws.
    let locale: Locale
    let displayName: String
    let nativeName: String
    let shortName: String
    let flag: String
    let script: TextScript
    let spellChecker: String?
    let digits: String
    let currency: String
    let lettersLabel: String?
    let spaceLabel: String?

    init(
        id: String,
        tag: String,
        displayName: String,
        nativeName: String,
        shortName: String,
        flag: String,
        script: TextScript,
        spellChecker: String?,
        currency: String,
        lettersLabel: String? = nil,
        spaceLabel: String? = nil,
        digits: String = "1234567890"
    ) {
        self.id = id
        self.tag = tag
        self.locale = Locale(identifier: tag)
        self.displayName = displayName
        self.nativeName = nativeName
        self.shortName = shortName
        self.flag = flag
        self.script = script
        self.spellChecker = spellChecker
        self.digits = digits
        self.currency = currency
        self.lettersLabel = lettersLabel
        self.spaceLabel = spaceLabel
    }
}

extension Definition {

    /// **The order is load-bearing in three places.** English leads because it is
    /// the first switch on the Languages screen, and `AppGroupCrossProcessTests`
    /// turns that switch off to prove the App Group is shared. Hebrew follows
    /// because the two of them are what this build enables by default.
    ///
    /// Russian follows *those*, out of alphabetical order and for one measured
    /// reason: `SuggestionEngine.language(writtenIn:among:)` falls back to the
    /// first entry written in a script when its caller has no candidate list, so
    /// this order decides which language a script is named as. Every other script
    /// here is led by its most widely written language already — Arabic before
    /// Persian, Pashto and Urdu; Hindi before Marathi and Nepali; English before
    /// the thirty-six other Latin keyboards — because alphabetical order happens
    /// to agree. Cyrillic is the one where it does not: leave Russian in place and
    /// `давай сделаем sync по roadmap завтра` gets badged Belarusian, which is
    /// the first Cyrillic entry by name and is not what anyone typed.
    ///
    /// Everything after that is alphabetical by English name.
    static let all: [Definition] = [
        english, hebrew, russian,
        albanian, arabic, azerbaijani, belarusian, bulgarian, catalan, croatian, czech, danish,
        dhivehi, dutch, estonian, faroese, filipino, finnish, french, georgian, german, greek,
        haitian, hausa, hawaiian, hindi, hungarian, icelandic, igbo, indonesian, irish, italian,
        kyrgyz, latvian, lithuanian, macedonian, malay, maltese, maori, marathi, nepali, norwegian,
        pashto, persian, polish, portuguese, romanian, samoan, serbian, serbianLatin,
        slovak, slovenian, spanish, swahili, swedish, tajik, tamil, tongan, turkish, turkmen,
        ukrainian, urdu, welsh, yoruba
    ]

    static let byID: [String: Definition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) })

    static let english = Definition(
        id: "english", tag: "en", displayName: "English", nativeName: "English",
        shortName: "EN", flag: "🇺🇸", script: .latin, spellChecker: "en_US",
        currency: "$", lettersLabel: "ABC", spaceLabel: "space")

    static let hebrew = Definition(
        id: "hebrew", tag: "he", displayName: "Hebrew", nativeName: "עברית",
        shortName: "עב", flag: "🇮🇱", script: .hebrew, spellChecker: "he_IL",
        currency: "₪", lettersLabel: "אבג", spaceLabel: "רווח")

    static let arabic = Definition(
        id: "arabic", tag: "ar", displayName: "Arabic", nativeName: "العربية",
        shortName: "ع", flag: "🇸🇦", script: .arabic, spellChecker: "ar",
        currency: "$", lettersLabel: "ابج", spaceLabel: "مسافة")

    static let french = Definition(
        id: "french", tag: "fr", displayName: "French", nativeName: "Français",
        shortName: "FR", flag: "🇫🇷", script: .latin, spellChecker: "fr_FR",
        currency: "€", lettersLabel: "ABC", spaceLabel: "espace")

    static let german = Definition(
        id: "german", tag: "de", displayName: "German", nativeName: "Deutsch",
        shortName: "DE", flag: "🇩🇪", script: .latin, spellChecker: "de_DE",
        currency: "€", lettersLabel: "ABC", spaceLabel: "Leerzeichen")

    static let greek = Definition(
        id: "greek", tag: "el", displayName: "Greek", nativeName: "Ελληνικά",
        shortName: "ΕΛ", flag: "🇬🇷", script: .greek, spellChecker: "el_GR",
        currency: "€", lettersLabel: "ΑΒΓ", spaceLabel: "διάστημα")

    static let hindi = Definition(
        id: "hindi", tag: "hi", displayName: "Hindi", nativeName: "हिन्दी",
        shortName: "हि", flag: "🇮🇳", script: .devanagari, spellChecker: "hi",
        currency: "₹", lettersLabel: "अआइ", spaceLabel: "स्पेस")

    static let italian = Definition(
        id: "italian", tag: "it", displayName: "Italian", nativeName: "Italiano",
        shortName: "IT", flag: "🇮🇹", script: .latin, spellChecker: "it_IT",
        currency: "€", lettersLabel: "ABC", spaceLabel: "spazio")

    /// The one shipped language Apple has no spell checker for: `fa` is not in
    /// `UITextChecker.availableLanguages`, so the suggestion bar offers the
    /// keystrokes and nothing else rather than offering Arabic's.
    static let persian = Definition(
        id: "persian", tag: "fa", displayName: "Persian", nativeName: "فارسی",
        shortName: "فا", flag: "🇮🇷", script: .arabic, spellChecker: nil,
        currency: "﷼", lettersLabel: "ابپ", spaceLabel: "فاصله",
        digits: "۱۲۳۴۵۶۷۸۹۰")

    static let portuguese = Definition(
        id: "portuguese", tag: "pt", displayName: "Portuguese", nativeName: "Português",
        shortName: "PT", flag: "🇧🇷", script: .latin, spellChecker: "pt_BR",
        currency: "R$", lettersLabel: "ABC", spaceLabel: "espaço")

    static let russian = Definition(
        id: "russian", tag: "ru", displayName: "Russian", nativeName: "Русский",
        shortName: "РУ", flag: "🇷🇺", script: .cyrillic, spellChecker: "ru_RU",
        currency: "₽", lettersLabel: "АБВ", spaceLabel: "пробел")

    static let spanish = Definition(
        id: "spanish", tag: "es", displayName: "Spanish", nativeName: "Español",
        shortName: "ES", flag: "🇪🇸", script: .latin, spellChecker: "es_ES",
        currency: "€", lettersLabel: "ABC", spaceLabel: "espacio")

    static let turkish = Definition(
        id: "turkish", tag: "tr", displayName: "Turkish", nativeName: "Türkçe",
        shortName: "TR", flag: "🇹🇷", script: .latin, spellChecker: "tr_TR",
        currency: "₺", lettersLabel: "ABC", spaceLabel: "boşluk")

    static let ukrainian = Definition(
        id: "ukrainian", tag: "uk", displayName: "Ukrainian", nativeName: "Українська",
        shortName: "УК", flag: "🇺🇦", script: .cyrillic, spellChecker: "uk_UA",
        currency: "₴", lettersLabel: "АБВ", spaceLabel: "пробіл")

    // MARK: The fifty added in one pass, every field read off Apple's own data
    //
    // `displayName` and `nativeName` are `Locale.localizedString(forIdentifier:)`
    // verbatim, so "Norwegian Bokmål" and "srpski (latinica)" are Apple's
    // spellings rather than tidied ones. `flag` is the region CLDR calls the
    // language's likely home (`Locale.Language.maximalIdentifier`) — a claim
    // about CLDR, not about where the language is spoken, which is why Catalan
    // flies Spain's and Welsh the United Kingdom's. `currency` is
    // `Locale.currencySymbol` for that language in that region, so a language
    // CLDR has no symbol for shows the ISO code (Romanian RON, Samoan WST) and
    // no key is invented. `spellChecker` is an exact entry in the live
    // `UITextChecker.availableLanguages`, or nil — never a neighbour's. `digits`
    // is `NumberFormatter` under the language's own locale, which is how Nepali
    // gets Devanagari digits and Pashto gets Persian ones while Urdu, in the
    // same script, keeps Latin. `shortName` is the language subtag upper-cased:
    // no abbreviation is invented, and Serbian's two scripts share "SR" because
    // they are one language. The seven older non-Latin entries keep the badges
    // they shipped with.

    static let albanian = Definition(
        id: "albanian", tag: "sq", displayName: "Albanian", nativeName: "shqip",
        shortName: "SQ", flag: "🇦🇱", script: .latin, spellChecker: nil, currency: "Lekë")

    static let azerbaijani = Definition(
        id: "azerbaijani", tag: "az", displayName: "Azerbaijani", nativeName: "azərbaycan",
        shortName: "AZ", flag: "🇦🇿", script: .latin, spellChecker: nil, currency: "₼")

    static let belarusian = Definition(
        id: "belarusian", tag: "be", displayName: "Belarusian", nativeName: "беларуская",
        shortName: "BE", flag: "🇧🇾", script: .cyrillic, spellChecker: nil, currency: "Br")

    static let bulgarian = Definition(
        id: "bulgarian", tag: "bg", displayName: "Bulgarian", nativeName: "български",
        shortName: "BG", flag: "🇧🇬", script: .cyrillic, spellChecker: "bg_BG", currency: "€",
        spaceLabel: "Интервал")

    static let catalan = Definition(
        id: "catalan", tag: "ca", displayName: "Catalan", nativeName: "català",
        shortName: "CA", flag: "🇪🇸", script: .latin, spellChecker: nil, currency: "€",
        spaceLabel: "Espai")

    static let croatian = Definition(
        id: "croatian", tag: "hr", displayName: "Croatian", nativeName: "hrvatski",
        shortName: "HR", flag: "🇭🇷", script: .latin, spellChecker: nil, currency: "€",
        spaceLabel: "Razmaknica")

    static let czech = Definition(
        id: "czech", tag: "cs", displayName: "Czech", nativeName: "čeština",
        shortName: "CS", flag: "🇨🇿", script: .latin, spellChecker: "cs_CZ", currency: "Kč",
        spaceLabel: "Mezerník")

    static let danish = Definition(
        id: "danish", tag: "da", displayName: "Danish", nativeName: "dansk",
        shortName: "DA", flag: "🇩🇰", script: .latin, spellChecker: "da_DK", currency: "kr.",
        spaceLabel: "Mellemrum")

    static let dhivehi = Definition(
        id: "dhivehi", tag: "dv", displayName: "Dhivehi", nativeName: "ދިވެހިބަސް",
        shortName: "DV", flag: "🇲🇻", script: .thaana, spellChecker: nil, currency: "ރ.")

    static let dutch = Definition(
        id: "dutch", tag: "nl", displayName: "Dutch", nativeName: "Nederlands",
        shortName: "NL", flag: "🇳🇱", script: .latin, spellChecker: "nl_NL", currency: "€",
        spaceLabel: "Spatie")

    static let estonian = Definition(
        id: "estonian", tag: "et", displayName: "Estonian", nativeName: "eesti",
        shortName: "ET", flag: "🇪🇪", script: .latin, spellChecker: nil, currency: "€")

    static let faroese = Definition(
        id: "faroese", tag: "fo", displayName: "Faroese", nativeName: "føroyskt",
        shortName: "FO", flag: "🇫🇴", script: .latin, spellChecker: nil, currency: "kr")

    static let filipino = Definition(
        id: "filipino", tag: "fil", displayName: "Filipino", nativeName: "Filipino",
        shortName: "FIL", flag: "🇵🇭", script: .latin, spellChecker: nil, currency: "₱")

    static let finnish = Definition(
        id: "finnish", tag: "fi", displayName: "Finnish", nativeName: "suomi",
        shortName: "FI", flag: "🇫🇮", script: .latin, spellChecker: "fi_FI", currency: "€",
        spaceLabel: "Välilyönti")

    static let georgian = Definition(
        id: "georgian", tag: "ka", displayName: "Georgian", nativeName: "ქართული",
        shortName: "KA", flag: "🇬🇪", script: .georgian, spellChecker: nil, currency: "₾")

    static let haitian = Definition(
        id: "haitian", tag: "ht", displayName: "Haitian Creole", nativeName: "Kreyòl Ayisyen",
        shortName: "HT", flag: "🇭🇹", script: .latin, spellChecker: nil, currency: "HTG")

    static let hausa = Definition(
        id: "hausa", tag: "ha", displayName: "Hausa", nativeName: "Hausa",
        shortName: "HA", flag: "🇳🇬", script: .latin, spellChecker: nil, currency: "₦")

    static let hawaiian = Definition(
        id: "hawaiian", tag: "haw", displayName: "Hawaiian", nativeName: "ʻŌlelo Hawaiʻi",
        shortName: "HAW", flag: "🇺🇸", script: .latin, spellChecker: nil, currency: "$")

    static let hungarian = Definition(
        id: "hungarian", tag: "hu", displayName: "Hungarian", nativeName: "magyar",
        shortName: "HU", flag: "🇭🇺", script: .latin, spellChecker: "hu_HU", currency: "Ft",
        spaceLabel: "Szóköz")

    static let icelandic = Definition(
        id: "icelandic", tag: "is", displayName: "Icelandic", nativeName: "íslenska",
        shortName: "IS", flag: "🇮🇸", script: .latin, spellChecker: "is_IS", currency: "kr.")

    static let igbo = Definition(
        id: "igbo", tag: "ig", displayName: "Igbo", nativeName: "Igbo",
        shortName: "IG", flag: "🇳🇬", script: .latin, spellChecker: nil, currency: "₦")

    static let indonesian = Definition(
        id: "indonesian", tag: "id", displayName: "Indonesian", nativeName: "Indonesia",
        shortName: "ID", flag: "🇮🇩", script: .latin, spellChecker: "id_ID", currency: "Rp",
        spaceLabel: "Spasi")

    static let irish = Definition(
        id: "irish", tag: "ga", displayName: "Irish", nativeName: "Gaeilge",
        shortName: "GA", flag: "🇮🇪", script: .latin, spellChecker: "ga_IE", currency: "€")

    static let kyrgyz = Definition(
        id: "kyrgyz", tag: "ky", displayName: "Kyrgyz", nativeName: "кыргызча",
        shortName: "KY", flag: "🇰🇬", script: .cyrillic, spellChecker: nil, currency: "сом")

    static let latvian = Definition(
        id: "latvian", tag: "lv", displayName: "Latvian", nativeName: "latviešu",
        shortName: "LV", flag: "🇱🇻", script: .latin, spellChecker: nil, currency: "€")

    static let lithuanian = Definition(
        id: "lithuanian", tag: "lt", displayName: "Lithuanian", nativeName: "lietuvių",
        shortName: "LT", flag: "🇱🇹", script: .latin, spellChecker: "lt_LT", currency: "€",
        spaceLabel: "Tarpas")

    static let macedonian = Definition(
        id: "macedonian", tag: "mk", displayName: "Macedonian", nativeName: "македонски",
        shortName: "MK", flag: "🇲🇰", script: .cyrillic, spellChecker: nil, currency: "ден.")

    static let malay = Definition(
        id: "malay", tag: "ms", displayName: "Malay", nativeName: "Bahasa Melayu",
        shortName: "MS", flag: "🇲🇾", script: .latin, spellChecker: nil, currency: "RM",
        spaceLabel: "Space")

    static let maltese = Definition(
        id: "maltese", tag: "mt", displayName: "Maltese", nativeName: "Malti",
        shortName: "MT", flag: "🇲🇹", script: .latin, spellChecker: nil, currency: "€")

    static let maori = Definition(
        id: "maori", tag: "mi", displayName: "Māori", nativeName: "Māori",
        shortName: "MI", flag: "🇳🇿", script: .latin, spellChecker: nil, currency: "$")

    static let marathi = Definition(
        id: "marathi", tag: "mr", displayName: "Marathi", nativeName: "मराठी",
        shortName: "MR", flag: "🇮🇳", script: .devanagari, spellChecker: nil, currency: "₹",
        spaceLabel: "स्पेस")

    static let nepali = Definition(
        id: "nepali", tag: "ne", displayName: "Nepali", nativeName: "नेपाली",
        shortName: "NE", flag: "🇳🇵", script: .devanagari, spellChecker: nil, currency: "नेरू",
        digits: "१२३४५६७८९०")

    static let norwegian = Definition(
        id: "norwegian", tag: "nb", displayName: "Norwegian Bokmål", nativeName: "norsk bokmål",
        shortName: "NB", flag: "🇳🇴", script: .latin, spellChecker: "nb_NO", currency: "kr",
        spaceLabel: "Mellomrom")

    static let pashto = Definition(
        id: "pashto", tag: "ps", displayName: "Pashto", nativeName: "پښتو",
        shortName: "PS", flag: "🇦🇫", script: .arabic, spellChecker: nil, currency: "؋",
        digits: "۱۲۳۴۵۶۷۸۹۰")

    static let polish = Definition(
        id: "polish", tag: "pl", displayName: "Polish", nativeName: "polski",
        shortName: "PL", flag: "🇵🇱", script: .latin, spellChecker: "pl_PL", currency: "zł",
        spaceLabel: "Spacja")

    static let romanian = Definition(
        id: "romanian", tag: "ro", displayName: "Romanian", nativeName: "română",
        shortName: "RO", flag: "🇷🇴", script: .latin, spellChecker: "ro_RO", currency: "RON",
        spaceLabel: "Spațiu")

    static let samoan = Definition(
        id: "samoan", tag: "sm", displayName: "Samoan", nativeName: "Gagana faʻa Sāmoa",
        shortName: "SM", flag: "🇼🇸", script: .latin, spellChecker: nil, currency: "WST")

    static let serbian = Definition(
        id: "serbian", tag: "sr", displayName: "Serbian", nativeName: "српски",
        shortName: "SR", flag: "🇷🇸", script: .cyrillic, spellChecker: nil, currency: "RSD")

    static let serbianLatin = Definition(
        id: "serbianLatin", tag: "sr-Latn", displayName: "Serbian (Latin)",
        nativeName: "srpski (latinica)", shortName: "SR", flag: "🇷🇸", script: .latin,
        spellChecker: nil, currency: "RSD")

    static let slovak = Definition(
        id: "slovak", tag: "sk", displayName: "Slovak", nativeName: "slovenčina",
        shortName: "SK", flag: "🇸🇰", script: .latin, spellChecker: nil, currency: "€",
        spaceLabel: "Medzerník")

    static let slovenian = Definition(
        id: "slovenian", tag: "sl", displayName: "Slovenian", nativeName: "slovenščina",
        shortName: "SL", flag: "🇸🇮", script: .latin, spellChecker: "sl_SI", currency: "€",
        spaceLabel: "Presledek")

    static let swahili = Definition(
        id: "swahili", tag: "sw", displayName: "Swahili", nativeName: "Kiswahili",
        shortName: "SW", flag: "🇹🇿", script: .latin, spellChecker: nil, currency: "TSh")

    static let swedish = Definition(
        id: "swedish", tag: "sv", displayName: "Swedish", nativeName: "svenska",
        shortName: "SV", flag: "🇸🇪", script: .latin, spellChecker: "sv_SE", currency: "kr",
        spaceLabel: "Mellanslag")

    static let tajik = Definition(
        id: "tajik", tag: "tg", displayName: "Tajik", nativeName: "тоҷикӣ",
        shortName: "TG", flag: "🇹🇯", script: .cyrillic, spellChecker: nil, currency: "сом.")

    static let tamil = Definition(
        id: "tamil", tag: "ta", displayName: "Tamil", nativeName: "தமிழ்",
        shortName: "TA", flag: "🇮🇳", script: .tamil, spellChecker: nil, currency: "₹",
        spaceLabel: "ஸ்பேஸ்")

    static let tongan = Definition(
        id: "tongan", tag: "to", displayName: "Tongan", nativeName: "lea fakatonga",
        shortName: "TO", flag: "🇹🇴", script: .latin, spellChecker: nil, currency: "T$")

    static let turkmen = Definition(
        id: "turkmen", tag: "tk", displayName: "Turkmen", nativeName: "türkmen dili",
        shortName: "TK", flag: "🇹🇲", script: .latin, spellChecker: nil, currency: "TMT")

    static let urdu = Definition(
        id: "urdu", tag: "ur", displayName: "Urdu", nativeName: "اردو",
        shortName: "UR", flag: "🇵🇰", script: .arabic, spellChecker: nil, currency: "Rs",
        spaceLabel: "اسپیس")

    static let welsh = Definition(
        id: "welsh", tag: "cy", displayName: "Welsh", nativeName: "Cymraeg",
        shortName: "CY", flag: "🇬🇧", script: .latin, spellChecker: nil, currency: "£")

    static let yoruba = Definition(
        id: "yoruba", tag: "yo", displayName: "Yoruba", nativeName: "Èdè Yorùbá",
        shortName: "YO", flag: "🇳🇬", script: .latin, spellChecker: nil, currency: "₦")
}
