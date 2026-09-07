import SwiftUI
import UIKit

extension KeyboardController {

    public func insertEmoji(_ emoji: String) {
        Feedback.keyPress()
        // Picked from the grid rather than pressed as a `KeyCap`, so this is the
        // one insertion `press(_:)` never speaks for. It still put text in.
        Feedback.keyClick(.tock)
        closeGroupedIfCurrentWord()
        if !consumeGroupedSkipLearn() { learnWordJustCommitted() }
        target?.insertText(emoji)
        // **Recorded untoned, inserted toned.** The document gets exactly what
        // the cell showed; Recents gets the spelling the grid is keyed by, so
        // holding 👋 and picking three tones in a row leaves one wave in the tab
        // rather than three, and switching back to plain does not strand a row
        // of somebody else's tone there. `EmojiCatalog.toned` puts the modifier
        // back on when the tab is drawn.
        let remembered = EmojiCatalog.untoned(emoji)
        recentEmoji.removeAll { $0 == remembered }
        recentEmoji.insert(remembered, at: 0)
        recentEmoji = Array(recentEmoji.prefix(Self.recentEmojiLimit))
        // Written through on every pick rather than on teardown. A keyboard
        // extension is killed without warning and gets no `applicationWillTerminate`
        // of its own, so anything saved "on the way out" is saved never.
        store.recentEmoji = recentEmoji
        // **`visibleRecentEmoji` is deliberately not touched here.** The grid the
        // finger is on keeps the order it opened with; `settleRecentEmoji` is what
        // picks the new one up, the next time that grid becomes visible.
        refreshSuggestions()
        reportInteraction(.emoji)
    }

    /// Adopts the recorded order as the order to draw.
    ///
    /// **Called when the emoji surface becomes visible after not being visible,
    /// and nowhere else** — a re-sort while it is open is a picker that moves the
    /// emoji out from under the thumb. That is two moments, not one: `show(_:)`
    /// arriving at an emoji overlay from a different one, and the keyboard itself
    /// coming back on screen (`KeyboardViewController.viewWillAppear`). Nothing
    /// resets `overlay` when the keyboard goes away, so an extension instance iOS
    /// keeps alive comes back with the grid still open, and without the second
    /// call the emoji picked just before it was dismissed would be missing from
    /// Recents until the user closed the panel and opened it again.
    ///
    /// See `KeyboardController.visibleRecentEmoji`.
    public func settleRecentEmoji() {
        guard visibleRecentEmoji != recentEmoji else { return }
        visibleRecentEmoji = recentEmoji
    }

    /// Four full columns of the strip at ten columns across — enough that the tab
    /// is worth opening, few enough that it stays a list of what you actually use.
    static let recentEmojiLimit = 20

    /// Adopts the tone a held cell was released on, for the whole grid.
    ///
    /// **Written through immediately**, for the reason `insertEmoji` writes
    /// recents through: a keyboard extension is killed without warning, so a
    /// tone saved on the way out is saved never.
    ///
    /// The emoji the finger lifted on is inserted by `insertEmoji` on the same
    /// lift; this only decides what the *next* 304 cells look like. Silent when
    /// the tone has not changed, so lifting on the item the popup opened resting
    /// on writes nothing.
    public func setEmojiSkinTone(_ tone: EmojiSkinTone) {
        guard tone != emojiSkinTone else { return }
        emojiSkinTone = tone
        store.emojiSkinTone = tone
    }

    // MARK: Emoji search

