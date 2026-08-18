import UIKit
import XCTest

@testable import AIKeyboardCore

/// The suggestion bar carries two brand-tinted buttons side by side, and both of
/// them were wrong in a way no screenshot showed: one could not be reached in the
/// state it exists for, and the other wore the same drawing as its neighbour.

// MARK: - Reaching the AI menu

/// D8: "we should have a quick button to share screen context in the keyboard".
///
/// The start lives in the app. Reply with no session used to overlay ReplayKit
/// on the key; that picker does not present over a keyboard, so the tap now
/// hands off the way dictation does. What has not changed is the state the
/// defect is about, which is why this file still exists: an empty field with no
/// session must leave a route open. The sparkle was enabled by `hasTextToWorkWith || canReply`, which is
/// false on an empty field with no session: open WhatsApp, tap the compose box,
/// tap the AI button to answer the message on screen, and nothing happens under a
/// hint reading "Type something first".
///
/// The decision is asserted rather than the pixels because there is no way to read
/// `.disabled()` back off a SwiftUI view. What makes these more than a tautology is
/// that the bar no longer holds an opinion at all: it asks `AIAction`, so the two
/// surfaces cannot disagree again.
///
/// **The sparkle itself is deleted, and the question outlived it.** The button
/// opened `AIMenuPanel`; every action that panel listed has its own key now, so the
/// panel and the button went together. What survives is the state the defect was
/// about — an empty field with no session — which must still leave at least one
/// action runnable, because that is the state Reply exists for.
final class SparkleReachabilityTests: XCTestCase {

    /// The state the defect is about, and the one the old expression answered
    /// `false` for.
    func testAnEmptyFieldWithNoSessionStillLeavesAnActionRunnable() {
        XCTAssertTrue(
            SuggestionBar.anyActionCouldRun(hasTextToWorkWith: false),
            "every route to the screen-context affordance is shut in the state it is for")
    }

    /// The button is open exactly when at least one card inside is.
    ///
    /// **Read this for what it is.** Comparing `anyActionCouldRun` against
    /// `hasRunnableAction` would be a tautology, because one is a call to the
    /// other; the right-hand side here is rebuilt from `isAvailable`, which is what
    /// each *action* is refused by, so it is the same question asked of the surface
    /// that answers it rather than of the surface that delegates. That still only
    /// catches a future re-divergence — the shipped bug lived in an expression
    /// neither side now has, and `testAnEmptyFieldWithNoSessionStillOpensTheMenu`
    /// is the one that rejects it.
    func testTheBarIsOpenExactlyWhenACardInsideIs() {
        for hasText in [false, true] {
            let anyActionIsRunnable = AIAction.allCases.contains {
                $0.isAvailable(hasTextToWorkWith: hasText)
            }
            XCTAssertEqual(
                SuggestionBar.anyActionCouldRun(hasTextToWorkWith: hasText), anyActionIsRunnable,
                "the sparkle and the cards behind it disagree with hasTextToWorkWith = \(hasText)")
        }
    }

    /// Which action carries it: Reply, with no text and no session. The three text
    /// actions stay greyed, because they genuinely have nothing to do.
    func testReplyIsTheActionThatKeepsTheMenuWorthOpening() {
        XCTAssertTrue(AIAction.reply.isAvailable(hasTextToWorkWith: false))
        for action in AIAction.allCases where !action.worksWithoutTypedText {
            XCTAssertFalse(
                action.isAvailable(hasTextToWorkWith: false),
                "\(action.title) has nothing to work on and must not look tappable")
            XCTAssertTrue(action.isAvailable(hasTextToWorkWith: true))
        }
    }

    /// Tapping Reply on an empty field with nothing running reaches the banner that
    /// explains screen context and, when a session could start, hosts ReplayKit.
    /// This is the other end of the same route, and it is what makes the
    /// assertions above more than a statement about a boolean: there really is
    /// something behind that button in the state it was shut in.
    @MainActor
    func testReplyWithNoSessionOpensTheExplanation() {
        let allowed = SharedStore.shared.screenContextAllowed
        ScreenContextSession.shared.stop()
        SharedStore.shared.screenContextAllowed = false
        // Nothing copied either, or Reply has a clipboard message to answer and
        // rightly does not refuse at all. See `prepareLedger`.
        let restoreLedger = prepareLedger([])
        defer {
            SharedStore.shared.screenContextAllowed = allowed
            restoreLedger()
        }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        XCTAssertFalse(controller.hasTextToWorkWith, "the state under test is an empty field")
        controller.run(.reply)

        // **Both halves, and the first is the point of the change.** Asserting the
        // block alone passes against the build that set one and opened
        // `AIResultPanel(.needsScreenContext)` over every key on top of it.
        XCTAssertEqual(controller.overlay, .none, "the keys must stay visible")
        XCTAssertEqual(controller.block?.action, .reply)
        XCTAssertFalse(
            controller.block?.title.isEmpty ?? true,
            "the refusal has to say which of the four refusals it is")
    }

