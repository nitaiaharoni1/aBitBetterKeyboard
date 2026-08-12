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
            let source = aiSourceText
            // **No overlay, and there is no longer one to ask for.** Fix,
            // Rewrite and Reply report in the banner, so the keys stay visible and
            // usable while the call runs — the user can see the sentence being
            // corrected, which is the one thing the panel that used to cover them
            // hid. The screen-context setup screen was the last case argued to need
            // a panel, because it holds `BroadcastPickerButton`, a real `UIView`;
            // that view is 42pt in the banner's trailing slot instead, at the cost
            // of 10pt of tap target.
            beginWork(.fix, showing: .none) { [engine] in
                try await engine.fix(source)
            } apply: { controller, text in
                // **Straight into the field, with no Use button in front of it.**
                // See `applyDirectly`. `aiResultText` is still set on the way past,
                // because it is what `BannerState.resolve` reads to tell "the model
                // answered" from "the model answered with nothing" — and an empty
                // answer is the one case that still has to reach the strip.
                controller.aiResultText = text
                controller.applyDirectly(text, for: .fix)
            }
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

    /// Reply, against whatever is on screen at the moment of the tap.
    ///
    /// The reading is asked for here rather than read off the state, and the two
    /// are not the same thing: `screenContext` may be showing a reading the
    /// freshness gate has since refused, and `contextForReply()` will raise a new
    /// read and wait rather than answer the wrong message. The wait happens
    /// inside `beginWork`, so the panel shimmers through it exactly as it does
    /// through a model call.
    private func runReply() {
        guard screenContextIsPermitted, screenContext.isLive || screenContext.context != nil else {
            // No session, so say so, rather than showing an empty result the user
            // cannot explain — and say it in the strip rather than in a panel over
            // the keys. `screenContextPrompt` is the single place that decides
            // *which* refusal this is, and whether starting a broadcast now could
            // get further than the last one did; only that last case earns a button.
            let prompt = screenContextPrompt
            refuse(
                .init(
                    action: .reply,
                    title: prompt.title,
                    detail: prompt.detail,
                    remedy: prompt.offersPicker ? .broadcastPicker : .none))
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
            aiError = .screenNotRead(
                "Screen context does not read password fields, and this field either is one or would not say."
            )
            // Named, so the banner can label the refusal with the action that was
            // refused. Without it `BannerState.resolve` has an error and nothing to
            // attribute it to, and falls back to the idle hint — which would make a
            // refusal look like nothing having happened at all.
            runningAction = .reply
            return
        }

        // A reply replaces nothing; it is inserted where the cursor already is.
        aiSourceText = ""
        replyContext = nil
        beginWork(.reply, showing: .none) { [engine, weak self] in
            let context = try await session.contextForReply()
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

    /// Runs one model call. The latency here is the model's, not a sleep: the
    /// shimmer runs until the answer lands, however long that takes.
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
        isWorking = true
        aiError = nil
        // An action that actually starts clears the previous refusal. Without it a
        // "type something first" from a moment ago sits under the new shimmer.
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
            let animation = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.workingPhase += 0.03
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            defer { animation.cancel() }

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
        Feedback.success()
        // **Before the insertion, not after.** A reply lands in a field that may
        // still be carrying a Fix's way back, and that way back replaces the *whole*
        // field with what was there before — so reverting after inserting a reply
        // would delete the reply along with the correction.
        clearRevertibleEdit()
        replaceTargetText(with: text)
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
    /// there, `SuggestionBar` draws the way back, and the next keystroke clears it
    /// (`clearRevertibleEdit`). `UITextDocumentProxy` offers no undo of any kind, so
    /// having kept the text is the entire mechanism.
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
        // the selection. See `AIEdit.Undo`.
        let selected = selection
        let undo: AIEdit.Undo = (inserts || selected != nil) ? .spanAtCursor : .wholeField
        // **What the undo puts back, which is not always what was sent to the
        // model.** For Fix and Rewrite the two are the same string. For a reply
        // over a *selection* they are not: nothing was sent, so `previous` is
        // empty, and yet `insertText` on a real proxy replaces the selected words —
        // so an undo built on `previous` would delete the reply and leave the words
        // it consumed gone for good. Reply had no undo at all until it started
        // applying itself, which is why this only matters now.
        let restored = inserts ? (selected ?? "") : previous
        // Nothing at all: leave it to `BannerState.resolve`'s "Nothing came back".
        guard !text.isEmpty else { return }
        // **Byte-for-byte identical is an answer, not a failure.** It is what
        // `EditScope.applied` returns when the model named no mistakes, and it is
        // the ordinary outcome of running Fix over a sentence that is already
        // right. Re-typing the same characters would move the cursor and leave a
        // revert button offering to change nothing, so it says so instead — a
        // shimmer that ends in silence is the one thing the user cannot read.
        guard text != previous else {
            refuse(
                .init(
                    action: action,
                    title: "Nothing to change",
                    detail: "That already reads the way it should.",
                    remedy: .none))
            return
        }
        Feedback.success()
        // **Before the insertion, not after.** A reply lands in a field that may
        // still be carrying a Fix's way back, and that way back replaces the
        // *whole* field with what was there before — so reverting after inserting a
        // reply would delete the reply along with the correction.
        clearRevertibleEdit()
        replaceTargetText(with: text)
        revertibleEdit = AIEdit(action: action, previous: restored, applied: text, undo: undo)
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

    /// Puts back what the last Fix, Rewrite or Reply wrote.
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
    /// `replaceTargetText` leaves the caret immediately after what it inserted, so
    /// the field must still end there. If it does not — a caret the host moved,
    /// which fires no callback this keyboard can see — the edit is dropped without
    /// touching the document, because deleting a count from the wrong place is the
    /// one outcome worse than no undo at all.
    public func revertAIEdit() {
        guard let edit = revertibleEdit else { return }
        Feedback.modifierPress()
        revertibleEdit = nil

        guard edit.undo == .spanAtCursor else {
            // `replaceTargetText` refuses on an empty source — that guard is what
            // makes an insertion an insertion — so it is told what is standing
            // there now, which is exactly what this is taking out.
            aiSourceText = edit.applied
            replaceTargetText(with: edit.previous)
            aiSourceText = ""
            return
        }

        guard contextBefore.hasSuffix(edit.applied) else { return }
        deleteBackward(utf16Units: edit.applied.utf16.count)
        // Empty for a reply, which replaced nothing: `insertText("")` is harmless
        // and the branch is here to say so rather than to guard against it.
        if !edit.previous.isEmpty { target?.insertText(edit.previous) }
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
    /// `isWorking`, so the progress bar would run for ever.
    func cancelAIWork() {
        workingTask?.cancel()
        workingTask = nil
        aiSourceText = ""
        clearBannerState()
    }

    /// Drops the way back, because the field has moved on.
    ///
    /// Called from every path that changes the document by the user's own hand. It
    /// is deliberately *not* called from `refreshSuggestions`, which would be one
    /// line instead of five: `replaceTargetText` refreshes the bar itself, so the
    /// revert would be cleared by the very edit that created it.
    func clearRevertibleEdit() {
        guard revertibleEdit != nil else { return }
        revertibleEdit = nil
    }
}
