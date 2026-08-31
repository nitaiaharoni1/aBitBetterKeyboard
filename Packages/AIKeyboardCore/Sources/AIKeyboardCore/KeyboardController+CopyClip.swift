import UIKit

/// Reads the system pasteboard without putting `UIPasteboard` on
/// `KeyboardController`'s public surface. The ledger is pure; this is the
/// only place that names the board.
///
/// **Two calls now, not three, because the one that actually raised the
/// alert is gone.** Since iOS 16 the first read of the *contents* of a board
/// another app filled raises the system "Allow Paste?" alert — that used to
/// be `text()`, called automatically the moment CopyClip opened. It is
/// deleted: `UIPasteControl` is the only route left to a new item's text (see
/// `CopyClipPasteControl`), because tapping it is consent and nothing in
/// Swift code has to name `.string` to get there. What remains are the two
/// calls Apple treats as metadata rather than content.
enum PasteboardReader {
    /// The board's generation. **The only member a passive refresh may call**,
    /// and the only one Apple documents as free of any consent step: it is a
    /// counter, not content. Everything the keyboard does on appear is decided
    /// from this.
    static var changeCount: Int { UIPasteboard.general.changeCount }

    /// Whether the board holds text at all.
    ///
    /// Metadata rather than content, and it exists to skip a *pointless*
    /// control: a copied screenshot can never become a clip, so opening
    /// CopyClip over one should offer nothing rather than a paste button that
    /// can only ever be empty. It is deliberately reached only from inside the
    /// `userAsked` path even so — Apple documents `detectPatterns(for:)` as
    /// requiring no permission and says nothing either way about `hasStrings`,
    /// so nothing that has to be silent is allowed to depend on it.
    static var holdsText: Bool { UIPasteboard.general.hasStrings }
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

    /// Reconcile the ledger, never reading the board's contents.
    ///
    /// **The keyboard used to snapshot the contents on every appearance, and
    /// that is what put "Allow Paste?" in front of somebody who had only tapped
    /// a text field.** `viewWillAppear` runs on every focused field and every
    /// host app, so a single copy in Safari bought an alert on the next
    /// keystroke session, and a session that copied nothing still paid a read.
    /// The first fix moved that read to the moment CopyClip opened, which is at
    /// least the moment the user asked for their clipboard — but it was still a
    /// read, so opening CopyClip over freshly copied text still raised the
    /// alert once per copied item. **This function no longer reads at all.**
    ///
    /// A new generation splits two ways, both alert-free. Holding no text — a
    /// screenshot, a file — can never become a clip, so the cursor advances
    /// past it immediately and nothing is offered. Holding text leaves the
    /// cursor exactly where it is: `copyclipCaptureState` reports `.control`,
    /// the panel draws `UIPasteControl` for that one generation, and
    /// `captureFromPasteControl(_:)` is what advances the cursor, once the
    /// user's own tap — not this function — has granted the read. The cost is
    /// the same one the ledger has always paid for capturing on open rather
    /// than on every change: two copies between two openings leave only the
    /// second on offer.
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
        // case on appear, and it costs one integer read, never an alert.
        let changeCount = PasteboardReader.changeCount
        guard changeCount != lastChangeCount else { return }

        // **A passive refresh stops here, one accessor in.** The cursor is
        // deliberately *not* advanced: nothing has been read, so there is
        // nothing to record, and leaving it behind is what lets the panel
        // notice this generation when it opens.
        guard refresh == .userAsked else { return }

