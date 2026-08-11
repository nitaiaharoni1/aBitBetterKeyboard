import SwiftUI
import UIKit

extension KeyboardController {

    // MARK: Typing

    /// **A space bar touch that is still open pays what it owes before this key.**
    /// The space bar commits on lift rather than on finger-down (see
    /// `spaceBarTouch`), and two thumbs overlap constantly on a phone keyboard: a
    /// finger lands on space, the other thumb taps a letter, and only then does the
    /// first lift. Without this line the letter goes in first and the space lands
    /// after it — and worse, `insertSpace` would read `currentWordPrefix` and
    /// `suggestions` *after* that letter had re-scored both, so `sched` + space +
    /// `t` comes back as one word autocorrected from `schedt`. Paying here means
    /// the space is typed in the order the fingers made it and against the
    /// candidate that was on screen when it was pressed.
    public func press(_ cap: KeyCap) {
        if cap != .space, spaceTouch.interrupted() {
            // Clicks *before* this key does, for the reason the space is typed
            // before it: the other thumb pressed it first. `insertSpace` is
            // reached from here as well as from the `.space` branch below, and
            // only that branch goes through the line under this block.
            Feedback.keyClick(KeyCap.space.clickSound)
            insertSpace()
        }

        // **One click for this key, here, and nowhere else.** Which sound is the
        // cap's own business (`KeyCap.clickSound`); this is the only line that
        // plays one. Scattering the call down the branches below is what left
        // backspace and every function key silent, and it is also what would make
        // the accents popup click twice, since that popup reaches this function
        // through a `deleteBackward()` the user never pressed. Above the
        // emoji-search branch, because a key typing into that box is still a key.
        Feedback.keyClick(cap.clickSound)

        // The emoji search box is the one thing on this keyboard that types into
        // something other than the document, so it gets first refusal on the key.
        if overlay == .emojiSearch, consumeForEmojiSearch(cap) { return }

        switch cap {
        case .character(let value):
            insertCharacter(value)
        case .shift:
            toggleShift()
        case .backspace:
            deleteBackward()
        case .plane(let destination, _):
            Feedback.modifierPress()
            withAnimation(Theme.Motion.quick) { plane = destination }
        case .globe:
            Feedback.modifierPress()
            advanceLanguage()
        case .settings:
            Feedback.modifierPress()
            onOpenContainingApp?(SharedStore.settingsURL)
        case .space:
            insertSpace()
        case .ret:
            Feedback.keyPress()
            target?.insertText("\n")
            shift = store.autocapitalise ? .on : .off
            refreshSuggestions()
        case .dictation:
            Feedback.actionPress()
            startDictation()
        case .emoji:
            // No `modifierPress()` here: `show(_:)` fires one as its first line,
            // and this key was buzzing twice for one tap.
            //
            // From either emoji state this key is the way back to the letters,
            // which is what its `אבג` cap promises while the grid is open. It is
            // also the only way back: the category row has no `אבג` of its own,
            // deliberately — see `EmojiCategoryRow`.
            show(overlay.isEmoji ? .none : .emoji)
        case .aiReply:
            // Straight to the action. Reply is deliberately not guarded on
            // `hasTextToWorkWith` — answering a message you have not started
            // writing is the whole point of it — and `run(_:)` already carries
            // that exception, plus the explanation for a tap with no session
            // behind it.
            run(.reply)
        case .aiFix:
            run(.fix)
        case .quickTone:
            Feedback.actionPress()
            // The same three-way answer `SuggestionBar`'s own button gives, asked
            // of the same function, so the key and the button cannot disagree
            // about what a tap does on an empty field. That divergence has already
            // shipped once between the bar and the panel behind it.
            switch SuggestionBar.toneTap(
                hasTextToWorkWith: hasTextToWorkWith, isWorking: isWorking)
            {
            case .rewrite: runDefaultTone()
            case .needsText: refuseForEmptyField(.rewrite)
            case .ignore: break
            }
        case .cursorLeft:
            Feedback.keyPress()
            target?.adjustTextPosition(byCharacterOffset: -1)
            refreshSuggestions()
        case .cursorRight:
            Feedback.keyPress()
            target?.adjustTextPosition(byCharacterOffset: 1)
            refreshSuggestions()
        case .hideKeyboard:
            Feedback.modifierPress()
            onDismissKeyboard?()
        }
    }

