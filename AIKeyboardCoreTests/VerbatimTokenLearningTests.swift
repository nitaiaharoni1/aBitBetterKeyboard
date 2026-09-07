import XCTest

@testable import AIKeyboardCore

/// The keyboard could not learn its own owner's email address.
///
/// **Scouted root cause.** `PersonalLanguageModel.record()` required every
/// folded character to be a letter, an ASCII apostrophe or a hyphen — `@`,
/// `.` and every digit refused — so the one string this keyboard's owner
/// retypes constantly was never stored. A sibling defect sat at the same
/// gate: a word carrying Hebrew's geresh or gershayim, the Catalan interpunct
/// or a standalone Persian zero-width non-joiner — the exact marks
/// `KeyboardController.staysInsideWord` calls word-internal — was refused
/// too, on both sides of a bigram. The non-joiner attached to the letter
/// before it is a narrower case than the other three: Unicode's own grapheme
/// rules fold it into that letter's `Character`, which already read
/// `isLetter` under the old gate — see `testALeadingNonJoinerIsLearnedAsAnOrdinaryMark`
/// for where the two gates actually part ways.
///
/// **The fix is a shape, not a wider character class, for the verbatim
/// half.** `PersonalLanguageModel.isVerbatimToken` accepts the one shape an
/// email has and nothing else: pure digits, a price and a URL carrying a `/`
/// all fail it because none of them has a single `@` in the right place, and
/// a half-typed `nitai@gmail` fails it because its domain has no dot to end
/// a TLD on. A verbatim token is stored with no bigram half and is not handed
/// back by any reader — `words(startingWith:)`, `neighbours`, `allWords` —
/// until it reaches `protectThreshold` sightings, not `boostThreshold`, so a
/// pasted address seen once or twice stays out of the bar. And
/// `SuggestionEngine.commitReason` now refuses to let space auto-commit any
/// winner outside plain letters and the marks that stay inside a word, so an
/// address can fill a slot and be tapped but can never paste itself over an
/// unrelated fragment the way the old four-letter unknown-word gate did.
///
/// **Round 2: complete-on-pause is a second automatic door to the same
/// document, and it read straight off `suggestions` with no character-class
/// question at all.** `performIdleTyping` → `idleCompletion(for:)` picks "the
/// first suggestion that is not the typed word" and calls `replaceCurrentWord`
/// — or `apply`, which does the same insert — with no tap in between and no
/// `commitReason` ever asked. A learned email at three sightings, typed as far
/// as its own local part, ranks `.learned`, so it was exactly what that rule
/// picked: pasted on a pause, with `recordCommittedWord` on the very next line
/// then counting the insertion as a fourth sighting, the defect feeding its
/// own evidence. `SuggestionEngine.isAutomaticallyInsertable` is the one
/// spelling of "letters or a mark that stays inside a word" both doors read
/// now — `commitReason`'s own guard and `idleCompletion`'s filter — so they
/// cannot drift the way the second door already had once. A candidate that
/// fails it is skipped, not refused outright: `idleCompletion` falls through
/// to whatever legitimate completion sits behind it, or holds if there is
/// none. The neighbour door had the smaller half of the same leak — `matchCase`
/// instead of `matchCaseUnlessVerbatim` on a personal near-miss, so a typo'd
/// `Nitai@gmail.con` under shift offered `Nitai@gmail.com`, a string never
/// stored — fixed the same way.
@MainActor
final class VerbatimTokenLearningTests: XCTestCase {

    private var savedDictionary: [String] = []
    private var savedLanguages: [KeyboardLanguage] = []
    private var savedAutocorrect = AutocorrectLevel.full
    private var savedPredictions = true
    private var savedCompleteOnIdle = false
    private var savedSpaceOnIdle = false

    override func setUp() {
        super.setUp()
        savedDictionary = SharedStore.shared.personalDictionary
        savedLanguages = SharedStore.shared.enabledLanguages
        savedAutocorrect = SharedStore.shared.autocorrectLevel
        savedPredictions = SharedStore.shared.predictions
        savedCompleteOnIdle = SharedStore.shared.completeOnIdle
        savedSpaceOnIdle = SharedStore.shared.spaceOnIdle
        SharedStore.shared.personalDictionary = []
        SharedStore.shared.enabledLanguages = [.english, .hebrew]
        SharedStore.shared.autocorrectLevel = .full
        SharedStore.shared.predictions = true
        SharedStore.shared.completeOnIdle = false
        SharedStore.shared.spaceOnIdle = false
    }

