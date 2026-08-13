import SwiftUI

extension KeyboardController {

    // MARK: Dictation

    public func startDictation() {
        reportInteraction(.dictation)
        // **These resets are above the guard, not below it, and that is not
        // tidiness.** They used to run unconditionally, before the availability
        // check opened the panel; putting the check first left the no-session tap
        // without them. The last two are the streaming bookkeeping, and they belong
        // in the same place for the same reason: a refused tap has to leave nothing
        // behind that a later recording would try to delete. `dictation.$failure`
        // used to only ever *set* `dictationFailure`, and the only other place
        // that cleared it was `stopDictation`'s teardown — which the user reached
        // through a Dismiss button on a "Nothing to insert" strip that is gone.
        // A refusal left behind by a session that closed itself sat in the
        // property until the next live session brought it back on screen,
        // attached to a recording that had not failed. The sink no longer sets
        // it; this reset stays so a leftover cannot resurface.
        dictationTranscript = ""
        dictationFailure = ""
        pendingDictationInsert = false
        streamedDictation = ""
        dictationStreamAbandoned = false

        // **This is what the guard below is asking, and without it the answer
        // was a value nothing had ever read.** `DictationSession.availability`
        // only tracks the shared page while its poll is running, and the poll
        // used to be started *below* the check that reads it — after the refusal
        // had already returned. So the check read the `.noSession(.notEnded)` the
        // session is initialised with, the banner said "No dictation session" over
        // a session that was live in the app, and the poll that would have
        // corrected it was never reached: every tap refused, on every device, for
        // as long as the keyboard was up. `refresh()` rather than
        // `startWatching()` because the refusal must not leave a timer running —
        // `DictationRequest.keyboardAliveAt` is a dead-man's switch and a timer
        // outliving the keyboard is the one thing that defeats it — and because
        // `stopWatching()` clears the availability this refusal is about to
        // print. The live path starts the watch below, where `refresh()` runs
        // again for nothing.
        dictation.refresh()

        guard dictation.availability.isLive else {
            let remedy = dictationRefusalRemedy
            refuse(
                .init(
                    action: nil,
                    title: dictationRefusalTitle,
                    detail: dictationRefusalDetail,
                    remedy: remedy))
            // For `.noSession`: record the handoff intent so the app can pick it
            // up on cold launch, then immediately ask the host to open the app.
            // The banner's `Link` also records on tap via the same helper so a
            // user who waits longer than 30 seconds before tapping it still
            // lands a fresh request.
            if case .openApp(let url) = remedy {
                recordDictationHandoff()
                onOpenContainingApp?(url)
            }
            return
        }

        dictation.startWatching()
        observeDictation()
        isDictating = dictation.beginUtterance()
        if isDictating {
            // **No haptic here, and there used to be one.** The only route in is
            // `toggleDictation()` from `press(.dictation)`, which has already fired
            // `Feedback.actionPress()` for the key — so this buzzed a second time
            // for one tap, which is the defect `.claude/rules/keyboard-layout.md`
            // records the Emoji key shipping. The refusal path below deliberately
            // has none either, for the same reason `refuse(_:)` does not.
            //
            // **The way back from the last Fix goes when the recording opens, not
            // when its first words land.** Two reasons, and the second is the one
            // that matters. A revert replaces the *whole* field with what was there
            // before, so once anything has been spoken into it that undo would
            // delete the sentence — which is why the transcript sinks clear it too.
            // Inside this branch rather than beside the resets above it, so a
            // *refused* tap does not quietly take away an undo the user still has.
            clearRevertibleEdit()
            // And a call that was already running when the microphone was tapped
            // goes with it. `run(_:)` refuses to *start* one during a recording;
            // this is the other half, and without it the answer to the pre-recording
            // sentence reappears behind a Use button the moment the recording ends,
            // offering to replace everything that was said. See `cancelAIWork`.
            cancelAIWork()
            // **Written on every utterance opened, not once at install.** A
            // user who slides the space bar to a different language between
            // two dictations needs the second one hinted with that language,
            // and `enabledLanguages` alone cannot say which of the enabled
            // languages is live right now — only the layout on screen at the
            // moment of the tap can. See `SharedStore.storedDictationLanguage`.
            store.recordDictationLanguage(language)
        }
    }

