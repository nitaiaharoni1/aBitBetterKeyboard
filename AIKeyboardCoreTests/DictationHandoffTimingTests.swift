import Foundation
import XCTest

@testable import AIKeyboardCore

/// Unit tests for the shared-store dictation handoff timestamp contract.
///
/// Uses the internal date seams so the clock is not the variable under test:
/// `recordDictationHandoff(at:)` and `consumeDictationHandoff(at:)` accept an
/// explicit `Date`, which the public no-argument overloads call with `Date()`.
///
/// Every case cleans up its key in `tearDown` so run order does not matter.
final class DictationHandoffTimingTests: XCTestCase {

    private let store = SharedStore.shared

    override func tearDown() {
        super.tearDown()
        store.defaults.removeObject(forKey: SharedStore.Key.dictationHandoffRequest)
    }

    // MARK: Fresh one-shot consumption

    /// A record consumed within 30 seconds returns `true` exactly once — the
    /// key is deleted on consume, so a second call in the same session is `false`.
    func testFreshHandoffIsConsumedExactlyOnce() {
        let written = Date()
        store.recordDictationHandoff(at: written)

        XCTAssertTrue(
            store.consumeDictationHandoff(at: written.addingTimeInterval(5)),
            "a 5-second-old handoff is fresh and must return true")
        XCTAssertFalse(
            store.consumeDictationHandoff(at: written.addingTimeInterval(5)),
            "second consume of the same record must return false: key was already removed")
    }

    // MARK: 30-second boundary / stale rejection

    /// 29.9 s is within the window; 30 s is not (`age < 30`, strict).
    func testHandoffIsStaleAtExactly30Seconds() {
        let written = Date()

        store.recordDictationHandoff(at: written)
        XCTAssertTrue(
            store.consumeDictationHandoff(at: written.addingTimeInterval(29.9)),
            "29.9 s is strictly less than 30 and must be accepted")

        store.recordDictationHandoff(at: written)
        XCTAssertFalse(
            store.consumeDictationHandoff(at: written.addingTimeInterval(30)),
            "exactly 30 s is not < 30 and must be rejected")

        store.recordDictationHandoff(at: written)
        XCTAssertFalse(
            store.consumeDictationHandoff(at: written.addingTimeInterval(60)),
            "a minute-old request must be rejected")
    }

    // MARK: Future timestamp rejection

    /// A record whose timestamp is *later* than the consume date has negative
    /// age and must not trigger an auto-start (clock skew or tampered store).
    func testFutureTimestampIsRejected() {
        let now = Date()
        store.recordDictationHandoff(at: now.addingTimeInterval(1))
        XCTAssertFalse(
            store.consumeDictationHandoff(at: now),
            "a future timestamp has negative age and must be rejected")
    }

    // MARK: No record

    func testConsumeWithNoRecordReturnsFalse() {
        XCTAssertFalse(
            store.consumeDictationHandoff(at: Date()),
            "consume with nothing stored must return false without crashing")
    }
}
