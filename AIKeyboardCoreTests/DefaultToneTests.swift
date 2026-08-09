import XCTest

@testable import AIKeyboardCore

/// An engine that records what it was asked for, so a test can tell a rewrite
/// from a fix and one register from another.
///
/// `RoutingTests` has a stub of its own and it is `private` to that file. This one
/// records rather than counts, and it can be held open, which is what the
/// call-in-flight case needs.
private final class ToneRecorder: TextIntelligence, @unchecked Sendable {

    private let lock = NSLock()
    private var recordedSources: [String] = []
    private var recordedTones: [ToneStyle?] = []
    private var recordedInstructions: [String?] = []
    private var fixes = 0
    private var released = true

    var failure: AIEngineError?
    var answer = "rewritten"

    var sources: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSources
    }
    var tones: [ToneStyle?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTones
    }
    var instructions: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedInstructions
    }
    var fixCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fixes
    }
    var variantCount: Int { tones.count }

    /// Hold the next call open until `release()`, so a second tap lands while the
    /// first is genuinely still in flight.
    func hold() {
        lock.lock()
        released = false
        lock.unlock()
    }
    func release() {
        lock.lock()
        released = true
        lock.unlock()
    }
    private var isReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return released
    }

    func canHandle(_ text: String, action: AIAction) -> Bool { true }

    func fix(_ text: String) async throws -> String {
        lock.lock()
        fixes += 1
        lock.unlock()
        if let failure { throw failure }
        return text
    }

    func variants(
        for text: String, tone: ToneStyle?, instruction: String?
    ) async throws
        -> [RewriteVariant]
    {
        lock.lock()
        recordedSources.append(text)
        recordedTones.append(tone)
        recordedInstructions.append(instruction)
        lock.unlock()

        // Bounded, so a mistake in a test times out rather than wedging the suite.
        let deadline = Date().addingTimeInterval(5)
        while !isReleased, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        if let failure { throw failure }
        return [RewriteVariant(tone: tone ?? .clearer, text: answer)]
    }

    func replies(to context: ScreenContext) async throws -> [ReplyOption] { [] }
}

/// `SharedStore.init` is private and the singleton is the App Group plist, so
/// there is no scratch instance to build. Every test that writes a setting puts it
/// back.
private struct ToneSettings {
    let tone: ToneStyle
    let prefersCustom: Bool
    let custom: String

    static func snapshot() -> ToneSettings {
        let store = SharedStore.shared
        return ToneSettings(
            tone: store.defaultTone,
            prefersCustom: store.prefersCustomTone,
            custom: store.customTone
        )
    }

    func restore() {
        let store = SharedStore.shared
        store.defaultTone = tone
        store.prefersCustomTone = prefersCustom
        store.customTone = custom
    }
}

/// D6: a one-tap rewrite in the suggestion row, run against the user's default
/// tone, where that tone may be a line they wrote themselves.
@MainActor
final class DefaultToneTests: XCTestCase {

    private var store: SharedStore { .shared }

    private func makeController(
        text: String,
        engine: ToneRecorder
    ) -> KeyboardController {
        KeyboardController(
            target: MockTextTarget(text: text),
            engine: RoutedIntelligence(onDevice: engine, cloud: nil)
        )
    }

    private func settle(_ controller: KeyboardController, timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while controller.isWorking, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

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
        let controller = makeController(text: "i cant make the standup", engine: engine)

        controller.runDefaultTone()
        await settle(controller)

        XCTAssertEqual(engine.tones, [.professional], "the bar ignored the stored default tone")
        XCTAssertEqual(engine.fixCount, 0, "the one-tap action ran Fix, which has no tone to run by")
        XCTAssertEqual(
            controller.overlay, .aiResult(.variants(.professional)),
            "the result panel does not name the register it just ran")
        XCTAssertEqual(controller.variants.first?.text, "rewritten")
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
        let controller = makeController(text: "see you at six", engine: engine)
        controller.aiSourceText = "an older sentence from an earlier action"

        controller.runDefaultTone()
        await settle(controller)

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
        let controller = makeController(text: "", engine: engine)

        controller.runDefaultTone()
        await settle(controller, timeout: 0.3)

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
        let controller = makeController(text: "can you send me the deck", engine: engine)

        controller.runDefaultTone()
        XCTAssertTrue(controller.isWorking, "the first tap did not start a call")

        controller.runDefaultTone()
        engine.release()
        await settle(controller)

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
        let controller = makeController(text: "יאללה נדבר אחכ", engine: engine)

        controller.runDefaultTone()
        await settle(controller)

        XCTAssertEqual(controller.aiError, .refused, "the failure never reached the panel")
        XCTAssertEqual(controller.overlay, .aiResult(.variants(.confident)))
        XCTAssertTrue(controller.variants.isEmpty)
        XCTAssertFalse(controller.isWorking)
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
        let controller = makeController(text: "could you possibly take a look", engine: engine)
        controller.runDefaultTone()
        await settle(controller)

        XCTAssertEqual(engine.instructions, ["short, blunt, no pleasantries"])
        XCTAssertEqual(engine.tones, [.friendly], "the register the answer is labelled with was lost")
        XCTAssertTrue(controller.selectedToneIsCustom, "the panel does not know a custom tone ran")
    }

