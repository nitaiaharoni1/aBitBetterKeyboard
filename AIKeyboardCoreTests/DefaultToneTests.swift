import XCTest

@testable import AIKeyboardCore

/// D6: a one-tap rewrite in the suggestion row, run against the user's default
/// tone, where that tone may be a line they wrote themselves.
@MainActor
final class DefaultToneTests: XCTestCase {

    private var store: SharedStore { .shared }

    // MARK: The action itself

    /// The bar runs Rewrite in the stored register, not Fix and not a hardcoded
    /// tone.
    ///
    /// Three assertions and each rejects a different plausible wrong build. A
    /// version wired to `run(.fix)` never calls `variants`, so `fixCount` catches
    /// it. A version wired to `run(.rewrite)` calls `variants` with `tone: nil`
    /// and lands on `.variants(nil)`, so both the recorded tone and the overlay
    /// catch it. A version that hardcodes a register answers `.clearer`, which is
    /// why the setting under test is deliberately not the shipped default.
    func testTheOneTapActionRewritesInTheStoredDefaultTone() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.prefersCustomTone = false
        store.defaultTone = .professional

        let engine = ToneRecorder()
        let controller = makeToneController(text: "i cant make the standup", engine: engine)

        controller.runDefaultTone()
        await settleToneController(controller)

