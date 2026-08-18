import Foundation
import XCTest

@testable import AIKeyboardCore

/// Where Reply gets the message it answers, now that a ReplayKit capture session
/// is not it.
///
/// **`FeatureFlags.screenCaptureReply` is false and the capture code is all
/// still there.** The broadcast extension, the channel, the fingerprint and the
/// reader are untouched; what changed is that nothing in the keyboard can reach
/// them, and that Reply has a second source — the message the user copied — which
/// needs no entitlement, no broadcast and no permission dialog.
@MainActor
final class ReplySourceTests: XCTestCase {

    private func clip(_ text: String) -> Clip {
        Clip(id: UUID(), text: ClipText(raw: text)!, capturedAt: Date())
    }

    // MARK: The flag

    /// The condition for flipping it is a device run, not a compile. Stated as a
    /// test so a build that turns it on has to come here and say so.
    func testCaptureIsOnHold() {
        XCTAssertFalse(
            FeatureFlags.screenCaptureReply,
            "capture is shipping again; NIT-6 has to have passed on a real device")
    }

    // MARK: Building a context out of a clip

    /// **The three fields a clip cannot know are empty, not invented.** A
    /// plausible sender would reach the model in the user prompt and, in Hebrew,
    /// decide the grammatical gender every reply is written in.
    func testAClipNamesNoSenderAndNoApp() {
        let context = ReplySource.context(for: clip("Are we still on for 6?"))

        XCTAssertEqual(context.message, "Are we still on for 6?")
        XCTAssertEqual(context.sender, "", "a sender was invented for a copied string")
        XCTAssertEqual(context.appName, "")
        XCTAssertEqual(context.appIcon, "")
    }

    /// And an empty sender must not reach the model as `From :`, which is what
    /// both engines interpolated before `modelPrompt` existed. The broken build
    /// answers `"From :\nAre we still on for 6?"`.
    func testAnUnnamedSenderIsNotHeadedAtTheModel() {
        let copied = ReplySource.context(for: clip("Are we still on for 6?"))
        XCTAssertEqual(copied.modelPrompt, "Are we still on for 6?")

        let read = ScreenContext(
            appName: "WhatsApp", appIcon: "message", sender: "Maya",
            message: "Are we still on for 6?", language: .english)
        XCTAssertEqual(
            read.modelPrompt, "From Maya:\nAre we still on for 6?",
            "a reading that does name the sender stopped naming it")
    }

    /// The language is detected rather than taken from the keyboard, because the
    /// reply has to be in the language of the message and the two are routinely
    /// different — answering a Hebrew message is exactly the case where the keys
    /// are still on English.
    func testTheLanguageComesFromTheCopiedTextRatherThanTheKeys() {
        XCTAssertEqual(
            ReplySource.context(for: clip("מתי נוח לך להיפגש מחר בבוקר?")).language,
            .hebrew)
        XCTAssertEqual(
            ReplySource.context(for: clip("Can you send that over before the standup?")).language,
            .english)
    }

    /// **The English fallback does not lose the script**, which is the property
    /// that makes it safe to have one at all. Two characters may be too few for
    /// `NLLanguageRecognizer` to name a language — this test deliberately does not
    /// claim which way it answers — and either way `Prompts.reply(for:)` returns
    /// the Hebrew instructions, because it asks `isHebrew(context.message)` one
    /// branch before it looks at the language. A fallback that turned a Hebrew
    /// message into an English prompt is the failure this rejects.
    func testAVeryShortHebrewMessageStillGetsTheHebrewPrompt() {
        let context = ReplySource.context(for: clip("מה"))
        XCTAssertTrue(
            Prompts.reply(for: context).contains("בעברית"),
            "a Hebrew message reached the English instructions")
    }

    // MARK: What the clipboard can offer

    /// The ordinary case: a clip is in the ledger and the pasteboard has not moved
    /// since, so it is the newest thing the user copied.
    func testTheNewestClipIsTheMessage() {
        let source = ReplySource.fromClipboard(
            newest: clip("Are we still on for 6?"), capture: .automatic)

        guard case .clipboard(let context) = source else {
            return XCTFail("expected the clipboard to answer, got \(String(describing: source))")
        }
        XCTAssertEqual(context.message, "Are we still on for 6?")
    }

    /// **A copy the keyboard has not been allowed to read refuses rather than
    /// falling back.** The ledger's newest clip is no longer the newest copy, and
    /// answering it would be a reply in the user's own name about somebody else's
    /// message. The broken build answers `.clipboard("yesterday's message")`.
    func testAnUnreadCopyRefusesRatherThanAnsweringTheClipBehindIt() {
        XCTAssertNil(
            ReplySource.fromClipboard(newest: clip("yesterday's message"), capture: .control),
            "Reply would answer the wrong message")
        XCTAssertEqual(
            ReplySource.clipboardGap(newest: clip("yesterday's message"), capture: .control),
            .copyNotRead)
    }

    /// A copied image can never become a clip, and `refreshCopyClip(.userAsked)`
    /// has already advanced the cursor past it — so `.neither` is not a reason to
    /// withhold the message that *is* in the ledger.
    func testACopiedImageDoesNotWithholdTheClipInTheLedger() {
        XCTAssertNotNil(ReplySource.fromClipboard(newest: clip("hello"), capture: .neither))
        XCTAssertNil(ReplySource.fromClipboard(newest: nil, capture: .neither))
        XCTAssertEqual(
            ReplySource.clipboardGap(newest: nil, capture: .automatic), .nothingCopied)
    }

    // MARK: Through the controller

