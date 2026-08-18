import XCTest

@testable import AIKeyboardCore

/// The three-position Autocorrect setting, and the confidence floor it is.
///
/// **Every case here needs a control that stays committed, or it passes against
/// a build that simply turned autocorrect off.** That is the failure this repo
/// has recorded three times: an assertion named after a bug that is also true of
/// the broken keyboard. `.confident` is only worth having if it keeps the
/// corrections it claims to keep, so each half of the split is asserted against
/// the same level in the same test.
@MainActor
final class AutocorrectLevelTests: XCTestCase {

    private var saved = AutocorrectLevel.full

    override func setUp() {
        super.setUp()
        saved = SharedStore.shared.autocorrectLevel
    }

    override func tearDown() {
        SharedStore.shared.autocorrectLevel = saved
        SharedStore.shared.userDefaults.removeObject(forKey: SharedStore.Key.autocorrect)
        super.tearDown()
    }

    /// Empty and in memory, so a run cannot inherit whatever the machine it runs
    /// on has been typing.
    private func personal() -> PersonalLanguageModel {
        PersonalLanguageModel(url: nil)
    }

    private func boldSlot(
        _ prefix: String, context: String = "", languages: [KeyboardLanguage] = [.english],
        level: AutocorrectLevel
    ) -> String? {
        SuggestionEngine.suggestions(
            prefix: prefix, context: context, languages: languages,
            personal: personal(), autocorrect: level
        )
        .first(where: \.isDefault)?.text
    }

    // MARK: The floor

    /// **The split, with both halves in one test.**
    ///
    /// `sched` reaches the four-letter fallback at the bottom of `commitReason`:
    /// no dictionary has heard of it, so whatever ranked first wins. That is the
    /// weakest claim the engine makes and `.confident` is meant to drop it.
    /// `dont` reaches the contraction table, which is a closed hand-authored list
    /// and the strongest claim there is, so it must survive.
    ///
    /// A build that reads `.confident` as "off" fails the second half. A build
    /// that ignores the level fails the first.
    func testConfidentDropsTheFallbackAndKeepsTheContraction() {
        XCTAssertEqual(
            boldSlot("sched", level: .full)?.lowercased(), "schedule",
            "the fallback has to commit at .full, or the first half proves nothing")

        XCTAssertEqual(
            boldSlot("sched", level: .confident), "sched",
            "space still finishes an unknown stem three insertions away at .confident")
        XCTAssertEqual(
            boldSlot("dont", level: .confident), "don't",
            "the contraction table was dropped with the guesses")
    }

    /// The candidate is still generated and still offered. Only the bold slot
    /// moves, which is the difference between a keyboard that declines to help
    /// and a keyboard that has stopped looking.
    func testARefusedCorrectionIsStillOfferedInTheBar() {
        let results = SuggestionEngine.suggestions(
            prefix: "sched", context: "", languages: [.english],
            personal: personal(), autocorrect: .confident)
        XCTAssertTrue(
            results.contains { $0.text.lowercased() == "schedule" },
            "the word left the bar as well as the bold slot: \(results.map(\.text))")
    }

    /// `.off` refuses what `.confident` keeps. Asserted against the contraction
    /// rather than the fallback, because the fallback is already refused one
    /// position up and would pass on a build that never read `.off` at all.
    func testOffRefusesEvenTheStrongestRule() {
        XCTAssertEqual(boldSlot("dont", level: .off), "dont")
    }

    // MARK: The prices

    /// The line the middle position cuts the frequency corrector on, measured
    /// over `Bar/typing/typos/`: at 60 or under it is right 30 times out of 31,
    /// above 60 it is 6 out of 12.
    ///
    /// **The transposition exemption is asserted at a cost that is otherwise
    /// refused**, because that is the only thing it does. `שלמו` → `שלום` costs
    /// 80 (a transposition at 60 plus a final form at 20) and is `typo-11`, one
    /// of the two entries NIT-153 shipped the corrector to close.
    func testTheFrequencyCorrectorIsPricedByWhatTheChannelCanExplain() {
        let floor = AutocorrectLevel.confident.confidenceFloor
        XCTAssertGreaterThanOrEqual(
            CommitReason.frequency(cost: 55, transposition: false).confidence, floor)
        XCTAssertGreaterThanOrEqual(
            CommitReason.frequency(cost: 60, transposition: false).confidence, floor)
        XCTAssertLessThan(
            CommitReason.frequency(cost: 70, transposition: false).confidence, floor,
            "a substitution above one explainable slip is a coin flip and must not commit")
        XCTAssertLessThan(
            CommitReason.frequency(cost: 100, transposition: false).confidence, floor)
        XCTAssertGreaterThanOrEqual(
            CommitReason.frequency(cost: 80, transposition: true).confidence, floor,
            "the transposition exemption is gone and typo-11 goes with it")
    }