    /// Starts a recording when none is open, and finishes the open one.
    ///
    /// **The microphone key's whole job, and it is the only control this feature
    /// has.** Two modes: record starts, pause stops. The × that used to cancel a
    /// transcription in flight is gone — the insert is already on its way, and
    /// cancelling it threw away a sentence the user had just spoken.
    ///
    /// `.finishing` is the window between the pause tap and the words arriving.
    /// `isDictating` is already false there, so a tap that asked only that
    /// question opened a **second** utterance on top of a transcription still in
    /// flight. The tap is ignored instead: not a cancel, not a new recording.
    public func toggleDictation() {
        switch dictationKeyState {
        case .recording: stopDictation(insert: true)
        case .finishing: return
        case .idle: startDictation()
        }
    }

    /// The two states that are not a recording, in the words the strip prints.
    private var dictationRefusalTitle: String {
        switch dictation.availability {
        case .needsFullAccess: return "Needs Full Access"
        default: return "Dictation isn't running"
        }
    }

    private var dictationRefusalDetail: String {
        switch dictation.availability {
        case .needsFullAccess:
            return
                "Dictation records in the app.\nTurn on Full Access in Settings › General › Keyboard › Keyboards."
        case .noSession(let reason):
            // The reason only prints when it is news. "Nobody has started one" and
            // "you stopped it" are the ordinary states, and narrating them would
            // make the sentence longer without making it more useful.
            let why =
                reason == .notEnded || reason == .stoppedByUser ? "" : reason.explanation + "\n"
            return
                "\(why)Dictation starts automatically in AI Keyboard — swipe back to continue."
        default:
            return ""
        }
    }

    /// What the banner trailing chip offers for this refusal.
    ///
    /// `.needsFullAccess` cannot be fixed from here — the user has to go to
    /// Settings, which no extension can open. `.noSession` can be handed off to
    /// the containing app via the deep link the banner button triggers.
    private var dictationRefusalRemedy: BannerState.Block.Remedy {
        switch dictation.availability {
        case .needsFullAccess: return .none
        default: return .openApp(SharedStore.dictationStartURL)
        }
    }

    /// Writes a fresh timestamped handoff request to the shared store.
    ///
    /// Called from the initial no-session tap and from the banner `Link`'s
    /// simultaneous gesture so a user who waits longer than 30 seconds before
    /// tapping the fallback button still lands a fresh request for the app to
    /// consume on cold launch.
    func recordDictationHandoff() {
        store.recordDictationHandoff()
    }

    public func stopDictation(insert: Bool) {
        if insert, isDictating {
            pendingDictationInsert = true
            isDictating = false
            dictation.stopUtterance()
            return
        }

        // **The third clause used to be `overlay == .dictation` and dropping it
        // outright would have wedged a leftover refusal.** It was what let a
        // *stopped* session still be torn down — and the state that needed that
        // was a recording that failed while the "Nothing to insert" strip was
        // still up: `dictation.$failure` cleared `isDictating` and
        // `pendingDictationInsert` before setting the reason, so by the time
        // the user tapped Dismiss the first two were both false. That strip is
        // gone and the sink stops the watch itself now; the clause stays so a
        // leftover `dictationFailure` can still be cleared rather than sitting
        // until the next session.
        guard isDictating || pendingDictationInsert || !dictationFailure.isEmpty else { return }

        pendingDictationInsert = false
        isDictating = false
        dictation.cancelUtterance()
        dictation.stopWatching()
        dictationTranscript = ""
        dictationFailure = ""
        // **Forgotten, never deleted.** What was streamed is what the user said,
        // and this is reached from the keyboard being dismissed as well as from a
        // cancel — taking text out of somebody's message on the way off screen is
        // not a thing a keyboard may do. Clearing the record only means the next
        // recording will not try to replace text it did not write.
        streamedDictation = ""
        dictationStreamAbandoned = false
    }

    // MARK: Streaming

    /// Puts the words into the field as they are spoken.
    ///
    /// **A transcript used to arrive once, at the end, and the wait was the whole
    /// feel of the feature**: the user finished a sentence, tapped Stop, and
    /// watched a keyboard do nothing for the two seconds a cloud call takes. The
    /// recorder publishes a better reading of the same audio every couple of
    /// seconds now (see `DictationService`), and each one replaces the last — so
    /// what is in the field is always the whole utterance as currently understood,
    /// never a growing pile of fragments, and words move as later audio settles
    /// them.
    ///
    /// It refuses to run once the field has moved out from under it. See
    /// `replaceStreamedDictation`.
    func streamDictation(_ text: String) {
        guard isDictating || pendingDictationInsert, !dictationStreamAbandoned else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != streamedText else { return }
        // **The field moved, so this recording stops writing to it.** A partial
        // that cannot take out the draft it replaces would put a second copy of
        // the sentence in beside the first, and then a third on the next partial —
        // so a draft is dropped rather than duplicated. The *final* transcript is
        // not, which is the whole reason this decision is here and not inside
        // `replaceStreamedDictation`: giving up on a draft costs a couple of
        // seconds of text that is already on screen, and giving up on the
        // transcript would lose the sentence outright.
        guard canReplaceStreamedDictation(with: trimmed) else {
            dictationStreamAbandoned = true
            streamedDictation = ""
            return
        }
        replaceStreamedDictation(with: trimmed)
    }

