import AIKeyboardShared
import ReplayKit
import os

// MARK: - Lifecycle

extension SampleHandler {

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        lastSampledAt = nil
        framesDelivered = 0
        framesSampled = 0
        lastOrientation = nil
        hasLoggedFormat = false

        let session = channel?.begin()
        let budget = memory.begin()
        startHeartbeat()

        // Seeded with the intent page as it stands right now, so a Reply tap
        // from a session that ended an hour ago cannot fire a read against
        // whatever happens to be on screen when this one starts.
        if let channel, let session {
            let service = ScreenReadService.standard(channel: channel)
            service.begin(session: session, intent: channel.intent())
            reads.withLock { $0 = service }
        }

        // Into the page as well as the log: the app can show it, and a device
        // that never gets near a Mac still answers R2c.
        channel?.recordFootprint(baselineMB: budget.baselineMB, currentMB: nil)

        Self.log.notice(
            """
            broadcast started intervalMs=\(Self.sampleIntervalMilliseconds, privacy: .public) \
            channel=\(self.channel == nil ? "unreachable" : "open", privacy: .public) \
            reader=\(self.reads.withLock { $0 }?.canRead == true ? "cloud" : "none", privacy: .public) \
            session=\(session?.uuidString ?? "none", privacy: .public) \
            baselineMB=\(budget.baselineMB.map { String(format: "%.1f", $0) } ?? "unmeasurable", privacy: .public) \
            watermarkMB=\(String(format: "%.1f", budget.watermarkMB), privacy: .public)
            """
        )

        // Two ways this session can be switched on and be incapable of the one
        // thing it exists for, both of which are known here, before a single frame
        // is sampled. Neither used to be reported: the extension captured happily,
        // the strip offered "Reply can read this screen", and the user found out
        // twelve seconds after a tap — or never, because with no channel the
        // keyboard shows no strip at all while iOS shows a recording indicator.
        guard let channel else {
            // The container is the diagnosis *and* the only way to deliver one, so
            // there is nothing to record: whatever this session observed, nobody
            // would ever read it. All that is left is to take the recording
            // indicator down instead of capturing a screen no process can collect.
            Self.log.error("broadcast refused: the shared container is out of reach")
            finishBroadcastWithError(
                Self.error(
                    // Outside `ScreenContextEndReason`'s raw values on purpose:
                    // this is the one refusal that has no reason in the enum,
                    // because the page a reason would be written to is exactly
                    // what is missing.
                    code: 100,
                    message: "Screen context could not reach AI Keyboard's shared storage.",
                    recovery: "Open AI Keyboard once, then start screen context again."))
            return
        }

        // The decision itself is `ScreenContextEndReason.refusalToStart`, in
        // `AIKeyboardShared`, because nothing can test a decision written inline
        // in an app extension no simulator ever launches. What is here is the I/O.
        if let refusal = ScreenContextEndReason.refusalToStart(
            canRead: reads.withLock({ $0 })?.canRead == true)
        {
            // Recorded *and* signalled. The page is what the keyboard's strip and
            // the app's Screen Context screen read; finishing the broadcast is what
            // takes the recording indicator down. Neither depends on the other
            // working, which matters because only one of the two has ever run.
            channel.end(refusal)
            stopHeartbeat()
            Self.log.error(
                "broadcast refused reason=\(refusal.rawValue, privacy: .public)")
            finishBroadcastWithError(
                Self.error(
                    code: Int(refusal.rawValue),
                    message: refusal.explanation,
                    recovery: refusal.recovery))
        }
    }

    override func broadcastPaused() {
        channel?.setPaused(true)
        channel?.recordPause(resumed: false)
        Self.log.notice("broadcast paused")
    }

    override func broadcastResumed() {
        // Delivery restarts from a cold gate: the next frame is always sampled
        // rather than measured against an instant from before the pause.
        lastSampledAt = nil
        channel?.setPaused(false)
        channel?.recordPause(resumed: true)
        Self.log.notice("broadcast resumed")
    }

    override func broadcastFinished() {
        stopHeartbeat()
        // Neither the reader nor the downscale buffer is torn down here, and that
        // is deliberate: ReplayKit does not document this callback to be on the
        // delivery queue, so releasing either could free memory a frame in flight
        // is still using. The process ends within moments of this, which is a
        // better collector than a race. A read already in flight keeps its own
        // JPEG and publishes a record the freshness gate refuses, because the
        // page it is measured against now carries an ending.
        //
        // `.stopped`, not `.userStopped`. This callback takes no argument and
        // `RPBroadcastSampleHandler` has no callback anywhere that carries an
        // `NSError`, so the extension is told *that* the broadcast finished and
        // never why — see `ScreenContextEndReason`. Writing "the user stopped it"
        // here was a claim nothing had checked, and the keyboard acted on it by
        // hiding the strip.
        //
        // **`.noFrames` is the one thing this side does know**, and it is the
        // difference between "you stopped it" and "ReplayKit never handed us the
        // screen" — R1, unmeasured on hardware, and the single most likely shape
        // of a broadcast that runs and does nothing. Counted off the shared page
        // rather than off `framesDelivered`: that counter is written on the
        // delivery queue and read here on ReplayKit's lifecycle queue, which are
        // not documented to be the same, and it was left unsynchronised only
        // because nothing keyed a decision off it. The page's counter is written
        // under `SharedPage`'s lock and read back through the seqlock.
        let delivered = channel?.status()?.framesDelivered ?? 0
        channel?.end(ScreenContextEndReason.ending(framesDelivered: delivered))
        Self.log.notice(
            """
            broadcast finished delivered=\(self.framesDelivered, privacy: .public) \
            sampled=\(self.framesSampled, privacy: .public) \
            published=\(delivered, privacy: .public)
            """
        )
    }

    /// Fires only when the broadcast was started from Control Center, and names
    /// the *first* application used during it, never the current one
    /// (`RPBroadcastExtension.h`). Logged as history; it is not a live signal and
    /// nothing may key a decision off it.
    override func broadcastAnnotated(withApplicationInfo applicationInfo: [AnyHashable: Any]) {
        let bundleID = applicationInfo[RPApplicationInfoBundleIdentifierKey] as? String
        Self.log.notice("broadcast annotated firstApp=\(bundleID ?? "unknown", privacy: .public)")
    }

    /// The `NSError` handed to `finishBroadcastWithError:`.
    ///
    /// **What this is verified to do is stop the broadcast**, which the header
    /// states plainly: *"Calling this method will stop the broadcast and deliver
    /// the error back to the broadcasting app through RPBroadcastControllerDelegate's
    /// broadcastController:didFinishWithError: method."* This app has no
    /// `RPBroadcastController` — sessions start from `RPSystemBroadcastPickerView`
    /// — so that delivery goes nowhere this code can observe, and whether iOS puts
    /// the message in front of the user is **not** something the SDK promises or
    /// that anything here has measured. The sentence rides along because it costs
    /// nothing; the load-bearing half is the page, wherever there is a page.
    private static func error(code: Int, message: String, recovery: String) -> NSError {
        NSError(
            domain: "com.nitai.aikeyboard.broadcast", code: code,
            userInfo: [
                NSLocalizedDescriptionKey: message,
                NSLocalizedRecoverySuggestionErrorKey: recovery
            ])
    }
}
