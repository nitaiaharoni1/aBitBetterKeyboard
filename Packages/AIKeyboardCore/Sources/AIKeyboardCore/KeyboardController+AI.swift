import Foundation
import SwiftUI

extension KeyboardController {

    // MARK: AI

    public func run(_ action: AIAction) {
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
            // **No overlay.** Fix, Rewrite and Reply now report in the banner, so
            // the keys stay visible and usable while the call runs — the user can
            // see the sentence being corrected, which is the one thing the panel
            // that used to cover them hid. `AIResultPanel` survives for the single
            // case that cannot be a strip: the screen-context setup screen, which
            // holds `BroadcastPickerButton`, a real `UIView`.
            beginWork(.fix, showing: .none) { [engine] in
                try await engine.fix(source)
            } apply: { controller, text in
                controller.aiResultText = text
            }
        // **Both of these clear `selectedToneIsCustom`, and forgetting it left the
        // flag lit across a Back.** It is set by `runTone` and only ever cleared by
        // `dismissOverlay`, but the panel's Back button goes to the AI menu without
        // dismissing anything — so running the user's own tone, tapping Back and
        // then Rewrite titled a plain three-decision Rewrite "My tone" and lit the
        // custom chip under it. `selectedTone = nil` alone does not cover it:
        // `AIResultPanel.title` reads the flag first.
        case .rewrite:
            selectedTone = nil
            selectedToneIsCustom = false
            let source = aiSourceText
            beginWork(.rewrite, showing: .none) { [engine] in
                try await engine.variants(for: source, tone: nil)
            } apply: { controller, variants in
                controller.variants = variants
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
            controller.replies = replies
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

    public func applyResult(_ text: String) {
        Feedback.success()
        replaceTargetText(with: text)
        dismissOverlay()
    }

}