    /// What this recording has written into the field, without the space that was
    /// put in front of it.
    private var streamedText: String {
        streamedDictation.hasPrefix(" ") ? String(streamedDictation.dropFirst()) : streamedDictation
    }

    /// What has to be standing at the caret before a single character is deleted.
    ///
    /// **The run that is actually about to be removed, not the whole draft, and
    /// that difference is what lets streaming survive a long dictation.**
    /// `documentContextBeforeInput` is a *window* — iOS truncates it, and there is
    /// nothing behind it to reach for — so a draft longer than that window can
    /// never be found whole inside it. Checking against the whole draft therefore
    /// stops streaming partway through exactly the long dictations streaming is
    /// for, and hands the user a duplicated sentence at the end for its trouble.
    /// The stale run is a word or two, so it is always inside the window.
    ///
    /// The safety guarantee is unchanged and is the one that matters: nothing is
    /// deleted unless the characters about to be deleted are the ones this
    /// recording wrote and are sitting at the caret right now.
    ///
    /// When the new reading only *extends* the old one there is nothing to delete,
    /// and the anchor becomes the end of the draft instead — otherwise a stray
    /// keystroke at the caret would be silently written over the top of.
    private func streamAnchor(replacing text: String) -> String {
        let old = streamedText
        let stale = String(old.dropFirst(old.commonPrefix(with: text).count))
        guard stale.isEmpty else { return stale }
        return String(old.suffix(Self.streamAnchorCharacters))
    }

    /// How much of an unchanged draft has to be found at the caret. Long enough
    /// that a keystroke or a caret move cannot slip past it, short enough to sit
    /// inside any host's context window.
    static let streamAnchorCharacters = 16

    /// Whether the draft this recording wrote is still where it was left.
    private func canReplaceStreamedDictation(with text: String) -> Bool {
        guard !streamedDictation.isEmpty else { return true }
        return contextBefore.hasSuffix(streamAnchor(replacing: text))
    }

    /// Swaps what this recording has already written for a better reading of it.
    ///
    /// **Only the tail that actually changed is rewritten, and that is a
    /// performance requirement rather than a nicety.** Each reading is nearly all
    /// of the one before it, and `deleteBackward(utf16Units:)` is a loop of proxy
    /// calls that reads `documentContextBeforeInput` twice per press to find out
    /// what a press removed. Retyping the whole utterance every two seconds is
    /// therefore hundreds of round trips through the host for a sentence that grew
    /// by one word — about 1,300 of them on a thirty-second dictation, on the main
    /// thread, while the user is speaking. Deleting from the first character that
    /// differs makes the ordinary partial a handful of keystrokes, and it stops the
    /// whole sentence flickering in the field four times a minute.
    ///
    /// **What it will not do is delete text it did not write.** When the draft is
    /// no longer at the end of the field it is left exactly where it is and the new
    /// text is inserted at the caret — a duplicate, and the honest one: this is
    /// reached with the final transcript, which is the whole of what was said, and
    /// dropping it would be losing the sentence to avoid an untidy field. The
    /// partial path never gets this far; `streamDictation` asks
    /// `canReplaceStreamedDictation(with:)` first and gives up instead.
    func replaceStreamedDictation(with text: String) {
        endGroupedWord()
        guard !streamedDictation.isEmpty else {
            insertStreamedDictation(text)
            return
        }
        guard canReplaceStreamedDictation(with: text) else {
            dictationStreamAbandoned = true
            streamedDictation = ""
            insertStreamedDictation(text)
            return
        }

        // `commonPrefix` compares by `Character`, so a grapheme cluster is either
        // wholly shared or wholly rewritten — which is what keeps the UTF-16 count
        // below from ever landing inside an emoji or a Hebrew letter with niqqud on
        // it. The count itself has to be UTF-16, because that is what the proxy
        // deletes in.
        let old = streamedText
        let shared = old.commonPrefix(with: text)
        deleteBackward(utf16Units: old.utf16.count - shared.utf16.count)
        let fresh = String(text.dropFirst(shared.count))
        if !fresh.isEmpty { target?.insertText(fresh) }
        streamedDictation = (streamedDictation.hasPrefix(" ") ? " " : "") + text
        refreshDocumentState()
    }