    /// Reply with no session hosts ReplayKit on the key. Opening the app is
    /// how this used to fail: the extension often cannot open a URL, and the
    /// key itself did nothing.
    @MainActor
    func testReplyWithNoSessionHostsThePickerAndDoesNotOpenTheApp() throws {
        try XCTSkipUnless(
            FeatureFlags.screenCaptureReply,
            "capture is on hold for NIT-6; the flag-off behaviour is asserted below")
        let restore = preparePickerReadyStore()
        defer { restore() }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        controller.screenContext = .off
        controller.screenContextSource = .none
        XCTAssertFalse(controller.hasTextToWorkWith, "the state under test is an empty field")
        XCTAssertTrue(
            CaptureChannel.isReachable,
            "the start is withheld without Full Access; this host has no App Group")
        XCTAssertTrue(
            BackendTransport.isReady(),
            "the start is withheld without a ready backend")
        XCTAssertTrue(
            controller.screenContextPrompt.offersPicker,
            "Reply would refuse, but the prompt is not offering a start")
        XCTAssertNotNil(
            controller.replyKeyBroadcastPrompt,
            "the Reply key is not hosting ReplayKit in the state it exists for")

        var openedURLs: [URL] = []
        controller.onOpenContainingApp = { openedURLs.append($0) }
        _ = SharedStore.shared.consumeDictationHandoff()

        controller.run(.reply)

        XCTAssertEqual(controller.overlay, .none, "the keys must stay visible")
        XCTAssertEqual(controller.block?.action, .reply)
        XCTAssertEqual(controller.block?.title, "Screen context is off")
        XCTAssertEqual(
            controller.block?.remedy, .broadcastPicker,
            "expected the sentence to host ReplayKit, got \(String(describing: controller.block?.remedy))")
        XCTAssertTrue(openedURLs.isEmpty, "Reply opened the app instead of hosting the picker")
        XCTAssertFalse(
            SharedStore.shared.consumeDictationHandoff(),
            "Reply wrote a dictation handoff, which would start the microphone")
    }

    /// Reply during dictation used to still start a broadcast because the overlay
    /// sits outside `KeyView`'s `.disabled`. The prompt must be nil so the
    /// overlay is not drawn, and the tap must not open the app either.
    @MainActor
    func testReplyDoesNotHostThePickerWhileDictating() throws {
        try XCTSkipUnless(
            FeatureFlags.screenCaptureReply,
            "with capture off the overlay is never drawn at all, so this cannot fail")
        let restore = preparePickerReadyStore()
        defer { restore() }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        controller.screenContext = .off
        controller.screenContextSource = .none
        controller.isDictating = true
        var openedURLs: [URL] = []
        controller.onOpenContainingApp = { openedURLs.append($0) }

        XCTAssertNil(
            controller.replyKeyBroadcastPrompt,
            "the overlay is back on a dim Reply key over a live recording")
        controller.run(.reply)

        XCTAssertTrue(openedURLs.isEmpty, "Reply opened the app over a live recording")
        XCTAssertNil(controller.block)
    }

    /// The overlay's touch-up cannot reach `press(.aiReply)`, so this is the
    /// only path that prints the refusal after the system button is pressed.
    @MainActor
    func testTheReplyKeyOverlayPrintsTheSameRefusalAsRunReply() throws {
        try XCTSkipUnless(
            FeatureFlags.screenCaptureReply,
            "capture is on hold for NIT-6; `acknowledgeReplyBroadcastTap` is unreachable")
        let restore = preparePickerReadyStore()
        defer { restore() }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        controller.screenContext = .off
        controller.screenContextSource = .none
        XCTAssertNotNil(controller.replyKeyBroadcastPrompt)

        controller.acknowledgeReplyBroadcastTap()

        XCTAssertEqual(controller.block?.action, .reply)
        XCTAssertEqual(controller.block?.remedy, .broadcastPicker)
        XCTAssertEqual(controller.block?.title, "Screen context is off")
    }

