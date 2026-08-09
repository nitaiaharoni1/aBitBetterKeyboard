import UIKit
import XCTest

@testable import AIKeyboardCore

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The sixty-four keyboards this build draws, and the Apple tables the catalogue
/// claims things about.
///
/// Every layout row was extracted from Apple's own keyboard layout data
/// (`TISCreateInputSourceList` + `UCKeyTranslate` over the macOS input source of
/// the same name), so what these tests protect is not the arrangement — that is
/// Apple's — but the properties a keyboard with three rows and no shift plane has
/// to keep anyway: every letter of the alphabet reachable, no two keys with the
/// same identity, and no row wider than the screen.
final class LanguageCatalogueTests: XCTestCase {

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

    // MARK: Layouts

    func testEveryLanguageHasThreeLetterRows() {
        for language in KeyboardLanguage.allCases {
            let rows = KeyboardLayout.rows(for: language, plane: .letters)
            XCTAssertEqual(rows.count, 3, "\(language.displayName) has \(rows.count) letter rows")
            XCTAssertFalse(rows.contains { $0.keys.isEmpty }, "\(language.displayName) has an empty row")
        }
    }

    /// Two keys with one identity is a `ForEach` with duplicate identity, which is
    /// undefined behaviour rather than a cosmetic clash. It happened for real:
    /// Greek writes its question mark as `;`, which collided with the `;` in the
    /// numbers plane's `-/:;()` run until that became an ano teleia.
    func testNoPlaneHasTwoKeysWithTheSameIdentity() {
        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                let identifiers = allKeys(language, plane).map(\.id)
                XCTAssertEqual(
                    Set(identifiers).count, identifiers.count,
                    "\(language.displayName) \(plane) repeats a key: "
                        + Dictionary(grouping: identifiers, by: { $0 })
                        .filter { $0.value.count > 1 }.keys.joined(separator: ", "))
            }
        }
    }

    /// Every row has to fit an iPhone 17 Pro in portrait. The tolerance is one key
    /// gap; a layout that is genuinely too wide overruns by whole keys.
    ///
    /// It used to be slack for one row: Hebrew's bottom row overran by 5.1pt,
    /// because nine letters plus delete leave `widths` less than the 1.15-unit
    /// floor it gives a stretcher. Moving delete to the top row — which is where
    /// Apple's own Hebrew keyboard has it — takes that to zero, and the delete key
    /// comes out 54.3pt, the same width as English's.
    func testNoRowOverflowsTheKeyboard() {
        let width: CGFloat = 402
        let sideInset = Theme.Metrics.sideInset
        let spacing = Theme.Metrics.keySpacing
        let available = width - sideInset * 2

        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                let columns = KeyboardLayout.columns(for: language, plane: plane)
                let unit = KeyboardLayout.unitWidth(
                    totalWidth: width, spacing: spacing, sideInset: sideInset, columns: columns)
                for row in allRows(language, plane) {
                    let widths = KeyboardLayout.widths(
                        for: row, totalWidth: available, unitWidth: unit, spacing: spacing)
                    let total =
                        widths.reduce(0, +) + spacing * CGFloat(row.keys.count - 1)
                        + row.sideInsetUnits * (unit + spacing) * 2
                    XCTAssertLessThanOrEqual(
                        total, available + spacing,
                        "\(language.displayName) \(plane) row \(row.id) is \(total - available)pt too wide")
                }
            }
        }
    }

    /// Ten for Latin and Hebrew; twelve for the layouts Apple itself draws twelve
    /// keys wide. Never fewer than ten, so nine-key Greek rows keep English's key
    /// size and centre rather than growing.
    func testColumnsFollowTheWidestRow() {
        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters), 10)
        XCTAssertEqual(KeyboardLayout.columns(for: .hebrew, plane: .letters), 10)
        XCTAssertEqual(KeyboardLayout.columns(for: .greek, plane: .letters), 10)
        XCTAssertEqual(KeyboardLayout.columns(for: .german, plane: .letters), 11)
        XCTAssertEqual(KeyboardLayout.columns(for: .hindi, plane: .letters), 11)
        for language in [KeyboardLanguage.arabic, .persian, .russian, .ukrainian, .turkish] {
            XCTAssertEqual(
                KeyboardLayout.columns(for: language, plane: .letters), 12,
                "\(language.displayName)")
        }
        // The numbers and symbols planes are ten keys wide in every language.
        for language in KeyboardLanguage.allCases {
            XCTAssertEqual(KeyboardLayout.columns(for: language, plane: .numbers), 10)
            XCTAssertEqual(KeyboardLayout.columns(for: language, plane: .symbols), 10)
        }
    }

    /// **Shift and delete are keys, and the column budget used to pretend they
    /// were not.** Apple's Bulgarian puts ten letters on the bottom row and
    /// eleven on the middle one, so the widest row said eleven columns while the
    /// bottom row needed thirteen, and it ran 45pt — a key and a half — off the
    /// side of an iPhone 17 Pro. `testNoRowOverflowsTheKeyboard` is what fails
    /// when this rule goes; this one says which rule.
    ///
    /// The three numbers below are the only ones that move, and the fourth
    /// assertion is why the rule is safe: English's bottom row is seven letters,
    /// 7 + 3 = 10, which is the ten columns it already had.
    func testTheBottomRowsFunctionKeysCountAgainstTheColumnBudget() {
        XCTAssertEqual(KeyboardLayout.columns(for: .bulgarian, plane: .letters), 13)
        XCTAssertEqual(KeyboardLayout.columns(for: .belarusian, plane: .letters), 12)
        XCTAssertEqual(KeyboardLayout.columns(for: .tongan, plane: .letters), 11)

        // Widest row alone would give these three 11, 11 and 10.
        for language in [KeyboardLanguage.bulgarian, .belarusian, .tongan] {
            let widest =
                KeyboardLayout.rows(for: language, plane: .letters).map(\.keys.count).max() ?? 0
            XCTAssertLessThan(
                widest, KeyboardLayout.columns(for: language, plane: .letters),
                "\(language.displayName) would fit its widest row and still overflow")
        }
        XCTAssertEqual(KeyboardLayout.columns(for: .english, plane: .letters), 10)
    }

    /// **Delete closes exactly one row, and which row is a measurement.** Sixty
    /// three layouts put it at the end of the bottom row; Apple's Hebrew keyboard
    /// puts it at the end of the *top* row, beside eight letters, and
    /// `Bar/layouts/stock-rendered-rows.json` is the photograph of that.
    ///
    /// The wrong implementations this rejects are both real shapes: delete on
    /// every row (a `map` that appends it unconditionally), and delete on no row
    /// at all for Hebrew (a `deleteRow` the row builder never reads, which is what
    /// happens when the field is added and the loop is not).
    func testDeleteClosesOneRowAndItIsTheRowAppleUses() {
        for language in KeyboardLanguage.allCases {
            let rows = KeyboardLayout.rows(for: language, plane: .letters)
            let carrying = rows.filter { row in row.keys.contains { $0.cap == .backspace } }
            XCTAssertEqual(
                carrying.count, 1,
                "\(language.displayName) has delete on \(carrying.count) letter rows")
            guard let row = carrying.first else { continue }
            XCTAssertEqual(
                row.id, language == .hebrew ? 0 : 2,
                "\(language.displayName) puts delete on row \(row.id)")
            XCTAssertEqual(
                row.keys.last?.cap, .backspace,
                "\(language.displayName) does not end that row with delete")
        }
    }

    // MARK: Reachability

    /// **The property that replaces a long-press popup being optional.** Apple's
    /// desktop layouts put a third of Arabic, every accented Greek vowel and half
    /// of InScript behind shift or a dead key, and none of those scripts has a
    /// case for a shift key to serve. Every one of them has to come back as a long
    /// press, or the letter cannot be typed at all.
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

    /// **The same property for all sixty-four, against CLDR's alphabet rather
    /// than a hand-written one.** `NSLocale.exemplarCharacterSet` is Apple's own
    /// answer to "what letters does this language write with", so a layout that
    /// cannot reach one of them cannot write the language — and nobody on this
    /// team reads Georgian, Tamil or Dhivehi to notice by eye.
    ///
    /// Combining marks count only where the layout puts them on keys, which is
    /// the difference between an abugida and everything else: Tamil's vowel signs
    /// and Devanagari's matras are letters and have to be typeable, while the
    /// harakat CLDR lists for Arabic and the tone marks it lists for Yoruba are
    /// optional diacritics no phone keyboard carries. The rule reads the layout,
    /// not a list of scripts.
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

    /// The exclusion list is three Devanagari entries and nothing else, and that
    /// is the assertion: an exception that spreads is a rule that has been given
    /// up on. Each character named there is one Apple's own `Hindi – InScript`
    /// layout cannot produce from its three letter rows either — ऌ and ऽ are on
    /// no key at all, ऍ and ॅ are on its number row, ॐ is on its option layer —
    /// so the phone loses nothing the desktop offers.
    func testTheAlphabetExclusionsAreThreeLanguagesAndAreNamed() {
        let excluded = KeyboardLanguage.allCases.filter { !Self.unreachable(for: $0).isEmpty }
        XCTAssertEqual(Set(excluded), [.hindi, .marathi, .nepali])
        for language in excluded {
            XCTAssertEqual(language.script, .devanagari)
        }
        // …and they are genuinely absent, so the list is not stale.
        let hindi = reachableLetters(.hindi)
        for character in ["ऌ", "ऽ", "ॅ"] {
            XCTAssertFalse(hindi.contains(character), "\(character) is reachable now; drop it")
        }
    }

    /// The forms Apple's `Arabic` layout hides behind shift. Without these a user
    /// cannot type أنا, شيء or مسؤول.
    func testArabicHamzaFormsAreReachable() {
        let reachable = reachableLetters(.arabic)
        for form in ["ة", "ى", "ء", "أ", "إ", "آ", "ؤ", "ئ"] {
            XCTAssertTrue(reachable.contains(form), "Arabic cannot type \(form)")
        }
    }

    /// Devanagari has no case, so InScript's shifted plane — which is where half
    /// the consonants and every independent vowel live — has to be long presses.
    func testTheInScriptShiftedPlaneIsReachable() {
        let reachable = reachableLetters(.hindi)
        let shifted = [
            "औ", "ऐ", "आ", "ई", "ऊ", "भ", "ङ", "घ", "ध", "झ", "ढ", "ञ", "ओ", "ए", "अ", "इ",
            "उ", "फ", "ऱ", "ख", "थ", "छ", "ठ", "ऑ", "ँ", "ण", "ऩ", "ऴ", "ळ", "श", "ष", "।", "य़"
        ]
        let missing = shifted.filter { !reachable.contains($0) }
        XCTAssertTrue(missing.isEmpty, "Hindi cannot type: \(missing.joined(separator: " "))")
    }

    /// Three words that could not be typed at all, each because one character was
    /// on a desktop key a phone does not have.
    ///
    /// `कृपया` — "please", among the commonest words in Hindi — needs `ृ`, which
    /// InScript puts on `=`. `दुःख` needs the visarga, on shift of `-`. And
    /// Spanish opens a question with `¿`, which Apple's Spanish layout shares with
    /// `¡` on one key. All three were missing, and none of them failed to compile.
    func testTheWordsThatCouldNotBeTypedCanBeTyped() {
        let hindi = reachableLetters(.hindi)
        for character in ["ृ", "ऋ", "ः"] {
            XCTAssertTrue(hindi.contains(character), "Hindi cannot type \(character)")
        }
        // Scalar by scalar, not `Character` by `Character`: `कृपया` is three
        // grapheme clusters (कृ, प, या) and five keystrokes, and iterating the
        // clusters would ask the keyboard for a key that is two keys.
        for scalar in "कृपया".unicodeScalars {
            XCTAssertTrue(hindi.contains(String(scalar)), "कृपया needs \(scalar)")
        }

        let spanish = reachablePunctuation(.spanish)
        XCTAssertTrue(spanish.contains("¿"), "Spanish cannot open a question")
        XCTAssertTrue(spanish.contains("¡"), "Spanish cannot open an exclamation")
        // …and nobody else grows them, because no other Latin language uses them.
        XCTAssertFalse(reachablePunctuation(.french).contains("¿"))
    }

    /// Turkish has two i's and they are different letters. `String.uppercased()`
    /// merges them, which turns `İstanbul` into `Istanbul` — a spelling error in
    /// every word it lands in. Both the document and the key cap go through
    /// `KeyboardLanguage.uppercased(_:)`; this pins the rule they share.
    func testTurkishUppercasesBothOfItsLetterI() {
        XCTAssertEqual(KeyboardLanguage.turkish.uppercased("i"), "İ")
        XCTAssertEqual(KeyboardLanguage.turkish.uppercased("ı"), "I")
        XCTAssertEqual(KeyboardLanguage.turkish.uppercased("istanbul"), "İSTANBUL")
        // The default rule, which every other shipped language wants.
        XCTAssertEqual(KeyboardLanguage.english.uppercased("i"), "I")
        XCTAssertEqual("i".uppercased(), "I", "the rule Turkish had to be rescued from")

        // Both letters are on the layout, so shift is the only thing that has to
        // tell them apart.
        let turkish = reachableLetters(.turkish)
        XCTAssertTrue(turkish.contains("i"))
        XCTAssertTrue(turkish.contains("ı"))
    }

    func testAnAlternateIsNeverTheKeyItSitsOn() {
        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                for key in allKeys(language, plane) {
                    guard case .character(let value) = key.cap else { continue }
                    XCTAssertFalse(
                        key.alternates.contains(value),
                        "\(language.displayName) offers \(value) as its own alternate")
                    XCTAssertEqual(Set(key.alternates).count, key.alternates.count)
                }
            }
        }
    }

    // MARK: Digits, measured against Apple's locale data

    /// Persian is the one shipped language whose numbers plane is not Latin
    /// digits, and it is not a judgement call: `Locale(identifier: "fa")` reports
    /// the `arabext` numbering system.
    func testPersianDigitsAreTheOnesApplesLocaleUses() throws {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fa")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        XCTAssertEqual(KeyboardLanguage.persian.digits, formatter.string(from: 1_234_567_890))
        XCTAssertEqual(Locale(identifier: "fa").numberingSystem.identifier, "arabext")
    }

    /// And Arabic is not, which is the more surprising half. Apple's bare `ar`
    /// locale reports Latin digits; only some of its regions report `arab`.
    /// This catalogue has one Arabic, so it follows the bare locale.
    func testArabicAndHindiUseLatinDigitsBecauseApplesLocalesDo() {
        XCTAssertEqual(Locale(identifier: "ar").numberingSystem.identifier, "latn")
        XCTAssertEqual(Locale(identifier: "hi_IN").numberingSystem.identifier, "latn")
        XCTAssertEqual(KeyboardLanguage.arabic.digits, "1234567890")
        XCTAssertEqual(KeyboardLanguage.hindi.digits, "1234567890")
        // The regions that disagree, so the decision is on the record rather than
        // the memory of it.
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
        // Thaana is not Arabic and Georgian is not Cyrillic, which is the pair of
        // mistakes a range table makes when it is written by eye: Thaana's block
        // sits immediately above Arabic's and Georgian's immediately above
        // Cyrillic's, so an off-by-one on either boundary lands here.
        XCTAssertEqual(KeyboardLanguage.dhivehi.script, .thaana)
        XCTAssertEqual(KeyboardLanguage.pashto.script, .arabic)
        XCTAssertEqual(KeyboardLanguage.georgian.script, .georgian)
        XCTAssertEqual(KeyboardLanguage.tajik.script, .cyrillic)
    }

    /// Every letter on every keyboard is written in the script its language
    /// claims. A key that types another script is the failure this catalogue is
    /// most exposed to — fifty layouts nobody on this team can read by eye — and
    /// the shipped Yiddish layout was dropped over exactly this: Apple's macOS
    /// arrangement emits Hebrew presentation forms rather than the letters
    /// Yiddish is stored in.
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

    /// A script this build cannot name still has to answer `other`, because that
    /// is what routes it to the cloud.
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

    /// **Pinned against the live list, not against memory.** Read on 2026-08-09
    /// from both macOS 26.5 and this Simulator, which agreed exactly. The count is
    /// deliberately not asserted; the shape is what the routing rests on.
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

    /// The routing consequence, and the bug it replaces: `.other` used to end up
    /// *inside* the supported set, because Japanese, Korean and Chinese had no
    /// name in `TextScript` and every unnamed script answers `.other`. Cyrillic,
    /// Greek, Arabic and Devanagari all passed the subset check and went to a
    /// model with no word of any of them.
    func testTheOnDeviceEngineDeclinesEveryScriptAppleDoesNotList() throws {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else {
            throw XCTSkip("FoundationModels needs iOS 26")
        }
        let engine = FoundationModelsEngine()
        XCTAssertTrue(engine.canHandle("can you send me the id", action: .fix))
        XCTAssertTrue(engine.canHandle("Merhaba nasılsın", action: .fix))
        // Every script this keyboard can type in that Apple's list does not name,
        // including the three added with the catalogue. A script the model has no
        // word of must reach the cloud, and Georgian, Tamil and Thaana are as
        // absent from `supportedLanguages` as Hebrew is.
        let unsupported = [
            "אני אבדוק את זה", "مرحبا كيف حالك", "привет как дела", "Καλημέρα", "नमस्ते",
            "გამარჯობა", "வணக்கம்", "އައްސަލާމް ޢަލައިކުމް", "سلام ورور"
        ]
        for text in unsupported {
            XCTAssertFalse(
                engine.canHandle(text, action: .fix),
                "\(text) must be routed to the cloud, not answered in English")
        }
        // …and the reason, so this cannot pass because the detector stopped
        // recognising them: each one is named, and none of them collapses to
        // `.other`.
        let scripts = Set(unsupported.flatMap { LanguageDetector.scripts(in: $0) })
        XCTAssertEqual(
            scripts,
            [.hebrew, .arabic, .cyrillic, .greek, .devanagari, .georgian, .tamil, .thaana])
        #else
        throw XCTSkip("FoundationModels is not in this SDK")
        #endif
    }

    /// The message the user reads when nothing can serve their language names the
    /// language rather than shrugging at it.
    func testTheUnsupportedLanguageMessageNamesTheScript() {
        XCTAssertTrue(AIEngineError.unsupportedLanguage(.arabic).message.contains("Arabic"))
        XCTAssertTrue(AIEngineError.unsupportedLanguage(.cyrillic).message.contains("Cyrillic"))
        XCTAssertTrue(AIEngineError.unsupportedLanguage(.hebrew).message.contains("Hebrew"))
    }

    // MARK: Every other field, against the Apple table it came from

    /// `displayName` and `nativeName` are `Locale.localizedString(forIdentifier:)`
    /// verbatim for everything added after the first fourteen, which is why they
    /// read "Norwegian Bokmål" and "srpski (latinica)" rather than tidied
    /// versions of those.
    ///
    /// The fourteen are compared case-insensitively, in their own locale: they
    /// were written with an initial capital ("Français", "Русский") where CLDR
    /// writes lower case, and the word is what is being checked. Turkish is the
    /// reason the fold is locale-aware.
    func testEveryNameIsApplesOwnNameForTheLanguage() {
        let english = Locale(identifier: "en")
        for language in KeyboardLanguage.allCases {
            let locale = self.locale(for: language)
            guard let apples = locale.localizedString(forIdentifier: language.languageTag),
                let inEnglish = english.localizedString(forIdentifier: language.languageTag)
            else {
                XCTFail("\(language.rawValue) has no name in Apple's own tables")
                continue
            }
            XCTAssertEqual(
                language.nativeName.lowercased(with: locale), apples.lowercased(with: locale),
                "\(language.rawValue) calls itself \(language.nativeName); Apple says \(apples)")
            XCTAssertEqual(
                language.displayName.lowercased(with: english),
                inEnglish.lowercased(with: english),
                "\(language.rawValue) is \(language.displayName); Apple says \(inEnglish)")
        }
    }

    /// **The space bar's caption is Apple's own word, checked against Apple's own
    /// table at run time.** `UIKitCore` carries `Space` in 53 `.lproj` folders,
    /// and `Bundle(for: UIView.self)` reaches every one of them from inside a
    /// test, so nothing here is a translation somebody wrote down.
    ///
    /// Two shapes are allowed and both are honest. Where Apple has the language,
    /// the caption is Apple's string case-insensitively — the casing differs
    /// because iOS draws this cap in lower case and Apple's table is title case.
    /// Where Apple does not, the caption is the language's own name, which is
    /// what Gboard puts there, rather than a word nobody has checked.
    func testTheSpaceCaptionIsApplesOwnWordOrTheLanguagesOwnName() throws {
        let uiKit = Bundle(for: UIView.self)
        XCTAssertNotNil(uiKit.path(forResource: "en", ofType: "lproj"), "UIKitCore has no lprojs")

        var verified = 0
        var unverified: [KeyboardLanguage] = []
        for language in KeyboardLanguage.allCases {
            let locale = self.locale(for: language)
            guard let apples = Self.appleSpaceCaption(for: language, in: uiKit) else {
                if language.spaceLabel != language.nativeName { unverified.append(language) }
                continue
            }
            verified += 1
            XCTAssertEqual(
                language.spaceLabel.lowercased(with: locale), apples.lowercased(with: locale),
                "\(language.rawValue) says \(language.spaceLabel); Apple says \(apples)")
        }
        XCTAssertGreaterThan(verified, 25, "only \(verified) captions came from Apple's table")

        // Persian is the whole of the exception, and it is one of the fourteen
        // that predate the rule: `UIKitCore` has no `fa.lproj`, so its "فاصله"
        // is the last caption in this catalogue nothing verifies. Nothing added
        // since may join it — a new language with no Apple caption shows its own
        // name instead.
        XCTAssertEqual(unverified, [.persian], "\(unverified.map(\.rawValue)) invent a caption")
        XCTAssertNil(Self.appleSpaceCaption(for: .persian, in: uiKit))

        // The sentinel works: a key `UIKitCore` certainly does not carry reads as
        // absent rather than echoing itself back. Without it, `value: ""` returns
        // the key and every "Apple says so" above could be Apple saying nothing.
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

        // The one this file used to assert from memory.
        XCTAssertEqual(Self.appleSpaceCaption(for: .hebrew, in: uiKit), "רווח")
    }

    /// Apple has no localised return-key cap anywhere on this machine — the near
    /// misses are VoiceOver phrasings ("Volver", "वापस जाएँ") — so the fourteen
    /// that shipped with a word keep it and nothing added since invents one.
    /// `KeyView` draws the return glyph for the rest.
    func testOnlyTheOriginalFourteenClaimAReturnCaption() {
        let named = KeyboardLanguage.allCases.filter { $0.returnLabel != nil }
        XCTAssertEqual(named.count, 14, "\(named.map(\.rawValue)) claim a return caption")
        XCTAssertEqual(KeyboardLanguage.english.returnLabel, "return")
        XCTAssertNil(KeyboardLanguage.tamil.returnLabel)
    }

    /// The flag is the region CLDR calls this language's likely home, which is a
    /// fact about CLDR and not a claim about where the language is spoken. It is
    /// derived rather than chosen, so Catalan flies Spain's flag and Welsh the
    /// United Kingdom's.
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
            // The first fourteen chose their own and predate the rule: Arabic
            // flies Saudi Arabia's where CLDR maximises `ar` to Egypt.
            guard !Self.original.contains(language) else { continue }
            XCTAssertEqual(
                language.flag, flag,
                "\(language.rawValue) shows \(language.flag); CLDR says \(region)")
        }
        XCTAssertEqual(KeyboardLanguage.arabic.flag, "🇸🇦", "the older entries are left alone")
    }

    /// Digits follow the language's own numbering system, which is a measurement
    /// and not a guess about the script: Nepali writes Devanagari digits and
    /// Hindi, in the same script, does not; Pashto writes Persian digits and
    /// Urdu, in the same script, does not.
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

    /// The key back to the letters plane names the script, so every language
    /// written in one script says the same thing on it — and it is never "ABC"
    /// on a keyboard with no A on it.
    func testTheLettersPlaneKeyNamesTheScript() {
        XCTAssertEqual(KeyboardLanguage.bulgarian.lettersPlaneLabel, "АБВ")
        XCTAssertEqual(KeyboardLanguage.russian.lettersPlaneLabel, "АБВ")
        XCTAssertEqual(KeyboardLanguage.georgian.lettersPlaneLabel, "აბგ")
        XCTAssertEqual(KeyboardLanguage.tamil.lettersPlaneLabel, "அஆஇ")
        XCTAssertEqual(KeyboardLanguage.dhivehi.lettersPlaneLabel, "ހށނ")
        XCTAssertEqual(KeyboardLanguage.marathi.lettersPlaneLabel, "अआइ")
        // Persian keeps its own, because its alphabet does not open the way
        // Arabic's does.
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

    // MARK: Helpers

    /// The fourteen that shipped before the catalogue was extended, which is the
    /// set the rules above grandfather.
    private static let original: Set<KeyboardLanguage> = [
        .english, .hebrew, .arabic, .french, .german, .greek, .hindi, .italian, .persian,
        .portuguese, .russian, .spanish, .turkish, .ukrainian
    ]

    private func locale(for language: KeyboardLanguage) -> Locale {
        Locale(identifier: language.languageTag)
    }

    /// Apple's own word for the space bar in this language, or nil when Apple
    /// ships no localisation for it.
    private static func appleSpaceCaption(
        for language: KeyboardLanguage, in bundle: Bundle
    )
        -> String?
    {
        // `nb` is filed under `no`, and a language with a script subtag under its
        // base tag, which is how Apple's own folders are named.
        let candidates = [
            language.languageTag, language.languageTag.replacingOccurrences(of: "-", with: "_"),
            String(language.languageTag.prefix(while: { $0 != "-" })),
            language.languageTag == "nb" ? "no" : language.languageTag
        ]
        for candidate in candidates {
            guard let path = bundle.path(forResource: candidate, ofType: "lproj"),
                let localised = Bundle(path: path)
            else { continue }
            let caption = localised.localizedString(
                forKey: "Space", value: Self.missingCaption, table: nil)
            if caption != Self.missingCaption { return caption }
        }
        return nil
    }

    /// **`value:` has to be something no caption could be, and `""` is not it.**
    /// `localizedString(forKey:value:table:)` falls back to `value` when the key
    /// is missing *and* to the key itself when `value` is empty — so an `.lproj`
    /// that had lost `Space` would hand back the literal string `"Space"`, and a
    /// language whose caption happened to be checked against it would pass while
    /// verifying nothing. No language hits that today; this makes it unable to.
    private static let missingCaption = "\u{0}no caption in this lproj\u{0}"

    /// The characters CLDR lists in a language's alphabet that no keyboard here
    /// reaches — every one of them also absent from the three letter rows of
    /// Apple's own macOS layout for the same language.
    ///
    /// `ऌ` and `ऽ` are on no key of `Hindi – InScript` at all; `ऍ` and `ॅ` are on
    /// its number row and `ॐ` on its option layer, neither of which a phone has.
    private static func unreachable(for language: KeyboardLanguage) -> Set<String> {
        switch language {
        case .hindi, .marathi, .nepali: return ["ऌ", "ऽ", "ऍ", "ॅ", "ॐ"]
        default: return []
        }
    }

    /// The language's own alphabet as Apple spells it, folded to the case a key
    /// cap carries and reduced to what a three-row keyboard is answerable for.
    private func alphabet(of language: KeyboardLanguage) -> [String] {
        let locale = self.locale(for: language)
        guard
            let exemplar = (locale as NSLocale).object(forKey: .exemplarCharacterSet)
                as? CharacterSet
        else { return [] }

        let writesWithMarks = KeyboardLayout.rows(for: language, plane: .letters)
            .flatMap(\.keys)
            .contains { key in
                guard case .character(let value) = key.cap,
                    let scalar = value.unicodeScalars.first
                else { return false }
                return scalar.properties.generalCategory == .nonspacingMark
            }

        var found: Set<String> = []
        for value in UInt32(0x20)...UInt32(0x2FFF) {
            guard let scalar = Unicode.Scalar(value), exemplar.contains(scalar) else { continue }
            let category = scalar.properties.generalCategory
            switch category {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter,
                .otherLetter, .spacingMark:
                break
            case .nonspacingMark where writesWithMarks:
                break
            default:
                continue
            }
            // `İ` lower-cases to `i` plus a combining dot outside Turkish, and
            // Lithuanian adds dots of its own: those are casing artefacts of the
            // same letter, not letters a key has to carry.
            let lowered = String(scalar).lowercased(with: locale)
            guard lowered.unicodeScalars.count == 1 else { continue }
            found.insert(lowered)
        }
        return found.sorted()
    }

    private func allRows(_ language: KeyboardLanguage, _ plane: KeyboardPlane) -> [KeyRow] {
        KeyboardLayout.rows(for: language, plane: plane)
            + [KeyboardLayout.bottomRow(for: language, plane: plane, showsGlobe: true)]
    }

    private func allKeys(_ language: KeyboardLanguage, _ plane: KeyboardPlane) -> [KeySpec] {
        allRows(language, plane).flatMap(\.keys)
    }

    /// Everything the letters plane can produce: the keys themselves and their
    /// long presses.
    private func reachableLetters(_ language: KeyboardLanguage) -> Set<String> {
        reachable(language, .letters)
    }

    /// The same for the two planes that carry punctuation.
    private func reachablePunctuation(_ language: KeyboardLanguage) -> Set<String> {
        reachable(language, .numbers).union(reachable(language, .symbols))
    }

    private func reachable(_ language: KeyboardLanguage, _ plane: KeyboardPlane) -> Set<String> {
        var out: Set<String> = []
        for key in KeyboardLayout.rows(for: language, plane: plane).flatMap(\.keys) {
            if case .character(let value) = key.cap { out.insert(value) }
            out.formUnion(key.alternates)
        }
        return out
    }
}
