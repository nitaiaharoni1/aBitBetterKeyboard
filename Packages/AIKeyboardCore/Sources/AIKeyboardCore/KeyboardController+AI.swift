import Foundation
import SwiftUI

extension KeyboardController {

    // MARK: AI

    public func run(_ action: AIAction) {
        // **Nothing edits the field while it is still being spoken into.** The
        // three keys are drawn disabled for the length of a recording
        // (`isActionKeyDisabled`), which is where the user is told; this is the
        // backstop behind the two that reach here, Fix and Reply.
        //
        // **It is deliberately not the only one, because the one-tap rewrite key
        // does not come through this function.** `press(.quickTone)` calls
        // `runDefaultTone()` and the register popup calls `selectTone(named:)`,
        // both of which reach `runTone(_:)` without passing here — a guard written
        // only in this function would read like it covered all three actions and
        // would cover two. `runTone(_:)` carries the same line for the same reason.
        //
        // Returning silently is right in both places: the visible statement has
        // already been made by three dim keys, and a refusal strip opening under
        // somebody mid-sentence would be the banner coming back for exactly the
        // case it was taken away for.
        guard !isDictationActive else { return }

        // Reply works on an empty field on purpose: answering a message you have
        // not started writing is the whole point of it.
        if action == .reply {
            Feedback.actionPress()
            runReply()
            return
        }

        // **Says so rather than returning silently.** Fix used to fall out of this
        // guard and draw nothing at all, which is the dead button the suggestion
        // bar's own comment records this repo shipping once already.
        guard hasTextToWorkWith else {
            // Fired here rather than in `refuse`, because the tap has not been
            // acknowledged yet on this path: the `Feedback.actionPress()` below is
            // the one a running action gets, and it sits after this guard.
            Feedback.actionPress()
            refuseForEmptyField(action)
            return
        }
        Feedback.actionPress()
        aiSourceText = aiTargetText

        switch action {
        case .reply:
            break
        case .fix:
            // The tap is proofread. Spelling, Punctuate and Polish live on the
            // long-press popup and reach `runFix` through `selectFix(named:)`.
            runFix(.proofread)
        // **Both of these clear `selectedToneIsCustom`, and forgetting it left the
        // flag lit across a Back.** It is set by `runTone`, and it used to be
        // cleared only by `dismissOverlay` — which the result panel's Back button
        // did not call, because it went to the AI menu. So running the user's own
        // tone, tapping Back and then Rewrite titled a plain three-decision Rewrite
        // "My tone" and lit the custom chip under it. Both panels are deleted and
        // there is no Back to tap, but the flag is still set by one action and read
        // by the next, so these two lines are still what stops it carrying over.
        case .rewrite:
            selectedTone = nil
            selectedToneIsCustom = false
            let source = aiSourceText
            beginWork(.rewrite, showing: .none) { [engine] in
                try await engine.variants(for: source, tone: nil)
            } apply: { controller, variants in
                controller.variants = variants
                controller.applyDirectly(variants.first?.text ?? "", for: .rewrite)
            }
        case .tone:
            // **Runs the stored register instead of opening a picker.** The picker
            // was `AIResultPanel(.variants(nil))`, a panel of six chips over the
            // keys; the six live on the one-tap key's long press now, which is where
            // a register belongs — beside the key that will use it. `AIAction.tone`
            // itself stays, because `FoundationModelsEngine.competentActions` and
            // `TextIntelligence.route` use it to tell a named-register rewrite from
            // a three-way one, which has nothing to do with menus.
            runTone(store.toneSetting)
        }
    }

