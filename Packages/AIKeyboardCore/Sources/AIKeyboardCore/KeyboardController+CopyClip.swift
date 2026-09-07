import UIKit

enum PasteboardReader {
    static var changeCount: Int { UIPasteboard.general.changeCount }
    static var holdsText: Bool { UIPasteboard.general.hasStrings }
    static var text: String? { UIPasteboard.general.string }
}

public enum CopyClipRefresh {
    case passive
    case automatic
    case userAsked
}

extension KeyboardController {
    public func refreshCopyClip(_ refresh: CopyClipRefresh = .passive) {
        let stored = store.storedCopyclipRecord
        if stored.clips != clips || stored.lastChangeCount != lastChangeCount {
            clips = stored.clips
            lastChangeCount = stored.lastChangeCount
        }

        let changeCount = PasteboardReader.changeCount
        guard changeCount != lastChangeCount, refresh != .passive else { return }
        guard refresh == .userAsked || attemptedCopyclipGeneration != changeCount else { return }
        guard PasteboardReader.holdsText else { return }
        attemptedCopyclipGeneration = changeCount
        guard let text = PasteboardReader.text else { return }
        guard PasteboardReader.changeCount == changeCount else { return }
        let result = ClipboardHistory.reconcile(
            clips: clips,
            changeCount: changeCount,
            lastChangeCount: lastChangeCount,
            rawText: text,
            now: Date()
        )
        persistCopyclip(clips: result.clips, lastChangeCount: result.lastChangeCount)
    }

    public var copyclipCaptureState: CopyClipCaptureState {
        ClipboardHistory.captureState(
            changeCount: PasteboardReader.changeCount,
            lastChangeCount: lastChangeCount,
            holdsText: true)
    }

    static let copyclipWatchInterval = Duration.milliseconds(500)

    public func startWatchingPasteboard() {
        guard copyclipWatchTask == nil else { return }
        noticedPasteboardGeneration = PasteboardReader.changeCount
        copyclipWatchTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.refreshCopyClip(.automatic)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: KeyboardController.copyclipWatchInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                let generation = PasteboardReader.changeCount
                // Assigned only when it moved. `@Published` fires on assignment
                // whether or not the value changed, so an unconditional write
                // would re-run every observing `body` twice a second for as long
                // as the keyboard is visible — which is the cost this is supposed to be
                // small enough to avoid.
                if generation != self.noticedPasteboardGeneration {
                    self.noticedPasteboardGeneration = generation
                }
                guard generation != self.lastChangeCount,
                    generation != self.attemptedCopyclipGeneration
                else { continue }
                self.refreshCopyClip(.automatic)
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

    public func captureFromPasteControl(_ text: String, changeCount: Int? = nil) {
        Feedback.keyPress()
        let result = ClipboardHistory.reconcile(
            clips: clips,
            changeCount: changeCount ?? PasteboardReader.changeCount,
            lastChangeCount: lastChangeCount,
            rawText: text,
            now: Date(),
            acceptsUnchangedGeneration: true
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
