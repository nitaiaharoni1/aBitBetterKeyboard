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
        press(
            cap, at: unitPoint, touchEvidence: nil,
            playsFeedback: playsFeedback)
    }

    func press(
        _ cap: KeyCap, at unitPoint: CGPoint?, touchEvidence: KeyTouchEvidence?,
        playsFeedback: Bool
    ) {
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

        performPress(cap, at: unitPoint, touchEvidence: touchEvidence, playsFeedback: playsFeedback)
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

    /// Adds the UIKit contact sample to the character already waiting for its
    /// lift. An older rollover touch cannot overwrite a newer pending key.
    func characterTouchEvidence(_ evidence: KeyTouchEvidence, for cap: KeyCap) {
        guard var pending = pendingCharacter, pending.cap == cap else { return }
        if let currentID = pending.touchEvidence?.sequenceID,
            let nextID = evidence.sequenceID,
            currentID != nextID
        {
            return
        }
        pending.touchEvidence = evidence
        pendingCharacter = pending
    }

    /// Ends only the character owned by this finger. In a rollover, lifting the
    /// older key must not commit the newer key while that finger is still down.
    func endCharacterTouch(for cap: KeyCap, sequenceID: UUID?) {
        guard pendingCharacter?.cap == cap else { return }
        if let pendingID = pendingCharacter?.touchEvidence?.sequenceID,
            let sequenceID,
            pendingID != sequenceID
        {
            return
        }
        commitCharacterTouch()
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
        beginCharacterTouch(cap, at: unitPoint, touchEvidence: nil)
    }

    func beginCharacterTouch(
        _ cap: KeyCap, at unitPoint: CGPoint?, touchEvidence: KeyTouchEvidence?
    ) {
        payOpenTouches(before: cap)
        Feedback.keyClick(cap.clickSound)
        Feedback.keyPress()
        pendingCharacter = (cap, unitPoint, touchEvidence)
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
        press(
            pending.cap, at: pending.unitPoint, touchEvidence: pending.touchEvidence,
            playsFeedback: false)
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
    /// **Order is the whole job, and the character goes first.** The two should
    /// never be open together at all now: a character key landing on top of an
    /// open space bar pays that space on the way in, and the space bar landing
    /// on top of a parked character commits that character on the way in
    /// (`spaceBarTouch(.began)`). Before the second half existed, `o` down,
    /// space down, `o` up spelled `hello world` as `hell oworld`, because the
    /// letter's lift came through here and paid the space first. The character
    /// still goes first as a belt-and-braces order, so if a phase ever arrives
    /// out of sequence, `a b` cannot come out as ` ab`.
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
        _ value: String, at unitPoint: CGPoint? = nil,
        touchEvidence: KeyTouchEvidence? = nil, playsFeedback: Bool = true
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
        retirePendingAutocorrectUndo(.acceptLearning)
        // **A cap never types a line break.** The only newline any cap carries is
        // the one a banded grouped cap uses to say where its second row of letters
        // starts, and `.ret` is the key that inserts a line. Reachable only in the
        // narrow window where the keyboard is still drawn grouped and the dial has
        // already gone off — the user switched it in the containing app, or tapped
        // into a password field — where the alternative is a line break appearing
        // in somebody's message.
        let output = shift.isUppercase ? language.uppercased(value) : value
        let extendsPersonalValue = preparePersonalTokenForInput(output)
        // A full stop, a comma, emoji, `.com` — anything that is not a letter
        // inside a word — finishes the word the same way space does. Learn first:
        // once the mark is in the field, `learnWordJustCommitted` will refuse so
        // a later space does not count the same word twice. Apostrophe, hyphen
        // and Hebrew geresh stay inside the word.
        if Self.finishesWord(output), !extendsPersonalValue, !consumeGroupedSkipLearn() {
            learnWordJustCommitted()
        }
        let inserted = output.replacingOccurrences(of: "\n", with: "")
        target?.insertText(inserted)
        let word = currentWordPrefix
        if word.isEmpty {
            typingTouchTrace.clear()
        } else {
            let touchContext = String(contextBefore.dropLast(word.count))
            typingTouchTrace.record(
                inserted: inserted, evidence: touchEvidence, language: language, word: word,
                context: touchContext)
        }
        if shift == .on { shift = .off }
        refreshSuggestions()
        noteTypedInput()
    }

    /// Marks that close a token, not the ones that live inside one.
    static func finishesWord(_ value: String) -> Bool {
        if value.count == 1, let character = value.first {
            if staysInsideWord(character) { return false }
            return !character.isLetter && !character.isNumber
        }
        // Snippets such as `.com` finish the word in front of them.
        return value.contains { !staysInsideWord($0) && !$0.isLetter && !$0.isNumber }
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
        // Any other delete has moved on from the one exact backspace that can
        // restore the original. This includes deleting a selection that starts
        // at the same context boundary as the pending claim.
        retirePendingAutocorrectUndo(.acceptLearning)
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
        guard let pending = pendingAutocorrectUndo else { return false }
        guard pending.documentIdentifier == target?.documentIdentifier else {
            retirePendingAutocorrectUndo(.acceptLearning)
            return false
        }
        guard
            !pending.replacement.isEmpty,
            selection == nil,
            contextBefore == pending.contextAfterSwap
        else { return false }
        target?.deleteBackward()
        guard
            Self.unitsRemoved(
                from: Array(pending.contextAfterSwap.utf16), to: Array(contextBefore.utf16),
                expectedTrailingCharacterWidth: 1) == 1
        else { return true }
        guard replaceCurrentWord(with: pending.original) else {
            target?.insertText(" ")
            refreshSuggestions()
            return true
        }
        personal.recordRejectedCorrection(
            original: SuggestionEngine.wordCore(pending.original),
            replacement: SuggestionEngine.wordCore(pending.replacement),
            language: pending.learnedCommit.language,
            permitted: pending.learnedCommit.permitted)
        vocabularyVersion &+= 1
        retirePendingAutocorrectUndo(.discardLearningForUndo)
        undoneAutocorrectSpellings.insert(SeedLanguageModel.fold(pending.original))
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
        guard pending.documentIdentifier == target?.documentIdentifier else {
            retirePendingAutocorrectUndo(.acceptLearning)
            return
        }
        if pending.replacement.isEmpty {
            retirePendingAutocorrectUndo(.acceptLearning)
        } else if contextBefore != pending.contextAfterSwap {
            retirePendingAutocorrectUndo(.acceptLearning)
        }
    }

    func retirePendingAutocorrectUndoIfDocumentChanged() {
        guard let pending = pendingAutocorrectUndo,
            pending.documentIdentifier != target?.documentIdentifier
        else { return }
        retirePendingAutocorrectUndo(.acceptLearning)
    }

    func retirePendingAutocorrectUndo(_ retirement: PendingAutocorrectRetirement) {
        guard let pending = pendingAutocorrectUndo else { return }
        pendingAutocorrectUndo = nil
        switch retirement {
        case .discardLearningForUndo:
            return
        case .acceptLearning:
            break
        }
        guard pending.shouldLearn else { return }
        recordCommittedWord(pending.learnedCommit)
        // The replacement's own space already crossed its word boundary. Keep
        // the duplicate guard from leaking into the next word, including
        // repeated text such as "hello hello".
        lastLearnedFolded = nil
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

    /// Whether the caret sits where automatic capitalisation may arm at all.
    ///
    /// **`shift` started `.on` at construction and `adoptFieldAutocapitalization`
    /// re-armed it at focus with the same unconditional answer**, so a keyboard
    /// coming up over a field that already held text capitalised whatever letter
    /// was typed next, wherever the caret sat: a half-written message reopened at
    /// `hey how are yo` typed `yoU`. The first letter after an autocorrect undo
    /// came back `heloW` the same way, and *nothing on the undo path arms shift* —
    /// the arm had been standing since construction, `insertSpace` and
    /// `undoAutocorrectIfPending` never touch it, and only `insertCharacter`'s
    /// one-shot ever lowers it, so a document whose word was placed rather than
    /// typed carries the arm all the way to the letter after the undo. A
    /// `.sentences` field capitalises the start of a *sentence*, not the next key
    /// pressed.
    ///
    /// **Only the automatic arm asks this.** A `.on` the user set by hand comes
    /// from `toggleShift()` and is never re-decided — the same "decide at focus,
    /// do not fight them mid-field" rule `armShiftAtBoundary` guards `.locked`
    /// under. `armShiftAtBoundary`'s own three call sites, Return, the
    /// double-space full stop and a `.words` space, are boundaries by
    /// construction and so do not ask; this is for the two places that arm with
    /// no key having been pressed at all.
    func caretBeginsACapitalizedRun(mode: UITextAutocapitalizationType) -> Bool {
        let before = contextBefore
        if mode == .words {
            // Every position that is not inside a word starts the next one.
            guard let last = before.last else { return true }
            return !(last.isLetter || last.isNumber || Self.staysInsideWord(last))
        }
        // `.sentences`, and the nil fallback that reads as it: the start of the
        // document, a fresh line, or the mark that ended the sentence before.
        // Trailing closers are stepped over, so `He said "Hi." ` still arms.
        var run = Substring(before)
        while let last = run.last,
            (last.isWhitespace && !last.isNewline) || Self.sentenceClosers.contains(last)
        {
            run = run.dropLast()
        }
        guard let last = run.last else { return true }
        return last.isNewline || Self.sentenceTerminators.contains(last)
    }

    /// The marks that end a sentence.
    static let sentenceTerminators: Set<Character> = [
        ".", "!", "?", "\u{2026}", "\u{3002}", "\u{FF01}", "\u{FF1F}", "\u{061F}"
    ]

    /// Quotes and brackets that may stand between the mark that ended a sentence
    /// and the caret.
    static let sentenceClosers: Set<Character> = [
        "\"", "'", ")", "]", "}", "\u{00BB}", "\u{201D}", "\u{2019}"
    ]

    // MARK: Emoji

}