    /// Unrestartable ending and no backend are the two `offersPicker == false`
    /// fixtures this controller can actually enter. Full Access is
    /// `CaptureChannel.isReachable` and cannot be faked here.
    @MainActor
    func testReplyDoesNotOpenTheAppWhenThePromptWithholdsTheStart() {
        let allowed = SharedStore.shared.screenContextAllowed
        let token = SharedStore.shared.cloudBackendToken
        let sessionToken = SharedStore.shared.cloudSessionToken
        ScreenContextSession.shared.stop()
        // An empty ledger, so the refusal's remedy is `Remedy.none` rather than
        // the CopyClip chip an unread copy would earn.
        let restoreLedger = prepareLedger([])
        defer {
            SharedStore.shared.screenContextAllowed = allowed
            SharedStore.shared.cloudBackendToken = token
            SharedStore.shared.cloudSessionToken = sessionToken
            restoreLedger()
        }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        var openedURLs: [URL] = []
        controller.onOpenContainingApp = { openedURLs.append($0) }

        controller.screenContext = .ended(.notConfigured)
        XCTAssertFalse(controller.screenContextPrompt.offersPicker)
        XCTAssertNil(controller.replyKeyBroadcastPrompt)
        controller.run(.reply)
        // `BannerState.Block.Remedy.none` spelled out. `block` is optional, so a
        // bare `.none` here is `Optional.none` and this asserted there was no
        // block at all, against a refusal that correctly carries one with no
        // remedy button. `refuseForScreenContext` builds it as
        // `remedy: prompt.offersPicker ? .broadcastPicker : .none`, and
        // `offersPicker` is false one line above, so `Remedy.none` is precisely
        // what this means to check.
        XCTAssertEqual(controller.block?.remedy, BannerState.Block.Remedy.none)
        XCTAssertTrue(openedURLs.isEmpty, "an unrestartable ending still opened the app")

        openedURLs.removeAll()
        controller.screenContext = .off
        SharedStore.shared.cloudBackendToken = ""
        SharedStore.shared.cloudSessionToken = ""
        XCTAssertFalse(controller.screenContextPrompt.offersPicker)
        XCTAssertNil(controller.replyKeyBroadcastPrompt)
        controller.run(.reply)
        XCTAssertEqual(
            controller.block?.remedy, BannerState.Block.Remedy.none,
            "no-cloud still offers a start")
        XCTAssertTrue(openedURLs.isEmpty, "no-cloud still opened the app")
    }

    /// The Open chip is shared with dictation. Tapping it for screen context
    /// must not write the timestamp that auto-starts the microphone.
    @MainActor
    func testOpenAppChipDoesNotRecordADictationHandoffForScreenContext() {
        _ = SharedStore.shared.consumeDictationHandoff()
        let controller = KeyboardController(target: MockTextTarget(text: ""))

        controller.recordDictationHandoffIfNeeded(for: SharedStore.screenContextURL)
        XCTAssertFalse(
            SharedStore.shared.consumeDictationHandoff(),
            "Open for screen context wrote a dictation handoff")

        controller.recordDictationHandoffIfNeeded(for: SharedStore.settingsURL)
        XCTAssertFalse(
            SharedStore.shared.consumeDictationHandoff(),
            "Open for settings wrote a dictation handoff")

        controller.recordDictationHandoffIfNeeded(for: SharedStore.dictationStartURL)
        XCTAssertTrue(
            SharedStore.shared.consumeDictationHandoff(),
            "dictation Open must still write a handoff")
    }

    /// The session becoming live is what proves a start worked, and
    /// `BannerState.resolve` prefers `block` over a reading, so leaving the
    /// refusal up would keep printing "Screen context is off" on a Reply that
    /// is about to generate.
    @MainActor
    func testTheBroadcastRefusalLeavesOnceASessionIsLive() throws {
        try XCTSkipUnless(
            FeatureFlags.screenCaptureReply,
            "no refusal carries `.broadcastPicker` while capture is on hold")
        let restore = preparePickerReadyStore()
        defer { restore() }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        controller.screenContext = .off
        controller.screenContextSource = .none
        controller.run(.reply)
        XCTAssertEqual(
            controller.block?.remedy, .broadcastPicker,
            "the state under test is the picker strip")

        controller.screenContext = .starting
        XCTAssertNil(
            controller.block,
            "Screen context is off is still on the strip after the session started")
        XCTAssertFalse(controller.showsActionBanner)
    }

