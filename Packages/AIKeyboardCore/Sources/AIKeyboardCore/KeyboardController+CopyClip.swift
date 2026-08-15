import UIKit

/// Reads the system pasteboard without putting `UIPasteboard` on
/// `KeyboardController`'s public surface. The ledger is pure; this is the
/// only place that names the board.
///
/// **Split into three calls on purpose, because iOS charges for them
/// differently and the previous shape charged for all of them at once.** Since
/// iOS 16 the first read of the *contents* of a board another app filled raises
/// the system "Allow Paste?" alert. `snapshot()` returned the generation and
/// the string together, so every caller paid the alert even when all it wanted
/// to know was whether anything had moved. They are separate now and each one
/// carries what it costs.
enum PasteboardReader {
    /// The board's generation. **The only member a passive refresh may call**,
    /// and the only one Apple documents as free of any consent step: it is a
    /// counter, not content. Everything the keyboard does on appear is decided
    /// from this.
    static var changeCount: Int { UIPasteboard.general.changeCount }

    /// Whether the board holds text at all.
    ///
    /// Metadata rather than content, and it exists to skip a *pointless* alert:
    /// a copied screenshot can never become a clip, so opening CopyClip over one
    /// should ask for nothing. It is deliberately reached only from inside the
    /// `userAsked` path even so — Apple documents `detectPatterns(for:)` as
    /// requiring no permission and says nothing either way about `hasStrings`,
    /// so nothing that has to be silent is allowed to depend on it.
    static var holdsText: Bool { UIPasteboard.general.hasStrings }

    /// **The call that raises "Allow Paste?", and it blocks the main thread
    /// until the user answers it.** Only `CopyClipRefresh.userAsked` reaches it.
    static func text() -> String? { UIPasteboard.general.string }
}

/// Whether a refresh is allowed to look at what is *on* the board.
///
/// The distinction exists because reading the contents raises a system alert
/// and reading the generation does not, so "has anything moved" and "show me
/// what moved" have to be separate questions. See `refreshCopyClip(_:)`.
public enum CopyClipRefresh {
    /// The keyboard came up, or a setting was re-read. Syncs the ledger with
    /// the shared container and reads `changeCount`. **Nothing else**, so it
    /// cannot prompt however iOS chooses to treat the other accessors.
    case passive
    /// The user opened CopyClip. Reading the board is the thing they asked
    /// for, so this is the one path allowed to prompt.
    case userAsked
}

extension KeyboardController {

    /// Reconcile the ledger, reading the board's contents only when asked to.
    ///
    /// **The keyboard used to snapshot the contents on every appearance, and
    /// that is what put "Allow Paste?" in front of somebody who had only tapped
    /// a text field.** `viewWillAppear` runs on every focused field and every
    /// host app, so a single copy in Safari bought an alert on the next
    /// keystroke session, and a session that copied nothing still paid a read.
    /// No *read* avoids the alert — `detectPatterns(for:)` answers what kind of
    /// thing is on the board without prompting but never the value, and
    /// `detectValues(for:)` prompts like a plain read — so the only lever a read
    /// has is *when* it is spent. It is spent when CopyClip opens, which is the
    /// moment the user asked for their clipboard, and at most once per copied
    /// item because the generation is the cursor. A refusal costs nothing
    /// further: `.string` comes back nil, `reconcile` advances the cursor on it,
    /// and that generation is never asked about again.
    ///
    /// The cost is honest and worth stating: two copies between two openings
    /// leave only the second in the ledger. Auto-capture and no-alert are
    /// mutually exclusive for anything built on a *read*, and this trade picks
    /// the one the user does not have to dismiss.
    ///
    /// **The one genuinely alert-free route is `UIPasteControl`**, iOS 16's
    /// system paste button, which grants access on its own tap. It is not used
    /// here yet, and the reason is a real trade rather than an oversight: it is
    /// a system-drawn control with its own styling, it would have to sit inside
    /// a panel whose cards are deliberately letter keys, and it turns one alert
    /// per copied item into one tap per capture. Reach for it if the alert on
    /// open ever proves to be the thing people complain about.
    public func refreshCopyClip(_ refresh: CopyClipRefresh = .passive) {
        // Re-read the suite, not the published copy. Clear is written in the
        // app. This process stays alive, so `copyclipRecord` is still the
        // list from the last `load()`. Same trap as `storedHaptics`.
        let stored = store.storedCopyclipRecord
        if stored.clips != clips || stored.lastChangeCount != lastChangeCount {
            clips = stored.clips
            lastChangeCount = stored.lastChangeCount
        }

        // Nothing has been copied since the last reconcile. This is the common
        // case on appear, and it now costs one integer read rather than an
        // alert.
        let changeCount = PasteboardReader.changeCount
        guard changeCount != lastChangeCount else { return }

        // **A passive refresh stops here, one accessor in.** The cursor is
        // deliberately *not* advanced: nothing has been read, so there is
        // nothing to record, and leaving it behind is what lets the panel
        // capture this generation when it opens.
        guard refresh == .userAsked else { return }

        // A new generation carrying no text — a screenshot, a file — can never
        // become a clip. Skipping it here is what stops CopyClip opening on an
        // alert about an image. The cursor moves, because that generation has
        // been examined as far as it is ever worth examining.
        guard PasteboardReader.holdsText else {
            persistCopyclip(clips: clips, lastChangeCount: changeCount)
            return
        }

        let result = ClipboardHistory.reconcile(
            clips: clips,
            changeCount: changeCount,
            lastChangeCount: lastChangeCount,
            rawText: PasteboardReader.text(),
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
    ///
    /// **This popup shows the ledger, which since the capture moved to
    /// panel-open no longer includes a string copied since the keyboard last
    /// captured.** It is not fixable here and it is not a defect to chase: the
    /// popup opens 200ms into a hold, and capturing there would put a modal
    /// alert under a finger that is mid-gesture, on a call that blocks the main
    /// thread until it is answered. What saves it is that the gesture already
    /// degrades correctly — index 0 is the rest title, so a hold that does not
    /// find the wanted clip and lifts without moving opens the panel, which
    /// captures. One extra tap, no alert during a drag.
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