    /// Whether this key belonged to the search box rather than to the document.
    ///
    /// **Query keys are taken.** Shift, the plane switch and Settings fall through
    /// on purpose: the whole reason search needs the letters back is that the
    /// words being searched for are Hebrew *or* English, and a user who cannot
    /// reach the other alphabet can only search in one of them. Forward delete is
    /// swallowed so it cannot reach the document. Everything else falls through
    /// too, so a control the user put in the suggestion bar behaves the same here
    /// as it does anywhere.
    func consumeForEmojiSearch(_ cap: KeyCap, playsFeedback: Bool = true) -> Bool {
        switch cap {
        case .character(let value):
            // A letter typed into the box is still a deferred letter, so its thud
            // may already have played on the finger-down. See `press`.
            if playsFeedback { Feedback.keyPress() }
            setEmojiQuery(emojiQuery + (shift.isUppercase ? language.uppercased(value) : value))
            if shift == .on { shift = .off }
            return true
        case .space:
            Feedback.keyPress()
            setEmojiQuery(emojiQuery + " ")
            return true
        case .backspace:
            // Backspacing past the start of an empty query closes search rather
            // than deleting from the user's message, which is the one thing a
            // delete key must never do while it is pointed somewhere else.
            // `show` fires the haptic. A `keyPress` here would be two thuds
            // for one tap, the same double the Emoji key used to have.
            if emojiQuery.isEmpty {
                show(.emoji)
            } else {
                Feedback.keyPress()
                setEmojiQuery(String(emojiQuery.dropLast()))
            }
            return true
        case .deleteForward:
            return true
        case .ret:
            show(.emoji)
            return true
        default:
            return false
        }
    }

    public func setEmojiQuery(_ query: String) {
        emojiQuery = query
        emojiResults = EmojiSearch.results(for: query, recent: recentEmoji)
    }

    func consumeForCopyclipSearch(_ cap: KeyCap, playsFeedback: Bool = true) -> Bool {
        switch cap {
        case .character(let value):
            // Same as `consumeForEmojiSearch`: the thud may already be spent.
            if playsFeedback { Feedback.keyPress() }
            setCopyclipQuery(
                copyclipQuery + (shift.isUppercase ? language.uppercased(value) : value))
            if shift == .on { shift = .off }
            return true
        case .space:
            Feedback.keyPress()
            setCopyclipQuery(copyclipQuery + " ")
            return true
        case .backspace:
            if copyclipQuery.isEmpty {
                show(.copyclip)
            } else {
                Feedback.keyPress()
                setCopyclipQuery(String(copyclipQuery.dropLast()))
            }
            return true
        case .deleteForward:
            return true
        case .ret:
            show(.copyclip)
            return true
        default:
            return false
        }
    }

    public func setCopyclipQuery(_ query: String) {
        copyclipQuery = query
        copyclipResults = ClipboardHistory.matching(query: query, in: clips)
    }

    // MARK: Overlays

    public func show(_ newOverlay: KeyboardOverlay) {
        Feedback.modifierPress()
        // The query belongs to one open search, not to the keyboard. Leaving it
        // set would reopen the box on yesterday's word — and worse, leaving
        // `emojiResults` set holds 60 strings alive for the rest of the session.
        if newOverlay != .emojiSearch {
            emojiQuery = ""
            emojiResults = []
        }
        if newOverlay != .copyclipSearch {
            copyclipQuery = ""
            copyclipResults = []
        }
        if newOverlay == .copyclip || newOverlay == .copyclipSearch {
            // **The one place the pasteboard's contents are read**, because it
            // is the one place the user has said they want their clipboard.
            // Everywhere else refreshes passively; see `refreshCopyClip(_:)`.
            //
            // **Above `withAnimation`, deliberately.** The read blocks the main
            // thread while iOS's "Allow Paste?" alert is up, so the two orders
            // are "alert, then a panel that is already right" and "a panel
            // holding yesterday's list, an alert over it, then a row appearing
            // underneath". The first is one transition and is what this is.
            // `.copyclipSearch` is only ever entered from `.copyclip`
            // (`CopyClipBar` is drawn only while `overlay.isCopyClip`), so the
            // second case is a re-entry over a cursor that has already caught
            // up and reads nothing at all.
            refreshCopyClip(.userAsked)
        }
        if newOverlay == .copyclipSearch {
            setCopyclipQuery(copyclipQuery)
        }
        // Arriving at the emoji surface from outside it, which is one of the two
        // moments the Recent order may move (`viewWillAppear` is the other).
        // `overlay.isEmoji` on the right is what makes the grid and its search box
        // one visit — search is opened from the grid and backspaced out of it
        // again, and re-sorting on either leg is the same emoji-under-the-thumb
        // shuffle seen from a different key.
        if newOverlay.isEmoji && !overlay.isEmoji {
            settleRecentEmoji()
        }
        withAnimation(Theme.Motion.panel) { overlay = newOverlay }
    }

