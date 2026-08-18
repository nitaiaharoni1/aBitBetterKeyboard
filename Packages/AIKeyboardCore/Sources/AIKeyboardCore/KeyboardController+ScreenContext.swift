import Foundation

extension KeyboardController {

    // MARK: Screen context

    /// Where the message Reply would answer is coming from, or nil when there is
    /// none.
    ///
    /// **The order is the precedence and it is not arbitrary.** The scripted
    /// sample is first because it is the *only* thing the in-app playground can
    /// answer with — it is a fiction the app labels as one, and letting a clip
    /// win there would put a real message into a demo. A live capture session is
    /// next, because it is about the screen actually in front of the user, and it
    /// is unreachable until `FeatureFlags.screenCaptureReply` flips (NIT-6). The
    /// clipboard is last and is the only one that answers on a shipping build.
    ///
    /// Read at the tap. `copyclipCaptureState` inside `ReplySource.fromClipboard`
    /// asks `UIPasteboard.changeCount`, which is the free counter and never the
    /// contents — see `PasteboardReader`.
    var replySource: ReplySource? {
        if screenContextIsPermitted, screenContextSource == .scripted, screenContext.isLive {
            return .scripted
        }
        if FeatureFlags.screenCaptureReply, screenContextIsPermitted,
            screenContext.isLive || screenContext.context != nil
        {
            return .capture
        }
        return ReplySource.fromClipboard(newest: clips.first, capture: copyclipCaptureState)
    }

    /// Whether Reply has anything to answer.
    ///
    /// **It used to be a question about a capture session** — live or not — and
    /// that was right while a broadcast was the only source. It is the source
    /// itself now, so a clip in the ledger makes this true with no session,
    /// no broadcast and no Full Access prompt.
    public var canReply: Bool { replySource != nil }

    /// The same question under the name `runReply()` and the ReplayKit overlay
    /// read it by. The two used to differ — `canReply` demanded a live session
    /// and this also accepted a reading left behind by one — and `replySource`
    /// collapsed the difference by answering with the source rather than with a
    /// bool about one of them.
    var hasUsableReplyContext: Bool { canReply }

    /// Non-nil only when the Reply key must become ReplayKit's real button.
    ///
    /// **Nil in every shipping build, because `FeatureFlags.screenCaptureReply`
    /// is false.** That flag is what makes the Reply key a Reply key again: with
    /// it off nothing here can put a screen-recording picker under the user's
    /// thumb, `KeyboardView+Keys` draws no overlay, and `ScreenContextPrompt`
    /// prints no sentence about starting a broadcast. Flip it with NIT-6, not
    /// before — the flag's own comment carries the conditions.
    ///
    /// Dictation is excluded because the overlay sits *outside* `KeyView`, past
    /// `.disabled`, so a dim Reply key would still start a broadcast while
    /// somebody is speaking.
    var replyKeyBroadcastPrompt: ScreenContextPrompt? {
        guard FeatureFlags.screenCaptureReply else { return nil }
        guard !isDictationActive, !hasUsableReplyContext else { return nil }
        let prompt = screenContextPrompt
        return prompt.offersPicker ? prompt : nil
    }

    /// The clipboard's half of `dropStaleReplyBroadcastRefusal`, and it exists for
    /// exactly the same reason: `BannerState.resolve` prefers `block` over
    /// everything below it, so "Paste it in first" would sit on the strip after
    /// the user had done precisely that, over a Reply that would now generate.
    ///
    /// Called from `persistCopyclip`, which is the one place the ledger changes.
    /// Narrow on purpose — only the refusal a clip can actually answer, so a Full
    /// Access or a not-connected refusal is left standing, the way a live session
    /// leaves those two standing one function down.
    func dropStaleReplyClipboardRefusal() {
        // `Remedy.copyclip` spelled out. `block?.remedy` is an optional, and this
        // repo has been bitten four times by a bare case name resolving to
        // `Optional` in that position — see AGENTS.md.
        guard block?.action == .reply,
            block?.remedy == BannerState.Block.Remedy.copyclip,
            canReply
        else { return }
        block = nil
    }

    /// `BannerState.resolve` prefers `block` over a reading, so once a session
    /// is actually live the "Screen context is off" sentence is a lie sitting
    /// on top of a Reply that would generate.
    func dropStaleReplyBroadcastRefusal() {
        guard screenContext.isLive else { return }
        guard block?.action == .reply else { return }
        switch block?.remedy {
        case .broadcastPicker, .openApp(SharedStore.screenContextURL):
            block = nil
        default:
            return
        }
    }

    /// The ending on the record, if the last thing that happened was one.
    ///
    /// `.off` is not an ending: it is the ordinary state of a phone that has never
    /// started a broadcast, and it has no reason to print.
    var screenContextEndReason: ScreenContextEndReason? {
        guard case .ended(let reason) = screenContext else { return nil }
        return reason
    }

