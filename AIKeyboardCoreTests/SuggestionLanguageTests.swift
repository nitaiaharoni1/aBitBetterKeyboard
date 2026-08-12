import UIKit
import XCTest

@testable import AIKeyboardCore

/// What the suggestion bar does in the twelve languages it was not written for.
///
/// `SuggestionEngineTests` covers English and Hebrew, where there is a
/// hand-written next-word table and a measured autocorrect rule. This covers the
/// rest, where the answer is mostly "offer less, never offer another language's
/// words", and pins the two Apple tables that decide which is which.
@MainActor
final class SuggestionLanguageTests: XCTestCase {

    // MARK: Apple's checker list

    /// Every identifier the catalogue claims has to be one `UITextChecker`
    /// actually answers to. The shape of that list is its own and cannot be
    /// derived: `he_IL` and `de_DE` carry a region, `ar` and `hi` do not.
    func testEverySpellCheckerLocaleIsOneAppleActuallyHas() {
        let available = Set(UITextChecker.availableLanguages)
        XCTAssertFalse(available.isEmpty)
        for language in KeyboardLanguage.allCases {
            guard let locale = language.spellCheckerLocale else { continue }
            XCTAssertTrue(
                available.contains(locale),
                "\(language.displayName) claims \(locale), which is not in UITextChecker's list")
        }
        // The claim this repo has made since the suggestion bar was written.
        XCTAssertTrue(available.contains("he_IL"))
    }

    /// Persian is the reason `spellCheckerLocale` is optional. Nothing under `fa`
    /// is in the list, and nothing was substituted for it.
    func testPersianIsAbsentFromApplesCheckerList() {
        let available = Set(UITextChecker.availableLanguages)
        XCTAssertFalse(available.contains("fa"))
        XCTAssertFalse(available.contains("fa_IR"))
        XCTAssertNil(KeyboardLanguage.persian.spellCheckerLocale)
    }

    // MARK: Degrading honestly

    /// With no dictionary there is nothing to complete from, and the answer is to
    /// offer the keystrokes rather than to borrow Arabic's — the scripts are the
    /// same and the languages are not.
    func testALanguageWithoutACheckerOffersOnlyTheKeystrokes() {
        let results = SuggestionEngine.suggestions(
            prefix: "سلا", context: "", languages: [.persian])

        XCTAssertEqual(results.map(\.text), ["سلا"])
        XCTAssertFalse(
            results.contains { $0.isDefault && $0.text != "سلا" },
            "nothing may be autocorrected without evidence that it is wrong")
    }

    /// The final-form rule is Hebrew orthography, not a right-to-left rule. Arabic
    /// and Persian change letter shape at the end of a word too, but in the font
    /// rather than the code point, so there is nothing there to correct.
    func testTheHebrewFinalFormRuleDoesNotTouchArabic() {
        for prefix in ["مرحبا", "شكرا", "من"] {
            let results = SuggestionEngine.suggestions(
                prefix: prefix, context: "", languages: [.arabic])
            XCTAssertEqual(results.first?.text, prefix, "the keystrokes always stay first")
            for suggestion in results {
                XCTAssertTrue(
                    LanguageDetector.scripts(in: suggestion.text).isSubset(of: [.arabic]),
                    "\(prefix) was offered \(suggestion.text), which is not Arabic")
            }
        }
    }

    /// The next-word table is two hand-written dictionaries. For the other twelve
    /// languages the honest answer to "what comes next" is nothing, not "I", "The",
    /// "We" under a Greek keyboard.
    func testNextWordSuggestionsAreEmptyWhereThereIsNoTable() {
        XCTAssertTrue(
            SuggestionEngine.suggestions(prefix: "", context: "καλημέρα ", languages: [.greek])
                .isEmpty)
        XCTAssertTrue(
            SuggestionEngine.suggestions(prefix: "", context: "", languages: [.russian]).isEmpty)
        // …and the two that do have one still answer. The words changed when the
        // table became a bigram model — see
        // `SuggestionEngineTests.testNothingTypedAndNoContextOffersTheDefaults` —
        // but which languages get an answer at all did not, which is what this
        // test is about.
        XCTAssertEqual(
            SuggestionEngine.suggestions(prefix: "", context: "", languages: [.english])
                .map(\.text), ["Thanks", "I", "Hi"])
    }