    /// A live session only retires the "please start a broadcast" sentence.
    /// Full Access and a dead backend are refusals a picker cannot fix, and
    /// `BannerState.resolve` still has to print them.
    @MainActor
    func testALiveSessionDoesNotClearARefusalThePickerCouldNotFix() {
        let controller = KeyboardController(target: MockTextTarget(text: ""))
        controller.refuse(
            .init(
                action: .reply, title: "Needs Full Access", detail: "Turn it on.",
                remedy: .none))
        controller.screenContext = .watching
        XCTAssertEqual(
            controller.block?.remedy, BannerState.Block.Remedy.none,
            "a live session cleared a refusal starting a broadcast cannot fix")
    }

    /// Puts the CopyClip ledger into a known state and syncs its cursor to the
    /// live pasteboard, so `ReplySource` answers the same thing on every run.
    ///
    /// **Both halves matter.** The clips decide whether Reply has anything to
    /// answer; the cursor decides whether the keyboard believes a *newer* copy is
    /// waiting that it has not been allowed to read — and a cursor left at its
    /// `-1` default makes every simulator report `CopyClipCaptureState.control`,
    /// which is a different refusal with a different remedy. Restored because
    /// `SharedStore.shared` is process-wide.
    @MainActor
    private func prepareLedger(_ clips: [Clip]) -> () -> Void {
        let store = SharedStore.shared
        let before = store.copyclipRecord
        store.copyclipRecord = CopyclipRecord(
            clips: clips, lastChangeCount: PasteboardReader.changeCount)
        return { store.copyclipRecord = before }
    }

    /// Typed token so `ScreenContextPrompt.offersPicker` can be true; restored
    /// because `SharedStore.shared` is process-wide.
    @MainActor
    private func preparePickerReadyStore() -> () -> Void {
        let store = SharedStore.shared
        let token = store.cloudBackendToken
        let sessionToken = store.cloudSessionToken
        ScreenContextSession.shared.stop()
        if token.isEmpty { store.cloudBackendToken = "test-token" }
        return {
            store.cloudBackendToken = token
            store.cloudSessionToken = sessionToken
        }
    }

    /// **A refusal must not hide the next one.**
    ///
    /// `runReply`'s secure-field guard is the only place in the module that sets
    /// `aiError` without going through `beginWork`, and `beginWork` is what clears
    /// `block` everywhere else. `BannerState.resolve` tests `block` above `error`,
    /// so a stale "Nothing to fix yet" from an earlier tap stayed on screen while
    /// the password-field refusal the user had just earned was never drawn at all.
    ///
    /// Driven through `run(.reply)` rather than by setting the fields, because the
    /// bug is that one code path forgets a line: a test that assigns `block = nil`
    /// itself passes against the build that forgets it. The state has to be set up
    /// with a real refusal standing, or both versions look identical.
    @MainActor
    func testAPasswordFieldRefusalIsNotHiddenByAnEarlierOne() {
        let allowed = SharedStore.shared.screenContextAllowed
        SharedStore.shared.screenContextAllowed = true
        defer { SharedStore.shared.screenContextAllowed = allowed }

        // A message exists, so `runReply` gets past its first guard and reaches
        // the secure-field one, which is the guard under test. It comes from the
        // clipboard rather than from a reading, because with
        // `FeatureFlags.screenCaptureReply` off a reading is not a source Reply
        // will act on — and the guard has to hold for the clipboard path too,
        // which is the point of asserting it here.
        let restoreLedger = prepareLedger([
            Clip(id: UUID(), text: ClipText(raw: "sent it")!, capturedAt: Date())
        ])
        defer { restoreLedger() }

        let controller = KeyboardController(target: SecureTextTarget())

        controller.refuseForEmptyField(.fix)
        XCTAssertEqual(controller.block?.action, .fix, "the state under test was not set up")

        controller.run(.reply)

        XCTAssertNotNil(controller.aiError, "the secure-field guard did not fire")
        XCTAssertNil(
            controller.block,
            "the stale refusal is still standing, and resolve draws it over the new one")
    }
}

/// A field that says it is secure, which is what `runReply`'s §3.3.1 guard refuses
/// on. Local to this file: every other mock here answers `false`.
@MainActor
private final class SecureTextTarget: TextTarget {
    var documentContextBeforeInput: String? { "" }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var isSecureTextEntry: Bool? { true }
    var textContentType: UITextContentType?? { .some(.password) }
    var keyboardType: UIKeyboardType? { .default }

    func insertText(_ text: String) {}
    func deleteBackward() {}
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}

