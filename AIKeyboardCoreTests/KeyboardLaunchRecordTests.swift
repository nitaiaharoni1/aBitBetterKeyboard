import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// The instrument that says whether the keyboard was asked for and did not
/// arrive.
///
/// Every test takes an explicit URL rather than reaching `SharedContainer`, for
/// the reason `KeyboardMemoryPeakTests` sets out in full: the simulator hands
/// this target a real App Group container even though it carries no entitlement,
/// so a test against the singleton proves nothing about a device and writes into
/// state the app and keyboard actually share.
final class KeyboardLaunchRecordTests: XCTestCase {

    private var directory: URL!
    private var url: URL!

    private let boot: UInt64 = 7_777
    private let otherBoot: UInt64 = 8_888

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("launch-record-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(KeyboardLaunchRecord.fileName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func record(
        loads: Int, presentations: Int, slowest: Double = 0, last: Double = 0,
        boot: UInt64? = nil
    ) -> KeyboardLaunchRecord {
        KeyboardLaunchRecord(
            loads: loads, presentations: presentations, slowestPresentMS: slowest,
            lastPresentMS: last, recordedAt: 1, bootIdentity: boot ?? self.boot)
    }

    // MARK: The counters

    /// The whole point of the record, and the assertion a broken version fails.
    ///
    /// A launch that began and never reached the screen is the shape the device
    /// report described. A merge that counted `.loaded` into both counters, or
    /// into neither, would leave `loads == presentations` here — which reads as
    /// "every launch arrived" over the one case this exists to catch.
    func testALoadThatNeverPresentsLeavesTheCountersApart() {
        let loaded = KeyboardLaunchRecord.merge(
            .loaded, into: nil, now: 10, bootIdentity: boot)
        XCTAssertEqual(loaded.loads, 1)
        XCTAssertEqual(loaded.presentations, 0)

        let presented = KeyboardLaunchRecord.merge(
            .presented(millis: 40), into: loaded, now: 20, bootIdentity: boot)
        XCTAssertEqual(presented.loads, 1)
        XCTAssertEqual(presented.presentations, 1)
    }

    /// Both counters climb across launches, so the *ratio* survives to be read.
    ///
    /// Asserted on three launches with one failure in the middle rather than on
    /// one, because a merge that overwrote instead of accumulating would still
    /// pass a single-launch test.
    func testCountersAccumulateAcrossLaunchesWithinABoot() {
        var current = KeyboardLaunchRecord.merge(.loaded, into: nil, now: 1, bootIdentity: boot)
        current = KeyboardLaunchRecord.merge(
            .presented(millis: 30), into: current, now: 2, bootIdentity: boot)
        current = KeyboardLaunchRecord.merge(.loaded, into: current, now: 3, bootIdentity: boot)
        current = KeyboardLaunchRecord.merge(.loaded, into: current, now: 4, bootIdentity: boot)
        current = KeyboardLaunchRecord.merge(
            .presented(millis: 50), into: current, now: 5, bootIdentity: boot)

        XCTAssertEqual(current.loads, 3)
        XCTAssertEqual(current.presentations, 2)
    }

    // MARK: The timing

    /// The excursion is the reading, so a later, faster launch must not delete
    /// it.
    ///
    /// The same rule `KeyboardMemoryPeak` keeps for its peak. `lastPresentMS`
    /// moves to the new value in the same merge, which is what tells a reader
    /// whether the slowest was a one-off.
    func testASlowLaunchSurvivesTheFastOnesAfterIt() {
        var current = KeyboardLaunchRecord.merge(
            .presented(millis: 400), into: nil, now: 1, bootIdentity: boot)
        current = KeyboardLaunchRecord.merge(
            .presented(millis: 12), into: current, now: 2, bootIdentity: boot)

        XCTAssertEqual(current.slowestPresentMS, 400)
        XCTAssertEqual(current.lastPresentMS, 12)
    }

    /// A clock that appeared to run backwards must not make the slowest launch
    /// look instant. `CLOCK_MONOTONIC_RAW` does not do this; the clamp is what
    /// stops a bad subtraction poisoning the one field that matters.
    func testANegativeDurationIsClampedRatherThanStored() {
        let merged = KeyboardLaunchRecord.merge(
            .presented(millis: -5), into: nil, now: 1, bootIdentity: boot)
        XCTAssertEqual(merged.lastPresentMS, 0)
        XCTAssertEqual(merged.slowestPresentMS, 0)
    }

    // MARK: Boot scoping

    /// A record from a previous boot describes an experiment nobody can
    /// reproduce, so it is replaced outright rather than added to.
    ///
    /// The counters are the assertion: adding to them would report six launches
    /// on a phone that has had one since it restarted.
    func testAPreviousBootIsReplacedRatherThanAddedTo() {
        let stale = record(loads: 5, presentations: 5, slowest: 900, last: 900, boot: otherBoot)
        let merged = KeyboardLaunchRecord.merge(
            .loaded, into: stale, now: 10, bootIdentity: boot)

        XCTAssertEqual(merged.loads, 1)
        XCTAssertEqual(merged.presentations, 0)
        XCTAssertEqual(merged.slowestPresentMS, 0)
        XCTAssertEqual(merged.bootIdentity, boot)
    }

    /// A stale slow launch does not survive into this boot's timing either.
    ///
    /// Asserted separately from the counters because `slowestPresentMS` is the
    /// one field whose rule is "never lower it", and a merge that applied that
    /// rule *across* boots would carry last week's 900 ms forward forever, into
    /// a reading nobody could reproduce.
    func testAPreviousBootsSlowLaunchDoesNotSurviveIntoThisOne() {
        let stale = record(loads: 5, presentations: 5, slowest: 900, last: 900, boot: otherBoot)
        let merged = KeyboardLaunchRecord.merge(
            .presented(millis: 20), into: stale, now: 10, bootIdentity: boot)

        XCTAssertEqual(merged.slowestPresentMS, 20)
        XCTAssertEqual(merged.bootIdentity, boot)
    }

    // MARK: The round trip

    /// What the app reads is what the keyboard wrote, across the file.
    func testTheRecordSurvivesTheRoundTripThroughTheContainer() {
        KeyboardLaunchRecord.record(.loaded, at: url, now: 1, bootIdentity: boot)
        KeyboardLaunchRecord.record(.presented(millis: 120), at: url, now: 2, bootIdentity: boot)
        KeyboardLaunchRecord.record(.loaded, at: url, now: 3, bootIdentity: boot)

        let loaded = KeyboardLaunchRecord.load(from: url)
        XCTAssertEqual(loaded?.loads, 2)
        XCTAssertEqual(loaded?.presentations, 1)
        XCTAssertEqual(loaded?.slowestPresentMS, 120)
        XCTAssertEqual(loaded?.bootIdentity, boot)
    }

    /// No file is not a reading of zero, and must not be rendered as one.
    func testNoFileReadsAsNilRatherThanAsAZeroedRecord() {
        XCTAssertNil(KeyboardLaunchRecord.load(from: url))
    }
}