    /// The fallback's own split: the same gate, told apart by whether
    /// `TypoChannel` can price the distance it is crossing.
    func testTheFallbackIsPricedByWhetherTheChannelCanExplainTheDistance() {
        XCTAssertLessThan(
            CommitReason.unknownWord(explainable: false).confidence,
            AutocorrectLevel.confident.confidenceFloor,
            "an unpriceable jump is the fallback guessing, and must not commit")
        XCTAssertGreaterThanOrEqual(
            CommitReason.unknownWord(explainable: true).confidence,
            AutocorrectLevel.confident.confidenceFloor,
            "a priceable slip is the same claim singleEdit makes")
    }

    /// Nothing reaches `.off`'s floor, which is what makes three positions one
    /// comparison instead of a special case wrapped around two.
    func testNoRuleCanReachTheOffFloor() {
        let every: [CommitReason] = [
            .contraction, .hebrewFinalForm, .transposition, .wrongLayout, .singleEdit,
            .sentenceFollower, .unknownWord(explainable: true), .unknownWord(explainable: false),
            .frequency(cost: 20, transposition: false),
            .frequency(cost: 200, transposition: false),
            .frequency(cost: 200, transposition: true)
        ]
        for reason in every {
            XCTAssertLessThan(reason.confidence, AutocorrectLevel.off.confidenceFloor, "\(reason)")
            XCTAssertGreaterThanOrEqual(reason.confidence, AutocorrectLevel.full.confidenceFloor)
        }
    }

    // MARK: The upgrade

    /// **An install that had the old boolean lands where a fresh install lands.**
    ///
    /// On, per `storedAutocorrectLevel`'s own reasoning, is one answer to a
    /// question that now has three, so it is not information about which of the
    /// three the user wants: they get `shippedDefault`, the same as somebody
    /// installing today. Off is not ambiguous and stays off.
    ///
    /// **This assertion could once tell a decision from an accident and no longer
    /// can, which is worth knowing before trusting it.** `UserDefaults` reads a
    /// stored `Bool` back as the integer 1, so a build that reused
    /// `Key.autocorrect` as a raw value would coerce true to `.confident` and
    /// false to `.off`. While `shippedDefault` was `.full` those two paths gave
    /// different answers and asserting `.full` caught the coercion. `shippedDefault`
    /// is `.confident` now (`AutocorrectConfidence.swift`), whose raw value *is*
    /// 1 — so the correct path and the coercion bug now agree on both inputs and
    /// nothing asserted here can separate them. That is why this asserts
    /// `shippedDefault` rather than the literal `.confident`: it tracks the
    /// product decision instead of a number that currently coincides with a bug.
    ///
    /// `testTheNewKeyWinsOverTheOldOne` below is what still has teeth against the
    /// key being reused, because it proves the new key is read at all.
    func testAnOldBooleanUpgradesToWhatItMeant() {
        let defaults = SharedStore.shared.userDefaults
        defaults.removeObject(forKey: SharedStore.Key.autocorrectLevel)

        defaults.set(true, forKey: SharedStore.Key.autocorrect)
        XCTAssertEqual(SharedStore.shared.storedAutocorrectLevel, .shippedDefault)

        defaults.set(false, forKey: SharedStore.Key.autocorrect)
        XCTAssertEqual(SharedStore.shared.storedAutocorrectLevel, .off)
    }

    /// And a choice made since the upgrade wins over the value left behind.
    func testTheNewKeyWinsOverTheOldOne() {
        let defaults = SharedStore.shared.userDefaults
        defer { defaults.removeObject(forKey: SharedStore.Key.autocorrectLevel) }

        // **`.full`, not `.confident`, and that is the whole of what makes this
        // test say anything.** It stored `.confident` until 2026-08-18, whose raw
        // value is 1 — the same 1 a stored `Bool` coerces to — so a build that had
        // dropped the new key entirely and read `Key.autocorrect` as a raw value
        // would have passed it, on both inputs, while being exactly the defect the
        // test is named after. `.full` is raw value 2, which no boolean can
        // produce, so this now fails on that build and only on that build.
        defaults.set(true, forKey: SharedStore.Key.autocorrect)
        defaults.set(AutocorrectLevel.full.rawValue, forKey: SharedStore.Key.autocorrectLevel)
        XCTAssertEqual(SharedStore.shared.storedAutocorrectLevel, .full)
    }
}
