import Foundation

// MARK: - Reply with nothing to reply to

/// What the Reply panel says when there is nothing to reply to, and whether
/// starting a session now could get somewhere (`offersPicker`).
///
/// A value type rather than computed properties on the view, because the decision
/// is pure and two of the things worth pinning are not renderable.
///
/// **The first is that the start must be offered only when a broadcast started
/// now could get further than the last one did.** It shipped asking two of the
/// three questions. `SampleHandler.broadcastStarted` refuses a session outright
/// when `ScreenReadService.canRead` is false, so with no backend the keyboard was
/// putting a real screen recording in front of the user — countdown, system
/// recording indicator and all — that iOS would end inside a second.
///
/// **The second is that with `FeatureFlags.screenCaptureReply` off, none of that
/// may be said at all.** `capturePermitted` is that flag, threaded in rather than
/// read here so the capture sentences stay testable while the shipping build has
/// them switched off. With it false there is no broadcast to start, no session to
/// have ended, and no honest way to name screen context to the user — so those
/// three branches are skipped and the clipboard's own two sentences take their
/// place. `offersPicker` is then false in every state this type can be in, which
/// is what keeps ReplayKit off the Reply key.
///
/// The refusals are deliberately distinct sentences. "Turn on Full Access", "we
/// are reconnecting", "copy a message" and "let the message you copied in" are
/// four different pieces of work, and one of them is not work at all.
struct ScreenContextPrompt: Equatable {
    let title: String
    let detail: String
    let offersPicker: Bool
    /// Whether the strip should offer a way into CopyClip. True only for
    /// `.copyNotRead`, which is the one refusal a control inside this keyboard
    /// can actually clear.
    let offersCopyClip: Bool

    init(
        capturePermitted: Bool,
        canReachChannel: Bool,
        cloudConfigured: Bool,
        ended: ScreenContextEndReason?,
        clipboard: ClipboardReplyGap
    ) {
        // **Asked first whether or not capture is permitted, because it is not a
        // capture question.** `CaptureChannel.isReachable` is
        // `SharedContainer.url != nil` — whether this process can reach the App
        // Group at all — and iOS hands a keyboard extension that container only
        // once Full Access is granted. Without it there is no session token
        // either, so every route to a reply is shut, and "we are reconnecting"
        // would be a status about a thing the user can fix in Settings.
        guard canReachChannel else {
            title = "Needs Full Access"
            detail =
                "Turn on Full Access for aBitBetterKeyboard in Settings › General › Keyboard › Keyboards."
            offersPicker = false
            offersCopyClip = false
            return
        }
        // An ending is news about a capture session, and with capture switched
        // off there is nothing a user could do with it: the page may still be
        // lying in the shared container from an earlier build for the ten minutes
        // `ScreenContextSession.endingWorthShowing` allows, and printing "Start it
        // again" over a build that cannot start one is the dead end this whole
        // gate exists to avoid.
        if capturePermitted, let ended, !ended.canRestart {
            title = "Can't run yet"
            detail = "\(ended.explanation)\n\(ended.recovery)"
            offersPicker = false
            offersCopyClip = false
            return
        }
        // Every source ends at the same cloud call, so this refuses ahead of all
        // of them — and ahead of the broadcast, which is the same wall reached one
        // second earlier than `SampleHandler` would reach it.
        guard cloudConfigured else {
            title = "Not connected"
            detail =
                "Reply needs a connection.\n\(BackendTransport.setUpRecovery)"
            offersPicker = false
            offersCopyClip = false
            return
        }
        guard capturePermitted else {
            switch clipboard {
            case .nothingCopied:
                title = "Nothing to reply to"
                // **Says how the message gets in, not just to copy it.** A copy
                // alone leaves a pasteboard generation this keyboard is not
                // allowed to read (see `ClipboardReplyGap.copyNotRead`), so
                // "copy the message, then tap Reply" would be an instruction
                // that ends where it started. The Paste button is named because
                // it is Apple's own control and carries Apple's own word.
                detail = "Copy the message you want to answer, then let it in with CopyClip's Paste."
            case .copyNotRead:
                title = "Paste it in first"
                // The one refusal with a control behind it: `offersCopyClip`
                // opens the panel that draws `UIPasteControl`, so this does not
                // have to name a key the user may have moved off the bar.
                detail = "Tap Paste in CopyClip, then tap Reply and it answers what you copied."
            }
            offersPicker = false
            offersCopyClip = clipboard == .copyNotRead
            return
        }
        title = "Screen context is off"
        // The Reply key *is* ReplayKit's button in this state. The sentence
        // hosts the same control so a tap on the strip still reaches replayd
        // if the system sheet was dismissed. Simulator has no replayd, so
        // neither surface can start a session there.
        detail = "Tap to pick aBitBetterKeyboard, then Start Broadcast."
        offersPicker = true
        offersCopyClip = false
    }
}
