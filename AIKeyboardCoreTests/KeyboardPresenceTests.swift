import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// The evidence the containing app has that its keyboard exists.
///
/// Every test here writes into a scratch directory rather than the App Group,
/// which is why `record(hasFullAccess:at:)` and `load(from:)` take a URL.
///
/// **The reason is not the one this comment used to give.** It said
/// `SharedContainer.url` is nil in this target, matching the state a real keyboard
/// is in before Full Access. Measured 2026-08-16, it is not: the iOS 26 Simulator
/// hands this target a real container despite the missing entitlement, the same
/// way `UserDefaults(suiteName:)` succeeds without one. So reaching the container
/// from a test proves nothing about a device and writes into state the app and
/// keyboard both read. See `KeyboardMemoryPeakTests`, where that was measured.
final class KeyboardPresenceTests: XCTestCase {

    private var directory: URL!
    private var url: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("presence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(KeyboardPresence.fileName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: Absence

    /// A file that is not a record must not decode into one.
    ///
    /// The wrong implementation this rejects is a lenient decode — a hand-rolled
    /// one, or a `Codable` conformance that defaults the fields it cannot find.
    /// `{"hasFullAccess": true}` with no timestamp would come back as a
    /// confirmation stamped zero, and zero is the one value `CaptureClock.elapsed`
    /// treats as infinitely old, so it would tick Full Access and then never
    /// expire. Both halves are asserted, because the decode returning nil is only
    /// half the reason it is safe.
    func testAFileThatIsNotARecordIsNotAConfirmation() throws {
        try Data(#"{"hasFullAccess":true}"#.utf8).write(to: url)
        XCTAssertNil(KeyboardPresence.load(from: url))

        let stampless = SetupState(
            presence: KeyboardPresence(hasFullAccess: true, recordedAt: 0, bootIdentity: 7),
            now: 5_000, bootIdentity: 7)
        XCTAssertEqual(stampless.fullAccess, .unknown)
        XCTAssertEqual(stampless.keyboardAdded, .unknown)
    }

    /// A record written by the build before `bootIdentity` existed has to fail the
    /// decode rather than migrate to a default, because a default would be either
    /// zero — which never matches — or this boot, which would be a fabricated claim
    /// that the previous build's record was written since the last restart.
    func testARecordWithoutABootIdentityDoesNotDecode() throws {
        try Data(#"{"hasFullAccess":true,"recordedAt":1000}"#.utf8).write(to: url)
        XCTAssertNil(KeyboardPresence.load(from: url))
    }

    /// The one thing `bootIdentity` is read from, checked against itself: a value
    /// that changed between two reads inside one test run would make every
    /// confirmation expire immediately, and a zero would make every confirmation
    /// impossible. Neither is a hypothetical — both are what this device would do
    /// if `kern.boottime` were unreadable in an app extension's sandbox.
    func testTheBootIdentityIsReadableAndStable() {
        let first = KeyboardPresence.bootIdentity
        XCTAssertNotEqual(first, 0, "kern.boottime could not be read")
        XCTAssertEqual(first, KeyboardPresence.bootIdentity)
    }

    /// A container the process cannot write to is the keyboard without Full
    /// Access, and it must report failure rather than leaving the caller
    /// believing a record exists.
    func testAnUnwritableContainerRecordsNothing() {
        let unreachable =
            directory
            .appendingPathComponent("no-such-directory", isDirectory: true)
            .appendingPathComponent(KeyboardPresence.fileName)

        XCTAssertFalse(KeyboardPresence.record(hasFullAccess: true, at: unreachable))
        XCTAssertNil(KeyboardPresence.load(from: unreachable))
    }

    // MARK: Presence

    func testRecordingLeavesAReadableRecord() {
        XCTAssertTrue(
            KeyboardPresence.record(hasFullAccess: true, at: url, now: 5_000, bootIdentity: 11))

        let record = KeyboardPresence.load(from: url)
        XCTAssertEqual(record?.hasFullAccess, true)
        XCTAssertEqual(record?.recordedAt, 5_000)
        XCTAssertEqual(record?.bootIdentity, 11)
    }

    // MARK: Cost

    /// The write sits on the keyboard's own launch path, so a record that is
    /// already current must not be rewritten. `record` still reports true: the
    /// question it answers is "does the container hold a record for this run",
    /// not "did I just write one".
    func testACurrentRecordIsNotRewritten() {
        let written = CaptureClock.nanoseconds(10)
        XCTAssertTrue(KeyboardPresence.record(hasFullAccess: true, at: url, now: written))

        let later = written + KeyboardPresence.refreshInterval
        XCTAssertTrue(KeyboardPresence.record(hasFullAccess: true, at: url, now: later))
        XCTAssertEqual(
            KeyboardPresence.load(from: url)?.recordedAt, written,
            "a record inside the refresh interval was rewritten")
    }

    func testAStaleRecordIsRewritten() {
        let written = CaptureClock.nanoseconds(10)
        KeyboardPresence.record(hasFullAccess: true, at: url, now: written)

        let later = written + KeyboardPresence.refreshInterval + 1
        KeyboardPresence.record(hasFullAccess: true, at: url, now: later)
        XCTAssertEqual(KeyboardPresence.load(from: url)?.recordedAt, later)
    }

    // MARK: Self-healing

    /// A run that read `hasFullAccess` as false must not pin the answer until the
    /// refresh interval runs out: a disagreeing flag rewrites the record however
    /// recent it is. This is the whole reason the app may believe a `false` — one
    /// bad reading costs the user one more switch to the keyboard, not six hours
    /// of being told a permission they granted is missing.
    func testADisagreeingFlagRewritesImmediately() {
        let now = CaptureClock.nanoseconds(10)
        KeyboardPresence.record(hasFullAccess: false, at: url, now: now)
        XCTAssertEqual(KeyboardPresence.load(from: url)?.hasFullAccess, false)

        KeyboardPresence.record(hasFullAccess: true, at: url, now: now)
        XCTAssertEqual(
            KeyboardPresence.load(from: url)?.hasFullAccess, true,
            "a flag that disagrees with the stored one has to win, whatever the timestamp says")
    }

    // MARK: The clock

    /// A stamp in the future — a corrupt record, since the boot identity is what
    /// covers restarts now — has to read as "write it again" rather than as
    /// "written zero seconds ago". This is `CaptureClock.elapsed` saturating, and
    /// it is the *easy* direction; the hard one is below and in `SetupStateTests`.
    func testNeedsWritingSaturatesOnAFutureTimestamp() {
        let fromTheFuture = KeyboardPresence(
            hasFullAccess: true, recordedAt: CaptureClock.nanoseconds(9_000), bootIdentity: 3)
        XCTAssertTrue(
            KeyboardPresence.needsWriting(
                over: fromTheFuture, hasFullAccess: true, bootIdentity: 3,
                now: CaptureClock.nanoseconds(4)))
    }

    /// The direction saturation cannot see, on the writing side.
    ///
    /// A record stamped two hours into the previous boot is a *smaller* number than
    /// two hours and one minute of the current boot's uptime, so every age test
    /// passes it. Only the boot identity separates them — and it has to force the
    /// rewrite, or a keyboard in active use spends the first six hours after every
    /// restart unable to refresh the record the reader is refusing, and the card
    /// keeps saying it has never seen the keyboard while the user types on it.
    func testARecordFromAnotherBootIsRewrittenEvenWhenItsStampLooksFresh() {
        let twoHours = CaptureClock.nanoseconds(2 * 60 * 60)
        KeyboardPresence.record(hasFullAccess: true, at: url, now: twoHours, bootIdentity: 100)

        let slightlyLater = twoHours + CaptureClock.nanoseconds(60)
        // The guard the test rests on: the *age* of the record must sit inside the
        // refresh interval, or `needsWriting` would rewrite on staleness alone and
        // this would pass without the boot-identity clause it exists to pin. Sixty
        // seconds against six hours. (It used to compare `refreshInterval` against
        // three hours, which asserted the interval was shorter than it is and
        // failed outright — the age was never the thing being checked.)
        XCTAssertLessThan(
            CaptureClock.elapsed(since: twoHours, now: slightlyLater),
            KeyboardPresence.refreshInterval,
            "this test needs a stamp that is inside the refresh interval to be meaningful")
        KeyboardPresence.record(
            hasFullAccess: true, at: url, now: slightlyLater, bootIdentity: 200)

        let record = KeyboardPresence.load(from: url)
        XCTAssertEqual(record?.bootIdentity, 200, "a record from another boot was left in place")
        XCTAssertEqual(record?.recordedAt, slightlyLater)
    }

    // A test that the record survives `CaptureChannel.sweep` used to sit here and
    // has been deleted rather than kept: `sweep(container:)` removes only
    // *directories* whose name has the prefix `channel`, plus `channel/reading.json`
    // by name, so a JSON file called anything else survives from anywhere this code
    // could plausibly put it — including inside `channel/`. It asserted a property
    // no wrong implementation lacks, which is a test that cannot fail.

    // MARK: The two constants have to be in the right order

    /// The decay ceiling must be longer than the refresh interval, and this is the
    /// assertion rather than the doc comment because getting it backwards has a
    /// silent, intermittent symptom: the keyboard rewrites the record only once
    /// every `refreshInterval`, so a ceiling shorter than that would let a
    /// correctly installed keyboard fall to `.unknown` in the gap between two
    /// writes and tick again on the next use, over and over.
    func testTheConfirmationWindowOutlastsTheRefreshInterval() {
        XCTAssertGreaterThan(
            KeyboardPresence.confirmationWindow, KeyboardPresence.refreshInterval,
            "a record can be up to one refresh interval old on a phone in constant use")
    }
}
