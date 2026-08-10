import Foundation

// MARK: - The fifty added in one pass, every field read off Apple's own data
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

extension Definition {

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
