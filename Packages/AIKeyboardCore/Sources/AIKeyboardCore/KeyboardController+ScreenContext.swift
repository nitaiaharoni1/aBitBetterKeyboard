import Foundation

extension KeyboardController {

    // MARK: Screen context

    /// Reply is worth offering for as long as a session is live, whether or not
    /// anything has been read yet.
    ///
    /// It used to require a reading. That was right when the session read every
    /// frame speculatively and is wrong now: there is one trigger for a read and
    /// it is this tap, so waiting for a reading before showing the button would
    /// mean never showing it. The tap raises `intent.readNow` and waits.
    public var canReply: Bool {
        screenContextIsPermitted && screenContext.isLive
    }

    /// The same gate `runReply()` takes before it generates.
    var hasUsableReplyContext: Bool {
        screenContextIsPermitted
            && (screenContext.isLive || screenContext.context != nil)
    }

    /// Non-nil only when the Reply key must become ReplayKit's real button.
    ///
    /// Dictation is excluded because the overlay sits *outside* `KeyView`, past
    /// `.disabled`, so a dim Reply key would still start a broadcast while
    /// somebody is speaking.
    var replyKeyBroadcastPrompt: ScreenContextPrompt? {
        guard !isDictationActive, !hasUsableReplyContext else { return nil }
        let prompt = screenContextPrompt
        return prompt.offersPicker ? prompt : nil
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

    /// Why Reply cannot run, in the four distinct sentences `ScreenContextPrompt`
    /// separates, and whether starting a broadcast now could get further than the
    /// last one did.
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
            canReachChannel: CaptureChannel.isReachable,
            cloudConfigured: BackendTransport.isReady(),
            ended: screenContextEndReason)
    }

    /// What screen context has to say when it has not read anything, or nil when
    /// it has nothing to say at all.
    ///
    /// **This is what is left of `ScreenContextStrip`, and the strip is gone.** It
    /// was a 30pt row that appeared and disappeared with the session; the banner is
    /// always drawn and already shows the reading itself, so the only part that
    /// needed a home was the five states that are not a reading. The strip's own
    /// restart button is not reproduced: Reply with no session hosts the
    /// picker on the key itself. `ScreenContextPrompt.offersPicker` is
    /// whether that overlay is worth drawing.
    ///
    /// `.off` returns nil rather than a sentence, because a phone that has never
    /// started a broadcast is not in an error state and the banner has an ordinary
    /// hint to show instead.
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
