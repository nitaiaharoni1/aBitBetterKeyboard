import XCTest

@testable import AIKeyboardCore

/// Pure ledger rules. Every assertion names what the broken build would return.
final class CopyClipHistoryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testSameChangeCountIsANoOp() {
        let clip = makeClip("hello", at: now)
        let clips = [clip]
        let result = ClipboardHistory.reconcile(
            clips: clips,
            changeCount: 4,
            lastChangeCount: 4,
            rawText: "other",
            now: now.addingTimeInterval(60)
        )
        XCTAssertEqual(result.clips, clips)
        XCTAssertEqual(result.clips.first?.capturedAt, now)
        XCTAssertEqual(result.lastChangeCount, 4)
    }

    func testEmptyTextUpdatesChangeCountOnly() {
        let clip = makeClip("kept", at: now)
        for raw in [nil, "", "   ", "\n\t"] {
            let result = ClipboardHistory.reconcile(
                clips: [clip],
                changeCount: 8,
                lastChangeCount: 3,
                rawText: raw,
                now: now.addingTimeInterval(10)
            )
            XCTAssertEqual(result.clips, [clip], "raw \(String(describing: raw)) invented a clip")
            XCTAssertEqual(result.lastChangeCount, 8)
        }
    }

    func testTooLongTextIsRejected() {
        let raw = String(repeating: "a", count: ClipPolicy.maxCharacters + 1)
        XCTAssertNil(ClipText(raw: raw))
        let result = ClipboardHistory.reconcile(
            clips: [],
            changeCount: 2,
            lastChangeCount: 1,
            rawText: raw,
            now: now
        )
        XCTAssertEqual(result.clips, [])
        XCTAssertEqual(result.lastChangeCount, 2)
    }

    func testSameTextMovesToFrontAndKeepsId() {
        let older = makeClip("one", id: UUID(), at: now)
        let newer = makeClip("two", id: UUID(), at: now.addingTimeInterval(1))
        let movedAt = now.addingTimeInterval(30)
        let result = ClipboardHistory.reconcile(
            clips: [older, newer],
            changeCount: 5,
            lastChangeCount: 4,
            rawText: "two",
            now: movedAt
        )
        XCTAssertEqual(result.clips.map(\.id), [newer.id, older.id])
        XCTAssertEqual(result.clips.first?.text.value, "two")
        XCTAssertEqual(result.clips.first?.capturedAt, movedAt)
        XCTAssertEqual(result.lastChangeCount, 5)
    }

    func testNewTextPrependsAndCapsAtFifty() {
        let existing = (0..<ClipPolicy.maxClips).map { index in
            makeClip("clip-\(index)", at: now.addingTimeInterval(TimeInterval(index)))
        }
        let result = ClipboardHistory.reconcile(
            clips: existing,
            changeCount: 20,
            lastChangeCount: 19,
            rawText: "fresh",
            now: now.addingTimeInterval(100)
        )
        XCTAssertEqual(result.clips.count, ClipPolicy.maxClips)
        XCTAssertEqual(result.clips.first?.text.value, "fresh")
        XCTAssertFalse(
            result.clips.contains { $0.text.value == existing.last?.text.value },
            "the 51st clip was kept")
    }

    func testRemoveDropsOnlyThatClip() {
        let keep = makeClip("keep")
        let drop = makeClip("drop")
        XCTAssertEqual(ClipboardHistory.remove(id: drop.id, from: [keep, drop]), [keep])
    }

    func testClearEmptiesTheLedger() {
        XCTAssertEqual(ClipboardHistory.cleared(), [])
        XCTAssertEqual(
            ClipboardHistory.remove(id: UUID(), from: ClipboardHistory.cleared()), [])
    }

    /// Clear writes an empty list and keeps the cursor. A later snapshot of
    /// the same board must not put the deleted string back.
    func testAClearedBoardDoesNotReturnOnTheSameChangeCount() {
        let result = ClipboardHistory.reconcile(
            clips: [],
            changeCount: 7,
            lastChangeCount: 7,
            rawText: "hello",
            now: now
        )
        XCTAssertEqual(result.clips, [], "Clear lost: the current board came back")
        XCTAssertEqual(result.lastChangeCount, 7)
    }

    func testAPersistedCursorSurvivesAReread() throws {
        let suite = "CopyClipStoreTests.cursor"
        UserDefaults().removePersistentDomain(forName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let record = CopyclipRecord(clips: [], lastChangeCount: 7)
        defaults.set(try JSONEncoder().encode(record), forKey: SharedStore.copyclipHistoryKey)
        let decoded = SharedStore.decodeCopyclipRecord(from: defaults)
        XCTAssertEqual(decoded.clips, [], "Clear lost: the stored list was not empty")
        XCTAssertEqual(decoded.lastChangeCount, 7, "the cursor did not survive the reread")
    }

    func testAnOldClipArrayDecodesWithoutACursor() throws {
        let suite = "CopyClipStoreTests.legacy"
        UserDefaults().removePersistentDomain(forName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let clip = Clip(id: UUID(), text: ClipText(raw: "hello")!, capturedAt: now)
        defaults.set(try JSONEncoder().encode([clip]), forKey: SharedStore.copyclipHistoryKey)
        let decoded = SharedStore.decodeCopyclipRecord(from: defaults)
        XCTAssertEqual(decoded.clips, [clip])
        XCTAssertEqual(
            decoded.lastChangeCount, -1,
            "a pre-record list must snapshot again, not pretend it already saw the board")
    }

    func testMatchingEmptyQueryReturnsTheLedgerInOrder() {
        let newer = makeClip("hello")
        let older = makeClip("world")
        XCTAssertEqual(
            ClipboardHistory.matching(query: "", in: [newer, older]),
            [newer, older],
            "an empty query must open on the full list, the way emoji opens on recents")
        XCTAssertEqual(ClipboardHistory.matching(query: "   ", in: [newer, older]), [newer, older])
    }

    func testMatchingFiltersByLocalizedContains() {
        let hello = makeClip("Hello there")
        let goodbye = makeClip("goodbye")
        let shalom = makeClip("שלום עליכם")
        let clips = [hello, goodbye, shalom]
        XCTAssertEqual(
            ClipboardHistory.matching(query: "hello", in: clips).map(\.id),
            [hello.id],
            "case-insensitive contains missed a clip the broken filter would drop")
        XCTAssertEqual(ClipboardHistory.matching(query: "שלו", in: clips).map(\.id), [shalom.id])
        XCTAssertEqual(
            ClipboardHistory.matching(query: "xyz", in: clips),
            [],
            "a miss must be empty, not the full list")
    }

    func testInvalidStoredClipTextDoesNotBecomeAClip() throws {
        let suite = "CopyClipStoreTests.invalid"
        UserDefaults().removePersistentDomain(forName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let json = Data(
            #"{"clips":[{"id":"00000000-0000-0000-0000-000000000000","text":{"value":"   "},"capturedAt":0}],"lastChangeCount":3}"#
                .utf8)
        defaults.set(json, forKey: SharedStore.copyclipHistoryKey)
        let decoded = SharedStore.decodeCopyclipRecord(from: defaults)
        XCTAssertEqual(decoded, .empty, "whitespace-only clip text was accepted")
    }

    // MARK: Hebrew

    /// **Reported from a phone as "CopyClip does not remember Hebrew", and the
    /// ledger was never the reason.** The cause was that the panel could not see
    /// a copy made while it was open (`CopyClipModeTests`), and long-press-to-copy
    /// — which is how a Hebrew message leaves a chat app — is exactly the gesture
    /// that leaves the keyboard up. This is here so the half that was *not* at
    /// fault stays measured rather than remembered.
    ///
    /// The whole path in one test, because each stage could drop it on its own:
    /// validation, the ledger, the JSON the store actually writes, dedup, and
    /// search.
    func testHebrewSurvivesTheWholePathFromPasteboardToStoredLedger() throws {
        let hebrew = "שלום, מה נשמע?"
        let sentence = "אני מגיע בעוד רבע שעה, נתראה"

        let first = ClipboardHistory.reconcile(
            clips: [], changeCount: 1, lastChangeCount: -1, rawText: hebrew, now: now)
        XCTAssertEqual(
            first.clips.first?.text.value, hebrew,
            "Hebrew must reach the ledger with not one character changed")

        let second = ClipboardHistory.reconcile(
            clips: first.clips, changeCount: 2, lastChangeCount: 1, rawText: sentence, now: now)
        XCTAssertEqual(second.clips.count, 2)

        let record = CopyclipRecord(clips: second.clips, lastChangeCount: 2)
        let data = try JSONEncoder().encode(record)
        let back = try JSONDecoder().decode(CopyclipRecord.self, from: data)
        XCTAssertEqual(
            back.clips.map(\.text.value), [sentence, hebrew],
            "the round trip the store performs on every write must not lose it")

        let again = ClipboardHistory.reconcile(
            clips: back.clips, changeCount: 3, lastChangeCount: 2, rawText: hebrew, now: now)
        XCTAssertEqual(again.clips.count, 2, "re-copying Hebrew must not make a duplicate")
        XCTAssertEqual(again.clips.first?.id, first.clips.first?.id, "and must keep its identity")

        XCTAssertEqual(ClipboardHistory.matching(query: "נשמע", in: again.clips).count, 1)
    }

    /// A chat app can put its bubble's own bidi formatting on the board with the
    /// text. Those marks are neither whitespace nor newlines, so the trim leaves
    /// them and the clip is valid — asserted because the opposite would be a
    /// silent, script-specific drop, which is precisely what the report sounded
    /// like.
    func testHebrewCarryingBidiMarksIsStillAValidClip() throws {
        let plain = "שלום"
        for wrapped in ["\u{2067}\(plain)\u{2069}", "\u{200F}\(plain)", "\(plain)\u{200E}"] {
            let text = try XCTUnwrap(ClipText(raw: wrapped), "bidi-marked Hebrew was refused")
            XCTAssertTrue(text.value.contains(plain))
        }
    }

    private func makeClip(
        _ raw: String, id: UUID = UUID(), at date: Date? = nil
    ) -> Clip {
        Clip(id: id, text: ClipText(raw: raw)!, capturedAt: date ?? now)
    }
}
