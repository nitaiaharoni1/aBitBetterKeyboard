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
    ///
    /// It is two open touches now rather than one — a character key defers to its
    /// lift as well — and `payOpenTouches(before:)` is where both are settled.
    public func press(_ cap: KeyCap, at unitPoint: CGPoint? = nil, playsFeedback: Bool = true) {
        payOpenTouches(before: cap)

        // **One click for this key, here, and nowhere else.** Which sound is the
        // cap's own business (`KeyCap.clickSound`); this is the only line that
        // plays one. Scattering the call down the branches below is what left
        // backspace and every function key silent, and it is also what would make
        // the accents popup click twice, since that popup reaches this function
        // through a `deleteBackward()` the user never pressed. Above the
        // emoji-search branch, because a key typing into that box is still a key.
        //
        // `playsFeedback` is false on exactly one path: a character key whose
        // finger-down already clicked and thudded and whose letter is only now
        // being typed. See `beginCharacterTouch`.
        if playsFeedback { Feedback.keyClick(cap.clickSound) }

        // A search box is the one thing on this keyboard that types into
        // something other than the document, so it gets first refusal on the key.
        if overlay == .emojiSearch,
            consumeForEmojiSearch(cap, playsFeedback: playsFeedback)
        {
            return
        }
        if overlay == .copyclipSearch,
            consumeForCopyclipSearch(cap, playsFeedback: playsFeedback)
        {
            return
        }

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
            insertCharacter(value, at: unitPoint, playsFeedback: playsFeedback)
        case .shift:
            toggleShift()
        case .backspace:
            deleteBackward()
        case .plane(let destination, _):
            // **A plane the user cannot see is not a plane they switched to.**
            // `123` sits beside Emoji on the bottom row, which is the one row a
            // panel may not cover, so it stays tappable while the grid is up —
            // and tapping it moved `plane` behind the grid, redrawing rows nobody
            // could see and leaving the emoji exactly where they were. The key
            // answered nothing. Asking for the digits is asking to type, so the
            // grid closes and the plane arrives on screen together.
            //
            // **`showsLetterKeys` is the question, not a list of overlays**, and
            // the difference is a keyboard a user can build: `KeyboardView+Keys`
            // usually drops this row while the CopyClip list is open, but only
            // when the key that closes the list is in the action row, so somebody
            // who moved CopyClip down here keeps `123` under the panel and would
            // meet the same invisible switch. The panels that hide the letters
            // are exactly the panels a plane switch has to close.
            //
            // The two search states are deliberately not among them: they put the
            // letters back, and `consumeForEmojiSearch` lets the plane switch
            // through on purpose so a query can be typed in either alphabet —
            // closing the box here would be this key deleting what was typed
            // into it.
            //
            // `show(.none)` fires the modifier haptic itself, so this key takes
            // its own in the `else` or it buzzes twice for one tap, which is the
            // defect `case .emoji` below records.
            if overlay.showsLetterKeys {
                Feedback.modifierPress()
            } else {
                show(.none)
            }
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
            armShiftAtBoundary()
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
        case .copyclip:
            // Same as emoji: `show(_:)` already fires the haptic.
            show(overlay.isCopyClip ? .none : .copyclip)
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
        // **Both of these end a hand repair, and they are the only keys that do so
        // without changing a character**: it is a claim about the word under the
        // caret, and the caret is what just moved.
        //
        // **They used to end the undo window too, and no longer do.** That was
        // right while a selection-scoped revert deleted a count of units from
        // wherever the caret happened to be standing; `RevertibleEdit
        // .spanUndo(behind:)` locates what the edit wrote before it deletes
        // anything, so a caret moved off the span refuses on its own and a caret
        // moved back over it undoes correctly. `refreshSuggestions` below asks
        // that question either way.
        case .cursorLeft:
            Feedback.keyPress()
            deletedWordPrefix = nil
            pendingAutocorrectUndo = nil
            target?.adjustTextPosition(byCharacterOffset: -1)
            refreshSuggestions()
        case .cursorRight:
            Feedback.keyPress()
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

    // MARK: A character key's own touch

    /// One touch on a character key, forwarded from `KeyView`.
    ///
    /// The counterpart of `spaceBarTouch(_:)`, and the same division of labour:
    /// the key reports what the finger did and the controller decides what the
    /// document gets.
    public func characterTouch(_ phase: CharacterTouchPhase) {
        switch phase {
        case .began(let cap, let point):
            beginCharacterTouch(cap, at: point)
        case .ended:
            commitCharacterTouch()
        }
    }

    /// A finger landed on a character key. Nothing is typed yet.
    ///
    /// **The letter waits for the lift so a long press can replace it**, which is
    /// NIT-108 and is argued in `KeyView.defersCharacterToLift`. Two things about
    /// the wait are load-bearing here rather than there.
    ///
    /// **The rollover answer is this function, not the lift.** A fast typist has
    /// the next key down before the last one is up, and lifts them in whatever
    /// order the hands happen to take — press `a`, press `b`, lift `b`, lift `a`
    /// is an ordinary thing for two thumbs to do, and committing on lift alone
    /// would spell it `ba`. So the *arrival* of a touch is what settles the one
    /// before it: every key that acts pays the open ones first, and a letter can
    /// therefore never outrun a letter that went down earlier. The longest a
    /// character can be held back is the dwell of the finger that is still on it,
    /// and only when nothing else has been pressed since.
    ///
    /// **The click and the thud stay on the finger-down.** They are the half of
    /// the answer a thumb feels rather than reads, and moving them to the lift
    /// would make the whole key feel like a button that fires on release. The
    /// deferred press is told they are already spent (`playsFeedback: false`),
    /// because one tap buzzing twice is the Emoji key's defect recorded in
    /// `.claude/rules/keyboard-layout.md`.
    public func beginCharacterTouch(_ cap: KeyCap, at unitPoint: CGPoint? = nil) {
        payOpenTouches(before: cap)
        Feedback.keyClick(cap.clickSound)
        Feedback.keyPress()
        pendingCharacter = (cap, unitPoint)
    }

    /// Types the character a finger has been holding, if one is waiting.
    ///
    /// **Idempotent, and every exit path a touch has calls it.** `KeyView.endPress`
    /// runs on a lift, on a cancelled gesture and on the key leaving the screen,
    /// and a normal lift reaches it twice; clearing the slot before typing is what
    /// makes the second call and the cancellation-after-lift ordering harmless.
    @discardableResult
    public func commitCharacterTouch() -> Bool {
        guard let pending = pendingCharacter else { return false }
        // Cleared first: `press` pays open touches of its own, and a slot still
        // holding this character would send it straight back in here.
        pendingCharacter = nil
        press(pending.cap, at: pending.unitPoint, playsFeedback: false)
        return true
    }

    /// Throws away a character no finger is still holding, without typing it.
    ///
    /// **The one path that discards rather than commits, and the reason is that
    /// the document it was meant for is gone.** iOS keeps one extension instance
    /// alive across fields *and across host apps* (`.claude/rules/keyboard-wiring.md`),
    /// and a keyboard torn down mid-press is not promised a `SwiftUI` disappear
    /// callback — so without this, a character parked in a WhatsApp reply could be
    /// typed into the Notes field the keyboard came back up over. That is the
    /// "pending state becomes a character from the last app" failure, and it is
    /// strictly worse than losing the keystroke: the user saw the keyboard go
    /// away, and nothing they did in the old field belongs in the new one.
    ///
    /// Called from `prepareForNewDocument()`, which `KeyboardViewController`
    /// runs from `viewWillAppear`. Every *other* way a touch ends still commits,
    /// through `KeyView.endPress` — see `CharacterTouchPhase.ended`.
    public func discardPendingCharacter() {
        pendingCharacter = nil
    }

    /// What touches still on the glass owe the document, paid before the key that
    /// is about to act.
    ///
    /// **Order is the whole job, and the character goes first.** The two can only
    /// ever be open together in one order: a character key landing on top of an
    /// open space bar pays that space on the way in, so a character that is still
    /// parked while a space is owed can only have been parked *before* that space
    /// bar was touched. Three fingers on the glass is what reaches it — a thumb
    /// resting on a letter, the other on space, and a third key pressed under both
    /// — and paying the space first there would spell `a b` as ` ab`. In the
    /// ordinary two-finger case the character commit is a no-op and this order
    /// costs nothing.
    /// **The debt is claimed before either is paid, and that is what makes the
    /// order hold.** `commitCharacterTouch` goes back through `press`, which pays
    /// open touches of its own — so settling the space first inside that nested
    /// call would put it back in front of the character it is supposed to follow.
    /// `interrupted()` marks the space spent as it answers, so the nested pass
    /// finds nothing left to do and the space lands where this function puts it.
    func payOpenTouches(before cap: KeyCap? = nil) {
        let owesSpace = cap != .space && spaceTouch.interrupted()
        commitCharacterTouch()
        if owesSpace {
            // Clicks *before* this key does, for the reason the space is typed
            // before it: the other thumb pressed it first. `insertSpace` is
            // reached from here as well as from `press`'s own `.space` branch,
            // and only that branch goes through this function's click line.
            Feedback.keyClick(KeyCap.space.clickSound)
            insertSpace()
        }
    }

    /// Shifted through `KeyboardLanguage.uppercased`, which is the one place that
    /// knows Turkish has two i's — and the one place that holds the language's
    /// `Locale`, so this does not build one per keystroke. The key cap, the
    /// callout and the long-press popup go through the same call, or the key
    /// shows one letter and types another.
    func insertCharacter(
        _ value: String, at unitPoint: CGPoint? = nil, playsFeedback: Bool = true
    ) {
        if playsFeedback { Feedback.keyPress() }
        // A key carrying several letters types no letter of its own: it adds one
        // keystroke to the word in progress and the decoder says what that word
        // is. A single letter arriving *while* a grouped word is open is the
        // long-press escape hatch picking one letter out of the group just
        // pressed, which pins that position rather than starting a new key.
        if isGroupedCap(value) {
            pressGroupedKey(value, at: unitPoint)
            return
        }
        if isGroupedTyping, pinGroupedLetter(value) {
            return
        }
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
        // **The way back to what Fix or Rewrite replaced survives this keystroke**,
        // which it did not until NIT-154: it used to be cleared here, on the
        // argument that putting the old text back would take the new characters
        // with it. That was true of a revert that replaced the whole field and is
        // no longer true of one that finds its own span
        // (`RevertibleEdit.rebased(onto:)`), so the retirement moved to
        // `expireRevertibleEditIfUnusable`, which `refreshSuggestions` asks below.
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
        let inserted = output.replacingOccurrences(of: "\n", with: "")
        target?.insertText(inserted)
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
    ///
    /// Not private: `selectedWord` asks the same question of the character after
    /// a selection, and two lists of the marks that live inside a word is one
    /// list that can disagree with itself about Hebrew's geresh. The set itself
    /// lives on `SuggestionEngine`, not here, because `Bar/typing/harness`
    /// compiles `SuggestionEngine*.swift` and the models for a scoring run with
    /// no `KeyboardController` in the build at all, and `commitReason` needs to
    /// ask the identical question of a candidate before it ever reaches a
    /// controller.
    static func staysInsideWord(_ character: Character) -> Bool {
        SuggestionEngine.staysInsideWord(character)
    }

    /// An item picked out of a character key's popup, replacing the letter that
    /// key has already typed.
    ///
    /// **Delete-then-retype, because the letter is already in the field.** The
    /// key commits on the lift now (NIT-108) and `KeyView.endPress` reports that
    /// lift one line above the pick, so by the time this runs the base letter is
    /// standing where the alternate has to go. The delete does not go through
    /// `press(.backspace)`: this is a key the user never pressed, and routing it
    /// there would click twice for one keystroke.
    ///
    /// **The last line is the whole reason this is a function rather than two
    /// calls at the call site.** A word reached through the popup is a word
    /// placed by hand, and `isCorrectingWordByHand` is what keeps the space bar
    /// from correcting it — `צ׳יפס`, `col·legi` and `café` are exactly the words
    /// no dictionary holds. The popup rode on `deleteBackward`'s own snapshot for
    /// that, and **that snapshot is the word *left standing*, so it is `""`
    /// whenever the mark is on the first letter of the word** — which is where
    /// Hebrew's geresh always is. An empty prefix is refused by
    /// `isCorrectingWordByHand`, and has to be, because it is a prefix of every
    /// word (`deletePreviousWord` sets exactly that). So the snapshot is retaken
    /// from the word the popup actually left in the field, one insert later:
    /// `צ׳` rather than nothing, `café` rather than `caf`. Re-reading the same
    /// expression `deleteBackward` used means a search box, where the retype
    /// never reaches the document, records exactly what it already recorded.
    public func insertAlternate(_ alternate: String) {
        deleteBackward()
        press(.character(alternate))
        deletedWordPrefix = currentWordPrefix
    }

    func insertSpace() {
        Feedback.keyPress()
        // **The way back survives a space**, which is most of what NIT-154 asked
        // for: a wrong word is noticed in the sentence it landed in, and a space
        // is what finishes the word after it. `refreshSuggestions` at the end of
        // this retires it if the correction has been typed over since.
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
            armShiftAtBoundary()
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
        // second lock on the same door, exactly as `storedAutocorrectLevel` is checked
        // both here and there: slot zero being the literal is a fact about
        // `SuggestionEngine`, and the space bar should not be the thing that breaks
        // if it ever stops being one.
        let original = currentWordPrefix
        // **Read now, before anything below writes to the document.** This is
        // what `contextAfterSwap` is built from — never a proxy read taken
        // after the swap or the space, which `insertCommittalSpace`'s own doc
        // comment already records as unreliable: "this keyboard's own
        // delete-then-insert can leave the proxy reporting stale context for a
        // moment right after a write it just made." A stale post-write read
        // there only cost a wasted hop; here it would poison the undo's claim
        // forever, since every later, honest read would then disagree with a
        // snapshot that was wrong from the moment it was taken. See the note on
        // `pendingAutocorrectUndo`'s own declaration.
        let contextBeforeSwap = contextBefore
        var swapped: (original: String, replacement: String)?
        if store.storedAutocorrectLevel != .off,
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
        // can be taken back by the next delete. **Built from `contextBeforeSwap`,
        // never re-asked of the proxy**: the context right after the swap's own
        // space landed is exactly the text in front of the word that was there
        // before the swap, plus the replacement, plus that space — arithmetic on
        // a string this function already holds, not a fact that needs asking
        // `target` for a second time.
        pendingAutocorrectUndo = swapped.map {
            (
                original: $0.original, replacement: $0.replacement,
                contextAfterSwap: String(contextBeforeSwap.dropLast(original.count)) + $0.replacement
                    + " "
            )
        }
        // The one case an ordinary space arms shift: a `.words` field
        // capitalises every word, not only the first letter of a sentence.
        if autocapitalizationMode == .words { armShiftAtBoundary() }
        refreshSuggestions()
    }

    public func deleteBackward() {
        Feedback.keyPress()
        // Deleting can empty the field as easily as typing can fill it, so the
        // refusal has to be re-earned either way rather than left standing.
        block = nil
        // A delete that eats into what the last action wrote is what retires the
        // way back, and `refreshSuggestions` at the end of this notices. A delete
        // somewhere else leaves it standing.
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
    ///
    /// **Not over a selection.** A backspace with a range selected deletes the
    /// selection, the way it does everywhere else on this keyboard — a selection
    /// starting right after a fresh swap used to satisfy the claim check below
    /// exactly the same as a plain caret, which deleted the selection *and*
    /// resurrected `original` in front of it, destroying text the selection
    /// never touched.
    @discardableResult
    func undoAutocorrectIfPending() -> Bool {
        guard let pending = pendingAutocorrectUndo,
            !pending.replacement.isEmpty,
            selection == nil,
            contextBefore == pending.contextAfterSwap
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
    /// lands, so the first refresh still sees the exact context that was
    /// captured then.
    func expirePendingAutocorrectUndoIfCaretMoved() {
        guard let pending = pendingAutocorrectUndo else { return }
        if pending.replacement.isEmpty || contextBefore != pending.contextAfterSwap {
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
        if overlay == .copyclipSearch {
            if copyclipQuery.isEmpty {
                show(.copyclip)
            } else {
                let suffix = Self.previousWordSuffix(in: copyclipQuery)
                setCopyclipQuery(String(copyclipQuery.dropLast(suffix.count)))
            }
            return
        }

        Feedback.keyPress()
        block = nil
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
    /// `מאמין` leaves `מאמי`, which no dictionary knows, so `commitReason`
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

    /// Arms or disarms shift for a word or sentence boundary, following the
    /// mode `KeyboardController.adoptFieldAutocapitalization` decided at focus.
    ///
    /// Called from Return, the double-space full stop, and — only in a
    /// `.words` field — an ordinary space; nowhere else touches shift
    /// automatically. `.sentences` and its nil fallback keep the exact
    /// expression Return and the double-space full stop already used, so a
    /// host that stays silent about the trait sees no change.
    ///
    /// **Never touches a `.locked` shift.** Caps lock only ever comes from the
    /// user's own `toggleShift()`, and a boundary this keyboard crosses is not
    /// a decision to cancel it — the same "decide at focus, do not fight them
    /// mid-field" rule `adoptFieldAutocapitalization` is written under.
    func armShiftAtBoundary() {
        guard shift != .locked else { return }
        switch autocapitalizationMode {
        case .none: shift = .off
        case .allCharacters: break
        case .words, .sentences: shift = store.storedAutocapitalise ? .on : .off
        @unknown default: shift = store.storedAutocapitalise ? .on : .off
        }
    }

    // MARK: Emoji

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
        // Starts on the way in and stops on the way out, both from here, because
        // this is the one function that sees every overlay change. See
        // `watchPasteboardWhileCopyClipIsOpen()` for what it is for; without it
        // a copy made while the panel is open is never offered.
        watchPasteboardWhileCopyClipIsOpen()
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
