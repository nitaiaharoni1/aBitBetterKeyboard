import XCTest

@testable import AIKeyboardCore

/// One tone call, recorded. Deliberately its own type rather than a shared one:
/// `DefaultToneTests` keeps its recorder `private` and the two suites assert
/// different things about the same call.
private final class ToneCallRecorder: TextIntelligence, @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: [(tone: ToneStyle?, instruction: String?)] = []

    var calls: [(tone: ToneStyle?, instruction: String?)] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func canHandle(_ text: String, action: AIAction) -> Bool { true }

    func fix(_ text: String) async throws -> String { text }

    func variants(
        for text: String, tone: ToneStyle?, instruction: String?
    ) async throws -> [RewriteVariant] {
        lock.lock()
        recorded.append((tone, instruction))
        lock.unlock()
        return [RewriteVariant(tone: tone ?? .clearer, text: "rewritten")]
    }

    func replies(to context: ScreenContext) async throws -> [ReplyOption] { [] }
}

/// **Picking a register from the one-tap rewrite key**, which is now the only route
/// to a register at all. It used to be the only one on a *stock* install, because
/// `AIAction.tone` reached a panel of six chips that no shipped layout carried; that
/// panel is deleted and the action runs the stored register outright, so this popup
/// is the whole of the feature rather than the convenient half of it.
///
/// The gesture itself is `KeyView`'s alternates popup and cannot be driven from
/// here. What can be, and what the broken versions get wrong, is the *list* and
/// the *resolution*: an order that does not lead with the default silently runs a
/// register the user did not pick, and a lookup that cannot find a title runs
/// nothing at all.
@MainActor
final class ToneAlternatesTests: XCTestCase {

    private var saved: (tone: ToneStyle, prefersCustom: Bool, custom: String)!
    private let store = SharedStore.shared

    override func setUp() {
        super.setUp()
        saved = (store.defaultTone, store.prefersCustomTone, store.customTone)
    }

    override func tearDown() {
        store.defaultTone = saved.tone
        store.prefersCustomTone = saved.prefersCustom
        store.customTone = saved.custom
        super.tearDown()
    }

    /// Nil rather than a default `MockTextTarget()`, because a default argument is
    /// evaluated in a nonisolated context and that type is main-actor isolated.
    private func makeController(
        engine: ToneCallRecorder, target: MockTextTarget? = nil
    ) -> KeyboardController {
        KeyboardController(
            target: target ?? MockTextTarget(text: "i cant make the standup"),
            engine: RoutedIntelligence(onDevice: engine, cloud: nil))
    }

    // MARK: The list

    /// **The default leads, and this is the assertion that rejects the obvious
    /// build.** `KeyView` treats index 0 of a popup as "the long press changed
    /// nothing" — for a letter it is the character already inserted. A list
    /// spelled `ToneStyle.allCases.map(\.title)` looks right, is in a sensible
    /// order, and puts Clearer first for every user: hold the key, look at the
    /// list, lift without moving, and a user whose default is Professional gets
    /// Clearer.
    func testTheDefaultRegisterLeadsTheList() {
        store.prefersCustomTone = false
        for tone in ToneStyle.allCases {
            store.defaultTone = tone
            let controller = makeController(engine: ToneCallRecorder())
            XCTAssertEqual(
                controller.toneAlternates.first, tone.title,
                "lifting without moving would run \(controller.toneAlternates.first ?? "nothing") "
                    + "for a user whose default is \(tone.title)")
        }
    }

    /// Every register is reachable, and none twice. A list that appended the six
    /// built-ins to a default that is one of them offers it in two places, and the
    /// second one is dead: `selectTone(named:)` matches by title.
    func testEveryRegisterAppearsExactlyOnce() {
        store.prefersCustomTone = false
        store.defaultTone = .professional
        let list = makeController(engine: ToneCallRecorder()).toneAlternates
        XCTAssertEqual(Set(list).count, list.count, "a register is offered twice: \(list)")
        for tone in ToneStyle.allCases {
            XCTAssertTrue(list.contains(tone.title), "\(tone.title) is unreachable")
        }
    }

    /// **A written custom tone is not offered unless it is the selected one, and
    /// that is deliberate rather than an oversight.** `ToneSetting` only resolves
    /// to `.custom` when `prefersCustomTone` is on, so with the switch off there is
    /// no instruction to send and the popup would be offering a name over the
    /// built-in register standing behind it. `AIResultPanel.toneChips` used to
    /// follow the same rule and was the other surface this had to agree with; it is
    /// deleted, so this popup is now the only reader of `customTone` — which removes
    /// the drift `SuggestionBar` and `AIMenuPanel` already shipped once rather than
    /// guarding against it.
    func testAWrittenCustomToneIsNotOfferedUnlessItIsSelected() {
        store.defaultTone = .friendly
        store.customTone = "short, blunt, no pleasantries"
        store.prefersCustomTone = false
        let controller = makeController(engine: ToneCallRecorder())
        XCTAssertEqual(controller.toneAlternates.first, ToneStyle.friendly.title)
        XCTAssertNil(controller.customTone, "the setting itself does not resolve to a custom tone")
        XCTAssertFalse(controller.toneAlternates.contains(ToneSetting.customTitle))
    }

