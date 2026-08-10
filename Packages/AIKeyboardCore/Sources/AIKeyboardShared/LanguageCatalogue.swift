import Foundation

// MARK: - Catalogue rows

/// One row of the language catalogue. Everything a keyboard needs to know about a
/// language except the arrangement of its keys, which is `KeyboardLayout`'s.
struct Definition: Sendable {
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

}