    /// Writes a reading into a field this recording has nothing standing in.
    private func insertStreamedDictation(_ text: String) {
        endGroupedWord()
        // Asked of the field as it is now, which after an abandoned draft includes
        // that draft: this is a question about what the text is landing next to.
        let before = contextBefore
        let inserted = (before.isEmpty || before.hasSuffix(" ") ? "" : " ") + text
        target?.insertText(inserted)
        streamedDictation = inserted
        // The two keys that need text light up as soon as there is some. The full
        // `refreshSuggestions` is deliberately not called: the host's own
        // `textDidChange` will run it for this insertion anyway, and this path also
        // runs in the in-app playground, where there is no host to do it.
        refreshDocumentState()
    }

    static func isRightToLeft(reported: String, text: String) -> Bool {
        if let tag = reported.split(separator: ",").first,
            let language = KeyboardLanguage(languageTag: String(tag))
        {
            return language.isRightToLeft
        }
        return SuggestionEngine.languages(in: text).first?.isRightToLeft == true
    }

    func observeDictation() {
        guard dictationObservers.isEmpty else { return }

        // The words so far, replaced wholesale each time a better reading of the
        // same audio arrives. See `streamDictation`.
        dictation.$partialTranscript
            .sink { [weak self] text in
                guard let self, !text.isEmpty else { return }
                self.dictationTranscript = text
                self.dictationIsRightToLeft = Self.isRightToLeft(
                    reported: self.dictation.transcriptLanguages, text: text)
                // A spoken sentence is text arriving in the field by the user's own
                // act, so it takes the way back from a Fix or a Rewrite with it —
                // that undo replaces the *whole* field with what was there before,
                // which after this would mean deleting what they just said.
                self.clearRevertibleEdit()
                self.streamDictation(text)
            }
            .store(in: &dictationObservers)

        dictation.$transcript
            .sink { [weak self] text in
                guard let self, !text.isEmpty else { return }
                self.dictationTranscript = text
                self.dictationIsRightToLeft = Self.isRightToLeft(
                    reported: self.dictation.transcriptLanguages, text: text)
                guard self.pendingDictationInsert else { return }
                self.pendingDictationInsert = false
                Feedback.success()
                self.clearRevertibleEdit()
                // **The last reading replaces every earlier one rather than being
                // appended to them.** It is a transcription of the whole utterance
                // with all of the audio behind it, so it is the better text as well
                // as the complete one; the partials that preceded it are drafts of
                // this exact sentence. With nothing streamed — a recording shorter
                // than the first partial, or one whose field moved — this is a plain
                // insertion, which is what it always was.
                self.replaceStreamedDictation(with: text)
                self.streamedDictation = ""
                self.dictationStreamAbandoned = false
                self.refreshSuggestions()
                self.dictation.stopWatching()
                withAnimation(Theme.Motion.panel) { self.overlay = .none }
            }
            .store(in: &dictationObservers)

        dictation.$failure
            .sink { [weak self] detail in
                guard let self, !detail.isEmpty else { return }
                self.pendingDictationInsert = false
                self.isDictating = false
                self.streamedDictation = ""
                self.dictationStreamAbandoned = false
                // **Never raise "Nothing to insert".** A silent take is a second
                // tap, and a 69pt strip that says so is the banner coming back
                // for a case the microphone key already settled: it is orange
                // record again. The last second of a failed cloud call after
                // something was streamed is the same — the sentence is in the
                // field, and a strip saying otherwise would be the keyboard
                // disagreeing with itself.
                //
                // **The watch has to stop here, by hand.** Leaving
                // `dictationFailure` empty is what keeps the strip off, and it
                // is also what makes `stopDictation` return at its own guard —
                // so nothing else would ever tear this down, not even
                // `KeyboardViewController.viewWillDisappear`, and a `RunLoop`
                // timer left running in a dismissed keyboard goes on refreshing
                // `DictationRequest.keyboardAliveAt`. That is the one thing that
                // defeats the dead-man's switch.
                self.dictation.stopWatching()
                self.refreshSuggestions()
            }
            .store(in: &dictationObservers)
    }
}
