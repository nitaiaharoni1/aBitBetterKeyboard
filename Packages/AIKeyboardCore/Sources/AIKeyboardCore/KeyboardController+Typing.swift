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
    public func press(_ cap: KeyCap, at unitPoint: CGPoint? = nil) {
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

        // A grouped word is a claim about the characters directly behind the
        // cursor, so anything that moves the cursor, opens a plane, switches
        // language or writes text this keyboard did not decode retires it —
        // otherwise the next grouped press rewrites whatever now sits there.
        // Letters, delete and shift are the three that continue it.
        if grouped.isTyping, GroupedInput.interrupts(cap) {
            if cap == .space || cap == .ret {
                closeGroupedIfCurrentWord()
            } else {
                endGroupedWord()
            }
        }

        switch cap {
        case .character(let value):
            insertCharacter(value, at: unitPoint)
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
            // Before the newline: `previousWords` reads only the last line, so
            // learning after `\n` would see an empty line and skip the word
            // Return just finished. Chat Send is often this key.
            if !consumeGroupedSkipLearn() { learnWordJustCommitted() }
            target?.insertText("\n")
            lastLearnedFolded = nil
            // The line is finished, so any word on it was finished with it — the
            // same close-out `insertSpace` does. See `isCorrectingWordByHand`.
            deletedWordPrefix = nil
            pendingAutocorrectUndo = nil
            shift = store.storedAutocapitalise ? .on : .off
            refreshSuggestions()
        case .dictation:
            // **The only haptic on this path.** `startDictation` used to fire a
            // second one of its own, which is one tap buzzing twice — the Emoji
            // key's defect, recorded in `.claude/rules/keyboard-layout.md`.
            Feedback.actionPress()
            // **The one control this feature has.** It starts a recording, it is
            // drawn in record red while one is running, it stops it, and a tap
            // while the last words are still being transcribed calls the insert
            // off. There is no strip behind it any more to offer any of that, so a
            // key that could start something it could not end would be a trap.
            // `toggleDictation` carries all three halves.
            toggleDictation()
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
        // **Both of these end the undo window, and they are the only keys that do
        // so without changing a character.** A selection-scoped revert deletes a
        // count of units from where the caret is standing, so a caret that has
        // moved since would take the wrong ones — see `revertAIEdit`, whose guard
        // catches the case the host moves it and this catches the case we do.
        //
        // They end a hand repair for the same reason: it is a claim about the
        // word under the caret, and the caret is what just moved.
        case .cursorLeft:
            Feedback.keyPress()
            clearRevertibleEdit()
            deletedWordPrefix = nil
            pendingAutocorrectUndo = nil
            target?.adjustTextPosition(byCharacterOffset: -1)
            refreshSuggestions()
        case .cursorRight:
            Feedback.keyPress()
            clearRevertibleEdit()
            deletedWordPrefix = nil
            pendingAutocorrectUndo = nil
            target?.adjustTextPosition(byCharacterOffset: 1)
            refreshSuggestions()
        case .deleteForward:
            if selection != nil {
                deleteBackward()
                return
            }
            // Empty after-context: a move-then-delete would erase the character behind the cursor.
            guard let first = contextAfter.first else { return }
            target?.adjustTextPosition(byCharacterOffset: String(first).utf16.count)
            deleteBackward()
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
    func insertCharacter(_ value: String, at unitPoint: CGPoint? = nil) {
        Feedback.keyPress()
        // A key carrying several letters types no letter of its own: it adds one
        // keystroke to the word in progress and the decoder says what that word
        // is. A single letter arriving *while* a grouped word is open is the
        // long-press escape hatch picking one letter out of the group just
        // pressed, which pins that position rather than starting a new key.
        if isGroupedCap(value) {
            pressGroupedKey(value, at: unitPoint)
            return
        }
        if isGroupedTyping, pinGroupedLetter(value) { return }
        // A full stop is a commit, the same as space. Closing without the flag
        // would teach the decoder's guess; a letter that is not a grouped cap
        // just ends the claim.
        if grouped.isTyping, Self.finishesWord(value) {
            closeGroupedIfCurrentWord()
        } else if isGroupedTyping {
            endGroupedWord()
        }
        // **Only the refusal, never the whole banner.** "Type something first" stops
        // being true the moment they type something. An *answer* has to survive the
        // same keystroke, because fixing a typo before accepting a rewrite is
        // ordinary, so this cannot be `clearBannerState()`.
        block = nil
        // The way back to what Fix or Rewrite replaced lasts until the next
        // keystroke, which is this one: past it the field is no longer the field
        // that answer was written into, and putting the old text back would take
        // the new characters with it.
        clearRevertibleEdit()
        pendingAutocorrectUndo = nil
        // **A cap never types a line break.** The only newline any cap carries is
        // the one a banded grouped cap uses to say where its second row of letters
        // starts, and `.ret` is the key that inserts a line. Reachable only in the
        // narrow window where the keyboard is still drawn grouped and the dial has
        // already gone off — the user switched it in the containing app, or tapped
        // into a password field — where the alternative is a line break appearing
        // in somebody's message.
        let output = shift.isUppercase ? language.uppercased(value) : value
        // A full stop, a comma, emoji, `.com` — anything that is not a letter
        // inside a word — finishes the word the same way space does. Learn first:
        // once the mark is in the field, `learnWordJustCommitted` will refuse so
        // a later space does not count the same word twice. Apostrophe, hyphen
        // and Hebrew geresh stay inside the word.
        if Self.finishesWord(output), !consumeGroupedSkipLearn() {
            learnWordJustCommitted()
        }
        target?.insertText(output.replacingOccurrences(of: "\n", with: ""))
        if shift == .on { shift = .off }
        refreshSuggestions()
        noteTypedInput()
    }

    /// Marks that close a token, not the ones that live inside one.
    static func finishesWord(_ value: String) -> Bool {
        if value.count == 1, let character = value.first {
            if staysInsideWord(character) { return false }
            return !character.isLetter
        }
        // Snippets such as `.com` finish the word in front of them.
        return value.contains { !staysInsideWord($0) && !$0.isLetter }
    }

    /// Apostrophe, hyphen, maqaf, geresh, gershayim, Catalan interpunt, ZWNJ.
    private static func staysInsideWord(_ character: Character) -> Bool {
        "'’-\u{05BE}\u{05F3}\u{05F4}\u{00B7}\u{200C}".contains(character)
    }

    func insertSpace() {
        Feedback.keyPress()
        clearRevertibleEdit()
        // The word is finished, so the strokes that built it stop describing
        // anything under the cursor. Everything below — including committing the
        // bold suggestion — then runs exactly as it does with grouping off, on the
        // text the decoder already wrote into the field.
        //
        // `press` already closed a matching grouped word on `.space`. Idle
        // space-on-pause, and a caret that moved, still have to decide here.
        closeGroupedIfCurrentWord()

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
            shift = store.storedAutocapitalise ? .on : .off
            _ = consumeGroupedSkipLearn()
            pendingAutocorrectUndo = nil
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
        // And never over a word the user is repairing by hand — see
        // `isCorrectingWordByHand`. `refreshSuggestions` has already put the bold
        // slot back on the literal keystrokes for that case, so this clause is the
        // second lock on the same door, exactly as `storedAutocorrect` is checked
        // both here and there: slot zero being the literal is a fact about
        // `SuggestionEngine`, and the space bar should not be the thing that breaks
        // if it ever stops being one.
        let original = currentWordPrefix
        var swapped: (original: String, replacement: String)?
        if store.storedAutocorrect,
            !isCorrectingWordByHand,
            selection == nil,
            let candidate = suggestions.first(where: \.isDefault),
            !original.isEmpty,
            candidate.text.lowercased() != original.lowercased(),
            !undoneAutocorrectSpellings.contains(SeedLanguageModel.fold(original))
        {
            replaceCurrentWord(with: candidate.text)
            swapped = (original, Self.restoringEdgeMarks(of: original, to: candidate.text))
        }

        // After any correction, so what gets remembered is the word that ended up
        // in the field rather than the keystrokes that were replaced. A grouped
        // guess the user did not pin is not a word they typed.
        if !consumeGroupedSkipLearn() { learnWordJustCommitted() }
        target?.insertText(" ")
        lastLearnedFolded = nil
        // The repair is over: this word is committed and the next one is nobody's
        // correction yet.
        deletedWordPrefix = nil
        // A new space closes any earlier undo. Only this swap, if there was one,
        // can be taken back by the next delete.
        pendingAutocorrectUndo = swapped
        refreshSuggestions()
    }

    public func deleteBackward() {
        Feedback.keyPress()
        // Deleting can empty the field as easily as typing can fill it, so the
        // refusal has to be re-earned either way rather than left standing.
        block = nil
        clearRevertibleEdit()
        // Backspace takes back a whole key press while a grouped word is open,
        // because the letters on screen were never typed one at a time: removing
        // one leaves a word the remaining keystrokes cannot produce, and the next
        // press then decodes against a code that no longer matches the field.
        if deleteGroupedStroke() { return }
        if undoAutocorrectIfPending() { return }
        target?.deleteBackward()
        // **Read after the delete, because the word that matters is the one now
        // standing in the field.** This is the whole record of "the user is
        // repairing this word by hand"; everything it switches off is in
        // `isCorrectingWordByHand`.
        deletedWordPrefix = currentWordPrefix
        refreshSuggestions()
        // The letters just deleted armed a wait on a prefix that is gone.
        noteTypedInput()
    }

    /// The first delete after space swapped a word restores the keystrokes.
    ///
    /// Gboard and the system keyboard do this. We used to eat the trailing
    /// space and leave the wrong word standing. Only the automatic replacement
    /// is undone; the bar still offers the correction. The same spelling is
    /// not swapped again this session.
    @discardableResult
    func undoAutocorrectIfPending() -> Bool {
        guard let pending = pendingAutocorrectUndo,
            !pending.replacement.isEmpty,
            contextBefore.hasSuffix(pending.replacement + " ")
        else { return false }
        target?.deleteBackward()
        replaceCurrentWord(with: pending.original)
        undoneAutocorrectSpellings.insert(SeedLanguageModel.fold(pending.original))
        pendingAutocorrectUndo = nil
        deletedWordPrefix = pending.original
        refreshSuggestions()
        noteTypedInput()
        return true
    }

    /// A caret that is no longer sitting after the swapped word has moved on.
    /// Asked from `refreshSuggestions`, which is also what a host caret tap
    /// runs. Safe during our own insert: pending is assigned after the text
    /// lands, so the first refresh still sees `replacement `.
    func expirePendingAutocorrectUndoIfCaretMoved() {
        guard let pending = pendingAutocorrectUndo else { return }
        if pending.replacement.isEmpty || !contextBefore.hasSuffix(pending.replacement + " ") {
            pendingAutocorrectUndo = nil
        }
    }

    /// Held backspace. Each tick removes a word, including the spaces that
    /// would otherwise stall the hold. Finger-down is still `press(.backspace)`
    /// and still one character; this is only the repeater.
    ///
    /// **The click lives here, not in `press`,** because a hold must not
    /// re-enter the one-character path. Emoji search is intercepted here for
    /// the same reason `press` intercepts it: a delete pointed at the query
    /// must never eat the message.
    public func deletePreviousWord() {
        Feedback.keyClick(KeyCap.backspace.clickSound)
        if overlay == .emojiSearch {
            if emojiQuery.isEmpty {
                show(.emoji)
            } else {
                let suffix = Self.previousWordSuffix(in: emojiQuery)
                setEmojiQuery(String(emojiQuery.dropLast(suffix.count)))
            }
            return
        }

        Feedback.keyPress()
        block = nil
        clearRevertibleEdit()
        if grouped.isTyping {
            endGroupedWord()
            replaceCurrentWord(with: "")
        } else if selection != nil {
            target?.deleteBackward()
        } else {
            let units = Self.previousWordSuffix(in: contextBefore).utf16.count
            if units > 0 {
                deleteBackward(utf16Units: units)
            }
        }
        // Always the prefix now in the field, including `""` after the last
        // word. Nil would look like "nobody has deleted" to `adoptOpenWord`.
        deletedWordPrefix = currentWordPrefix
        refreshSuggestions()
        noteTypedInput()
    }

    /// Whether the word under the cursor is one the user has backspaced into.
    ///
    /// **A word somebody is deleting from is a word they are correcting on
    /// purpose, and the space bar must not overrule them.** Deleting the `ן` off
    /// `מאמין` leaves `מאמי`, which no dictionary knows, so `shouldAutocorrect`
    /// takes it as a typo and space put a different word in the field — the user
    /// pressed delete to *change* the word and the keyboard changed it back, which
    /// is the single most infuriating thing an autocorrect does. Every candidate is
    /// still offered in the bar and a deliberate tap still commits one; only the
    /// automatic replacement is off, and only for this word.
    ///
    /// **Held as the prefix rather than a flag, so it expires by itself.** The
    /// caret can move without this keyboard hearing about it — a tap elsewhere in
    /// the host's field goes through no key at all — and a flag would then suppress
    /// autocorrect on a word nobody has touched. The snapshot only matches while
    /// the word in the field still starts with what the delete left behind, which
    /// is true of typing on from the repair and false of any other word. It is the
    /// same claim-checked-rather-than-trusted shape as `GroupedInput.lastWritten`.
    ///
    /// **It is still cleared outright wherever a word is finished on purpose** —
    /// space, a tapped candidate, return, and either cursor key — because the
    /// residual case the prefix test cannot see is the *same* word typed again
    /// straight afterwards, and a short repaired prefix is a prefix of plenty of
    /// other words.
    ///
    /// **The accents popup counts, and that is deliberate rather than incidental.**
    /// It picks an alternate by calling `deleteBackward()` and retyping (see
    /// `KeyboardView.alternateHandler`), so it lands here — and it should: `צ׳יפס`,
    /// `col·legi` and `café` are exactly the words no dictionary holds and
    /// autocorrect destroys, and a character reached through a long press is as
    /// hand-placed as one reached by deleting the wrong one.
    var isCorrectingWordByHand: Bool {
        guard let edited = deletedWordPrefix, !edited.isEmpty else { return false }
        return currentWordPrefix.hasPrefix(edited)
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
        clearRevertibleEdit()
        // Picked from the grid rather than pressed as a `KeyCap`, so this is the
        // one insertion `press(_:)` never speaks for. It still put text in.
        Feedback.keyClick(.tock)
        closeGroupedIfCurrentWord()
        if !consumeGroupedSkipLearn() { learnWordJustCommitted() }
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
    /// **Query keys are taken.** Shift, the plane switch and Settings fall through
    /// on purpose: the whole reason search needs the letters back is that the
    /// words being searched for are Hebrew *or* English, and a user who cannot
    /// reach the other alphabet can only search in one of them. Forward delete is
    /// swallowed so it cannot reach the document. Everything else falls through
    /// too, so a control the user put in the suggestion bar behaves the same here
    /// as it does anywhere.
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