// MARK: - The one-tap rewrite button on an empty field

/// The other button, in the state a keyboard spends most of its life in.
///
/// It shipped `.disabled(!canRun)` behind `Theme.Brand.softGradient` at 0.45
/// opacity, with the icon itself drawn at full `Theme.Brand.solid` — only the
/// background faded, so beside the fully-lit sparkle it read as live. The owner of
/// the first device this went on tapped it on an empty field and nothing happened
/// and nothing said why.
///
/// The decision is asserted rather than the pixels for the reason
/// `SparkleReachabilityTests` gives: `.disabled()` cannot be read back off a
/// SwiftUI view. What the assertions below reject is the shipped behaviour — the
/// old wiring answers "do nothing" to exactly the input the first test names.
final class ToneButtonTapTests: XCTestCase {

    /// **The empty field is its own state, and that is what this holds.** It used
    /// to answer the tap with a sentence in the banner and now it takes no tap at
    /// all — the button and the Rewrite key beside Fix are both drawn dim and
    /// disabled, which is the statement the banner was making, in the place the
    /// user is already looking. What must not come back is the shipped defect that
    /// `ToneTap` was written against: a *third* answer, where the control looks lit
    /// and does nothing. So the state stays distinguishable from `.rewrite`, and
    /// the view is what turns it into a disabled control.
    func testAnEmptyFieldIsItsOwnState() {
        XCTAssertEqual(
            SuggestionBar.toneTap(hasTextToWorkWith: false, isWorking: false), .needsText,
            "an empty field is indistinguishable from a field with something in it")
    }

    func testWithSomethingToRewriteItRewrites() {
        XCTAssertEqual(
            SuggestionBar.toneTap(hasTextToWorkWith: true, isWorking: false), .rewrite)
    }

    /// **The one state a tap may be ignored in is a call already in flight.**
    /// `beginWork` cancels its predecessor, so a second tap would throw away
    /// the answer the first is waiting on — and the user can see a call is running,
    /// which is what makes ignoring it honest rather than silent.
    func testATapIsOnlyEverIgnoredWhileACallIsInFlight() {
        for hasText in [false, true] {
            XCTAssertNotEqual(
                SuggestionBar.toneTap(hasTextToWorkWith: hasText, isWorking: false), .ignore,
                "a tap goes unanswered with hasTextToWorkWith = \(hasText)")
            XCTAssertEqual(
                SuggestionBar.toneTap(hasTextToWorkWith: hasText, isWorking: true), .ignore)
        }
    }

    /// The other half, and why the button cannot simply be wired to the action:
    /// `runDefaultTone` on an empty field is a no-op and rightly so — there is
    /// nothing to rewrite. That is the code the tap used to reach.
    @MainActor
    func testTheActionItselfDoesNothingOnAnEmptyFieldWhichIsWhyTheTapIsRouted() {
        let controller = KeyboardController(target: MockTextTarget(text: ""))
        XCTAssertFalse(controller.hasTextToWorkWith, "the state under test is an empty field")

        controller.runDefaultTone()
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertFalse(controller.isWorking)

        // Where the tap goes instead, and that there is something behind it. It
        // used to be `show(.aiMenu)` and a panel; the answer is now a sentence in
        // the strip, with the keys still under it.
        controller.refuseForEmptyField(.rewrite)
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertEqual(controller.block?.action, .rewrite)
        XCTAssertTrue(AIAction.hasRunnableAction(hasTextToWorkWith: false))
    }
}

// MARK: - Telling the two buttons apart

/// The one-tap tone button wears the tone's own SF Symbol and sits directly beside
/// the AI menu's `SparkleMark`. The shipped default tone's icon was `sparkle`,
/// which is `sparkles` drawn once instead of three times, so the bar showed two
/// sparkles side by side that did two different things — and every instruction in
/// the app that said "tap ✨" named both of them.
///
/// `ToneSetting.settingsNote` fixed this sentence in Settings and left the
/// playground and onboarding saying "tap ✨"; those now build their copy from
/// `SuggestionBar.aiButtonName`.
final class ToneIconTests: XCTestCase {

    func testNoToneWearsTheAIMenusSparkle() {
        for tone in ToneStyle.allCases {
            XCTAssertFalse(
                tone.icon.contains("sparkle"),
                "\(tone.title) wears \(tone.icon) next to \(SparkleMark.symbolName) in the same panel")
        }
        XCTAssertEqual(ToneSetting.customTitle, "My tone")
    }

