import FoundationModels
import XCTest

@testable import AIKeyboardCore

/// Digit, script-detection, and on-device-model tests extracted from `LanguageCatalogueTests`.
final class LanguageScriptTests: LanguageCatalogueTestFixture {

    // MARK: Digits, measured against Apple's locale data

    func testPersianDigitsAreTheOnesApplesLocaleUses() throws {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fa")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        XCTAssertEqual(KeyboardLanguage.persian.digits, formatter.string(from: 1_234_567_890))
        XCTAssertEqual(Locale(identifier: "fa").numberingSystem.identifier, "arabext")
    }

    func testArabicAndHindiUseLatinDigitsBecauseApplesLocalesDo() {
        XCTAssertEqual(Locale(identifier: "ar").numberingSystem.identifier, "latn")
        XCTAssertEqual(Locale(identifier: "hi_IN").numberingSystem.identifier, "latn")
        XCTAssertEqual(KeyboardLanguage.arabic.digits, "1234567890")
        XCTAssertEqual(KeyboardLanguage.hindi.digits, "1234567890")
        XCTAssertEqual(Locale(identifier: "ar_EG").numberingSystem.identifier, "arab")
    }

    // MARK: Script detection

    func testEveryShippedScriptIsNamedRatherThanFallingIntoOther() {
        XCTAssertEqual(LanguageDetector.scripts(in: "مرحبا"), [.arabic])
        XCTAssertEqual(LanguageDetector.scripts(in: "سلام"), [.arabic])
        XCTAssertEqual(LanguageDetector.scripts(in: "привет"), [.cyrillic])
        XCTAssertEqual(LanguageDetector.scripts(in: "привіт"), [.cyrillic])
        XCTAssertEqual(LanguageDetector.scripts(in: "καλημέρα"), [.greek])
        XCTAssertEqual(LanguageDetector.scripts(in: "नमस्ते"), [.devanagari])
        XCTAssertEqual(LanguageDetector.scripts(in: "שלום"), [.hebrew])
        XCTAssertEqual(LanguageDetector.scripts(in: "merhaba"), [.latin])
        XCTAssertEqual(LanguageDetector.scripts(in: "გამარჯობა"), [.georgian])
        XCTAssertEqual(LanguageDetector.scripts(in: "வணக்கம்"), [.tamil])
        XCTAssertEqual(LanguageDetector.scripts(in: "ދިވެހި"), [.thaana])
        XCTAssertEqual(KeyboardLanguage.dhivehi.script, .thaana)
        XCTAssertEqual(KeyboardLanguage.pashto.script, .arabic)
        XCTAssertEqual(KeyboardLanguage.georgian.script, .georgian)
        XCTAssertEqual(KeyboardLanguage.tajik.script, .cyrillic)
    }

    func testEveryKeyIsWrittenInItsOwnLanguagesScript() {
        for language in KeyboardLanguage.allCases {
            for key in allKeys(language, .letters) {
                var characters: [String] = key.alternates
                if case .character(let value) = key.cap { characters.append(value) }
                for character in characters {
                    let scripts = LanguageDetector.scripts(in: character)
                    XCTAssertTrue(
                        scripts.isSubset(of: [language.script]),
                        "\(language.rawValue) has a \(scripts.map(\.displayName)) key: \(character)")
                }
            }
        }
    }

    func testAnUnnamedScriptIsStillReportedAsOther() {
        XCTAssertTrue(LanguageDetector.scripts(in: "こんにちは").contains(.other))
        XCTAssertTrue(LanguageDetector.scripts(in: "สวัสดี").contains(.other))
    }

    func testEveryShippedLanguageIsWrittenInAScriptTheDetectorNames() {
        for language in KeyboardLanguage.allCases {
            XCTAssertNotEqual(
                language.script, .other, "\(language.displayName) has an unnamed script")
        }
    }

    // MARK: Apple's on-device model

    func testTheOnDeviceModelListsNoScriptThisKeyboardShipsBesidesLatin() throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("FoundationModels needs iOS 26")
        }
        let languages = SystemLanguageModel.default.supportedLanguages
        XCTAssertFalse(languages.isEmpty, "supportedLanguages came back empty")

        let scripts = Set(languages.compactMap { $0.script?.identifier })
        XCTAssertEqual(scripts, ["Latn", "Hans", "Hant", "Jpan", "Kore"])
        for absent in ["Hebr", "Arab", "Cyrl", "Grek", "Deva"] {
            XCTAssertFalse(scripts.contains(absent), "Apple now lists \(absent)")
        }

        let codes = Set(languages.compactMap { $0.languageCode?.identifier })
        XCTAssertEqual(
            codes,
            ["da", "de", "en", "es", "fr", "it", "ja", "ko", "nb", "nl", "pt", "sv", "tr", "vi", "zh"])
        #else
        throw XCTSkip("FoundationModels is not in this SDK")
        #endif
    }

    func testTheOnDeviceEngineDeclinesEveryScriptAppleDoesNotList() throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("FoundationModels needs iOS 26")
        }
        let engine = FoundationModelsEngine()
        XCTAssertTrue(engine.canHandle("can you send me the id", action: .fix))
        XCTAssertTrue(engine.canHandle("Merhaba nasılsın", action: .fix))
        let unsupported = [
            "אני אבדוק את זה", "مرحبا كيف حالك", "привет как дела", "Καλημέρα", "नमस्ते",
            "გამარჯობა", "வணக்கம்", "އައްސަލާމް ޢަލައިކުމް", "سلام ورور"
        ]
        for text in unsupported {
            XCTAssertFalse(
                engine.canHandle(text, action: .fix),
                "\(text) must be routed to the cloud, not answered in English")
        }
        let scripts = Set(unsupported.flatMap { LanguageDetector.scripts(in: $0) })
        XCTAssertEqual(
            scripts,
            [.hebrew, .arabic, .cyrillic, .greek, .devanagari, .georgian, .tamil, .thaana])
        #else
        throw XCTSkip("FoundationModels is not in this SDK")
        #endif
    }

    func testTheUnsupportedLanguageMessageNamesTheScript() {
        XCTAssertTrue(AIEngineError.unsupportedLanguage(.arabic).message.contains("Arabic"))
        XCTAssertTrue(AIEngineError.unsupportedLanguage(.cyrillic).message.contains("Cyrillic"))
        XCTAssertTrue(AIEngineError.unsupportedLanguage(.hebrew).message.contains("Hebrew"))
    }
}
