import Foundation

// MARK: - Reply with no session behind it

/// What the Reply panel says when there is nothing to reply to, and whether
/// starting a session now could get somewhere (`offersPicker`).
///
/// A value type rather than three computed properties on the view, because the
/// decision is pure and the one thing worth pinning is not renderable: **the
/// start must be offered only when a broadcast started now could get further
/// than the last one did.** It shipped asking two of the three questions.
/// `SampleHandler.broadcastStarted` refuses a session outright when
/// `ScreenReadService.canRead` is false, so with no cloud model the keyboard was
/// putting a real screen recording in front of the user — countdown, system
/// recording indicator and all — that iOS would end inside a second. That is the
/// same trap `ScreenContextView` reordered its own sections to avoid, one process
/// away.
///
/// The three refusals are deliberately distinct sentences. "Turn on Full Access"
/// and "set up a cloud model" are different work, in different places, and an
/// ending a restart cannot fix is a fourth thing again.
struct ScreenContextPrompt: Equatable {
    let title: String
    let detail: String
    let offersPicker: Bool

    init(canReachChannel: Bool, cloudConfigured: Bool, ended: ScreenContextEndReason?) {
        // The keyboard reads what the capture process writes through the App
        // Group, and iOS hands a keyboard extension that container only once Full
        // Access is granted. Starting a broadcast from here would run a capture
        // this keyboard could never read.
        guard canReachChannel else {
            title = "Needs Full Access"
            detail =
                "Turn on Full Access for aBitBetterKeyboard in Settings › General › Keyboard › Keyboards."
            offersPicker = false
            return
        }
        // The same two strings the strip prints, off the same reason.
        if let ended, !ended.canRestart {
            title = "Can't run yet"
            detail = "\(ended.explanation)\n\(ended.recovery)"
            offersPicker = false
            return
        }
        // The same wall as the one above, reached before the broadcast instead of
        // one second after it.
        guard cloudConfigured else {
            title = "Not connected"
            detail =
                "Reply needs a connection.\n\(BackendTransport.setUpRecovery)"
            offersPicker = false
            return
        }
        title = "Screen context is off"
        // ReplayKit's picker does not present over a keyboard (dead on the
        // simulator, unmeasured on a device). The start lives in the app, same
        // as dictation. Nothing auto-starts there: the user still has to tap
        // Apple's button.
        detail = "Start it in aBitBetterKeyboard — swipe back to continue."
        offersPicker = true
    }
}