    /// The contraction table is English. `dont` is an ordinary French word and
    /// `cant` an ordinary Catalan one, so the rule may not fire on a Latin
    /// alphabet in general.
    ///
    /// **The second language in each list is not padding.** This test used to pass
    /// `[.french]` alone — a one-element list the only call site can never produce,
    /// because English ships enabled and `LanguagesView` appends. Written that way
    /// it passed against the bug it is named after: with `[.english, .french]` the
    /// engine resolved Latin to English and `don't` became the space-committed
    /// default in a French sentence.
    func testEnglishContractionsDoNotFireInAnotherLatinLanguage() {
        let french = SuggestionEngine.suggestions(
            prefix: "dont", context: "le livre ", languages: [.french, .english, .hebrew])
        XCTAssertFalse(
            french.contains { $0.text == "don't" }, "French got: \(french.map(\.text))")
        XCTAssertEqual(
            french.first(where: \.isDefault)?.text, "dont",
            "space must commit the word the user typed, not an English contraction")

        let english = SuggestionEngine.suggestions(
            prefix: "dont", context: "I ", languages: [.english, .french, .hebrew])
        XCTAssertTrue(english.contains { $0.text == "don't" })
    }

    /// Characters name a script, not a language, so with two languages of one
    /// script enabled the *order* of the list is the only thing that can separate
    /// them — and the head of it is the layout on screen.
    ///
    /// The three pairs are the ones the catalogue cannot tell apart on characters
    /// alone: two Cyrillic, two written in the Arabic script, and eight Latin.
    func testTheLayoutOnScreenDecidesBetweenTwoLanguagesOfOneScript() {
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "привіт", among: [.ukrainian, .russian]),
            .ukrainian)
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "привет", among: [.russian, .ukrainian]), .russian)
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "سلام", among: [.persian, .arabic]), .persian)
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "مرحبا", among: [.arabic, .persian]), .arabic)
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "bonjour", among: [.french, .english, .hebrew]),
            .french)
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "Schlüssel", among: [.german, .english]), .german)
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "nasılsın", among: [.turkish, .english]), .turkish)
    }

    /// And the consequence: which dictionary the word is checked against.
    func testTheCheckerFollowsTheLayoutOnScreen() {
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "bonjour", among: [.french, .english])?
                .spellCheckerLocale, "fr_FR")
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "привіт", among: [.ukrainian, .russian])?
                .spellCheckerLocale, "uk_UA")
        // Persian beside Arabic keeps the degradation the catalogue promises: no
        // checker at all, rather than Arabic's.
        XCTAssertNil(
            SuggestionEngine.dominantLanguage(in: "سلام", among: [.persian, .arabic])?
                .spellCheckerLocale)
        XCTAssertEqual(
            SuggestionEngine.suggestions(prefix: "سلا", context: "", languages: [.persian, .arabic])
                .map(\.text), ["سلا"])
    }

    func testAScriptNobodyEnabledIsStillNamed() {
        XCTAssertEqual(SuggestionEngine.dominantLanguage(in: "مرحبا"), .arabic)
        XCTAssertEqual(SuggestionEngine.dominantLanguage(in: "καλημέρα"), .greek)
        XCTAssertEqual(SuggestionEngine.dominantLanguage(in: "नमस्ते"), .hindi)
        // The text is Greek whether or not Greek is on.
        XCTAssertEqual(
            SuggestionEngine.dominantLanguage(in: "καλημέρα", among: [.english]), .greek)
    }

    /// The code-switch list is English work vocabulary ranked ahead of the
    /// dictionary inside a Hebrew sentence, and it was measured against Hebrew
    /// alone. It must not start firing inside an Arabic or Greek one.
    func testTheCodeSwitchListStaysScopedToHebrew() {
        let arabic = SuggestionEngine.suggestions(
            prefix: "sta", context: "مرحبا كيف", languages: [.arabic, .english])
        XCTAssertFalse(arabic.contains { $0.text == "standup" })

        let hebrew = SuggestionEngine.suggestions(
            prefix: "sta", context: "בוא נעשה", languages: [.hebrew, .english])
        XCTAssertTrue(hebrew.contains { $0.text == "standup" })
    }
}