    /// Reply, against whatever the user copied — or, once
    /// `FeatureFlags.screenCaptureReply` flips, whatever is on screen at the
    /// moment of the tap.
    ///
    /// **The source is decided here, at the tap, and never read off held state.**
    /// `ReplySource` answers with the message rather than with a bool about a
    /// session, because the two are not the same thing in either direction:
    /// `screenContext` may be showing a reading the freshness gate has since
    /// refused, so the capture branch asks `contextForReply()` to raise a new read
    /// and wait; and the newest clip may have been overtaken by a copy this
    /// keyboard is not allowed to read, which `ReplySource.fromClipboard` refuses on
    /// rather than answering the message before it. The wait, where there is one,
    /// happens inside `beginWork`, so the key wears the working orbit through
    /// it exactly as it does through a model call.
    private func runReply() {
        // **Before the source is asked, because it is what makes the answer
        // current.** A copied image leaves a pasteboard generation the ledger has
        // not classified, and `.userAsked` is the one refresh allowed to settle
        // that — a Reply tap is the user asking. It reads no contents and raises
        // no alert; see `refreshCopyClip(_:)`.
        refreshCopyClip(.userAsked)

        guard let source = replySource else {
            refuseForScreenContext(screenContextPrompt)
            return
        }

        let session = ScreenContextSession.shared

        // §3.3.1's guard, asked here because this is the only process that can
        // see the focused field and this is the only moment at which the field
        // is the one the user tapped in. It fails closed: a host that does not
        // answer is refused, so a Reply in a password field never becomes a
        // screenshot of a password field, and a host that answers nothing at all
        // disables the feature *visibly* — as a refusal the user reads and a
        // counter the next device run can be checked against.
        //
        // It refuses the whole action rather than only the read, which is a
        // little wider than §3.3.1 asks. Deliberate: the branch it would
        // otherwise leave open is an already-offerable reading, and writing a
        // generated sentence into a password field is not an improvement on
        // photographing one.
        //
        // **That wider half is the whole of why the clipboard path is guarded
        // too.** A clip photographs nothing — it is text the user copied
        // themselves, somewhere else, and no frame of this screen leaves the
        // device for it — so the privacy argument the guard was written for does
        // not apply to it at all. What does apply is the sentence above: Reply
        // *inserts*, and inserting a generated sentence into a credential field
        // is wrong whatever the sentence was written about. The counters keep
        // measuring the same question they always did, which is whether any host
        // populates `isSecureTextEntry` through a `UITextDocumentProxy`; every
        // Reply tap is a decision about the focused field regardless of where the
        // message came from, so counting them all is the answer rather than a
        // dilution of it.
        guard session.permitsRead(secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
        else {
            replies = []
            replyContext = nil
            isWorking = false
            // **The one `aiError` set outside `beginWork`, so the one that has to
            // clear `block` by hand.** `beginWork` does it for every other call;
            // this path never reaches it. `BannerState.resolve` tests `block` above
            // `error`, so without this a refusal left by an earlier tap — "Nothing
            // to fix yet" — stays on screen and the password-field refusal the user
            // has just earned is never shown at all.
            block = nil
            // Names what Reply would do rather than naming screen context, which
            // this build has switched off and which was never the whole reason
            // anyway: the refusal covers the insertion as well as the read.
            aiError = .screenNotRead(
                "Reply doesn't write into password fields, and this field either is one or wouldn't say."
            )
            // Named, so the banner can label the refusal with the action that was
            // refused. Without it `BannerState.resolve` has an error and nothing to
            // attribute it to, and falls back to the idle hint — which would make a
            // refusal look like nothing having happened at all.
            runningAction = .reply
            return
        }

        // **The wall every source ends at, asked after the secure-field guard and
        // not before it.** A clip sitting in the ledger says nothing about whether
        // a reply can be *generated*, and that check was lost when the clipboard
        // source went in: `replySource` consults only the ledger and the pasteboard
        // generation, so a clip made it non-nil and carried the tap into
        // `beginWork` over a keyboard with no network. The call then failed and
        // printed `setUpRecovery`, "aBitBetterKeyboard is reconnecting. Try again
        // in a moment." — deliberately a status rather than an instruction,
        // because for a stale token there is nothing a person can do. A user
        // without Full Access has something to do, in Settings, and nothing was
        // saying so. `ScreenContextPrompt` asks `canReachChannel` first for
        // exactly this reason.
        //
        // **It sits here, below `permitsRead`, because putting it above cost two
        // things and both were caught by tests.** The secure-field guard has to
        // fire for a password field whatever the network is doing, or a refusal
        // about credentials is replaced by one about connectivity; and
        // `permitsRead` *counts* every decision it makes, which is the only
        // evidence that will ever answer whether a host populates
        // `isSecureTextEntry` through a `UITextDocumentProxy` at all. A guard in
        // front of it silences that measurement.
        //
        // **That last sentence stopped being true and is true again.** Gating
        // `startConsuming` on `FeatureFlags.screenCaptureReply` leaves the
        // session's `channel` nil, so the channel count cannot move in v1 — and
        // it was only ever written into a page nothing reads back anyway.
        // `SecureDecisionRecord` (NIT-187) is the count now: a boot-scoped App
        // Group record with a Settings row, written on every decision whatever
        // the flag says. So the ordering is load-bearing rather than merely
        // cheap — a guard in front of `permitsRead` silences a measurement that
        // is genuinely filling up on ordinary phones today.
        //
        // The no-source path above needs nothing from this: `screenContextPrompt`
        // already asks `canReachChannel` and `cloudConfigured` before it asks
        // about the clipboard, so "no clip and no Full Access" already says Full
        // Access. This is only for the case where a clip *is* there.
        //
        // **It asks `isReachable` and deliberately not `BackendTransport.isReady()`,
        // and the difference is a whole engine.** The two failures are not the same
        // shape. No shared container means no Full Access, which means no network
        // at all and no route to any answer, so refusing is the only honest move
        // and Settings is a real thing to do about it. A missing session token
        // means the *cloud* is dead — but `RoutedIntelligence` may still have an
        // on-device engine that answers without one, and Hebrew is the language
        // that needs the cloud rather than every language. Refusing both together
        // would turn an English reply Apple's model could have written into a
        // "not connected", which is a refusal the user cannot act on and did not
        // earn. When the cloud genuinely is the only route, the call fails and
        // `BackendTransport.mapped` turns the 401 into `.cloudNotConfigured`,
        // which is the path that already exists for it.
        guard CaptureChannel.isReachable else {
            refuseForScreenContext(screenContextPrompt)
            return
        }

        // A reply replaces nothing; it is inserted where the cursor already is.
        aiSourceText = ""
        replyContext = nil
        beginWork(.reply, showing: .none) { [engine, weak self] in
            let context: ScreenContext
            switch source {
            case .clipboard(let copied):
                // Already built, at the tap, from the clip that was newest then.
                context = copied
            case .scripted, .capture:
                // Both go through the session: the scripted sample short-circuits
                // inside `contextForReply` and a capture session raises the read
                // and waits there.
                context = try await session.contextForReply()
            }
            await MainActor.run { self?.replyContext = context }
            return try await engine.replies(to: context)
        } apply: { controller, replies in
            // **Straight into the field, like the other two.** `replies` is still
            // set on the way past for the reason `aiResultText` is in the Fix
            // branch: it is what `bannerOptions` reads, and an answer this cannot
            // apply — one that arrives after the caret moved — has to have
            // somewhere to be offered from.
            controller.replies = replies
            controller.applyDirectly(replies.first?.text ?? "", for: .reply)
        }
    }

    /// The Reply-key overlay steals the gesture, so this path never reaches
    /// `press(.aiReply)`. Same click and haptic that path already plays.
    func acknowledgeReplyBroadcastTap() {
        Feedback.keyClick(KeyCap.aiReply.clickSound)
        Feedback.actionPress()
        guard let prompt = replyKeyBroadcastPrompt else { return }
        refuseForScreenContext(prompt)
    }

    /// One refusal for `runReply` and the overlay's touch-up, so the two taps
    /// cannot print different sentences for one prompt.
    ///
    /// **At most one of the two flags is ever set**, and which one is available at
    /// all is decided by `FeatureFlags.screenCaptureReply`: `offersPicker` means a
    /// broadcast started now could get somewhere and is false in every shipping
    /// build, `offersCopyClip` means the copied message is one tap inside this
    /// keyboard away. `ScreenContextPrompt` is where that exclusivity is written;
    /// the order here only decides which would win if it ever stopped holding.
    private func refuseForScreenContext(_ prompt: ScreenContextPrompt) {
        let remedy: BannerState.Block.Remedy =
            prompt.offersPicker ? .broadcastPicker : (prompt.offersCopyClip ? .copyclip : .none)
        refuse(
            .init(
                action: .reply,
                title: prompt.title,
                detail: prompt.detail,
                remedy: remedy))
    }

    /// Runs one model call. The latency here is the model's, not a sleep: the
    /// orbit runs until the answer lands, however long that takes.
    ///
    /// A failure sets `aiError` rather than leaving the panel empty, because
    /// every one of these calls can fail for a reason the user can act on —
    /// Apple Intelligence switched off, a language no engine covers, a guardrail
    /// that fires on a benign Hebrew sign-off.
    func beginWork<Value: Sendable>(
        _ action: AIAction,
        showing destination: KeyboardOverlay,
        work: @escaping @Sendable () async throws -> AIOutput<Value>,
        apply: @MainActor @escaping (KeyboardController, Value) -> Void
    ) {
        workingTask?.cancel()
        // A stale rim must not fade over a call that has already started again.
        endArrival()
        isWorking = true
        aiError = nil
        // An action that actually starts clears the previous refusal. Without it a
        // "type something first" from a moment ago sits under the new orbit.
        block = nil
        aiProvenance = nil
        // Named here rather than at the four call sites, so an action that reports
        // in the banner cannot be started without saying which action it is.
        runningAction = action
        // Back to the first answer. Kept from the previous action this would page
        // straight to option 3 of a set that now has one member — clamped rather
        // than crashing, but showing the wrong thing.
        bannerIndex = 0
        // The previous action's answers, gone before this one's arrive. `apply`
        // only ever sets its own kind, so a Rewrite after a Reply would otherwise
        // leave three replies sitting in `replies` for `bannerOptions` to find.
        variants = []
        replies = []
        aiResultText = ""
        withAnimation(Theme.Motion.panel) { overlay = destination }

        workingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await work()
                guard !Task.isCancelled else { return }
                apply(self, output.value)
                aiProvenance = output.provenance
            } catch let error as AIEngineError {
                guard !Task.isCancelled else { return }
                aiError = error
            } catch {
                guard !Task.isCancelled else { return }
                aiError = .failed(error.localizedDescription)
            }
            withAnimation(Theme.Motion.content) { self.isWorking = false }
        }
    }

    /// Accepts an answer the banner is offering.
    ///
    /// **All three actions apply themselves now, so the only answer that ever
    /// reaches this is one they refused to apply** — an answer to a field that
    /// moved on while the model was thinking. See `applyDirectly`, which is where
    /// that decision is taken and where the reasoning for it lives.
    public func applyResult(_ text: String) {
        let preferred =
            bannerOptions.indices.contains(bannerIndex)
            ? bannerOptions[bannerIndex].language : nil
        let answer = runningAction == .fix ? MissingSpaces.restored(text) : text
        guard replaceTargetText(with: answer) else { return }
        Feedback.success()
        beginArrival(for: runningAction)
        clearRevertibleEdit()
        announceHostLanguage(
            preferred ?? Self.languageForHost(reported: "", text: answer) ?? language)
        dismissOverlay()
    }

    // MARK: Applying without being asked twice

    /// Writes an answer into the field the moment it arrives, and leaves a way
    /// back.
    ///
    /// **The banner is not the place a correction is read.** Fix, Rewrite and
    /// Reply used to put their answer on a strip behind a Use button, so the user
    /// read the sentence *beside* their message, decided about it there, and then
    /// read it again in the field. One of those two readings is the real one.
    /// Applying on arrival costs a tap and puts the change where it will actually
    /// be judged — and Fix in particular is a correction of the user's own words
    /// rather than a suggestion of new ones, which is exactly the kind of edit
    /// autocorrect has always made without asking.
    ///
    /// **Reply was the last of the three to move, and it is the one that gave up
    /// the most.** Three answers came back labelled by intent and the strip paged
    /// through them; now the first is inserted and the other two are reachable only
    /// if the insert is refused. What is bought is that the whole feature stops
    /// costing a row of the screen — and a reply the user does not want is one
    /// keystroke from gone, because the undo is drawn where they are already
    /// looking.
    ///
    /// **What that buys has to be paid for with an undo**, because the keyboard has
    /// now changed somebody's message on its own: `revertibleEdit` holds what was
    /// there and `SuggestionBar` draws the way back. `UITextDocumentProxy` offers
    /// no undo of any kind, so having kept the text is the entire mechanism.
    /// It used to expire on the next keystroke; it lasts as long as what it wrote
    /// is still standing where it wrote it now (`RevertibleEdit.rebased(onto:)`
    /// and `spanUndo(behind:)`), because a wrong word is noticed a few words after
    /// it lands rather than before the next one is typed.
    ///
    /// **An empty answer is left to the banner on purpose.** `BannerState.resolve`
    /// turns "finished, no error, nothing to show" into "Nothing came back", which
    /// is the one outcome the user can neither see nor explain — so this returns
    /// without clearing and lets that sentence through. Everything else clears the
    /// strip, because the answer is in the field where it can be read.
    ///
    /// **And so is an answer to a field that has moved on**, which is the hazard
    /// auto-applying creates and the Use button used to cover. A model call takes
    /// seconds and people keep typing through it: tap Fix, type the next word, and
    /// an answer written about the sentence as it was would replace the whole field
    /// and take that word out with it. `PredictiveRefiner` refuses on exactly this
    /// test for exactly this reason. Here the answer is not thrown away, it is left
    /// where it already is — `aiResultText` and `variants` are set before this runs,
    /// so falling through leaves `BannerState` showing it behind a Use button, and
    /// the user decides about a replacement they can see. It covers the second form
    /// of the same problem for free: a selection that was deselected mid-call, where
    /// applying would have written a correction of five words over the whole
    /// message.
    func applyDirectly(_ text: String, for action: AIAction) {
        // The staleness test below is also what makes this the right string: past
        // it, `previous` is what was sent to the model *and* what is standing in
        // the field right now — which is what `replaceTargetText` is about to take
        // out and what the undo has to put back.
        let previous = aiSourceText
        // **Empty means Reply, and Reply replaces nothing.** `runReply` empties
        // `aiSourceText` on purpose, because a reply is inserted where the cursor
        // is rather than over the message — so there is nothing for the staleness
        // test to compare and nothing for the undo to put back. It is also why a
        // reply is not stale when the field moves: it was written about what is on
        // the *screen*, not about what is in the field.
        let inserts = previous.isEmpty
        guard inserts || aiTargetText == previous else { return }
        // Both asked before the replacement, because the replacement is what removes
        // the selection. See `RevertibleEdit.Undo`.
        let selected = selection
        let undo: RevertibleEdit.Undo = (inserts || selected != nil) ? .spanAtCursor : .wholeField
        // **What the undo puts back, which is not always what was sent to the
        // model.** For Fix and Rewrite the two are the same string. For a reply
        // over a *selection* they are not: nothing was sent, so `previous` is
        // empty, and yet `insertText` on a real proxy replaces the selected words —
        // so an undo built on `previous` would delete the reply and leave the words
        // it consumed gone for good. Reply had no undo at all until it started
        // applying itself, which is why this only matters now.
        let undone = inserts ? (selected ?? "") : previous
        // Nothing at all: leave it to `BannerState.resolve`'s "Nothing came back".
        guard !text.isEmpty else { return }
        // **Jammed letters are split here, not in the engine.** The model can
        // echo `מהאופישלומהקורה` with `corrections: none`; `EditScope` then
        // returns the source and the identical-text guard below used to stay
        // quiet. `MissingSpaces` is the recovery that does not wait on a sampled
        // call. Rewrite and Reply are not proofreading, so they are left alone.
        let answer = action == .fix ? MissingSpaces.restored(text) : text
        // **Byte-for-byte identical is an answer, not a warning.** It is what
        // `EditScope.applied` returns when the model named no mistakes, and it is
        // the ordinary outcome of running Fix over a sentence that is already
        // right. Re-typing the same characters would move the cursor and leave a
        // revert button offering to change nothing. Telling the user "Nothing to
        // change" is a 69pt strip for a tap that did its job. The orbit on the
        // key ending is the signal; the field is already what they wanted.
        guard answer != previous else {
            clearBannerState()
            return
        }
        let documentIdentifier = target?.documentIdentifier
        guard replaceTargetText(with: answer) else { return }
        Feedback.success()
        beginArrival(for: action)
        clearRevertibleEdit()
        announceHostLanguage(
            (action == .reply ? replyContext?.language : nil)
                ?? Self.language(of: answer, fallback: language))
        revertibleEdit = RevertibleEdit(
            origin: .ai(action),
            previous: undone,
            applied: answer,
            undo: undo,
            documentIdentifier: documentIdentifier)
        // **Emptied, because the next action must not inherit it.**
        // `selectTone(_:)` keeps whatever is already in `aiSourceText` — correct
        // when it is reached from an action that has just filled it, and wrong from
        // the long-press popup, which fills nothing. So a Fix followed by holding
        // Rewrite and picking a register used to send the model the text as it was
        // *before* the Fix, and then replace the field with a rewrite of it.
        // `revertibleEdit` is what holds the old text now, and it holds it on
        // purpose.
        aiSourceText = ""
        // The answer is in the field now, so there is nothing for the strip to say
        // and it should not keep a row of the screen to say it.
        clearBannerState()
    }

    /// Puts back what the last Fix, Rewrite, Reply or clip insert wrote.
    ///
    /// **Two paths, because the two kinds of edit undo differently and getting it
    /// wrong destroys the message.** A whole-field edit is undone by replacing the
    /// whole field, which `replaceTargetText` already knows how to do across a
    /// cursor sitting anywhere in it — so that path is reused rather than
    /// reimplemented, and it does not care where the caret has moved to since.
    ///
    /// A **selection** edit replaced five characters in the middle of a sentence,
    /// and there is no selection left by the time this runs — the replacement is
    /// what consumed it. Sending that through `replaceTargetText` takes the
    /// whole-field branch and leaves the field holding nothing but the fragment:
    /// `hello there wrold friend`, Fix the selected `wrold`, revert, and the
    /// message is the single word `wrold`. So that path deletes exactly as many
    /// UTF-16 units as were inserted, from where they were inserted, and types the
    /// old ones back.
    ///
    /// The guard is what makes the second path safe rather than merely narrow:
    /// `RevertibleEdit.spanUndo(behind:)` has to *find* what the edit wrote in
    /// front of the caret before a single character is deleted. If it cannot — a
    /// caret the host moved, which fires no callback this keyboard can see, or a
    /// span the user has typed over — the edit is dropped without touching the
    /// document, because deleting a count from the wrong place is the one outcome
    /// worse than no undo at all. It is asked of a *window* rather than of the
    /// field, which is why a clip longer than iOS hands back still undoes.
    ///
    /// **Both paths rebase rather than replace, which is what lets the undo
    /// outlive the next keystroke.** They put back exactly the span this edit
    /// wrote and leave every character around it alone, so anything typed since
    /// survives being taken back. `refreshDocumentState` retires the edit the
    /// moment either of them stops being able to find its own span, so the
    /// control is never on screen over an undo that would do nothing or do harm.
    public func revertEdit() {
        guard let edit = revertibleEdit else { return }
        guard edit.documentIdentifier == target?.documentIdentifier else {
            revertibleEdit = nil
            return
        }

        guard edit.undo == .spanAtCursor else {
            // **A refusal takes the control away, and must, because the predicate
            // is cached between document callbacks.** `expireRevertibleEditIfUnusable`
            // retires the edit once per document change, so the button says what
            // was true at the last callback rather than what is true now — and
            // `applyDirectly` records the edit *after* `replaceTargetText` has
            // already run `refreshSuggestions`, so there is a window at the very
            // start of every edit's life where nothing has asked yet.
            //
            // Returning quietly there left a drawn control that did nothing, gave
            // no haptic, and stayed until the next keystroke. The property worth
            // keeping is the one the old caret-guarded code had for free by
            // clearing above its guard: a tap on Undo always has a visible
            // consequence, either the text comes back or the button goes.
            guard let rebased = edit.rebased(onto: wholeField) else {
                revertibleEdit = nil
                return
            }
            // `replaceTargetText` refuses on an empty source — that guard is what
            // makes an insertion an insertion — so it is told what is standing
            // there now, which is exactly what this is taking out.
            aiSourceText = wholeField
            let replaced = replaceTargetText(with: rebased)
            aiSourceText = ""
            revertibleEdit = nil
            if replaced { Feedback.modifierPress() }
            return
        }

        // Same refusal rule as the branch above, for the same reason.
        guard let step = edit.spanUndo(behind: contextBefore, ahead: contextAfter) else {
            revertibleEdit = nil
            return
        }
        let deletion = deleteBackwardReversibly(utf16Units: step.delete)
        guard deletion.unitsRemoved == step.delete else {
            if !deletion.deletedText.isEmpty { target?.insertText(deletion.deletedText) }
            revertibleEdit = nil
            refreshSuggestions()
            return
        }
        // Empty for a reply and for a clip taken back with nothing typed after
        // them, neither of which replaced anything: `insertText("")` is harmless
        // and the branch is here to say so rather than to guard against it.
        if !step.insert.isEmpty { target?.insertText(step.insert) }
        Feedback.modifierPress()
        revertibleEdit = nil
        refreshSuggestions()
    }

    /// Drops a model call in flight, and the answer of one that has already
    /// landed.
    ///
    /// **Starting a recording is the one thing that has to do this, and the reason
    /// is a way to destroy a message.** `run(_:)` refuses while a recording is
    /// open, but a call started a moment *before* the microphone was tapped keeps
    /// running: it answers about the sentence as it was, `applyDirectly` correctly
    /// refuses to apply it because the field has since filled with spoken words,
    /// and it therefore falls through to the strip — which is suppressed for the
    /// length of the recording and reappears the instant it ends, offering a Use
    /// button over a field the user has just dictated into. `aiSourceText` still
    /// holds the pre-recording sentence at that point, so `replaceTargetText`
    /// would take the whole-field branch and replace everything that was said with
    /// a correction of what was typed before it.
    ///
    /// `clearBannerState()` alone is not enough: a cancelled `beginWork` returns at
    /// its own `Task.isCancelled` guard without ever reaching the line that clears
    /// `isWorking`, so the orbit on the key would run for ever.
    func cancelAIWork() {
        workingTask?.cancel()
        workingTask = nil
        endArrival()
        aiSourceText = ""
        clearBannerState()
    }

    /// How long the rim holds after an answer lands, a shade past
    /// `ControlArrivalRim.fadeDuration` so the fade finishes before the state
    /// that hosts it goes.
    static let arrivalDwellMilliseconds = 500

    /// Holds `.arriving` on the live control while the rim closes, then lets
    /// go. Called beside `Feedback.success()` and nowhere else, so the eye
    /// gets the beat the hand already does — and never on a failure, which
    /// returns straight to idle while the banner explains.
    func beginArrival(for action: AIAction?) {
        guard let action else { return }
        arrivalTask?.cancel()
        arrivingAction = action
        arrivalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.arrivalDwellMilliseconds))
            guard !Task.isCancelled else { return }
            self?.arrivingAction = nil
        }
    }

    /// Drops the arrival state at once: a new call, a cancel, or a keyboard
    /// being handed a new document must not wear the previous answer's rim.
    func endArrival() {
        arrivalTask?.cancel()
        arrivalTask = nil
        arrivingAction = nil
    }

    /// Drops the way back outright.
    ///
    /// **The typing paths no longer call this, and that is the change NIT-154
    /// asked for.** It used to be called from every path that put a character in,
    /// so an undo lasted exactly one keystroke; what retires an edit now is
    /// `expireRevertibleEditIfUnusable`, asked once per document change, which
    /// drops it when what it wrote can no longer be found where it wrote it.
    ///
    /// What is left are callers that have successfully recorded another edit, a
    /// recording writing a transcript into the field, and a caret key we moved
    /// ourselves. It is still deliberately *not* called from
    /// `refreshSuggestions` — `replaceTargetText` refreshes the bar itself, so the
    /// revert would be cleared by the very edit that created it.
    func clearRevertibleEdit() {
        guard revertibleEdit != nil else { return }
        revertibleEdit = nil
    }

    /// Retires the way back the moment taking it would do nothing, or harm.
    ///
    /// **One question, asked of the document, in the one place every document
    /// change already goes through** (`refreshDocumentState`). It is the same
    /// question `revertEdit` asks before it touches a character, so the control
    /// and the action cannot disagree: if this leaves the edit standing, taking it
    /// puts back exactly what the keyboard wrote and leaves everything the user
    /// typed since alone; if it drops the edit, there was no safe way to do that.
    ///
    /// **This replaced nine calls to `clearRevertibleEdit()` on the typing
    /// paths** — both cursor keys, a character, space, backspace, word-delete, an
    /// emoji, a candidate tapped on the bar and the idle completion — and that is
    /// the point rather than a tidy-up: an undo that expired
    /// on the next keystroke was gone before the wrong word had been read in the
    /// sentence it landed in, which is when anybody notices one (NIT-154). The
    /// keystroke calls could not simply be deleted, because the undo they were
    /// protecting against was a whole-field replacement that would have taken the
    /// new characters with it — that is what `RevertibleEdit.rebased(onto:)` fixed
    /// and this is what makes the fix load-bearing rather than optimistic.
    func expireRevertibleEditIfUnusable() {
        guard let edit = revertibleEdit else { return }
        guard edit.documentIdentifier == target?.documentIdentifier else {
            revertibleEdit = nil
            return
        }
        let usable =
            edit.undo == .spanAtCursor
            ? edit.spanUndo(behind: contextBefore, ahead: contextAfter) != nil
            : edit.rebased(onto: wholeField) != nil
        if !usable { revertibleEdit = nil }
    }
}
