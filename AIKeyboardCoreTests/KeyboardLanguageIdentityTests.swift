import XCTest

@testable import AIKeyboardCore

/// Persistence contracts for `KeyboardLanguage`: raw values written to the App
/// Group plist and carried in `ScreenReadingRecord.language` between two
/// processes.
final class KeyboardLanguageIdentityTests: XCTestCase {

    // MARK: Identity and persistence

    /// **The migration, and there isn't one.** `english` and `hebrew` are what
    /// every install has been writing into the App Group plist since build 1, and
    /// what `ScreenReadingRecord.language` carries between two processes. Turning
    /// the enum into a struct kept them, so an existing install reads back exactly
    /// what it wrote.
    func testTheOriginalTwoIdentifiersStillResolve() {
        XCTAssertEqual(KeyboardLanguage(rawValue: "english"), .english)
        XCTAssertEqual(KeyboardLanguage(rawValue: "hebrew"), .hebrew)
        XCTAssertEqual(KeyboardLanguage.english.rawValue, "english")
        XCTAssertEqual(KeyboardLanguage.hebrew.rawValue, "hebrew")
    }

    /// How `SharedStore.load` reads the stored list. A value this build does not
    /// know drops out; the ones beside it survive, which is what stops a
    /// downgrade from wiping the user's languages.
    func testAStoredListSurvivesAnUnknownEntry() {
        let stored = ["english", "klingon", "hebrew"]
        XCTAssertEqual(
            stored.compactMap(KeyboardLanguage.init(rawValue:)), [.english, .hebrew])
    }

    func testCodableIsAPlainString() throws {
        let data = try JSONEncoder().encode([KeyboardLanguage.arabic, .hindi])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["arabic","hindi"]"#)
        XCTAssertEqual(
            try JSONDecoder().decode([KeyboardLanguage].self, from: data), [.arabic, .hindi])
    }

    func testEveryIdentifierIsUniqueAndResolvable() {
        let identifiers = KeyboardLanguage.allCases.map(\.rawValue)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        for identifier in identifiers {
            XCTAssertEqual(KeyboardLanguage(rawValue: identifier)?.rawValue, identifier)
        }
    }

    /// Direction is a property of the script, never of a hardcoded pair, which is
    /// how Persian gets it right without being mentioned anywhere — and Urdu and
    /// Pashto after it, and Dhivehi, whose script is not Arabic at all.
    func testRightToLeftFollowsFromTheScript() {
        let rightToLeft = Set(KeyboardLanguage.allCases.filter(\.isRightToLeft))
        XCTAssertEqual(rightToLeft, [.hebrew, .arabic, .persian, .urdu, .pashto, .dhivehi])
        XCTAssertEqual(KeyboardLanguage.persian.script, .arabic)
        XCTAssertEqual(KeyboardLanguage.dhivehi.script, .thaana)
        // Right to left is not a property of the region or of the language: the
        // three scripts here say so, and every other language of the same region
        // runs the other way.
        XCTAssertFalse(KeyboardLanguage.georgian.isRightToLeft)
        XCTAssertFalse(KeyboardLanguage.tamil.isRightToLeft)
    }

    /// `KeyboardViewController.publishInputLanguage` hands this to the host as
    /// `primaryLanguage`. WhatsApp and Notes pick writing direction from it, so
    /// a tag Apple does not treat as right-to-left is a Hebrew keyboard whose
    /// letters sit on the left. Apple's own Hebrew keyboard reports `he-IL`.
    func testTheHostInputModeTagIsWhatApplesKeyboardReports() {
        XCTAssertEqual(KeyboardLanguage.hebrew.inputModeTag, "he-IL")
        XCTAssertEqual(KeyboardLanguage.english.inputModeTag, "en-US")
        XCTAssertEqual(KeyboardLanguage.arabic.inputModeTag, "ar")
        XCTAssertEqual(KeyboardLanguage.persian.inputModeTag, "fa")
        XCTAssertEqual(KeyboardLanguage.dhivehi.inputModeTag, "dv")
        XCTAssertEqual(KeyboardLanguage.urdu.inputModeTag, "ur")
        XCTAssertEqual(KeyboardLanguage.pashto.inputModeTag, "ps")
    }

    func testAppleTreatsEveryRightToLeftInputModeTagAsRightToLeft() {
        for language in KeyboardLanguage.allCases where language.isRightToLeft {
            XCTAssertEqual(
                Locale.Language(identifier: language.inputModeTag).characterDirection,
                .rightToLeft,
                "\(language.displayName) publishes \(language.inputModeTag)")
        }
    }

    /// A `SharedStore` written by this build and read by the one before it must
    /// lose the new languages and keep the old, not fail the whole decode.
    func testEveryIdentifierAddedSinceTheFirstFourteenIsStillAPlainString() throws {
        let data = try JSONEncoder().encode([KeyboardLanguage.tamil, .serbianLatin, .dhivehi])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["tamil","serbianLatin","dhivehi"]"#)

        // The shape `SharedStore.load` relies on: the reader that does not know
        // Tamil keeps English and Hebrew.
        let stored = ["english", "tamil", "hebrew"]
        XCTAssertEqual(
            stored.compactMap(KeyboardLanguage.init(rawValue:)), [.english, .tamil, .hebrew])
        XCTAssertNil(KeyboardLanguage(rawValue: "Tamil"), "identifiers are case sensitive")
    }
}