        XCTAssertEqual(engine.tones, [.professional], "the bar ignored the stored default tone")
        XCTAssertEqual(engine.fixCount, 0, "the one-tap action ran Fix, which has no tone to run by")
        // **The answer arrives in the banner now, not in a panel over the keys.**
        // What is worth pinning is unchanged in substance: that the surface showing
        // the result names the action that produced it. `runningAction` is what the
        // banner labels itself from, and a version that left it nil renders the
        // idle hint over three fresh rewrites.
        XCTAssertEqual(controller.overlay, .none, "the one-tap rewrite covered the keys")
        XCTAssertEqual(controller.runningAction, .rewrite)
        XCTAssertEqual(controller.selectedTone, .professional)
        XCTAssertEqual(controller.variants.first?.text, "rewritten")
        XCTAssertEqual(controller.bannerOptions.first?.text, "rewritten")
    }

    /// The residue case.
    ///
    /// `aiSourceText` survives `dismissOverlay`, and `selectTone` deliberately
    /// keeps whatever is already in it — fine from the tone panel, which is only
    /// ever reached through `run(_:)`, and wrong from the bar, which is reached
    /// from nowhere. A build that forwards straight to `selectTone` rewrites the
    /// *previous* sentence and then `replaceTargetText` deletes that many
    /// characters out of the current one.
    func testTheOneTapActionWorksOnTheSentenceInTheFieldNotTheLastOneItSaw() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.prefersCustomTone = false
        store.defaultTone = .casual

        let engine = ToneRecorder()
        let controller = makeToneController(text: "see you at six", engine: engine)
        controller.aiSourceText = "an older sentence from an earlier action"

        controller.runDefaultTone()
        await settleToneController(controller)

        XCTAssertEqual(
            engine.sources, ["see you at six"],
            "the bar rewrote what an earlier action had left in aiSourceText")
        XCTAssertEqual(controller.aiSourceText, "see you at six")
    }

    /// Nothing to work with. The button is disabled for this, and the controller
    /// refuses it independently so the guard is not only a view's opinion.
    func testAnEmptyFieldRunsNothing() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }

        let engine = ToneRecorder()
        let controller = makeToneController(text: "", engine: engine)

        controller.runDefaultTone()
        await settleToneController(controller, timeout: 0.3)

        XCTAssertEqual(engine.variantCount, 0, "an empty field was sent to the model")
        XCTAssertEqual(controller.overlay, .none, "an empty field opened a result panel with nothing in it")
        XCTAssertFalse(controller.isWorking)
    }

    /// A call in flight. `beginWork` cancels its predecessor, so an unguarded
    /// second tap does not queue — it throws away the answer the user is waiting
    /// on and pays for a second call.
    func testASecondTapWhileACallIsInFlightIsRefused() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.prefersCustomTone = false
        store.defaultTone = .shorter

        let engine = ToneRecorder()
        engine.hold()
        let controller = makeToneController(text: "can you send me the deck", engine: engine)

        controller.runDefaultTone()
        XCTAssertTrue(controller.isWorking, "the first tap did not start a call")

        controller.runDefaultTone()
        engine.release()
        await settleToneController(controller)

        XCTAssertEqual(engine.variantCount, 1, "the second tap started a second call over the first")
        XCTAssertEqual(controller.variants.first?.text, "rewritten")
    }

    /// A call that failed. The reason has to reach the panel, and the panel has to
    /// be the one for the register that was run — a build that routes the bar
    /// through `run(.rewrite)` shows the failure under "Rewrite" with no chip
    /// selected, which is a different action from the one the user tapped.
    func testAFailedCallShowsTheReasonAgainstTheToneItRan() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.prefersCustomTone = false
        store.defaultTone = .confident

        let engine = ToneRecorder()
        engine.failure = .refused
        let controller = makeToneController(text: "יאללה נדבר אחכ", engine: engine)

        controller.runDefaultTone()
        await settleToneController(controller)

        XCTAssertEqual(controller.aiError, .refused, "the failure never reached the banner")
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertTrue(controller.variants.isEmpty)
        XCTAssertFalse(controller.isWorking)
        // The reason has to be *shown*, against the action that produced it.
        // `aiError` being set was always true of the broken version too — what it
        // could not do is name the action, because nothing recorded which one ran.
        XCTAssertEqual(controller.runningAction, .rewrite)
        XCTAssertEqual(controller.selectedTone, .confident)
    }

    // MARK: The user's own tone

    func testAWrittenCustomToneIsWhatTheDefaultResolvesTo() {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .friendly
        store.customTone = "short, blunt, no pleasantries"
        store.prefersCustomTone = true

        XCTAssertEqual(
            store.toneSetting, .custom(instruction: "short, blunt, no pleasantries", nearest: .friendly),
            "the default tone is still one of the six built-in registers")
        XCTAssertEqual(store.toneSetting.instruction, "short, blunt, no pleasantries")
        XCTAssertEqual(store.toneSetting.title, ToneSetting.customTitle)
        // What the answer is labelled with, and what an engine that cannot take
        // free text falls back to. The user's own last built-in choice rather than
        // a guess at what their sentence means.
        XCTAssertEqual(store.toneSetting.style, .friendly)
    }

    /// The user's own words reach the engine, rather than the built-in they fall
    /// back to. Fails against every build before the engine could carry an
    /// instruction, which is the point of it.
    func testACustomToneReachesTheEngineAsAnInstruction() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .friendly
        store.customTone = "short, blunt, no pleasantries"
        store.prefersCustomTone = true

        let engine = ToneRecorder()
        let controller = makeToneController(text: "could you possibly take a look", engine: engine)
        controller.runDefaultTone()
        await settleToneController(controller)

        XCTAssertEqual(engine.instructions, ["short, blunt, no pleasantries"])
        XCTAssertEqual(engine.tones, [.friendly], "the register the answer is labelled with was lost")
        XCTAssertTrue(controller.selectedToneIsCustom, "the panel does not know a custom tone ran")
    }

    /// **A custom tone must not still be lit after the user has left it.**
    ///
    /// `selectedToneIsCustom` is set by `runTone`, and it used to be cleared only by
    /// `dismissOverlay` — which `AIResultPanel`'s Back button did not call, because it
    /// went to the AI menu instead. So: run the user's own tone, tap Back, tap
    /// Rewrite, and a plain three-decision Rewrite was titled "My tone" with the
    /// custom chip lit under it. Both panels are deleted now and there is no Back to
    /// tap, but the flag is still set by one action and read by the next, so the
    /// invariant outlived the screens it was found on.
    func testLeavingACustomToneForRewriteStopsCallingItMyTone() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .friendly
        store.customTone = "short, blunt, no pleasantries"
        store.prefersCustomTone = true

        let engine = ToneRecorder()
        let controller = makeToneController(text: "could you possibly take a look", engine: engine)
        controller.runDefaultTone()
        await settleToneController(controller)
        XCTAssertTrue(controller.selectedToneIsCustom, "the custom tone never ran")

        // Straight to Rewrite, with nothing dismissed in between. The Back tap
        // this used to make had nowhere to go once `AIMenuPanel` was deleted, and it
        // was never what the test was about: `run(.rewrite)` is what has to clear
        // the flag, and it is the only step that ever did.
        controller.run(.rewrite)
        await settleToneController(controller)

        XCTAssertFalse(
            controller.selectedToneIsCustom,
            "Rewrite is titled \"\(ToneSetting.customTitle)\" and lights a chip nobody picked")
        XCTAssertNil(controller.selectedTone)
        // The answer lands in the banner and nothing covers the keys.
        XCTAssertEqual(controller.overlay, .none)
    }

    /// **`AIAction.tone` runs the stored register now, instead of opening a picker.**
    ///
    /// This test used to be `testOpeningTheTonePanelAfterACustomToneLeavesNoChipLit`,
    /// and its subject no longer exists: the action set `overlay =
    /// .aiResult(.variants(nil))`, a panel of six chips over the keys with nothing
    /// running until one was tapped, and it asserted that panel opened with no chip
    /// lit. The six registers live on the one-tap key's long press, so the action has
    /// nothing left to ask and runs what the user already chose.
    ///
    /// All three assertions are needed to reject the old build, and each rejects it
    /// differently: it left `overlay` set, it left `variants` empty because nothing
    /// had run, and it cleared the custom flag on the way into the picker.
    func testTheToneActionRunsTheStoredRegisterInsteadOfOpeningAPicker() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .professional
        store.customTone = "like a colleague, never like an assistant"
        store.prefersCustomTone = true

        let engine = ToneRecorder()
        let controller = makeToneController(text: "can you send me the deck", engine: engine)
        controller.run(.tone)
        await settleToneController(controller)

        XCTAssertEqual(
            controller.overlay, .none,
            "the picker is deleted, so nothing may cover the keys")
        XCTAssertFalse(
            controller.variants.isEmpty,
            "the action opened something instead of running the stored register")
        XCTAssertTrue(
            controller.selectedToneIsCustom,
            "it ran a register other than the one the user chose")
    }

    // Settings tests live in DefaultToneSettingsTests.swift.
}
