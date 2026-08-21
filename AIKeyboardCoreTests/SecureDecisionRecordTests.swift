import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// The instrument that answers whether any host ever tells this keyboard its
/// field is secure.
///
/// Every test takes an explicit URL rather than reaching `SharedContainer`, for
/// the reason `KeyboardMemoryPeakTests` and `KeyboardLaunchRecordTests` both set
/// out: the simulator hands this target a real App Group container even though it
/// carries no entitlement, so a test against the singleton proves nothing about a
/// device and writes into state the app and keyboard actually share.
final class SecureDecisionRecordTests: XCTestCase {

    private var directory: URL!
    private var url: URL!

    private let boot: UInt64 = 4_242
    private let otherBoot: UInt64 = 5_353

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("secure-decisions-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(SecureDecisionRecord.fileName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    /// The three decisions `SecureField`'s truth table can produce, spelled the
    /// way `ScreenContextSession.permitsRead` spells them.
    private func decision(secure: Bool?, sensitiveType: Bool) -> SecureDecisionRecord.Decision {
        let refusedSecure = secure == true
        return SecureDecisionRecord.Decision(
            answered: secure != nil,
            refusedSecure: refusedSecure,
            refusedContentType: !refusedSecure && sensitiveType)
    }

    // MARK: The number the record exists for

    /// **A silent host has to be told apart from one that says "not secure", and
    /// counting only refusals cannot do it.**
    ///
    /// Both of those decisions permit, so a record that moved only on a refusal
    /// would read as an identical zero for both — which is the question this
    /// exists to answer, answered by accident. `decisions` climbing while
    /// `answered` stays at zero is the reading that says no host implements the
    /// trait.
    func testASilentHostIsCountedAndDistinguishedFromOneThatAnswers() {
        var current = SecureDecisionRecord.merge(
            decision(secure: nil, sensitiveType: false), into: nil, now: 1, bootIdentity: boot)
        current = SecureDecisionRecord.merge(
            decision(secure: nil, sensitiveType: false), into: current, now: 2, bootIdentity: boot)

        XCTAssertEqual(current.decisions, 2)
        XCTAssertEqual(current.answered, 0, "silence must not be counted as an answer")
        XCTAssertEqual(current.permitted, 2, "silence permits, and that is the whole rule")

        current = SecureDecisionRecord.merge(
            decision(secure: false, sensitiveType: false), into: current, now: 3, bootIdentity: boot)
        XCTAssertEqual(current.decisions, 3)
        XCTAssertEqual(
            current.answered, 1,
            "a host saying `false` answered the question and a silent one did not")
        XCTAssertEqual(current.permitted, 3)
    }

    /// The two refusal reasons are separate numbers because they mean different
    /// things: one contradicts Apple's documented behaviour, the other is the
    /// guard catching something iOS does not handle.
    func testTheTwoRefusalReasonsAreCountedApart() {
        var current = SecureDecisionRecord.merge(
            decision(secure: true, sensitiveType: false), into: nil, now: 1, bootIdentity: boot)
        current = SecureDecisionRecord.merge(
            decision(secure: false, sensitiveType: true), into: current, now: 2, bootIdentity: boot)

        XCTAssertEqual(current.decisions, 2)
        XCTAssertEqual(current.refusedSecure, 1)
        XCTAssertEqual(current.refusedContentType, 1)
        XCTAssertEqual(current.permitted, 0)
    }

    /// **`permitted` is arithmetic and stays right only because the two refusal
    /// reasons cannot both fire**, which `SecureField.permitsRead` guarantees by
    /// returning on `secure == true` before it looks at the content type. A field
    /// that is both would otherwise be subtracted twice and this reads −1.
    func testAFieldThatIsBothSecureAndSensitiveIsCountedOnce() {
        let current = SecureDecisionRecord.merge(
            decision(secure: true, sensitiveType: true), into: nil, now: 1, bootIdentity: boot)

        XCTAssertEqual(current.decisions, 1)
        XCTAssertEqual(current.refusedSecure, 1)
        XCTAssertEqual(current.refusedContentType, 0)
        XCTAssertEqual(current.permitted, 0)
    }

    /// The truth table is `SecureField`'s and the helper above is a second
    /// spelling of it, so this asserts they agree rather than trusting the
    /// helper. Without it every test in this file could be right about a rule the
    /// product does not follow.
    func testTheHelperAgreesWithTheTruthTableItRestates() {
        XCTAssertEqual(
            decision(secure: true, sensitiveType: false).refusedSecure,
            !SecureField.permitsRead(secure: true, contentType: nil))
        XCTAssertEqual(
            decision(secure: false, sensitiveType: true).refusedContentType,
            !SecureField.permitsRead(secure: false, contentType: .some(.password)))
        XCTAssertTrue(SecureField.permitsRead(secure: nil, contentType: nil))
        XCTAssertEqual(decision(secure: nil, sensitiveType: false).answered, false)
        XCTAssertEqual(decision(secure: nil, sensitiveType: false).refusedSecure, false)
        XCTAssertEqual(decision(secure: nil, sensitiveType: false).refusedContentType, false)
    }

    // MARK: Boot scoping

    /// A record from a previous boot describes hosts used before the phone
    /// restarted, so it is replaced outright rather than added to. Adding would
    /// report a hundred decisions on a phone that has had one.
    func testAPreviousBootIsReplacedRatherThanAddedTo() {
        let stale = SecureDecisionRecord(
            decisions: 100, answered: 40, refusedSecure: 5, refusedContentType: 3,
            recordedAt: 1, bootIdentity: otherBoot)
        let merged = SecureDecisionRecord.merge(
            decision(secure: nil, sensitiveType: false), into: stale, now: 10, bootIdentity: boot)

        XCTAssertEqual(merged.decisions, 1)
        XCTAssertEqual(merged.answered, 0)
        XCTAssertEqual(merged.refusedSecure, 0)
        XCTAssertEqual(merged.refusedContentType, 0)
        XCTAssertEqual(merged.bootIdentity, boot)
    }

    // MARK: The round trip

    /// What Settings reads is what the keyboard wrote, across the file.
    func testTheRecordSurvivesTheRoundTripThroughTheContainer() {
        SecureDecisionRecord.record(
            decision(secure: nil, sensitiveType: false), at: url, now: 1, bootIdentity: boot)
        SecureDecisionRecord.record(
            decision(secure: true, sensitiveType: false), at: url, now: 2, bootIdentity: boot)
        SecureDecisionRecord.record(
            decision(secure: false, sensitiveType: true), at: url, now: 3, bootIdentity: boot)

        let loaded = SecureDecisionRecord.load(from: url)
        XCTAssertEqual(loaded?.decisions, 3)
        XCTAssertEqual(loaded?.answered, 2)
        XCTAssertEqual(loaded?.refusedSecure, 1)
        XCTAssertEqual(loaded?.refusedContentType, 1)
        XCTAssertEqual(loaded?.permitted, 1)
        XCTAssertEqual(loaded?.bootIdentity, boot)
    }

    /// **No file is not a reading of zero**, and this is the assertion that keeps
    /// Settings honest about it: a zero on that screen would be the question
    /// never asked, read as the question answered no, which is the exact hazard
    /// NIT-187 was filed for.
    func testNoFileReadsAsNilRatherThanAsAZeroedRecord() {
        XCTAssertNil(SecureDecisionRecord.load(from: url))
    }
}