// MARK: - The wiring between the layout and the engine

/// The engine can only honour an order it is given, and for a while it was not
/// given one: `KeyboardController.refreshSuggestions` passed
/// `store.enabledLanguages` — the *stored* list — and never mentioned
/// `controller.language`, which is the layout on screen and the thing the globe
/// key had just changed.
///
/// Every test above works on the engine directly and so could not see it. These
/// two go through the controller, which is where the argument is built, and they
/// differ only in which layout is active: same store, same document, two answers.
/// Against the shipped wiring both come out English.
@MainActor
final class SuggestionLayoutRoutingTests: XCTestCase {

    private var savedLanguages: [KeyboardLanguage] = []
    private var savedPredictions = true

    override func setUp() {
        super.setUp()
        savedLanguages = SharedStore.shared.enabledLanguages
        savedPredictions = SharedStore.shared.predictions
        SharedStore.shared.predictions = true
        // The configuration the product ships and the user extends: English on by
        // default, `LanguagesView` appends, so a French user has English first in
        // the stored list unless they deliberately turn it off.
        SharedStore.shared.enabledLanguages = [.english, .hebrew, .french]
    }

    override func tearDown() {
        SharedStore.shared.enabledLanguages = savedLanguages
        SharedStore.shared.predictions = savedPredictions
        super.tearDown()
    }

    /// The failure in the user's own words: type `le livre dont je parle` on
    /// AZERTY and press space, and the keyboard writes `le livre don't je parle`.
    func testTheFrenchLayoutIsNotSpellCheckedAgainstEnglish() {
        let controller = KeyboardController(
            target: MockTextTarget(text: "le livre dont"), language: .french)
        controller.refreshSuggestions()

        XCTAssertFalse(
            controller.suggestions.contains { $0.text == "don't" },
            "the French layout was offered an English contraction: \(controller.suggestions.map(\.text))")
        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text, "dont",
            "space would have committed \(controller.suggestions.first(where: \.isDefault)?.text ?? "nothing")"
        )
    }

    /// The globe and the space-bar strip read UserDefaults, not the copy `load()`
    /// filled at launch. Writing only into the suite is the state the defect
    /// lives in: the app turned English off and the keyboard's published list
    /// still has it first.
    func testTheSpaceBarSeesLanguagesTurnedOffInTheOtherProcess() {
        SharedStore.shared.userDefaults.set(
            [KeyboardLanguage.hebrew.rawValue], forKey: SharedStore.Key.enabledLanguages)
        XCTAssertEqual(
            SharedStore.shared.enabledLanguages, [.english, .hebrew, .french],
            "the published copy must stay stale, or this proves nothing")
        XCTAssertEqual(SharedStore.shared.storedEnabledLanguages, [.hebrew])

        let controller = KeyboardController(
            target: MockTextTarget(), language: .hebrew)
        XCTAssertEqual(
            controller.enabledLanguages, [.hebrew],
            "the space bar still offered \(controller.enabledLanguages)")
    }

    /// The other half, and the reason the first is not vacuous: with English as
    /// the layout, from the same store and the same word, the contraction is
    /// exactly what should be offered.
    func testTheEnglishLayoutStillGetsEnglishAutocorrect() {
        let controller = KeyboardController(
            target: MockTextTarget(text: "I dont"), language: .english)
        controller.refreshSuggestions()

        XCTAssertTrue(
            controller.suggestions.contains { $0.text == "don't" },
            "English lost its own autocorrect: \(controller.suggestions.map(\.text))")
    }
}

