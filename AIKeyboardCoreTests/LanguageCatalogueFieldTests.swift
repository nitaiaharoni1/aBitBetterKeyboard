import UIKit
import XCTest

@testable import AIKeyboardCore

/// "Every other field" tests extracted from `LanguageCatalogueTests`.
final class LanguageCatalogueFieldTests: LanguageCatalogueTestFixture {

    // MARK: Every other field, against the Apple table it came from

    func testEveryNameIsApplesOwnNameForTheLanguage() {
        let english = Locale(identifier: "en")
        for language in KeyboardLanguage.allCases {
            let loc = locale(for: language)
            guard let apples = loc.localizedString(forIdentifier: language.languageTag),
                let inEnglish = english.localizedString(forIdentifier: language.languageTag)
            else {
                XCTFail("\(language.rawValue) has no name in Apple's own tables")
                continue
            }
            XCTAssertEqual(
                language.nativeName.lowercased(with: loc), apples.lowercased(with: loc),
                "\(language.rawValue) calls itself \(language.nativeName); Apple says \(apples)")
            XCTAssertEqual(
                language.displayName.lowercased(with: english),
                inEnglish.lowercased(with: english),
                "\(language.rawValue) is \(language.displayName); Apple says \(inEnglish)")
        }
    }

    func testTheSpaceCaptionIsApplesOwnWordOrTheLanguagesOwnName() throws {
        let uiKit = Bundle(for: UIView.self)
        XCTAssertNotNil(uiKit.path(forResource: "en", ofType: "lproj"), "UIKitCore has no lprojs")

        var verified = 0
        var unverified: [KeyboardLanguage] = []
        for language in KeyboardLanguage.allCases {
            let loc = locale(for: language)
            guard let apples = Self.appleSpaceCaption(for: language, in: uiKit) else {
                if language.spaceLabel != language.nativeName { unverified.append(language) }
                continue
            }
            verified += 1
            XCTAssertEqual(
                language.spaceLabel.lowercased(with: loc), apples.lowercased(with: loc),
                "\(language.rawValue) says \(language.spaceLabel); Apple says \(apples)")
        }
        XCTAssertGreaterThan(verified, 25, "only \(verified) captions came from Apple's table")

        XCTAssertEqual(unverified, [.persian], "\(unverified.map(\.rawValue)) invent a caption")
        XCTAssertNil(Self.appleSpaceCaption(for: .persian, in: uiKit))

        let english = try XCTUnwrap(uiKit.path(forResource: "en", ofType: "lproj"))
        let lproj = try XCTUnwrap(Bundle(path: english))
        XCTAssertEqual(
            lproj.localizedString(forKey: "Space", value: Self.missingCaption, table: nil), "Space")
        XCTAssertEqual(
            lproj.localizedString(
                forKey: "NoSuchKeyboardCaption", value: Self.missingCaption, table: nil),
            Self.missingCaption)
        XCTAssertEqual(
            lproj.localizedString(forKey: "NoSuchKeyboardCaption", value: "", table: nil),
            "NoSuchKeyboardCaption", "the trap this sentinel exists for")

        XCTAssertEqual(Self.appleSpaceCaption(for: .hebrew, in: uiKit), "רווח")
    }

    func testEveryFlagIsTheRegionCLDRCallsTheLanguagesLikelyHome() {
        for language in KeyboardLanguage.allCases {
            let maximal = Locale.Language(
                identifier: Locale.Language(identifier: language.languageTag).maximalIdentifier)
            guard let region = maximal.region?.identifier, region.count == 2 else {
                XCTFail("\(language.rawValue) has no likely region")
                continue
            }
            let flag = String(
                String.UnicodeScalarView(
                    region.unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
            guard !Self.original.contains(language) else { continue }
            XCTAssertEqual(
                language.flag, flag,
                "\(language.rawValue) shows \(language.flag); CLDR says \(region)")
        }
        XCTAssertEqual(KeyboardLanguage.arabic.flag, "🇸🇦", "the older entries are left alone")
    }

    func testDigitsFollowTheNumberingSystemApplesLocaleReports() {
        for language in KeyboardLanguage.allCases {
            let formatter = NumberFormatter()
            formatter.locale = locale(for: language)
            formatter.numberStyle = .decimal
            formatter.usesGroupingSeparator = false
            XCTAssertEqual(
                language.digits, formatter.string(from: 1_234_567_890),
                "\(language.rawValue) digits")
        }
        XCTAssertEqual(KeyboardLanguage.nepali.digits, "१२३४५६७८९०")
        XCTAssertEqual(KeyboardLanguage.hindi.digits, "1234567890")
        XCTAssertEqual(KeyboardLanguage.pashto.digits, "۱۲۳۴۵۶۷۸۹۰")
        XCTAssertEqual(KeyboardLanguage.urdu.digits, "1234567890")
    }

    func testTheLettersPlaneKeyNamesTheScript() {
        XCTAssertEqual(KeyboardLanguage.bulgarian.lettersPlaneLabel, "АБВ")
        XCTAssertEqual(KeyboardLanguage.russian.lettersPlaneLabel, "АБВ")
        XCTAssertEqual(KeyboardLanguage.georgian.lettersPlaneLabel, "აბგ")
        XCTAssertEqual(KeyboardLanguage.tamil.lettersPlaneLabel, "அஆஇ")
        XCTAssertEqual(KeyboardLanguage.dhivehi.lettersPlaneLabel, "ހށނ")
        XCTAssertEqual(KeyboardLanguage.marathi.lettersPlaneLabel, "अआइ")
        XCTAssertEqual(KeyboardLanguage.persian.lettersPlaneLabel, "ابپ")
        XCTAssertEqual(KeyboardLanguage.urdu.lettersPlaneLabel, "ابج")

        for language in KeyboardLanguage.allCases {
            let label = language.lettersPlaneLabel
            guard language.script != .latin else {
                XCTAssertEqual(label, "ABC", "\(language.rawValue)")
                continue
            }
            XCTAssertEqual(
                LanguageDetector.scripts(in: label), [language.script],
                "\(language.rawValue) labels its letters plane \(label)")
        }
    }
}
