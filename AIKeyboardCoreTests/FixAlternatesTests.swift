import UIKit
import XCTest

@testable import AIKeyboardCore

/// One Fix call, recorded. Deliberately its own type rather than sharing
/// `ToneRecorder`: that one exists to prove the one-tap key is *not* Fix.
private final class FixCallRecorder: TextIntelligence, @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: [FixStyle] = []

    var styles: [FixStyle] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func canHandle(_ text: String, action: AIAction) -> Bool { true }

    func fix(_ text: String, style: FixStyle) async throws -> String {
        lock.lock()
        recorded.append(style)
        lock.unlock()
        return "fixed"
    }

    func variants(
        for text: String, tone: ToneStyle?, instruction: String?
    ) async throws -> [RewriteVariant] { [] }

    func replies(to context: ScreenContext) async throws -> [ReplyOption] { [] }
}

/// **Picking a pass from the Fix key**, which is the long-press counterpart to
/// the rewrite registers. The gesture itself is `KeyView`'s alternates popup
/// and cannot be driven from here. What can be, and what the broken versions
/// get wrong, is the *list* and the *resolution*: an order that does not lead
/// with Fix silently runs Spelling, and a lookup that cannot find a title
/// runs nothing at all.
@MainActor
final class FixAlternatesTests: XCTestCase {

    private func makeController(
        engine: FixCallRecorder, target: MockTextTarget? = nil
    ) -> KeyboardController {
        KeyboardController(
            target: target ?? MockTextTarget(text: "i cant make the standup"),
            engine: RoutedIntelligence(onDevice: engine, cloud: nil))
    }

    // MARK: The list

    /// **Proofread leads, and this is the assertion that rejects the obvious
    /// build.** `KeyView` treats index 0 of a popup as "the long press changed
    /// nothing". A list spelled with Spelling first looks right in isolation
    /// and would run a narrower pass for every user who held the key, looked,
    /// and lifted without moving.
    func testProofreadLeadsTheList() {
        let list = makeController(engine: FixCallRecorder()).fixAlternates
        XCTAssertEqual(list.first, FixStyle.proofread.title)
        XCTAssertEqual(list.first, "Fix")
    }

    /// Every pass is reachable, and none twice.
    func testEveryPassAppearsExactlyOnce() {
        let list = makeController(engine: FixCallRecorder()).fixAlternates
        XCTAssertEqual(Set(list).count, list.count, "a pass is offered twice: \(list)")
        XCTAssertEqual(list, FixStyle.allCases.map(\.title))
        XCTAssertEqual(list, ["Fix", "Spelling", "Punctuate", "Polish"])
    }

    /// A missing symbol draws an empty mark next to the pass name, which is
    /// how a list of four words with no pictures used to read.
    func testEveryPassHasItsOwnRealIcon() {
        let icons = FixStyle.allCases.map(\.icon)
        XCTAssertEqual(Set(icons).count, icons.count, "two passes share a mark: \(icons)")
        for style in FixStyle.allCases {
            XCTAssertFalse(style.icon.contains("sparkle"), "\(style.title) wears a sparkle")
            XCTAssertNotNil(
                UIImage(systemName: style.icon), "\(style.title): no such symbol \(style.icon)")
        }
    }

    // MARK: Running one

    /// The engine was asked for the pass the user picked, and the answer
    /// reached the field. Asserting `runningAction` after settle would pin
    /// banner state `applyDirectly` has already cleared.
    func testPickingAPassRunsThatPass() async {
        let engine = FixCallRecorder()
        let target = MockTextTarget(text: "i cant make the standup")
        let controller = makeController(engine: engine, target: target)

        controller.selectFix(named: FixStyle.spelling.title)
        await settleToneController(controller)

        XCTAssertEqual(engine.styles, [.spelling])
        XCTAssertEqual(
            target.text, "fixed",
            "the pass ran and its answer never reached the document")
    }

    func testPickingPolishRunsPolish() async {
        let engine = FixCallRecorder()
        let controller = makeController(engine: engine)

        controller.selectFix(named: FixStyle.polish.title)
        await settleToneController(controller)

        XCTAssertEqual(engine.styles, [.polish])
    }

    /// A tap still proofreads. The popup is how the other three are reached;
    /// a version that ran Spelling on every tap would make the long press the
    /// only way back to the pass the key is named after.
    func testATapProofreads() async {
        let engine = FixCallRecorder()
        let target = MockTextTarget(text: "i cant make the standup")
        let controller = makeController(engine: engine, target: target)

        controller.run(.fix)
        await settleToneController(controller)

        XCTAssertEqual(engine.styles, [.proofread])
        XCTAssertEqual(target.text, "fixed")
    }

    /// A name nothing matches runs nothing, rather than falling through to
    /// proofread the user did not choose.
    func testAnUnknownNameRunsNothing() async {
        let engine = FixCallRecorder()
        let controller = makeController(engine: engine)

        controller.selectFix(named: "Shorter")
        await settleToneController(controller)

        XCTAssertTrue(engine.styles.isEmpty)
    }

    func testAnEmptyFieldRunsNothing() async {
        let engine = FixCallRecorder()
        let controller = KeyboardController(
            target: MockTextTarget(text: ""),
            engine: RoutedIntelligence(onDevice: engine, cloud: nil))

        controller.selectFix(named: FixStyle.spelling.title)
        await settleToneController(controller)

        XCTAssertTrue(engine.styles.isEmpty)
        XCTAssertEqual(controller.block?.action, .fix)
    }

    /// The shipping handler, not just `selectFix`. A test that only calls the
    /// controller method passes on a build where the key is never given one.
    func testTheFixKeyHandlerRunsTheNamedPass() async throws {
        let engine = FixCallRecorder()
        let target = MockTextTarget(text: "i cant make the standup")
        let controller = makeController(engine: engine, target: target)
        let view = KeyboardView(controller: controller)
        let handler = try XCTUnwrap(
            view.alternateHandler(for: KeySpec(.aiFix)),
            "Fix must have a long-press handler")

        handler(FixStyle.punctuate.title)
        await settleToneController(controller)

        XCTAssertEqual(engine.styles, [.punctuate])
        XCTAssertEqual(target.text, "fixed")
    }
}
