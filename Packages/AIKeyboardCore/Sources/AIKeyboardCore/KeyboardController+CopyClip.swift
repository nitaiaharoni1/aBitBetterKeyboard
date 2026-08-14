import UIKit

/// Reads the system pasteboard without putting `UIPasteboard` on
/// `KeyboardController`'s public surface. The ledger is pure; this is the
/// only place that names the board.
enum PasteboardReader {
    static func snapshot() -> (changeCount: Int, rawText: String?) {
        let board = UIPasteboard.general
        return (board.changeCount, board.string)
    }
}

extension KeyboardController {

    /// Snapshot the pasteboard into the ledger. Called on appear, when the
    /// panel opens, and on `UIPasteboard.changedNotification` while this
    /// process is alive. Same `changeCount` is a no-op.
    public func refreshCopyClip() {
        // Re-read the suite, not the published copy. Clear is written in the
        // app. This process stays alive, so `copyclipRecord` is still the
        // list from the last `load()`. Same trap as `storedHaptics`.
        let stored = store.storedCopyclipRecord
        if stored.clips != clips || stored.lastChangeCount != lastChangeCount {
            clips = stored.clips
            lastChangeCount = stored.lastChangeCount
        }
        let snap = PasteboardReader.snapshot()
        let result = ClipboardHistory.reconcile(
            clips: clips,
            changeCount: snap.changeCount,
            lastChangeCount: lastChangeCount,
            rawText: snap.rawText,
            now: Date()
        )
        persistCopyclip(clips: result.clips, lastChangeCount: result.lastChangeCount)
    }

    /// The clips a long press on CopyClip offers, newest first after the rest title.
    ///
    /// **CopyClip leads, because index 0 of an alternates popup is the no-op.**
    /// Lifting without moving opens the panel via `onPress`. An empty ledger is
    /// just that title, so `hasAlternates` stays false and a tap still opens
    /// the empty panel.
    public var copyclipAlternates: [String] {
        [KeyCap.copyclip.accessibilityLabel]
            + clips.prefix(ClipPolicy.quickAccessCount).map(\.text.value)
    }

    /// Inserts the clip whose text the popup drew.
    ///
    /// By the full text rather than by index, for the same reason
    /// `selectTone(named:)` does. A name that is not in the ledger is a stale
    /// popup and a no-op: the overlay does not move.
    public func selectCopyclip(named name: String) {
        guard let clip = clips.first(where: { $0.text.value == name }) else { return }
        insertClip(clip)
    }

    public func insertClip(_ clip: Clip) {
        Feedback.keyPress()
        clearRevertibleEdit()
        Feedback.keyClick(.tock)
        closeGroupedIfCurrentWord()
        if !consumeGroupedSkipLearn() { learnWordJustCommitted() }
        target?.insertText(clip.text.value)
        refreshSuggestions()
        reportInteraction(.copyclip)
    }

    public func removeClip(id: UUID) {
        Feedback.keyPress()
        persistCopyclip(
            clips: ClipboardHistory.remove(id: id, from: clips),
            lastChangeCount: lastChangeCount)
    }

    public func clearClips() {
        Feedback.keyPress()
        persistCopyclip(clips: ClipboardHistory.cleared(), lastChangeCount: lastChangeCount)
    }

    private func persistCopyclip(clips next: [Clip], lastChangeCount nextCount: Int) {
        guard next != clips || nextCount != lastChangeCount else { return }
        clips = next
        lastChangeCount = nextCount
        store.copyclipRecord = CopyclipRecord(clips: next, lastChangeCount: nextCount)
        if overlay == .copyclipSearch {
            setCopyclipQuery(copyclipQuery)
        }
    }
}
