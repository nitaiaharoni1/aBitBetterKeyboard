import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// The instrument that says whether the keyboard is being killed for memory.
///
/// Every test writes into a scratch directory rather than the App Group, and the
/// reason is sharper than the one `KeyboardPresenceTests` states. That file says
/// this target has no App Group entitlement and therefore `SharedContainer.url`
/// is nil in it. The first half is true and the second is **not**, measured
/// 2026-08-16: on the iOS 26 Simulator the property answers with a real container
/// path here, and an earlier version of this class proved it by writing a record
/// into the shared container the app and keyboard actually use.
///
/// That is the simulator declining to enforce App Group entitlements, the same
/// way `UserDefaults(suiteName:)` succeeds without one — the fact `AGENTS.md`
/// already records about proving the App Group. So a test here that reaches the
/// container proves nothing about a device *and* writes into shared state other
/// tests read. Every one of these takes an explicit URL, which is what
/// `record(_:at:)` and `load(from:)` exist for.
final class KeyboardMemoryPeakTests: XCTestCase {

    private var directory: URL!
    private var url: URL!

    private let boot: UInt64 = 4_242

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-peak-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(KeyboardMemoryPeak.fileName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func reading(footprint: Double, peak: Double?, headroom: Double? = nil) -> MemoryReading {
        MemoryReading(footprintMB: footprint, peakMB: peak, headroomMB: headroom)
    }

    // MARK: The reading itself

    /// The three revision thresholds, against the arithmetic in `task_info.h`.
    ///
    /// **This is the assertion that catches a wrong struct layout**, which is the
    /// one way a versioned C struct read through Swift goes silently wrong: the
    /// call still returns `KERN_SUCCESS`, the numbers still look like numbers, and
    /// they are whichever field happens to sit at the offset that was guessed.
    /// `REV1_COUNT` is 38 and `REV4_COUNT` is 86 as the header computes them, and
    /// 44 is `ledger_phys_footprint_peak`'s own end rather than rev3's 84 — see
    /// `MemoryReading` for why the difference is deliberate.
    func testTheRevisionThresholdsMatchTheKernelHeader() {
        XCTAssertEqual(MemoryReading.unitsThroughFootprint, 38)
        XCTAssertEqual(MemoryReading.unitsThroughPeak, 44)
        XCTAssertEqual(MemoryReading.unitsThroughHeadroom, 86)

        let full = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        XCTAssertGreaterThanOrEqual(
            full, MemoryReading.unitsThroughHeadroom,
            "the struct this build compiled against cannot hold the fields being read from it")
    }

    /// The real kernel call, not a stub.
    ///
    /// **The rejecting assertion is `peak >= footprint`.** A process cannot have
    /// been smaller at its largest than it is now, so any reading that fails it is
    /// two fields read from the wrong offsets — which is precisely what a
    /// `count`-check that was written by eye rather than from the layout produces,
    /// and it produces it without any error the caller could notice.
    func testTheRealReadingIsSelfConsistent() throws {
        let live = try XCTUnwrap(MemoryReading.current(), "task_info(TASK_VM_INFO) would not answer")

        XCTAssertGreaterThan(live.footprintMB, 1, "a running process occupies more than a megabyte")
        XCTAssertLessThan(live.footprintMB, 8_192, "and less than eight gigabytes")

        let peak = try XCTUnwrap(live.peakMB, "the kernel filled no ledger peak")
        XCTAssertGreaterThanOrEqual(
            peak, live.footprintMB, "a peak below the current footprint is a misread offset")
        XCTAssertLessThan(peak, 8_192)
    }

    /// Headroom is expected to be nil everywhere this suite can run, and the code
    /// must say nil rather than zero.
    ///
    /// `limit_bytes_remaining` reads 0 on macOS and on the iOS Simulator because
    /// neither applies a footprint limit to the asking process. Zero megabytes
    /// remaining would mean a process that is already dead, so reporting the zero
    /// verbatim would put "0 MB to spare" on the Settings screen of a keyboard in
    /// perfect health. This is a characterisation: if it ever starts answering
    /// here, that is worth knowing and this test is where it surfaces.
    func testAnUnansweredHeadroomIsNilRatherThanZero() throws {
        let live = try XCTUnwrap(MemoryReading.current())
        if let headroom = live.headroomMB {
            XCTAssertGreaterThan(headroom, 0, "zero headroom must never be reported as a value")
        }
    }

    // MARK: The peak only climbs

    /// **The one rule the record exists to keep.** The interesting reading is the
    /// excursion, and the visits either side of it are ordinary; a merge that
    /// simply stored the newest number would have the calm visit after the spike
    /// delete the only evidence there was.
    ///
    /// Both halves are asserted. The stored peak stays at 47, and the merge
    /// returns nil for the smaller reading — a build that returned a record
    /// carrying the *unchanged* peak would keep the number right and rewrite the
    /// file on every appearance of the keyboard, which is the same defect wearing
    /// the correct answer.
    func testACalmerVisitNeitherLowersThePeakNorRewritesTheFile() {
        let spike = KeyboardMemoryPeak.merge(
            reading(footprint: 30, peak: 47), into: nil, warning: false, now: 1, bootIdentity: boot)
        XCTAssertEqual(spike?.peakMB, 47)

        let calm = KeyboardMemoryPeak.merge(
            reading(footprint: 18, peak: 22), into: spike, warning: false, now: 2,
            bootIdentity: boot)
        XCTAssertNil(calm, "nothing moved, so nothing should be written")
    }

    /// A higher peak does move it, which is the control on the test above: an
    /// implementation that returned nil unconditionally would pass that one.
    func testAHigherPeakIsRecorded() {
        let first = KeyboardMemoryPeak.merge(
            reading(footprint: 20, peak: 24), into: nil, warning: false, now: 1, bootIdentity: boot)
        let second = KeyboardMemoryPeak.merge(
            reading(footprint: 40, peak: 51), into: first, warning: false, now: 2,
            bootIdentity: boot)
        XCTAssertEqual(second?.peakMB, 51)
    }

    /// A kernel that filled no ledger peak still leaves the current footprint,
    /// which is a floor under the peak rather than a guess at it.
    func testAMissingLedgerPeakFallsBackToTheFootprint() {
        let record = KeyboardMemoryPeak.merge(
            reading(footprint: 33, peak: nil), into: nil, warning: false, now: 1, bootIdentity: boot)
        XCTAssertEqual(record?.peakMB, 33)
    }

    // MARK: Headroom takes the minimum, and nil is not a minimum

    /// Headroom moves the opposite way to the peak, so the record keeps the
    /// smallest.
    func testTheSmallestHeadroomIsKept() {
        let first = KeyboardMemoryPeak.merge(
            reading(footprint: 20, peak: 24, headroom: 30), into: nil, warning: false, now: 1,
            bootIdentity: boot)
        let tighter = KeyboardMemoryPeak.merge(
            reading(footprint: 30, peak: 34, headroom: 6), into: first, warning: false, now: 2,
            bootIdentity: boot)
        XCTAssertEqual(tighter?.headroomMB, 6)

        let roomier = KeyboardMemoryPeak.merge(
            reading(footprint: 21, peak: 25, headroom: 28), into: tighter, warning: false, now: 3,
            bootIdentity: boot)
        XCTAssertNil(roomier, "6 MB is still the tightest this boot has been")
    }

    /// **A reading that could not measure must not erase one that could.** This is
    /// the `min` over optionals that goes wrong by default in most languages and
    /// in one obvious Swift spelling of it: nil sorting below every number would
    /// make the first unanswered reading wipe a 6 MB record and replace it with
    /// "never measured", which is the reading that matters being deleted by the
    /// one that is not a reading at all.
    func testAnUnmeasuredHeadroomDoesNotWipeAMeasuredOne() {
        let measured = KeyboardMemoryPeak.merge(
            reading(footprint: 30, peak: 34, headroom: 6), into: nil, warning: false, now: 1,
            bootIdentity: boot)
        XCTAssertEqual(measured?.headroomMB, 6)

        let blind = KeyboardMemoryPeak.merge(
            reading(footprint: 31, peak: 35, headroom: nil), into: measured, warning: false, now: 2,
            bootIdentity: boot)
        XCTAssertEqual(blind?.headroomMB, 6, "an unanswered field is not a smaller answer")
        XCTAssertEqual(blind?.peakMB, 35, "and the peak still climbed on the same reading")
    }

    // MARK: Warnings

    /// The count accumulates. A build that stored `warning ? 1 : 0` would report
    /// one warning forever, which reads as a single unlucky moment rather than as
    /// a keyboard under constant pressure.
    func testMemoryWarningsAccumulate() {
        var record = KeyboardMemoryPeak.merge(
            reading(footprint: 40, peak: 44), into: nil, warning: true, now: 1, bootIdentity: boot)
        XCTAssertEqual(record?.warnings, 1)

        record = KeyboardMemoryPeak.merge(
            reading(footprint: 20, peak: 22), into: record, warning: true, now: 2,
            bootIdentity: boot)
        XCTAssertEqual(record?.warnings, 2, "the second warning arrived on a calmer reading")
    }

    /// A warning is always worth writing, even when it moves no number. It is the
    /// one signal iOS sends ahead of a kill, and the reading beside it is often
    /// unremarkable because the spike that triggered it has already been released.
    func testAWarningIsWrittenEvenWhenNoNumberMoved() {
        let quiet = KeyboardMemoryPeak.merge(
            reading(footprint: 30, peak: 47), into: nil, warning: false, now: 1, bootIdentity: boot)
        let warned = KeyboardMemoryPeak.merge(
            reading(footprint: 18, peak: 22), into: quiet, warning: true, now: 2, bootIdentity: boot)
        XCTAssertEqual(warned?.warnings, 1)
        XCTAssertEqual(warned?.peakMB, 47, "and the warning did not disturb the peak")
    }

    // MARK: Boots

    /// A record from another boot is replaced outright, however high its peak.
    ///
    /// The alternative — carrying the all-time maximum forever — keeps a number
    /// nobody can reproduce: memory pressure is a property of what else the phone
    /// was doing that day. It would also strand `recordedAt`, which is
    /// `CLOCK_MONOTONIC_RAW` and means nothing across a restart. See
    /// `KeyboardPresence`, which was bitten by exactly that.
    func testANewBootStartsAgainEvenIfThatLowersThePeak() {
        let old = KeyboardMemoryPeak.merge(
            reading(footprint: 50, peak: 58), into: nil, warning: true, now: 1, bootIdentity: boot)
        XCTAssertEqual(old?.peakMB, 58)

        let fresh = KeyboardMemoryPeak.merge(
            reading(footprint: 12, peak: 15), into: old, warning: false, now: 2,
            bootIdentity: boot &+ 1)
        XCTAssertEqual(fresh?.peakMB, 15, "a peak from a previous boot is a different experiment")
        XCTAssertEqual(fresh?.warnings, 0, "and so are its warnings")
    }

    // MARK: Through a real file

    /// The round trip the keyboard and the app actually make, across a file.
    ///
    /// Asserted through `load(from:)` rather than through the returned value,
    /// because the value is right in a build that never writes.
    func testTheRecordSurvivesTheTripThroughTheContainer() {
        KeyboardMemoryPeak.record(
            reading(footprint: 30, peak: 47, headroom: 9), at: url, now: 1, bootIdentity: boot)

        let stored = KeyboardMemoryPeak.load(from: url)
        XCTAssertEqual(stored?.peakMB, 47)
        XCTAssertEqual(stored?.headroomMB, 9)
        XCTAssertEqual(stored?.bootIdentity, boot)

        KeyboardMemoryPeak.record(
            reading(footprint: 12, peak: 14), warning: true, at: url, now: 2, bootIdentity: boot)

        let after = KeyboardMemoryPeak.load(from: url)
        XCTAssertEqual(after?.peakMB, 47, "the calmer visit must not have overwritten the spike")
        XCTAssertEqual(after?.headroomMB, 9)
        XCTAssertEqual(after?.warnings, 1)
    }

    /// A file that is not a record must not decode into one. The lenient decode
    /// this rejects would put a peak of zero on the Settings screen and read as a
    /// keyboard that has never used any memory at all.
    func testAFileThatIsNotARecordDoesNotDecode() throws {
        try Data(#"{"peakMB":41}"#.utf8).write(to: url)
        XCTAssertNil(KeyboardMemoryPeak.load(from: url))
    }

    /// Nowhere to write is the state of every keyboard without Full Access, and a
    /// failed write must report that rather than the record it wanted to make.
    ///
    /// The rejecting assertion is on the **return value** of `record`, not on the
    /// absence of the file. The obvious wrong implementation builds the merged
    /// record, tries the write, ignores the error and hands the caller the record
    /// it built — which puts a peak on the Settings screen that is on no disk
    /// anywhere and vanishes at the next launch.
    ///
    /// A directory that does not exist stands in for the missing container. It
    /// cannot be `SharedContainer.url` being nil: on the simulator that property
    /// answers with a real path in this target, which has no App Group
    /// entitlement — see the note on this class.
    func testAFailedWriteReportsNothingRatherThanTheRecordItWanted() {
        let unreachable =
            directory
            .appendingPathComponent("no-such-directory", isDirectory: true)
            .appendingPathComponent(KeyboardMemoryPeak.fileName)

        XCTAssertNil(KeyboardMemoryPeak.load(from: unreachable))
        XCTAssertNil(
            KeyboardMemoryPeak.record(reading(footprint: 20, peak: 24), at: unreachable),
            "a write that failed must not answer with the record it built")
    }
}