    override func tearDown() {
        SharedStore.shared.personalDictionary = savedDictionary
        SharedStore.shared.enabledLanguages = savedLanguages
        SharedStore.shared.autocorrectLevel = savedAutocorrect
        SharedStore.shared.predictions = savedPredictions
        SharedStore.shared.completeOnIdle = savedCompleteOnIdle
        SharedStore.shared.spaceOnIdle = savedSpaceOnIdle
        super.tearDown()
    }

    /// Types a whole word into a fresh document and presses space, exactly as a
    /// user finishing that word would. Reuses the same controller (and so the
    /// same in-memory `PersonalLanguageModel`) across calls, which is the whole
    /// point: the floor this file is about is measured in sightings across
    /// several commits, not inside one.
    private func typeAndSpace(
        _ word: String, on controller: KeyboardController, target: MockTextTarget
    ) {
        target.text = word
        controller.refreshSuggestions()
        controller.press(.space)
    }

    func testAnEmailSurfacesAfterOneCommittedSightingAcrossLanguages() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .hebrew)
        let email = "alex@example.org"
        typeAndSpace(email, on: controller, target: target)
        controller.language = .english
        target.text = "ale"
        controller.refreshSuggestions()
        XCTAssertTrue(controller.suggestions.contains { $0.text == email })
        XCTAssertFalse(controller.suggestions.first(where: { $0.text == email })?.isDefault ?? true)
    }

    // MARK: The shape

    /// A half-typed address with no domain dot is never stored, however many
    /// times it is committed — there is no TLD for `isVerbatimToken` to end
    /// on, and it also fails the ordinary-word character class outright.
    func testAHalfTypedAddressWithNoTLDIsNeverStored() {
        let model = PersonalLanguageModel(url: nil)
        for _ in 0..<5 {
            model.record(word: "nitai@gmail", previous: nil, language: .english, permitted: true)
        }
        XCTAssertEqual(model.count(of: "nitai@gmail", in: .english), 0)
    }

    /// Pure digits, a price and a URL carrying a slash are still refused.
    /// None of the three has a lone `@` in it, so `isVerbatimToken` refuses
    /// them before the ordinary-word character class even gets a say.
    func testDigitsPricesAndSlashedURLsAreStillRefused() {
        let model = PersonalLanguageModel(url: nil)
        for word in ["123456", "99.99", "http://example.com/page", "root@server.com/etc"] {
            for _ in 0..<3 {
                model.record(word: word, previous: nil, language: .english, permitted: true)
            }
            XCTAssertEqual(
                model.count(of: word, in: .english), 0, "\(word) was learned despite its shape")
        }
    }

    /// The sibling defect: a word carrying Hebrew's geresh — typed exactly the
    /// way the accents popup produces it — is learned as an ordinary word
    /// (today's `boostThreshold`, not the verbatim floor) and offered back
    /// through the same reader completions use.
    func testGereshWordIsLearnedAsAnOrdinaryWordAndOffered() {
        let model = PersonalLanguageModel(url: nil)
        let chips = "צ\u{05F3}יפס"
        model.record(word: chips, previous: nil, language: .hebrew, permitted: true)
        model.record(word: chips, previous: nil, language: .hebrew, permitted: true)
        XCTAssertEqual(model.count(of: chips, in: .hebrew), 2)
        XCTAssertEqual(model.words(startingWith: "צ", in: .hebrew, limit: 3), [chips])
    }

    /// **U+200C on its own, which is the shape that actually distinguishes the
    /// two gates.** Attached to the letter before it, the non-joiner has
    /// Extend grapheme-cluster behaviour and Swift folds the pair into one
    /// `Character` that already reads `isLetter` — measured directly: the old
    /// character class accepted a whole Persian compound typed through the
    /// popup (`علی` + U+200C + `بابا`) without this extension at all, because
    /// every `Character` in it still satisfied `isLetter`. Standing alone —
    /// nothing before it to extend — it is its own `Character` and `isLetter`
    /// is false, which is the one shape the old gate genuinely refused and the
    /// new one, matching `KeyboardController.staysInsideWord`, accepts.
    func testALeadingNonJoinerIsLearnedAsAnOrdinaryMark() {
        let model = PersonalLanguageModel(url: nil)
        let word = "\u{200C}test"
        model.record(word: word, previous: nil, language: .english, permitted: true)
        model.record(word: word, previous: nil, language: .english, permitted: true)
        XCTAssertEqual(model.count(of: word, in: .english), 2)
    }

    /// **Mirrors the extension into the `previous` half of a bigram.** The old
    /// gate only ever checked the character class of the word being recorded;
    /// a geresh word sitting on either side of a pair failed it, because a
    /// word carrying one was refused as a unigram in the first place. Both
    /// halves of the pair need two sightings apiece (`boostThreshold`) before
    /// `followers` will name them.
    func testGereshWordsAreAllowedOnBothSidesOfABigram() {
        let model = PersonalLanguageModel(url: nil)
        let chips = "צ\u{05F3}יפס"
        for _ in 0..<2 {
            model.record(word: "אכלתי", previous: nil, language: .hebrew, permitted: true)
            model.record(word: chips, previous: "אכלתי", language: .hebrew, permitted: true)
            model.record(word: "טעים", previous: chips, language: .hebrew, permitted: true)
        }
        XCTAssertTrue(
            model.followers(after: "אכלתי", in: .hebrew, limit: 5).contains(chips),
            "a geresh word following an ordinary one never reached the bigram store")
        XCTAssertTrue(
            model.followers(after: chips, in: .hebrew, limit: 5).contains("טעים"),
            "a geresh word standing as the previous word never reached the bigram store")
    }

    /// **The bigram store gains nothing from an email commit, in either
    /// direction.** An address is stored on its own, with no pair — the
    /// current-word branch returns before the pair-writing code ever runs,
    /// and an email as the *previous* word already fails the ordinary
    /// character class the `before` half is checked against.
    func testTheBigramStoreGainsNothingFromAnEmailCommit() {
        let model = PersonalLanguageModel(url: nil)
        let email = "nitai@gmail.com"
        for _ in 0..<3 {
            model.record(word: email, previous: "reach", language: .english, permitted: true)
            model.record(word: "thanks", previous: email, language: .english, permitted: true)
        }
        XCTAssertTrue(
            model.followers(after: "reach", in: .english, limit: 5).isEmpty,
            "an email committed after an ordinary word still wrote a bigram half")
        XCTAssertTrue(
            model.followers(after: email, in: .english, limit: 5).isEmpty,
            "an email standing as the previous word still wrote a bigram half")
    }

    // MARK: Commit exclusion

    /// **The commit-exclusion rejector.** With the address the top-ranked
    /// candidate over an unknown four-letter fragment, the old `commitReason`
    /// fell through to `.unknownWord` and auto-committed it; the new guard on
    /// the single winner refuses before that rule is ever asked. A deliberate
    /// tap on the very same candidate still inserts it.
    func testAnAddressNeverAutoCommitsOverAnUnrelatedFragmentButATapStillInsertsIt() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .english)
        let email = "zzqnitai@gmail.com"

        for _ in 0..<3 {
            typeAndSpace(email, on: controller, target: target)
        }

        target.text = "zzqn"
        controller.refreshSuggestions()
        guard let winner = controller.suggestions.first(where: { $0.text == email }) else {
            XCTFail(
                "the address was never offered, so this proves nothing: "
                    + "\(controller.suggestions.map(\.text))")
            return
        }
        XCTAssertEqual(
            controller.suggestions.first(where: \.isDefault)?.text, "zzqn",
            "space was armed to replace an unrelated fragment with a stored address")

        controller.press(.space)
        XCTAssertEqual(
            target.text, "zzqn ", "space auto-committed the address over the typed fragment")

        target.text = "zzqn"
        controller.refreshSuggestions()
        controller.apply(winner)
        XCTAssertEqual(target.text, "\(email) ", "a deliberate tap did not insert the address")
    }

    // MARK: matchCase

    /// **The matchCase rejector.** `matchCase` capitalises a candidate's first
    /// letter whenever the typed prefix is capitalised, which is exactly what
    /// happens at the start of a sentence. Applied to a verbatim token that
    /// would answer a shifted `Zzqn` with `Zzqnitai@gmail.com` — a string that
    /// was never stored and that autocorrect folds to lower case on the way
    /// in. The new guard skips `matchCase` for a verbatim token so it is
    /// offered exactly as stored.
    func testShiftedTypingDoesNotRecaseALearnedEmail() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .english)
        let email = "zzqnitai@gmail.com"

        for _ in 0..<3 {
            typeAndSpace(email, on: controller, target: target)
        }

        // Auto-capitalised the way the first word of a sentence would arrive.
        target.text = "Zzqn"
        controller.refreshSuggestions()

        XCTAssertTrue(
            controller.suggestions.contains { $0.text == email },
            "the address was not offered at all: \(controller.suggestions.map(\.text))")
        XCTAssertFalse(
            controller.suggestions.contains { $0.text != email && $0.text.lowercased() == email },
            "a shifted prefix re-cased the stored address: "
                + "\(controller.suggestions.map(\.text))")
    }

    func testAStoredEmailIsCompletedByPrefixAndNeverByTypoNeighbour() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .english)
        let email = "alex@example.org"
        typeAndSpace(email, on: controller, target: target)
        target.text = "alex@example.orh"
        controller.refreshSuggestions()
        XCTAssertFalse(controller.suggestions.contains { $0.text == email })
        target.text = "ale"
        controller.refreshSuggestions()
        XCTAssertTrue(controller.suggestions.contains { $0.text == email })
    }

    // MARK: Complete on pause — the second automatic door

    /// **The idle-completion rejector, the round-2 gap.** `performIdleTyping`
    /// never asks `commitReason` at all: it goes straight from a pause to
    /// `replaceCurrentWord` (or `apply`, the same insert) with no tap between
    /// them, so `commitReason`'s guard was never in front of it. A learned
    /// email at three sightings, typed exactly as far as its own local part,
    /// ranks `.learned` — the second-highest tier a mid-word candidate
    /// reaches — so it was exactly what `idleCompletion`'s "first suggestion
    /// that is not the typed word" picked, with `recordCommittedWord` on the
    /// very next line then counting the paste as a fourth sighting: the
    /// defect feeding its own evidence. Both controls matter as much as the
    /// rejection: a tap on the identical candidate still inserts it, and
    /// complete-on-pause still finishes an ordinary word.
    func testIdleCompletionNeverInsertsAnAddressButATapAndOrdinaryCompletionStillWork() {
        SharedStore.shared.completeOnIdle = true
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .english)
        let email = "zzqidle@gmail.com"
        let localPart = "zzqidle"

        for _ in 0..<3 {
            typeAndSpace(email, on: controller, target: target)
        }

        target.text = localPart
        controller.refreshSuggestions()
        guard let winner = controller.suggestions.first(where: { $0.text == email }) else {
            XCTFail(
                "the address was never offered, so this proves nothing: "
                    + "\(controller.suggestions.map(\.text))")
            return
        }

        controller.performIdleTyping()
        XCTAssertNotEqual(
            target.text, email,
            "complete-on-pause inserted the address with no tap: \(target.text)")
        XCTAssertEqual(
            target.text, localPart,
            "complete-on-pause did not hold on the typed letters: \(target.text)")

        // Control: a deliberate tap on the very same candidate still inserts it.
        target.text = localPart
        controller.refreshSuggestions()
        controller.apply(winner)
        XCTAssertEqual(target.text, "\(email) ", "a deliberate tap did not insert the address")

        // Control: complete-on-pause still completes an ordinary word — the
        // same shape `IdleTypingTests.testCompleteOnIdleReplacesTheWordWithoutASpace`
        // pins, repeated here so this file's fix cannot be the thing that broke it.
        let ordinaryTarget = MockTextTarget(text: "hel")
        let ordinaryController = KeyboardController(target: ordinaryTarget, language: .english)
        ordinaryController.suggestions = [
            Suggestion(text: "hel", language: .english, isDefault: true),
            Suggestion(text: "hello", language: .english)
        ]
        ordinaryController.performIdleTyping()
        XCTAssertEqual(ordinaryTarget.text, "hello")
    }

    // MARK: Where learning must stay refused

    /// A field that says it is a password, the same fixture shape
    /// `IdleTypingTests.SecureTypingTarget` uses. `MockTextTarget` always
    /// answers a positive `false`/`.none`, which is why this needs its own
    /// fixture.
    @MainActor
    private final class SecureFieldTarget: TextTarget {
        var text: String

        init(text: String) { self.text = text }

        var documentContextBeforeInput: String? { text }
        var documentContextAfterInput: String? { "" }
        var selectedText: String? { nil }
        var isSecureTextEntry: Bool? { true }
        var textContentType: UITextContentType?? { .some(.password) }
        var keyboardType: UIKeyboardType? { .default }

        func insertText(_ newText: String) { text.append(newText) }
        func deleteBackward() { if !text.isEmpty { text.removeLast() } }
        func adjustTextPosition(byCharacterOffset offset: Int) {}
    }

    /// **Unchanged by this feature.** An email typed into a password field is
    /// exactly the case `PersonalLanguageModel`'s own permission guard exists
    /// for, and the verbatim branch sits behind the same `guard permitted`
    /// every ordinary word does.
    func testAnEmailTypedInASecureFieldIsNotLearned() {
        let target = SecureFieldTarget(text: "nitai@gmail.com")
        let controller = KeyboardController(target: target, language: .english)
        controller.refreshSuggestions()
        controller.press(.space)

        XCTAssertEqual(controller.personal.count(of: "nitai@gmail.com", in: .english), 0)
    }

    /// **Unchanged by this feature.** With no App Group container to write to,
    /// the model keeps its counts in memory for as long as the instance lives
    /// and never touches disk — the same behaviour every test in this file
    /// already leans on by constructing `PersonalLanguageModel(url: nil)`.
    func testANilStoreURLStillLearnsInMemoryButPersistsNothing() {
        let model = PersonalLanguageModel(url: nil)
        for _ in 0..<3 {
            model.record(word: "nitai@gmail.com", previous: nil, language: .english, permitted: true)
        }
        XCTAssertEqual(model.count(of: "nitai@gmail.com", in: .english), 3)
        XCTAssertEqual(
            model.words(startingWith: "nita", in: .english, limit: 3), ["nitai@gmail.com"])
        model.save()
    }
    func testPhoneNumberIsRecalledAfterOneTypedCommitAcrossLanguages() {
        let model = PersonalLanguageModel(url: nil)
        XCTAssertTrue(
            model.record(
                word: "0541236789", previous: "טלפון", language: .hebrew, permitted: true))
        XCTAssertEqual(model.phoneNumbers(startingWith: "054", limit: 3), ["0541236789"])
        XCTAssertEqual(model.count(of: "0541236789", in: .english), 1)
        XCTAssertTrue(model.words(startingWith: "054", in: .english, limit: 3).isEmpty)
        XCTAssertTrue(model.phoneNumbers(startingWith: "05", limit: 3).isEmpty)
        XCTAssertTrue(model.phoneNumbers(startingWith: "", limit: 3).isEmpty)
        XCTAssertTrue(model.phoneNumbers(startingWith: "0541236789", limit: 3).isEmpty)
        XCTAssertTrue(model.followers(after: "טלפון", in: .hebrew, limit: 3).isEmpty)
        XCTAssertTrue(model.neighbours(of: "0541236788", in: .hebrew, limit: 3).isEmpty)
        XCTAssertTrue(model.allWords(in: .hebrew).isEmpty)
    }

    func testFormattedInternationalPhoneKeepsItsFormatAndMatchesDigitPrefixes() {
        let model = PersonalLanguageModel(url: nil)
        let phone = "+972 54-123-6789"
        XCTAssertTrue(model.recordPhoneNumber(phone, language: .hebrew, permitted: true))
        XCTAssertEqual(model.phoneNumbers(startingWith: "+97254", limit: 3), [phone])
        XCTAssertEqual(model.phoneNumbers(startingWith: "+972 54 1", limit: 3), [phone])
        XCTAssertEqual(PersonalLanguageModel.phoneNumberSuffix(in: "call +972 54 1"), "+972 54 1")
        XCTAssertFalse(PersonalLanguageModel.isPhoneNumber("+972 54 1"))
        XCTAssertEqual(model.count(of: "+972541236789", in: .english), 1)
    }

    func testPhoneShapeRefusesCodesDatesPricesCardsAndMalformedNumbers() {
        let model = PersonalLanguageModel(url: nil)
        for text in [
            "123456", "12345678", "99.99", "2026-09-07", "07-09-2026",
            "4111 1111 1111 1111", "+4532015112830366", "0541236789-",
            "054(1236789", "054)1236789(", "054+1236789", "+0123456789", "1111111111"
        ] {
            XCTAssertFalse(PersonalLanguageModel.isPhoneNumber(text), text)
            XCTAssertFalse(model.recordPhoneNumber(text, language: .english, permitted: true), text)
        }
        XCTAssertEqual(model.learnedWordCount, 0)
        for text in ["0541236789", "031234567", "(212) 555-0198", "+44 20 7946 0958"] {
            XCTAssertTrue(PersonalLanguageModel.isPhoneNumber(text), text)
        }
    }

    func testPhoneIsPersistedImmediatelyAndCanBeForgottenFromAnotherLanguage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = PersonalLanguageModel(url: url)
        writer.recordPhoneNumber("054-1236789", language: .hebrew, permitted: true)
        let reader = PersonalLanguageModel(url: url)
        XCTAssertEqual(reader.phoneNumbers(startingWith: "054", limit: 3), ["054-1236789"])
        XCTAssertEqual(reader.learnedWords().map(\.word), ["054-1236789"])
        reader.forget("0541236789", in: .english)
        writer.reload()
        XCTAssertTrue(writer.phoneNumbers(startingWith: "054", limit: 3).isEmpty)
        XCTAssertEqual(writer.learnedWordCount, 0)
    }

    func testPhoneLearningRefusesAutomaticAndForbiddenWrites() {
        let model = PersonalLanguageModel(url: nil)
        XCTAssertFalse(model.recordPhoneNumber("0541236789", language: .hebrew, permitted: false))
        XCTAssertFalse(
            model.record(
                word: "0541236789", previous: nil, language: .hebrew, permitted: true,
                source: .automatic))
        XCTAssertTrue(model.learnedWords().isEmpty)
    }

    func testAutomaticSuggestionsCannotTrainTheirOwnRankingOrProtection() {
        let model = PersonalLanguageModel(url: nil)
        for _ in 0..<5 {
            model.record(
                word: "mistyped", previous: "hello", language: .english, permitted: true,
                source: .automatic)
        }
        XCTAssertEqual(model.count(of: "mistyped", in: .english), 0)
        XCTAssertFalse(model.isProtected("mistyped", in: .english))
        XCTAssertTrue(model.words(startingWith: "mis", in: .english, limit: 3).isEmpty)
        XCTAssertTrue(model.followers(after: "hello", in: .english, limit: 3).isEmpty)
        model.record(
            word: "chosen", previous: nil, language: .english, permitted: true,
            source: .selectedSuggestion)
        XCTAssertEqual(model.count(of: "chosen", in: .english), 1)
        XCTAssertTrue(model.isProtected("chosen", in: .english))
        XCTAssertEqual(model.words(startingWith: "chos", in: .english, limit: 3), ["chosen"])
        XCTAssertEqual(model.rankingCount(of: "chosen", in: .english), PersonalLanguageModel.boostThreshold)
    }

    func testRejectedCorrectionPersistsAcrossInstancesAndForgetClearsIt() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = PersonalLanguageModel(url: url)
        writer.recordRejectedCorrection(
            original: "its", replacement: "it's", language: .english, permitted: true)
        let reader = PersonalLanguageModel(url: url)
        XCTAssertTrue(
            reader.isRejectedCorrection(
                original: "Its", replacement: "It's", language: .english))
        XCTAssertFalse(
            reader.isRejectedCorrection(
                original: "ill", replacement: "I'll", language: .english))
        reader.forget("its", in: .english)
        XCTAssertFalse(
            reader.isRejectedCorrection(
                original: "its", replacement: "it's", language: .english))
        reader.recordRejectedCorrection(
            original: "ill", replacement: "I'll", language: .english, permitted: false)
        XCTAssertFalse(
            reader.isRejectedCorrection(
                original: "ill", replacement: "I'll", language: .english))
    }

    func testLegacyStoreLoadsWithoutDiscardingLearnedVocabulary() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let tag = KeyboardLanguage.english.languageTag
        let legacy = ["unigrams": [tag: ["nitai": 4]], "bigrams": [tag: ["hi\u{1F}nitai": 3]]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let model = PersonalLanguageModel(url: url)
        XCTAssertEqual(model.words(startingWith: "nit", in: .english, limit: 3), ["nitai"])
        XCTAssertEqual(model.followers(after: "hi", in: .english, limit: 3), ["nitai"])
        model.recordPhoneNumber("0541236789", language: .hebrew, permitted: true)
        let reloaded = PersonalLanguageModel(url: url)
        XCTAssertEqual(reloaded.count(of: "nitai", in: .english), 4)
        XCTAssertEqual(reloaded.phoneNumbers(startingWith: "054", limit: 3), ["0541236789"])
        reloaded.clear()
        XCTAssertTrue(reloaded.learnedWords().isEmpty)
    }

    func testInvalidObservationsCannotCreateSelectedProtectionOrAutomaticEntries() {
        let model = PersonalLanguageModel(url: nil)
        for source in [PersonalLanguageModel.LearningSource.selectedSuggestion, .automatic] {
            for word in ["--", "'", "bad/token", String(repeating: "a", count: 321) + "@example.com"] {
                XCTAssertFalse(
                    model.record(
                        word: word, previous: nil, language: .english, permitted: true, source: source))
                XCTAssertFalse(model.isProtected(word, in: .english))
                XCTAssertEqual(model.count(of: word, in: .english), 0)
            }
        }
    }

    func testNumericSuffixInsideSerialIsNotAPhoneToken() {
        XCTAssertNil(PersonalLanguageModel.phoneNumberSuffix(in: "abc0541236789"))
        XCTAssertNil(PersonalLanguageModel.phoneNumberSuffix(in: "abc-0541236789"))
        XCTAssertEqual(PersonalLanguageModel.phoneNumberSuffix(in: "call 0541236789"), "0541236789")
        XCTAssertTrue(PhoneNumberToken.continues(in: " 123 6789"))
        XCTAssertFalse(PhoneNumberToken.continues(in: " please call"))
    }

    func testEmailFirstCommitPreservesOriginalSpellingAndRecallsAcrossLanguages() {
        let model = PersonalLanguageModel(url: nil)
        let email = "Nitai+Work@Example.com"
        XCTAssertTrue(model.recordVerbatimToken(email, language: .hebrew, permitted: true))
        XCTAssertEqual(model.verbatimTokens(startingWith: "nitai+", kind: .email, limit: 3), [email])
        XCTAssertEqual(model.words(startingWith: "NIT", in: .english, limit: 3), [email])
        XCTAssertEqual(model.count(of: "nitai+work@example.com", in: .english), 1)
        XCTAssertTrue(model.isProtected(email, in: .english))
        XCTAssertTrue(model.verbatimTokens(startingWith: "ni", kind: .email, limit: 3).isEmpty)
        XCTAssertTrue(model.verbatimTokens(startingWith: email, kind: .email, limit: 3).isEmpty)
        XCTAssertTrue(model.neighbours(of: "Nitai+Work@Example.con", in: .hebrew, limit: 3).isEmpty)
        XCTAssertTrue(model.allWords(in: .hebrew).isEmpty)
    }

    func testEmailFirstCommitPersistsImmediatelyAndCanBeForgottenAcrossLanguages() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = PersonalLanguageModel(url: url)
        writer.record(word: "My.Address@Example.com", previous: "email", language: .hebrew, permitted: true)
        let reader = PersonalLanguageModel(url: url)
        XCTAssertEqual(
            reader.verbatimTokens(startingWith: "my.", kind: .email, limit: 3), ["My.Address@Example.com"])
        XCTAssertEqual(reader.learnedWords().map(\.word), ["My.Address@Example.com"])
        reader.forget("my.address@example.com", in: .english)
        writer.reload()
        XCTAssertTrue(writer.verbatimTokens(startingWith: "my.", kind: .email, limit: 3).isEmpty)
        XCTAssertEqual(writer.learnedWordCount, 0)
    }

    func testVerbatimTokenLearningRefusesAutomaticAndForbiddenCommitsForBothKinds() {
        let model = PersonalLanguageModel(url: nil)
        for token in ["nitai@example.com", "0541236789"] {
            XCTAssertFalse(model.recordVerbatimToken(token, language: .hebrew, permitted: false))
            XCTAssertFalse(
                model.recordVerbatimToken(token, language: .hebrew, permitted: true, source: .automatic))
            XCTAssertFalse(
                model.record(
                    word: token, previous: nil, language: .english, permitted: true, source: .automatic))
            XCTAssertEqual(model.count(of: token, in: .english), 0)
        }
        XCTAssertEqual(model.learnedWordCount, 0)
    }

    func testLegacyEmailAndPhoneStoresMigrateTogetherWithoutLosingWordsOrDuplicatingCounts() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let english = KeyboardLanguage.english.languageTag
        let hebrew = KeyboardLanguage.hebrew.languageTag
        let legacy: [String: Any] = [
            "unigrams": [english: ["nitai@example.com": 2, "hello": 4], hebrew: ["nitai@example.com": 3]],
            "bigrams": [english: ["say\u{1F}hello": 3]],
            "selected": [english: ["nitai@example.com": 1]],
            "automatic": [english: ["nitai@example.com": 2]],
            "phones": ["0541236789": ["text": "054-1236789", "count": 2, "languageTag": hebrew]]
        ]
        try JSONSerialization.data(withJSONObject: legacy).write(to: url)
        let model = PersonalLanguageModel(url: url)
        XCTAssertEqual(model.count(of: "nitai@example.com", in: .hebrew), 5)
        XCTAssertEqual(model.count(of: "hello", in: .english), 4)
        XCTAssertEqual(model.followers(after: "say", in: .english, limit: 3), ["hello"])
        XCTAssertEqual(model.phoneNumbers(startingWith: "054", limit: 3), ["054-1236789"])
        XCTAssertEqual(
            model.verbatimTokens(startingWith: "nit", kind: .email, limit: 3), ["nitai@example.com"])
        XCTAssertEqual(model.learnedWordCount, 3)
        XCTAssertEqual(
            model.observationCount(of: "nitai@example.com", in: .english, source: .selectedSuggestion), 0)
        XCTAssertEqual(model.observationCount(of: "nitai@example.com", in: .english, source: .automatic), 0)
        model.save()
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil(encoded["phones"])
        XCTAssertEqual(PersonalLanguageModel(url: url).count(of: "nitai@example.com", in: .english), 5)
    }

    func testVerbatimStoreIsBoundedAndKeepsTheLatestExplicitCommit() {
        let model = PersonalLanguageModel(url: nil)
        for index in 0...200 {
            model.recordVerbatimToken("person\(index)@example.com", language: .english, permitted: true)
        }
        XCTAssertEqual(model.learnedWordCount, 200)
        XCTAssertEqual(model.count(of: "person200@example.com", in: .english), 1)
        model.clear()
        XCTAssertTrue(model.verbatimTokens(startingWith: "person", kind: .email, limit: 3).isEmpty)
    }

    func testReloadBeforeFirstFileSavePreservesUnsavedVocabulary() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let model = PersonalLanguageModel(url: url)
        model.record(word: "colleague", previous: nil, language: .english, permitted: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        model.reload()
        XCTAssertEqual(model.count(of: "colleague", in: .english), 1)
        model.record(word: "colleague", previous: nil, language: .english, permitted: true)
        model.reload()
        XCTAssertEqual(model.words(startingWith: "coll", in: .english, limit: 3), ["colleague"])
        model.save()
        XCTAssertEqual(PersonalLanguageModel(url: url).count(of: "colleague", in: .english), 2)
    }

    func testReloadHonorsClearEvenBeforeAnyFileWasSaved() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let keyboard = PersonalLanguageModel(url: url)
        keyboard.record(word: "colleague", previous: nil, language: .english, permitted: true)
        let app = PersonalLanguageModel(url: url)
        app.clear()
        keyboard.reload()
        XCTAssertEqual(keyboard.count(of: "colleague", in: .english), 0)
    }

    func testReloadDropsPreviouslyLoadedStoreWhenFileIsDeleted() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = PersonalLanguageModel(url: url)
        writer.recordVerbatimToken("nitai@example.com", language: .english, permitted: true)
        let reader = PersonalLanguageModel(url: url)
        reader.record(word: "colleague", previous: nil, language: .english, permitted: true)
        try FileManager.default.removeItem(at: url)
        reader.reload()
        XCTAssertEqual(reader.learnedWordCount, 0)
    }

}