    /// A search box starts on lower case and hands the document's shift back when
    /// it closes.
    ///
    /// **The box inherited the document's shift, and that is not a capitalisation
    /// the user asked for.** An empty field arms shift at focus, so opening emoji
    /// search and typing `cat` produced `Cat`, and a shift press from that
    /// inherited `.on` went straight to `.locked` — the query the user reads
    /// carrying prose rules into something that is not prose. Search is
    /// case-insensitive (`EmojiSearch.normalise`), so the results were right the
    /// whole time and only the box looked wrong.
    ///
    /// **Restoring is the half that makes it safe.** Simply switching shift off on
    /// entry loses the capital at the start of a sentence, which is a real bug
    /// traded for a cosmetic one. The parked value is put back on the way out, and
    /// only on a genuine crossing: `.emojiSearch` → `.copyclipSearch` is still one
    /// box owning the keys, so the document's shift stays parked rather than being
    /// restored and re-taken. Shift pressed *inside* the box belongs to the query
    /// and is deliberately discarded with it.
    func adoptSearchShift(from previous: KeyboardOverlay) {
        guard previous.isSearch != overlay.isSearch else { return }
        if overlay.isSearch {
            shiftBeforeSearch = shift
            shift = .off
        } else {
            if let parked = shiftBeforeSearch { shift = parked }
            shiftBeforeSearch = nil
        }
    }

    public func dismissOverlay() {
        stopDictation(insert: false)
        // The same tidy-up `show(_:)` does, and for the same two reasons: a query
        // left set reopens the box on yesterday's word, and `emojiResults` holds
        // sixty strings alive for the rest of a session in a process with a
        // memory cap. Both close paths, one answer.
        emojiQuery = ""
        emojiResults = []
        copyclipQuery = ""
        copyclipResults = []
        withAnimation(Theme.Motion.panel) {
            overlay = .none
            clearBannerState()
        }
    }

    /// Closes a panel that this orientation has no way out of.
    ///
    /// **Landscape sheds the action row, and that row holds the only key that
    /// closes the emoji grid or the CopyClip panel.**
    /// `Theme.Metrics.landscapeLayout(basedOn:)` sets `cursorRow = []`, so on a
    /// rotated phone `KeyboardView+Keys` draws no action row at all — while
    /// `KeyboardOverlay.copyclip` and `.emoji` still hide every letter key. A
    /// panel opened in portrait and rotated into therefore left a keyboard with
    /// no letters, no space bar, no return and nothing that could close it: the
    /// search box hands the letters back but types into the query, and its ✕ only
    /// ever returns to the panel. The way out was to rotate the phone back.
    ///
    /// Closing is the honest answer rather than keeping the row: landscape has
    /// about 169pt for the whole keyboard and that row was shed on purpose (see
    /// NIT-18). A panel that cannot be opened in this orientation should not be
    /// standing in it either. A user who put CopyClip or Emoji on a bar edge can
    /// reopen it there, because the bar is not shed.
    ///
    /// **Silent, because nobody pressed anything.** `show(_:)` speaks for a key
    /// with `Feedback.modifierPress()`, and a rotation is not one.
    public func closeOverlayForLandscape() {
        guard overlay != .none else { return }
        dismissOverlay()
    }
}