/// The two languages a mixed sentence is actually in, which is what the dictation
/// panel's badge claims to show.
///
/// **The badge named the runner-up as `dominant.next()` — the next row of the
/// catalogue.** That was right for exactly as long as the catalogue was English
/// and Hebrew, and became wrong the day it grew to fourteen: Hebrew's neighbour is
/// Arabic. The sentence below was the scripted transcript the mic key used to
/// play — it is gone now that dictation records for real, but it is still exactly
/// the shape this product exists for, Hebrew carrying English loanwords, and it
/// was badged `עב ⟷ ع`.
@MainActor
final class MixedLanguageDetectionTests: XCTestCase {

    /// Through the same call the badge makes. The broken version answers
    /// `[hebrew, arabic]` here — catalogue index 1 then 2 — so the assertion has
    /// to be on the pair and not merely on it being non-empty.
    func testACodeSwitchedTranscriptIsBadgedHebrewAndEnglish() {
        let transcript = "אני אשלח לך את ה-document מחר בבוקר, אחרי ה-standup"
        let detected = SuggestionEngine.languages(in: transcript)

        XCTAssertEqual(
            detected.prefix(2).map(\.shortName), ["עב", "EN"],
            "the mixed-language badge reads \(detected.prefix(2).map(\.shortName))")
        XCTAssertFalse(
            detected.contains(.arabic),
            "a script with no Arabic character in it was reported as Arabic")
    }

    /// Not a Hebrew rule. The scan this replaced looked for Hebrew code points
    /// against everything else, so a Russian sentence carrying an English word was
    /// "not mixed" and got no second name at all.
    func testAMixOfTwoLanguagesTheOldScanCouldNotSeeIsStillAMix() {
        let detected = SuggestionEngine.languages(in: "давай сделаем sync по roadmap завтра")
        XCTAssertEqual(detected.prefix(2).map(\.shortName), ["РУ", "EN"])
    }

    /// One language is one name. The badge draws its arrow and its second label
    /// only when there is a second language, so an empty runner-up has to be
    /// genuinely empty rather than a repeat of the first.
    func testASingleLanguageHasNoRunnerUp() {
        XCTAssertEqual(SuggestionEngine.languages(in: "can you review the deck"), [.english])
        XCTAssertEqual(SuggestionEngine.languages(in: "היי מה קורה"), [.hebrew])
        XCTAssertEqual(SuggestionEngine.languages(in: "1234 !?"), [])
    }

    /// The ordering rule `dominantLanguage` has always had, now visible: on a tie
    /// the script that is not Latin leads, because a sentence with as much Hebrew
    /// in it as English is a Hebrew sentence carrying loanwords. Three letters each
    /// side, deliberately — `שלום hello` is four against five and is not a tie at
    /// all.
    func testATieGoesToTheScriptThatIsNotLatin() {
        XCTAssertEqual(SuggestionEngine.languages(in: "היי hey"), [.hebrew, .english])
        XCTAssertEqual(SuggestionEngine.dominantLanguage(in: "היי hey"), .hebrew)
        // And a genuine majority still wins, so the tie-break is not a Hebrew rule.
        XCTAssertEqual(SuggestionEngine.languages(in: "שלום hello"), [.english, .hebrew])
    }

    /// The enabled list still decides *which* language of a script, so a Ukrainian
    /// keyboard is not badged Russian. Scripts name scripts; only the candidate
    /// order can separate two languages that share one.
    func testTheCandidateListPicksBetweenTwoLanguagesOfOneScript() {
        XCTAssertEqual(
            SuggestionEngine.languages(in: "привіт sync", among: [.ukrainian, .english]),
            [.ukrainian, .english])
    }

    /// `dominantLanguage` is the same arithmetic and must not have changed answer.
    /// A script the catalogue has no keyboard for makes it nil rather than skipping
    /// to the runner-up: a Japanese sentence with an English word in it is not an
    /// English sentence.
    func testAnUnknownScriptStillMakesTheDominantLanguageNil() {
        XCTAssertNil(SuggestionEngine.dominantLanguage(in: "これはテストです ok"))
        XCTAssertEqual(SuggestionEngine.languages(in: "これはテストです ok"), [.english])
    }
}