    /// The custom register is named in the same place as the six built-ins,
    /// because the button prints a name rather than drawing one.
    func testTheCustomRegisterIsNamedTheSameWayTheBuiltInsAre() {
        XCTAssertEqual(ToneSetting.builtIn(.professional).title, ToneStyle.professional.title)
        XCTAssertEqual(
            ToneSetting.custom(instruction: "x", nearest: .clearer).title, ToneSetting.customTitle)
    }

    /// Every icon has to be a symbol that exists, because a name with no symbol
    /// behind it draws nothing at all — which on this button is a blank rectangle
    /// where the only clue to what a tap will do used to be.
    func testEveryToneIconIsARealSymbol() {
        for tone in ToneStyle.allCases {
            XCTAssertNotNil(UIImage(systemName: tone.icon), "\(tone.title): no such symbol \(tone.icon)")
        }
        XCTAssertNotNil(UIImage(systemName: SparkleMark.symbolName))
        XCTAssertNotNil(
            UIImage(systemName: ToneSetting.customIcon),
            "My tone: no such symbol \(ToneSetting.customIcon)")
    }

    /// Two tones sharing an icon is the same defect one step along, so the six are
    /// held to being six.
    func testTheSixTonesAreSixDifferentIcons() {
        XCTAssertEqual(Set(ToneStyle.allCases.map(\.icon)).count, ToneStyle.allCases.count)
    }

    /// **The bar button's glyph does not change with the tone, and that is the
    /// whole fix.** Drawing `tone.icon` there made the control mean six things:
    /// with Casual selected it was `figure.wave`, a waving stick figure sitting in
    /// a keyboard, which reads as a profile button and says nothing about rewriting
    /// anything. So the assertion is written to reject the old behaviour outright —
    /// the symbol has to be one *no* tone wears — rather than merely to pass.
    func testTheOneTapButtonWearsOneFixedSymbolAndNotTheTonesOwn() {
        XCTAssertEqual(SuggestionBar.toneButtonSymbol, AIAction.rewrite.icon)
        XCTAssertNotNil(UIImage(systemName: SuggestionBar.toneButtonSymbol))
        XCTAssertFalse(SuggestionBar.toneButtonSymbol.contains("sparkle"))

        for tone in ToneStyle.allCases {
            XCTAssertNotEqual(
                SuggestionBar.toneButtonSymbol, tone.icon,
                "the button is back to drawing \(tone.title)'s own symbol")
        }
    }

    /// **The tone is printed now, and the button that prints it is a fixed width**,
    /// so a name that does not fit does not widen the bar — it truncates, and the
    /// user reads `Professiona…` under a glyph. The button cannot grow instead
    /// because its width is a setting: sizing to the text moved the three
    /// candidates sideways whenever the default tone changed on another screen.
    ///
    /// So every name is measured against the real font at the real inset. This is
    /// the test that fails the day a seventh register arrives with a long name,
    /// and the fix then is a wider button or a shorter name, deliberately.
    func testEveryToneNameFitsTheFixedWidthButtonItIsPrintedOn() {
        let room = SuggestionBar.toneButtonWidth - 2 * SuggestionBar.toneButtonInset
        let names = ToneStyle.allCases.map(\.title) + [ToneSetting.customTitle]

        for name in names {
            XCTAssertFalse(name.isEmpty)
            let width = (name as NSString).size(
                withAttributes: [.font: SuggestionBar.toneLabelFont]
            ).width
            XCTAssertLessThanOrEqual(
                width, room,
                "\"\(name)\" needs \(width)pt and the button offers \(room)pt, so it truncates")
        }
    }

    /// The other half of the same constraint, and the one a "does it fit" test
    /// cannot see: the button is allowed to be wider than its 44pt neighbours, but
    /// not so wide that the three candidates stop being readable on the narrowest
    /// screen the app runs on. 375pt is an iPhone SE; the bar's chrome is the two
    /// 44pt edge buttons, this one, and two hairline separators.
    func testTheButtonLeavesTheCandidatesRoomOnTheNarrowestScreen() {
        let separator = 1 + 2 * Theme.Space.xxs
        let chrome = 2 * Theme.Space.xxs + 44 + SuggestionBar.toneButtonWidth + 44 + 2 * separator
        let perCandidate = (375 - chrome) / 3

        XCTAssertGreaterThanOrEqual(
            perCandidate, 55,
            "each candidate gets \(perCandidate)pt, which is narrower than a six-letter word")
    }
}
