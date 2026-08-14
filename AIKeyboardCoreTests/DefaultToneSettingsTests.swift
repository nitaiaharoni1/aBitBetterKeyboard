import XCTest

@testable import AIKeyboardCore

/// Settings-section tests extracted from `DefaultToneTests`.
@MainActor
final class DefaultToneSettingsTests: XCTestCase {

    private var store: SharedStore { .shared }

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
            ToneSetting.custom(instruction: "short and blunt", nearest: .casual).settingsNote
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
        let controller = makeToneController(text: "could you possibly take a look", engine: engine)
        controller.runDefaultTone()
        await settleToneController(controller)

        XCTAssertEqual(engine.instructions, [String?.none])
        XCTAssertFalse(controller.selectedToneIsCustom)
    }

    /// The register composes into the prompt in place of the built-in direction,
    /// rather than beside it. Two registers arguing is one register the model
    /// picks at random.
    func testTheInstructionReplacesTheBuiltInDirectionInThePrompt() {
        let asked = "short, blunt, no pleasantries"
        let prompt = Prompts.tone(.casual, for: "could you possibly take a look", instruction: asked)
        XCTAssertTrue(prompt.contains(asked))
        XCTAssertFalse(
            prompt.contains("The way you would message a colleague"),
            "the built-in direction is still in the prompt alongside the user's")
        // The rules the register must not overrule are still ahead of it.
        XCTAssertTrue(prompt.contains("Same language as the message. Never translate."))
        // An empty register is not a register.
        XCTAssertEqual(
            Prompts.tone(.casual, for: "take a look", instruction: "   "),
            Prompts.tone(.casual, for: "take a look"))
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
        let english = Prompts.tone(.casual, for: "can you send me the deck", instruction: hebrewRegister)
        XCTAssertFalse(
            english.contains(hebrewRegister),
            "a Hebrew register was quoted inside the English instruction set")
        XCTAssertTrue(
            english.contains("The way you would message a colleague"),
            "the built-in register has to run when the user's own one cannot")

        // Cyrillic, Greek and Arabic registers go the same way, and so does a
        // Latin register under a Hebrew message's set — no, that one is spoken:
        // the Hebrew rules are about English loanwords keeping their letters.
        XCTAssertFalse(
            Prompts.tone(.shorter, for: "send me the deck", instruction: "коротко и по делу")
                .contains("коротко"))
        let hebrewMessage = Prompts.tone(
            .casual, for: "אפשר לשלוח לי את המצגת?", instruction: "short and blunt")
        XCTAssertTrue(
            hebrewMessage.contains("short and blunt"),
            "the Hebrew set speaks Latin and should have kept a Latin register")
        XCTAssertTrue(
            Prompts.tone(.casual, for: "אפשר לשלוח לי את המצגת?", instruction: hebrewRegister)
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
        let controller = makeToneController(text: "sounds good to me", engine: engine)
        controller.runDefaultTone()
        await settleToneController(controller)

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
        XCTAssertEqual(store.toneSetting, .builtIn(.normal))
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