    /// **A custom tone must not still be lit after the user has left it.**
    ///
    /// `selectedToneIsCustom` is set by `runTone` and cleared by `dismissOverlay`,
    /// and `AIResultPanel`'s Back button does not dismiss — it goes to the AI menu.
    /// So run the user's own tone, tap Back, tap Rewrite, and a plain
    /// three-decision Rewrite was titled "My tone" with the custom chip lit under
    /// it. `AIResultPanel.title` reads the flag *before* the overlay's tone, so
    /// `selectedTone = nil` alone does not cover it — which is exactly what the
    /// broken version did.
    func testLeavingACustomToneForRewriteStopsCallingItMyTone() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .friendly
        store.customTone = "short, blunt, no pleasantries"
        store.prefersCustomTone = true

        let engine = ToneRecorder()
        let controller = makeController(text: "could you possibly take a look", engine: engine)
        controller.runDefaultTone()
        await settle(controller)
        XCTAssertTrue(controller.selectedToneIsCustom, "the custom tone never ran")

        // Back, then Rewrite — the two taps, in order, with nothing dismissed.
        controller.show(.aiMenu)
        controller.run(.rewrite)
        await settle(controller)

        XCTAssertFalse(
            controller.selectedToneIsCustom,
            "Rewrite is titled \"\(ToneSetting.customTitle)\" and lights a chip nobody picked")
        XCTAssertNil(controller.selectedTone)
        XCTAssertEqual(controller.overlay, .aiResult(.variants(nil)))
    }

    /// The same for the tone panel, which is the other way back into a register
    /// after a custom one has run: it opens on "Pick a tone" and must not open with
    /// one already chosen.
    func testOpeningTheTonePanelAfterACustomToneLeavesNoChipLit() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .professional
        store.customTone = "like a colleague, never like an assistant"
        store.prefersCustomTone = true

        let engine = ToneRecorder()
        let controller = makeController(text: "can you send me the deck", engine: engine)
        controller.runDefaultTone()
        await settle(controller)

        controller.show(.aiMenu)
        controller.run(.tone)

        XCTAssertFalse(controller.selectedToneIsCustom)
        XCTAssertNil(controller.selectedTone)
        XCTAssertTrue(controller.variants.isEmpty)
    }

    // MARK: What Settings says about it

    /// **The note pointed at a button that does not exist.**
    ///
    /// It read "the ✦ button above the keys". Nothing in this keyboard draws ✦:
    /// the suggestion bar carries two brand-tinted buttons side by side, one
    /// wearing the tone's own SF Symbol and one wearing `sparkles`, and the
    /// playground calls the second one ✨. A user following Settings tapped the
    /// sparkle, which opens the AI menu and does not run their tone.
    ///
    /// Both branches are checked, because both carried the glyph.
    func testTheSettingsNoteNamesAButtonThatExists() {
        let notes = [
            ToneSetting.builtIn(.clearer).settingsNote,
            ToneSetting.custom(instruction: "short and blunt", nearest: .friendly).settingsNote
        ]
        for note in notes {
            XCTAssertFalse(note.contains("✦"), "Settings points at a glyph nothing draws: \(note)")
            XCTAssertTrue(
                note.contains("one-tap rewrite button above the keys"),
                "Settings does not name the button that runs the tone: \(note)")
        }
        // And it still says which register actually runs, which is the other half
        // of what this sentence is for.
        XCTAssertTrue(ToneSetting.builtIn(.casual).settingsNote.contains(ToneStyle.casual.title))
        XCTAssertTrue(
            ToneSetting.custom(instruction: "x", nearest: .shorter).settingsNote
                .contains(ToneStyle.shorter.title))
    }

    /// And a built-in one sends no instruction at all, so the six chips cannot
    /// quietly acquire a seventh register.
    func testABuiltInToneSendsNoInstruction() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .casual
        store.customTone = "short, blunt, no pleasantries"
        store.prefersCustomTone = false

        let engine = ToneRecorder()
        let controller = makeController(text: "could you possibly take a look", engine: engine)
        controller.runDefaultTone()
        await settle(controller)

        XCTAssertEqual(engine.instructions, [String?.none])
        XCTAssertFalse(controller.selectedToneIsCustom)
    }

    /// The register composes into the prompt in place of the built-in direction,
    /// rather than beside it. Two registers arguing is one register the model
    /// picks at random.
    func testTheInstructionReplacesTheBuiltInDirectionInThePrompt() {
        let asked = "short, blunt, no pleasantries"
        let prompt = Prompts.tone(.friendly, for: "could you possibly take a look", instruction: asked)
        XCTAssertTrue(prompt.contains(asked))
        XCTAssertFalse(
            prompt.contains("Warmer and more personal"),
            "the built-in direction is still in the prompt alongside the user's")
        // The rules the register must not overrule are still ahead of it.
        XCTAssertTrue(prompt.contains("Same language as the message. Never translate."))
        // An empty register is not a register.
        XCTAssertEqual(
            Prompts.tone(.friendly, for: "take a look", instruction: "   "),
            Prompts.tone(.friendly, for: "take a look"))
    }

    /// **A register in one language must never be quoted inside an instruction set
    /// written in another.** `AIPrompts`' own header is the measurement: a prompt
    /// carrying Hebrew in an otherwise English set made the model answer every
    /// English input in Hebrew, and Apple's model refuses such a session outright.
    /// The register is free text and a Hebrew-first keyboard is exactly where a
    /// Hebrew one gets typed, so the composer drops it and the built-in runs.
    ///
    /// Asserted on the composed prompt rather than on an engine, because both
    /// engines and every future one compose through this single function — the
    /// version of this fix that guarded inside `FoundationModelsEngine` left the
    /// cloud path merging the two languages with nothing to stop it.
    func testARegisterInAScriptTheInstructionSetDoesNotSpeakIsDropped() {
        let hebrewRegister = "קצר וישיר, בלי נימוסים"
        let english = Prompts.tone(.friendly, for: "can you send me the deck", instruction: hebrewRegister)
        XCTAssertFalse(
            english.contains(hebrewRegister),
            "a Hebrew register was quoted inside the English instruction set")
        XCTAssertTrue(
            english.contains("Warmer and more personal"),
            "the built-in register has to run when the user's own one cannot")

        // Cyrillic, Greek and Arabic registers go the same way, and so does a
        // Latin register under a Hebrew message's set — no, that one is spoken:
        // the Hebrew rules are about English loanwords keeping their letters.
        XCTAssertFalse(
            Prompts.tone(.shorter, for: "send me the deck", instruction: "коротко и по делу")
                .contains("коротко"))
        let hebrewMessage = Prompts.tone(
            .friendly, for: "אפשר לשלוח לי את המצגת?", instruction: "short and blunt")
        XCTAssertTrue(
            hebrewMessage.contains("short and blunt"),
            "the Hebrew set speaks Latin and should have kept a Latin register")
        XCTAssertTrue(
            Prompts.tone(.friendly, for: "אפשר לשלוח לי את המצגת?", instruction: hebrewRegister)
                .contains(hebrewRegister))
    }

    /// Preferring a custom tone you have not written is not a tone. A build that
    /// answers `.custom(instruction: "")` sends the model a register with nothing
    /// in it.
    func testAnUnwrittenCustomToneFallsBackToTheBuiltIn() async {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .clearer
        store.customTone = "   \n  "
        store.prefersCustomTone = true

        XCTAssertNil(store.toneSetting.instruction, "an empty instruction was offered as a tone")
        XCTAssertEqual(store.toneSetting, .builtIn(.clearer))

        let engine = ToneRecorder()
        let controller = makeController(text: "sounds good to me", engine: engine)
        controller.runDefaultTone()
        await settle(controller)

        XCTAssertEqual(engine.tones, [.clearer])
    }

    /// The instruction ends up in a model's *instructions*, where a newline is
    /// where a second instruction would start, and where an essay stops being a
    /// register.
    func testTheInstructionIsOneLineAndBounded() {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .casual
        store.prefersCustomTone = true

        store.customTone = "be blunt\nand always answer in English"
        let instruction = store.toneSetting.instruction
        XCTAssertEqual(instruction, "be blunt and always answer in English")
        XCTAssertFalse(
            instruction?.contains("\n") ?? true,
            "a newline in the instruction is where a second instruction starts")

        store.customTone = String(repeating: "long ", count: 200)
        XCTAssertEqual(
            store.customTone.count, SharedStore.customToneLimit,
            "the instruction is not bounded where it is written")
    }

    /// Two settings rather than one, so a user who tries the custom tone and goes
    /// back to Professional does not lose the sentence they wrote.
    func testSwitchingBackToABuiltInKeepsWhatTheUserWrote() {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.defaultTone = .professional
        store.customTone = "like a colleague, never like an assistant"
        store.prefersCustomTone = true
        XCTAssertNotNil(store.toneSetting.instruction)

        store.prefersCustomTone = false
        XCTAssertEqual(store.toneSetting, .builtIn(.professional))
        XCTAssertEqual(
            store.customTone, "like a colleague, never like an assistant",
            "switching back to a built-in register threw the user's own tone away")

        store.prefersCustomTone = true
        XCTAssertEqual(store.toneSetting.instruction, "like a colleague, never like an assistant")
    }

    /// The two keys, and the object they are written through.
    ///
    /// **This does not prove what its first version claimed, and the difference
    /// is worth writing down.** It used to say it rejected an implementation that
    /// reached for `UserDefaults.standard`. It cannot: `AIKeyboardCoreTests` runs
    /// unhosted, so `SharedContainer.url` is nil, `SharedStore` falls back to
    /// `.processLocal`, and `store.userDefaults` **is** `.standard` — an
    /// implementation writing to `.standard` directly passes both assertions byte
    /// for byte. What it does cover is the key names, which `resetToDefaults()`
    /// and `CaptureChannelTests.testNoRetiredKeyIsStillInUse` both hold lists of.
    /// The cross-process claim is only checkable where the container is real, so
    /// it is asserted there and skipped, loudly, everywhere else.
    /// `Scripts/prove-app-group.sh` is what settles it on a device.
    func testTheInstructionIsWrittenUnderTheKeysTheStoreClears() throws {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }

        store.customTone = "warm but brief"
        store.prefersCustomTone = true

        XCTAssertEqual(
            store.userDefaults.string(forKey: "customToneInstruction"), "warm but brief")
        XCTAssertTrue(store.userDefaults.bool(forKey: "prefersCustomTone"))

        try XCTSkipUnless(
            store.storage == .appGroup,
            "unhosted: store.userDefaults is .standard here, so nothing in this process can tell the two apart"
        )
        let suite = try XCTUnwrap(UserDefaults(suiteName: SharedStore.appGroupIdentifier))
        XCTAssertEqual(suite.string(forKey: "customToneInstruction"), "warm but brief")
    }

    /// `resetToDefaults()` claims to put every setting back, and `-uiTestReset`
    /// calls it. A hand-written tone left behind by one run is a tone the next run
    /// silently rewrites in.
    func testResettingClearsTheToneTheUserWrote() {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.customTone = "like a colleague, never like an assistant"
        store.prefersCustomTone = true

        store.resetToDefaults()

        XCTAssertEqual(store.customTone, "", "a reset left the user's own tone in the store")
        XCTAssertFalse(store.prefersCustomTone)
        XCTAssertEqual(store.toneSetting, .builtIn(.clearer))
    }

    /// **Settings runs in the other process, so the built-in register has to be
    /// read back rather than remembered.** `SharedStore.load()` fills the
    /// `@Published` copy once, when the process launched; a keyboard already on
    /// screen when the tone changed would otherwise keep answering with the old
    /// one. Writing the key directly is what the app's write looks like from
    /// inside the keyboard: the value arrives in the plist, and nothing has told
    /// this process's published property about it.
    func testTheDefaultToneIsReadBackRatherThanCachedFromLaunch() {
        let saved = ToneSettings.snapshot()
        defer { saved.restore() }
        store.prefersCustomTone = false
        store.defaultTone = .clearer
        XCTAssertEqual(store.toneSetting, .builtIn(.clearer))

        store.userDefaults.set(ToneStyle.casual.rawValue, forKey: "defaultTone")

        XCTAssertEqual(
            store.toneSetting, .builtIn(.casual),
            "the tone came off the copy taken when this process launched")
    }
}
