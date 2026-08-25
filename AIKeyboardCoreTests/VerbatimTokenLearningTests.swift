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

    // MARK: The floor — `PersonalLanguageModel.protectThreshold`, not `boostThreshold`

    /// **The floor rejector.** The broken direction is surfacing at two
    /// sightings, not at none — a store that gates a verbatim token on
    /// `boostThreshold` the way an ordinary word is offers a paste read once
    /// or twice.
    func testAnEmailSurfacesAfterThreeSightingsAndNotAfterTwo() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .english)
        let email = "nitai@gmail.com"

        typeAndSpace(email, on: controller, target: target)
        typeAndSpace(email, on: controller, target: target)

        target.text = "nita"
        controller.refreshSuggestions()
        XCTAssertFalse(
            controller.suggestions.contains { $0.text == email },
            "an address seen only twice already reached the bar: "
                + "\(controller.suggestions.map(\.text))")

        typeAndSpace(email, on: controller, target: target)

        target.text = "nita"
        controller.refreshSuggestions()
        XCTAssertTrue(
            controller.suggestions.contains { $0.text == email },
            "three sightings still did not surface the address: "
                + "\(controller.suggestions.map(\.text))")
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

    /// **The neighbour-door casing rejector.** `neighbourWords` also searches
    /// `personal.neighbours`, so a typo of a verbatim token can surface
    /// through this door too — one substitution off a stored, three-sighting
    /// `zzqnitai@gmail.com` — and its mapping used to re-case through plain
    /// `matchCase`: a shifted typo would answer `Zzqnitai@gmail.com`, a string
    /// this store never held, since every entry is folded to lower case on
    /// the way in. `matchCaseUnlessVerbatim` on that mapping is the fix; the
    /// candidate is offered in exactly the stored casing.
    func testANeighbourTypoOfAnEmailOffersExactlyTheStoredCasing() {
        let target = MockTextTarget(text: "")
        let controller = KeyboardController(target: target, language: .english)
        let email = "zzqnitai@gmail.com"

        for _ in 0..<3 {
            typeAndSpace(email, on: controller, target: target)
        }

        // One substitution off the stored address (`m` for `n`), under shift.
        target.text = "Zzqnitai@gmail.con"
        controller.refreshSuggestions()

        XCTAssertTrue(
            controller.suggestions.contains { $0.text == email },
            "the neighbour door never offered the stored address at all: "
                + "\(controller.suggestions.map(\.text))")
        XCTAssertFalse(
            controller.suggestions.contains { $0.text != email && $0.text.lowercased() == email },
            "the neighbour door re-cased the stored address: "
                + "\(controller.suggestions.map(\.text))")
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
}