    /// And is not offered twice when it *is* the default: the first slot already
    /// carries it.
    func testTheCustomToneIsNotOfferedTwiceWhenItIsTheDefault() {
        store.defaultTone = .friendly
        store.customTone = "short, blunt, no pleasantries"
        store.prefersCustomTone = true
        let list = makeController(engine: ToneCallRecorder()).toneAlternates
        XCTAssertEqual(list.first, ToneSetting.customTitle)
        XCTAssertEqual(
            list.filter { $0 == ToneSetting.customTitle }.count, 1,
            "\"\(ToneSetting.customTitle)\" is in the list twice: \(list)")
    }

    /// No custom tone written, so nothing to offer. A chip for a tone the user has
    /// not written runs the built-in behind it under a name that promises theirs.
    func testNoCustomEntryWhenTheUserHasNotWrittenOne() {
        store.prefersCustomTone = false
        store.defaultTone = .clearer
        store.customTone = ""
        XCTAssertFalse(
            makeController(engine: ToneCallRecorder()).toneAlternates
                .contains(ToneSetting.customTitle))
    }

    // MARK: Running one

    /// **The end of this test moved from the strip to the field, and that is the
    /// whole of what `applyDirectly` changed.** It used to finish on
    /// `controller.selectedTone == .professional`, which was the panel's contract:
    /// the answer waited behind a Use button and the six chips read that property
    /// to show which register was standing. There is no panel and no Use button —
    /// the rewrite is written into the document and `clearBannerState()` empties
    /// every field the strip reads, `selectedTone` among them. Asserting it now
    /// would pin a value nothing in the app reads back.
    ///
    /// So it asserts the two things that are still true and still worth breaking
    /// the build over: the engine was asked for the register the user picked, and
    /// the answer reached the field.
    func testPickingARegisterRunsThatRegister() async {
        store.prefersCustomTone = false
        store.defaultTone = .clearer
        let engine = ToneCallRecorder()
        let target = MockTextTarget(text: "i cant make the standup")
        let controller = makeController(engine: engine, target: target)

        controller.selectTone(named: ToneStyle.professional.title)
        await settleToneController(controller)

        XCTAssertEqual(engine.calls.count, 1)
        XCTAssertEqual(engine.calls.first?.tone, .professional)
        XCTAssertNil(engine.calls.first?.instruction, "a built-in register carries no instruction")
        XCTAssertEqual(
            target.text, "rewritten",
            "the register ran and its answer never reached the document")
        XCTAssertNil(
            controller.selectedTone,
            "the answer is in the field, so the strip must not still be holding one")
    }

    /// The user's own words have to reach the engine, not just the built-in they
    /// stand behind. `ToneSetting.custom` carries both and the instruction is the
    /// half a `ToneStyle`-only path drops.
    func testPickingTheCustomToneSendsTheUsersOwnWords() async {
        store.defaultTone = .friendly
        store.customTone = "short, blunt, no pleasantries"
        store.prefersCustomTone = true
        let engine = ToneCallRecorder()
        let target = MockTextTarget(text: "i cant make the standup")
        let controller = makeController(engine: engine, target: target)

        controller.selectTone(named: ToneSetting.customTitle)
        await settleToneController(controller)

        XCTAssertEqual(engine.calls.first?.instruction, "short, blunt, no pleasantries")
        XCTAssertEqual(engine.calls.first?.tone, .friendly, "the register it falls back to")
        // `selectedToneIsCustom` was the third assertion here and is gone for the
        // reason given on the test above: it is banner state, and there is no
        // banner left to hold it once the answer is in the field.
        XCTAssertEqual(
            target.text, "rewritten", "the user's own words ran and produced nothing in the field")
    }

    /// A name nothing matches runs nothing, rather than falling through to a
    /// default register the user did not choose.
    func testAnUnknownNameRunsNothing() async {
        store.prefersCustomTone = false
        store.defaultTone = .clearer
        let engine = ToneCallRecorder()
        let controller = makeController(engine: engine)

        controller.selectTone(named: "Sardonic")
        await settleToneController(controller)

        XCTAssertTrue(engine.calls.isEmpty)
    }

    /// The same two refusals `runDefaultTone` makes. Nothing to rewrite is a key
    /// that should not have fired; a call already in flight must not be thrown
    /// away, because `beginWork` cancels its predecessor.
    func testAnEmptyFieldRunsNothing() async {
        store.prefersCustomTone = false
        store.defaultTone = .clearer
        let engine = ToneCallRecorder()
        let controller = KeyboardController(
            target: MockTextTarget(text: ""),
            engine: RoutedIntelligence(onDevice: engine, cloud: nil))

        controller.selectTone(named: ToneStyle.professional.title)
        await settleToneController(controller)

        XCTAssertTrue(engine.calls.isEmpty)
    }

    /// **The list is read at the moment the key is held, not at launch.** Settings
    /// is a different process and `SharedStore.load()` fills the published copy
    /// once, so a keyboard already on screen when the default changed would
    /// otherwise offer the old order — and its first item is the one a lift
    /// without a slide runs. Same defect `storedDefaultTone` and
    /// `storedPersonalDictionary` exist to avoid.
    func testTheListFollowsTheStoredDefaultWithoutAReload() {
        store.prefersCustomTone = false
        store.defaultTone = .clearer
        let controller = makeController(engine: ToneCallRecorder())
        XCTAssertEqual(controller.toneAlternates.first, ToneStyle.clearer.title)

        store.defaultTone = .confident
        XCTAssertEqual(
            controller.toneAlternates.first, ToneStyle.confident.title,
            "the key is offering the register that was stored when the keyboard launched")
    }
}