    /// **The whole feature, end to end**, and the assertion is the message the
    /// engine was asked about rather than `canReply`: a build that decided the
    /// source correctly and then handed `contextForReply()` an empty capture
    /// session answers with a refusal, and one that answered `true` to `canReply`
    /// and generated about nothing at all would pass a flag check.
    func testReplyAnswersTheCopiedMessage() async {
        let restore = prepareLedger([clip("Are we still on for 6?")])
        defer { restore() }

        let engine = ReplyRecorder(answer: "Yes, six works.")
        let controller = KeyboardController(
            target: MockTextTarget(text: ""),
            engine: RoutedIntelligence(onDevice: engine, cloud: nil))

        XCTAssertTrue(controller.canReply, "a copied message is not being offered to Reply")
        controller.run(.reply)
        await settleToneController(controller)

        XCTAssertEqual(engine.asked?.message, "Are we still on for 6?")
        XCTAssertEqual(controller.contextBefore, "Yes, six works.")
    }

    /// With nothing copied, Reply refuses and the sentence names the one thing
    /// that would make it work. **It must not name screen context**, which is the
    /// half `FeatureFlags.screenCaptureReply` is about: the shipped build refused
    /// here with "Tap to pick aBitBetterKeyboard, then Start Broadcast."
    func testWithNothingCopiedTheRefusalNamesTheCopyRatherThanABroadcast() {
        let restore = prepareLedger([])
        defer { restore() }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        XCTAssertFalse(controller.canReply)

        // **Both states that used to reach `.broadcastPicker`**, driven through
        // `run(.reply)` rather than through `ScreenContextPrompt`, because
        // `refuseForScreenContext` is the only producer of that remedy in the
        // module and this is the path that reaches it. `.off` is the ordinary
        // one; an ending a restart *would* fix is the other, and it is the state
        // a page left in the shared container by an earlier build puts the
        // keyboard in for ten minutes (`ScreenContextSession.endingWorthShowing`).
        for state in [ScreenContextState.off, .ended(.stopped)] {
            controller.screenContext = state
            controller.run(.reply)

            let detail = controller.block?.detail ?? ""
            XCTAssertEqual(controller.block?.action, .reply, "\(state) refused silently")
            XCTAssertFalse(
                detail.localizedCaseInsensitiveContains("broadcast"),
                "the refusal still asks for a screen recording in \(state): \(detail)")
            XCTAssertNotEqual(
                controller.block?.remedy, BannerState.Block.Remedy.broadcastPicker,
                "the refusal still hosts ReplayKit on its sentence in \(state)")
        }
    }

    /// The key never becomes ReplayKit's button. Asserted through the controller
    /// rather than through the flag, because `KeyboardView+Keys` reads exactly
    /// this property to decide whether to draw the overlay.
    func testTheReplyKeyNeverHostsThePicker() {
        let restore = prepareLedger([])
        defer { restore() }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        for state in [ScreenContextState.off, .watching, .ended(.stopped)] {
            controller.screenContext = state
            XCTAssertNil(
                controller.replyKeyBroadcastPrompt,
                "the Reply key hosts a screen-recording picker in \(state)")
        }
    }

    /// **The scripted sample still wins, and it is not what the flag turned off.**
    /// It photographs nothing, it is what the in-app playground demonstrates with,
    /// and a clip in the ledger must not paint a real message over a demo.
    func testTheScriptedSampleOutranksTheClipboard() {
        let allowed = SharedStore.shared.screenContextAllowed
        SharedStore.shared.screenContextAllowed = true
        let restore = prepareLedger([clip("a real message")])
        defer {
            SharedStore.shared.screenContextAllowed = allowed
            restore()
        }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        controller.screenContextSource = .scripted
        controller.screenContext = .ready(MockScreenContext.sample(at: 0))

        XCTAssertEqual(controller.replySource, ReplySource.scripted)
    }

    /// Puts the CopyClip ledger into a known state and syncs its cursor to the
    /// live pasteboard.
    ///
    /// **Both halves matter.** The clips decide whether Reply has anything to
    /// answer; the cursor decides whether the keyboard believes a newer copy is
    /// waiting that it has not been allowed to read — and a cursor left at its
    /// `-1` default makes every simulator report `CopyClipCaptureState.control`,
    /// which is a different refusal with a different remedy. Restored because
    /// `SharedStore.shared` is process-wide.
    private func prepareLedger(_ clips: [Clip]) -> () -> Void {
        let store = SharedStore.shared
        let before = store.copyclipRecord
        store.copyclipRecord = CopyclipRecord(
            clips: clips, lastChangeCount: PasteboardReader.changeCount)
        return { store.copyclipRecord = before }
    }
}

/// An engine that keeps the context it was asked about, so a test can assert
/// *which message* Reply answered rather than only that it answered.
private final class ReplyRecorder: TextIntelligence, @unchecked Sendable {
    private let answer: String
    private let lock = NSLock()
    private var recorded: ScreenContext?

    var asked: ScreenContext? {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    init(answer: String) {
        self.answer = answer
    }

    func canHandle(_ text: String, action: AIAction) -> Bool { true }
    func fix(_ text: String, style: FixStyle) async throws -> String { text }
    func variants(
        for text: String, tone: ToneStyle?, instruction: String?
    ) async throws -> [RewriteVariant] { [] }

    func replies(to context: ScreenContext) async throws -> [ReplyOption] {
        lock.lock()
        recorded = context
        lock.unlock()
        return [ReplyOption(intent: "Accept", icon: "checkmark", text: answer)]
    }
}