    /// Shifted through `KeyboardLanguage.uppercased`, which is the one place that
    /// knows Turkish has two i's — and the one place that holds the language's
    /// `Locale`, so this does not build one per keystroke. The key cap, the
    /// callout and the long-press popup go through the same call, or the key
    /// shows one letter and types another.
    func insertCharacter(_ value: String) {
        Feedback.keyPress()
        // **Only the refusal, never the whole banner.** "Type something first" stops
        // being true the moment they type something. An *answer* has to survive the
        // same keystroke, because fixing a typo before accepting a rewrite is
        // ordinary, so this cannot be `clearBannerState()`.
        block = nil
        let output = shift.isUppercase ? language.uppercased(value) : value
        target?.insertText(output)
        if shift == .on { shift = .off }
        refreshSuggestions()
    }

    func insertSpace() {
        Feedback.keyPress()

        // Two spaces in quick succession become a full stop, as on the system keyboard.
        let now = Date()
        if let last = lastSpaceTapAt,
            now.timeIntervalSince(last) < 0.6,
            contextBefore.hasSuffix(" "),
            !contextBefore.hasSuffix("  ")
        {
            target?.deleteBackward()
            target?.insertText(". ")
            lastSpaceTapAt = nil
            shift = store.autocapitalise ? .on : .off
            refreshSuggestions()
            return
        }
        lastSpaceTapAt = now

        // A space commits the highlighted candidate, which is what makes a
        // suggestion bar worth having.
        //
        // Not over a selection: there the space replaces what is selected, the
        // way it does on the system keyboard, and the partial word in front of
        // the selection is not what the user is typing over.
        if store.storedAutocorrect,
            selection == nil,
            let candidate = suggestions.first(where: \.isDefault),
            !currentWordPrefix.isEmpty,
            candidate.text.lowercased() != currentWordPrefix.lowercased()
        {
            replaceCurrentWord(with: candidate.text)
        }

        // After any correction, so what gets remembered is the word that ended up
        // in the field rather than the keystrokes that were replaced.
        learnWordJustCommitted()
        target?.insertText(" ")
        refreshSuggestions()
    }

    public func deleteBackward() {
        Feedback.keyPress()
        // Deleting can empty the field as easily as typing can fill it, so the
        // refusal has to be re-earned either way rather than left standing.
        block = nil
        target?.deleteBackward()
        refreshSuggestions()
    }

    public func toggleShift() {
        Feedback.modifierPress()
        switch shift {
        case .off: shift = .on
        case .on: shift = .locked
        case .locked: shift = .off
        }
    }

    // MARK: Emoji

    public func insertEmoji(_ emoji: String) {
        Feedback.keyPress()
        // Picked from the grid rather than pressed as a `KeyCap`, so this is the
        // one insertion `press(_:)` never speaks for. It still put text in.
        Feedback.keyClick(.tock)
        target?.insertText(emoji)
        recentEmoji.removeAll { $0 == emoji }
        recentEmoji.insert(emoji, at: 0)
        recentEmoji = Array(recentEmoji.prefix(Self.recentEmojiLimit))
        // Written through on every pick rather than on teardown. A keyboard
        // extension is killed without warning and gets no `applicationWillTerminate`
        // of its own, so anything saved "on the way out" is saved never.
        store.recentEmoji = recentEmoji
        refreshSuggestions()
        reportInteraction(.emoji)
    }

    /// Four full columns of the strip at ten columns across — enough that the tab
    /// is worth opening, few enough that it stays a list of what you actually use.
    static let recentEmojiLimit = 20

    // MARK: Emoji search

    /// Whether this key belonged to the search box rather than to the document.
    ///
    /// **Only the four keys that edit a query are taken.** Shift, the plane
    /// switch and Settings fall through on purpose: the whole reason search needs
    /// the letters back is that the words being searched for are Hebrew *or*
    /// English, and a user who cannot reach the other alphabet can only search in
    /// one of them. Everything else falls through too, so a control the user put
    /// in the suggestion bar behaves the same here as it does anywhere.
    func consumeForEmojiSearch(_ cap: KeyCap) -> Bool {
        switch cap {
        case .character(let value):
            Feedback.keyPress()
            setEmojiQuery(emojiQuery + (shift.isUppercase ? language.uppercased(value) : value))
            if shift == .on { shift = .off }
            return true
        case .space:
            Feedback.keyPress()
            setEmojiQuery(emojiQuery + " ")
            return true
        case .backspace:
            Feedback.keyPress()
            // Backspacing past the start of an empty query closes search rather
            // than deleting from the user's message, which is the one thing a
            // delete key must never do while it is pointed somewhere else.
            if emojiQuery.isEmpty {
                show(.emoji)
            } else {
                setEmojiQuery(String(emojiQuery.dropLast()))
            }
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
        withAnimation(Theme.Motion.panel) { overlay = newOverlay }
    }

    public func dismissOverlay() {
        stopDictation(insert: false)
        withAnimation(Theme.Motion.panel) {
            overlay = .none
            clearBannerState()
        }
    }
}
