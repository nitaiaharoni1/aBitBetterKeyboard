import Foundation

// MARK: - Reply with no session behind it

/// What the Reply panel says when there is nothing to reply to, and whether it
/// offers to start a broadcast.
///
/// A value type rather than three computed properties on the view, because the
/// decision is pure and the one thing worth pinning is not renderable: **the
/// picker must be offered only when a broadcast started now could get further
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
            title = "Screen context needs Full Access"
            detail =
                "This keyboard cannot reach AI Keyboard's shared storage, so it could not read a screen even while one is being captured. Turn on Full Access for AI Keyboard in Settings, under General › Keyboard › Keyboards."
            offersPicker = false
            return
        }
        // The same two strings the strip prints, off the same reason.
        if let ended, !ended.canRestart {
            title = "Screen context can't run yet"
            detail = "\(ended.explanation) \(ended.recovery)"
            offersPicker = false
            return
        }
        // The same wall as the one above, reached before the broadcast instead of
        // one second after it.
        guard cloudConfigured else {
            title = "Screen context can't run yet"
            detail =
                "Reading a screen needs the cloud model, and it is not finished being set up. \(BackendTransport.setUpRecovery)"
            offersPicker = false
            return
        }
        title = "Screen context is off"
        // **Rewritten for a two-line strip, and the last clause is the load-bearing
        // one.** This used to be a paragraph in a panel that had room for a second
        // paragraph underneath saying what to do if the picker does nothing — and
        // that caveat is not decoration: the picker asks Control Center to present
        // its own recording view over a keyboard extension, and whether that works
        // is unmeasured on a device. See `BroadcastPickerButton`. The banner has two
        // lines at 11pt, so the fallback had to fit inside them or be lost.
        detail =
            "Tap to pick AI Keyboard, then Start Broadcast. If nothing opens, start it in the app."
        offersPicker = true
    }
}