    /// Why Reply cannot run, in the distinct sentences `ScreenContextPrompt`
    /// separates, and whether starting a broadcast now could get further than the
    /// last one did.
    ///
    /// **Which sentences are on the table is `FeatureFlags.screenCaptureReply`'s
    /// answer, not this one's**: with it off the two clipboard refusals replace
    /// the two that name screen context, and nothing here offers a broadcast.
    ///
    /// **Moved off the setup panel when that panel was deleted**, and it belongs
    /// here rather than in the banner for the reason it never belonged in a view:
    /// both measurements are about other processes, and the refusal is decided at
    /// the tap rather than at render time.
    ///
    /// Read at the tap, not held. `CaptureChannel.isReachable` is whether this
    /// process can reach the App Group at all — false in the keyboard until Full
    /// Access is granted, and the difference between "screen context is off" and
    /// "screen context cannot work here". `isReady()`, not `configured() != nil`: a
    /// broadcast that starts with no token ends inside a second, after asking the
    /// user for the screen-recording permission and recording their screen for
    /// nothing, and a shipped URL makes `configured()` true from the first launch.
    /// Internal, like `ScreenContextPrompt` itself: everything that asks — `runReply`
    /// and the tests — is inside this module, and making the type public to widen
    /// this would export four sentences of copy as API.
    var screenContextPrompt: ScreenContextPrompt {
        ScreenContextPrompt(
            capturePermitted: FeatureFlags.screenCaptureReply,
            canReachChannel: CaptureChannel.isReachable,
            cloudConfigured: BackendTransport.isReady(),
            ended: screenContextEndReason,
            clipboard: ReplySource.clipboardGap(
                newest: clips.first, capture: copyclipCaptureState))
    }

    /// What screen context has to say when it has not read anything, or nil when
    /// it has nothing to say at all.
    ///
    /// **This is what is left of `ScreenContextStrip`, and the strip is gone.** It
    /// was a 30pt row that appeared and disappeared with the session; the banner is
    /// always drawn and already shows the reading itself, so the only part that
    /// needed a home was the five states that are not a reading.
    ///
    /// `.off` returns nil rather than a sentence, because a phone that has never
    /// started a broadcast is not in an error state and the banner has an ordinary
    /// hint to show instead.
    ///
    /// **Every sentence below is unreachable in a v1 build, by two independent
    /// facts rather than by the guard on the first line.** With
    /// `FeatureFlags.screenCaptureReply` false nothing can raise a `.capture`
    /// session, and `SharedStore.screenContextAllowed` — the opt-in for the
    /// scripted sample, and the other half of `screenContextIsPermitted` — has no
    /// control in the app that writes it, so it is false on every install. With
    /// neither, `screenContext` never leaves `.off` and this answers nil.
    ///
    /// The flag is deliberately **not** added to `screenContextIsPermitted`: that
    /// property also gates the scripted sample, which photographs nothing and is
    /// not what the flag holds back. Narrowing it here would conflate the two.
    ///
    /// This comment used to end "Reply with no session hosts the picker on the key
    /// itself", which was true and is not: `replyKeyBroadcastPrompt` returns nil in
    /// every shipping build, so the Reply key never becomes ReplayKit's button.
    /// What Reply says with nothing to answer is `ScreenContextPrompt`'s clipboard
    /// half instead.
    public var screenContextHint: String? {
        guard screenContextIsPermitted else { return nil }
        switch screenContext {
        case .off:
            return nil
        case .starting:
            return "Starting screen context…"
        case .watching:
            // The offer, not a claim: nothing has been read, because a read only
            // ever happens in answer to a tap on Reply.
            return screenReadWentUnanswered
                ? "The last screen read didn't work" : "Tap Reply to answer what's on screen"
        case .ready:
            return nil
        case .paused:
            return "Screen context is paused"
        case .ended(let reason):
            return reason.explanation
        }
    }

    /// Whether a capture session is running right now, as opposed to the scripted
    /// sample. The recording indicator keys off this and nothing else: a red dot
    /// over a demo claims the screen is being watched when it is not.
    public var isCapturingScreen: Bool {
        screenContextSource == .capture && screenContext.isLive
    }

    /// Whether the strip may offer to stop the session. Only the scripted demo
    /// can be stopped from in here: a broadcast is ended by the user in iOS's own
    /// UI, and this process has no way to end one.
    public var canStopScreenContext: Bool {
        screenContextSource == .scripted && screenContext.isVisible
    }

    /// A real capture session is its own permission. The stored setting is the
    /// opt-in for the scripted in-app demo; a broadcast the user started in
    /// Apple's picker, with iOS showing the red pill for as long as it runs, is a
    /// stronger signal than any switch of ours and is not second-guessed here.
    var screenContextIsPermitted: Bool {
        screenContextSource == .capture || store.screenContextAllowed
    }
}