        // A new generation carrying no text can never become a clip. The
        // cursor moves, because that generation has been examined as far as
        // it is ever worth examining, and a `UIPasteControl` that could only
        // ever be empty is worse than offering nothing.
        if ClipboardHistory.captureState(
            changeCount: changeCount, lastChangeCount: lastChangeCount,
            holdsText: PasteboardReader.holdsText
        ) == .neither {
            persistCopyclip(clips: clips, lastChangeCount: changeCount)
        }
        // Otherwise: leave the cursor pending. `copyclipCaptureState` picks
        // this generation up the moment the panel is drawn.
    }

    /// What the panel should draw about the pasteboard right now.
    ///
    /// **Computed, not stored**, so there is nothing to keep in sync: the one
    /// live accessor it calls, `changeCount`, is the same free counter
    /// `refreshCopyClip(_:)` already reads, so asking again here costs
    /// nothing and self-heals if the board moved again while the panel sat
    /// open (there is deliberately no polling — see `refreshCopyClip(_:)`'s
    /// history with `UIPasteboard.changedNotification`). `holdsText` is
    /// fixed `true` rather than re-asked: by the time this is read,
    /// `refreshCopyClip(.userAsked)` has already resolved the *known*
    /// non-text case by advancing the cursor past it, so any generation still
    /// pending here either is text or is a change the keyboard has not
    /// classified yet — and for that second case `CopyClipPasteControl`
    /// itself is the authority, since it hides on its own when the pasteboard
    /// holds nothing it can paste. Nothing here can turn that into a false
    /// positive a user acts on.
    public var copyclipCaptureState: CopyClipCaptureState {
        ClipboardHistory.captureState(
            changeCount: PasteboardReader.changeCount,
            lastChangeCount: lastChangeCount,
            holdsText: true)
    }

    // MARK: Noticing a copy made while the panel is open

    /// How often the open panel asks whether the pasteboard has moved.
    ///
    /// **Half a second, and the thing being read is not the thing that costs.**
    /// This reads `UIPasteboard.changeCount`, an integer that says a generation
    /// happened and nothing about what is in it — the same free counter
    /// `refreshCopyClip(_:)` already calls "one integer read, never an alert".
    /// Reading the *contents* is what raises "Allow Paste?", and nothing here
    /// does that: the whole point is to put `UIPasteControl` on screen so the
    /// user's own tap is the read.
    ///
    /// Deliberately slower than `ScreenContextChannel.pollInterval`'s 0.25s, and
    /// unlike that one it is not the same trade. That timer ran for as long as
    /// the keyboard was up, woke a chain of `RunLoop.main` sinks, and cost a
    /// containermanagerd query per tick to learn about a page nothing could
    /// write. This runs only while a panel the user deliberately opened is on
    /// screen, and the user is looking straight at the thing it updates.
    static let copyclipWatchInterval = Duration.milliseconds(500)

    /// Starts or stops the watch to match the overlay.
    ///
    /// **The panel could not see a copy made while it was open, and that is the
    /// whole of both halves of the bug report it fixes.** The ordinary way to
    /// copy something on iOS is to long-press it — which does not dismiss the
    /// keyboard — so "copy the message, then look at CopyClip" leaves the panel
    /// standing on the generation it was opened against. `copyclipCaptureState`
    /// would have answered `.control` correctly at any moment it was asked; it
    /// was never asked again, because nothing published. The clip was then never
    /// offered and never kept, which reads as CopyClip not remembering.
    ///
    /// It reads as script-specific from the outside and is not: the ledger takes
    /// Hebrew unchanged through `reconcile`, the JSON round trip, dedup and
    /// search, verified end to end. What made it look like a Hebrew fault is that
    /// long-press-to-copy is how you get a Hebrew message out of a chat app, and
    /// that is exactly the gesture that leaves the keyboard up.
    public func watchPasteboardWhileCopyClipIsOpen() {
        copyclipWatchTask?.cancel()
        copyclipWatchTask = nil
        guard overlay.isCopyClip else { return }
        noticedPasteboardGeneration = PasteboardReader.changeCount
        copyclipWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: KeyboardController.copyclipWatchInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self, self.overlay.isCopyClip else { return }
                let generation = PasteboardReader.changeCount
                // Assigned only when it moved. `@Published` fires on assignment
                // whether or not the value changed, so an unconditional write
                // would re-run every observing `body` twice a second for as long
                // as the panel is open — which is the cost this is supposed to be
                // small enough to avoid.
                guard generation != self.noticedPasteboardGeneration else { continue }
                self.noticedPasteboardGeneration = generation
            }
        }
    }

    /// Stops the watch. Called when the keyboard goes away, because a task left
    /// running in a keyboard the user has dismissed is the shape of defect
    /// `viewWillDisappear` already stops dictation for — iOS keeps the process
    /// alive after the keyboard goes, and how long for is not ours to decide.
    public func stopWatchingPasteboard() {
        copyclipWatchTask?.cancel()
        copyclipWatchTask = nil
    }

    /// The one route into the ledger that does not go through
    /// `PasteboardReader`. `CopyClipPasteControl` resolves the tap into a
    /// plain `String` via its own item providers — never
    /// `UIPasteboard.general.string` — so by the time this runs, the read has
    /// already happened with the user's own gesture as consent. Advances the
    /// cursor the same way an ordinary reconcile does, so this generation is
    /// not offered again.
    public func captureFromPasteControl(_ text: String) {
        Feedback.keyPress()
        let result = ClipboardHistory.reconcile(
            clips: clips,
            changeCount: PasteboardReader.changeCount,
            lastChangeCount: lastChangeCount,
            rawText: text,
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
    /// captured.** It is not fixable here: the popup opens 200ms into a hold,
    /// and a blocking read under a finger that is mid-gesture is worse than
    /// the miss, whatever route the read takes. What changed is what the
    /// degrade costs. Index 0 is the rest title, so a hold that does not find
    /// the wanted clip and lifts without moving opens the panel — and the
    /// panel no longer answers a fresh item with an alert either, only with
    /// `UIPasteControl`. The gesture still degrades to one extra tap; it used
    /// to degrade to one extra tap *and* a modal alert, and only the second
    /// half is gone.
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

    /// Writes a clip into the field, leaves the panel open, and keeps the way back.
    ///
    /// **One tap can put a paragraph in somebody's message, and until this kept a
    /// `revertibleEdit` there was nothing on screen that could take it out.** The
    /// panel covers the letters, so the wrong card meant closing CopyClip, holding
    /// a delete key the panel had hidden, and counting characters. It is the same
    /// bargain Fix and Rewrite are drawn under — an edit the user did not type,
    /// arriving whole — so it is recorded in the same slot and undone by the same
    /// code. `.spanAtCursor` because an insert replaced nothing; `previous` is
    /// empty for the same reason. `CopyClipControlRow` draws the undo while the
    /// panel is up, `SuggestionBar` draws it once the letters are back, and
    /// `expireRevertibleEditIfUnusable` retires it either way, once the clip is no
    /// longer standing where it landed.
    ///
    /// Set *after* the insertion, not before, for the reason `applyDirectly` sets
    /// it after `replaceTargetText`: `refreshSuggestions` drops a way back that is
    /// standing over an empty field, and the field is only non-empty once the text
    /// has landed.
    public func insertClip(_ clip: Clip) {
        let documentIdentifier = target?.documentIdentifier
        Feedback.keyPress()
        clearRevertibleEdit()
        Feedback.keyClick(.tock)
        closeGroupedIfCurrentWord()
        if !consumeGroupedSkipLearn() { learnWordJustCommitted() }
        target?.insertText(clip.text.value)
        refreshSuggestions()
        revertibleEdit = RevertibleEdit(
            origin: .clip,
            previous: "",
            applied: clip.text.value,
            undo: .spanAtCursor,
            documentIdentifier: documentIdentifier)
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
        // The ledger is one of Reply's two sources, so a clip arriving can settle
        // a refusal the user is still looking at. See
        // `dropStaleReplyClipboardRefusal`.
        dropStaleReplyClipboardRefusal()
        if overlay == .copyclipSearch {
            setCopyclipQuery(copyclipQuery)
        }
    }
}
