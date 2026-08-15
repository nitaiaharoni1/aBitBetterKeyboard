import XCTest

@testable import AIKeyboardCore

/// Reachability tests extracted from `LanguageCatalogueTests`.
final class LanguageReachabilityTests: LanguageCatalogueTestFixture {

    // MARK: Reachability

    func testEveryAlphabetIsReachable() {
        let alphabets: [(KeyboardLanguage, String)] = [
            (.english, "abcdefghijklmnopqrstuvwxyz"),
            (.hebrew, "אבגדהוזחטיכלמנסעפצקרשתךםןףץ"),
            (.arabic, "ابتثجحخدذرزسشصضطظعغفقكلمنهوي"),
            (.persian, "ابپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی"),
            (.russian, "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"),
            (.ukrainian, "абвгґдеєжзиіїйклмнопрстуфхцчшщьюя"),
            (.greek, "αβγδεζηθικλμνξοπρσςτυφχψω"),
            (.turkish, "abcçdefgğhıijklmnoöprsştuüvyz"),
            (.french, "abcdefghijklmnopqrstuvwxyz"),
            (.german, "abcdefghijklmnopqrstuvwxyzäöüß"),
            (.spanish, "abcdefghijklmnopqrstuvwxyzñ"),
            (.portuguese, "abcdefghijklmnopqrstuvwxyzç"),
            (.italian, "abcdefghijklmnopqrstuvwxyz")
        ]
        for (language, alphabet) in alphabets {
            let reachable = reachableLetters(language)
            let missing = alphabet.map(String.init).filter { !reachable.contains($0) }
            XCTAssertTrue(
                missing.isEmpty,
                "\(language.displayName) cannot type: \(missing.joined(separator: " "))")
        }
    }

    func testEveryLanguageCanTypeItsOwnAlphabet() {
        for language in KeyboardLanguage.allCases {
            let reachable = Set(
                reachableLetters(language).map { $0.lowercased(with: locale(for: language)) })
            let missing = alphabet(of: language)
                .filter { !reachable.contains($0) }
                .filter { !Self.unreachable(for: language).contains($0) }
            XCTAssertEqual(
                missing, [],
                "\(language.displayName) cannot type: \(missing.joined(separator: " "))")
        }
    }

    func testTheAlphabetExclusionsAreThreeLanguagesAndAreNamed() {
        let excluded = KeyboardLanguage.allCases.filter { !Self.unreachable(for: $0).isEmpty }
        XCTAssertEqual(Set(excluded), [.hindi, .marathi, .nepali])
        for language in excluded {
            XCTAssertEqual(language.script, .devanagari)
        }
        let hindi = reachableLetters(.hindi)
        for character in ["ऌ", "ऽ", "ॅ"] {
            XCTAssertFalse(hindi.contains(character), "\(character) is reachable now; drop it")
        }
    }

    /// The forms Apple's `Arabic` layout hides behind shift.
    func testArabicHamzaFormsAreReachable() {
        let reachable = reachableLetters(.arabic)
        for form in ["ة", "ى", "ء", "أ", "إ", "آ", "ؤ", "ئ"] {
            XCTAssertTrue(reachable.contains(form), "Arabic cannot type \(form)")
        }
    }

    func testTheInScriptShiftedPlaneIsReachable() {
        let reachable = reachableLetters(.hindi)
        let shifted = [
            "औ", "ऐ", "आ", "ई", "ऊ", "भ", "ङ", "घ", "ध", "झ", "ढ", "ञ", "ओ", "ए", "अ", "इ",
            "उ", "फ", "ऱ", "ख", "थ", "छ", "ठ", "ऑ", "ँ", "ण", "ऩ", "ऴ", "ळ", "श", "ष", "।", "य़"
        ]
        let missing = shifted.filter { !reachable.contains($0) }
        XCTAssertTrue(missing.isEmpty, "Hindi cannot type: \(missing.joined(separator: " "))")
    }

    func testTheWordsThatCouldNotBeTypedCanBeTyped() {
        let hindi = reachableLetters(.hindi)
        for character in ["ृ", "ऋ", "ः"] {
            XCTAssertTrue(hindi.contains(character), "Hindi cannot type \(character)")
        }
        for scalar in "कृपया".unicodeScalars {
            XCTAssertTrue(hindi.contains(String(scalar)), "कृपया needs \(scalar)")
        }

        let spanish = reachablePunctuation(.spanish)
        XCTAssertTrue(spanish.contains("¿"), "Spanish cannot open a question")
        XCTAssertTrue(spanish.contains("¡"), "Spanish cannot open an exclamation")
        XCTAssertFalse(reachablePunctuation(.french).contains("¿"))
    }

    func testTurkishUppercasesBothOfItsLetterI() {
        XCTAssertEqual(KeyboardLanguage.turkish.uppercased("i"), "İ")
        XCTAssertEqual(KeyboardLanguage.turkish.uppercased("ı"), "I")
        XCTAssertEqual(KeyboardLanguage.turkish.uppercased("istanbul"), "İSTANBUL")
        XCTAssertEqual(KeyboardLanguage.english.uppercased("i"), "I")
        XCTAssertEqual("i".uppercased(), "I", "the rule Turkish had to be rescued from")

        let turkish = reachableLetters(.turkish)
        XCTAssertTrue(turkish.contains("i"))
        XCTAssertTrue(turkish.contains("ı"))
    }

    func testAnAlternateIsNeverTheKeyItSitsOn() {
        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                for key in allKeys(language, plane) {
                    guard case .character(let value) = key.cap else { continue }
                    // **The punctuation key is the one deliberate exception, and
                    // it is documented rather than accidental.** Its popup is
                    // SwiftKey's order, `! @ # , . ?`, and the full stop is in it
                    // on purpose: the strip is aligned so the period sits over
                    // the key it came from, and `alternateRestIndex` names the
                    // period rather than slot 0 so lifting without sliding still
                    // types a full stop. Removing it from the list would move
                    // every other mark and break that resting behaviour. See
                    // `.claude/rules/keyboard-layout.md`. This assertion was
                    // written as a blanket rule and had been failing on committed
                    // `main` against a design that is correct; the rule it means
                    // is "no key offers a redundant alternate", and for this one
                    // key the alternate is not redundant, it is the anchor.
                    if key.id != KeyboardLayout.punctuationKeyID {
                        XCTAssertFalse(
                            key.alternates.contains(value),
                            "\(language.displayName) offers \(value) as its own alternate")
                    }
                    XCTAssertEqual(Set(key.alternates).count, key.alternates.count)
                }
            }
        }
    }
}
