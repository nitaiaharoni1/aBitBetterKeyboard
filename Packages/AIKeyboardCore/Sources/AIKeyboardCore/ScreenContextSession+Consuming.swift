import Combine
import Foundation

extension ScreenContextSession {

    // MARK: - The real session

    /// Starts consuming a capture channel and publishing what it says.
    ///
    /// The keyboard calls this while it is on screen; the app calls it as an
    /// `.observer`, which reads the same page and never claims the keyboard is
    /// visible. `.observer` does **not** mean "writes nothing": the app renders
    /// the same `KeyboardView` in onboarding and the playground, so a Reply tap
    /// there raises `intent.readNow` like any other. `ScreenContextChannel.Role`
    /// says why that is the contract rather than a hole in it.
    ///
    /// `ownUIHeightFraction` is the keyboard's own geometry, which only the
    /// keyboard can measure and which the producer needs to keep our animating
    /// panel out of the frame fingerprint. `KeyboardGeometry` computes it.
    public func startConsuming(
        _ channel: ScreenContextChannel = .shared,
        as role: ScreenContextChannel.Role = .keyboard,
        ownUIHeightFraction: Double = 0
    ) {
        self.channel = channel
        self.role = role
        channel.startWatching(as: role, ownUIHeightFraction: ownUIHeightFraction)

        // `$verdict` is assigned on every poll, so this fires at the poll rate
        // even when the verdict has not moved — which is what carries a *new
        // reading* under an unchanged verdict. The published values this reads
        // back are the ones the same poll has already written; `verdict` itself
        // has not been assigned yet at `willSet` time, so it comes from the
        // parameter.
        cancellable = channel.$verdict
            .sink { [weak self, weak channel] verdict in
                guard let self, let channel else { return }
                apply(verdict, reading: channel.reading, status: channel.status)
            }
        apply(channel.verdict, reading: channel.reading, status: channel.status)
    }

    /// Republishes the keyboard's geometry without restarting the session.
    ///
    /// The height reaches the capture process once, when the keyboard appears,
    /// and a rotation invalidates it: the fraction of the screen we cover changes,
    /// so the band the producer cuts out of the fingerprint changes, so a frame
    /// captured before the rotation and a frame after it have different identities
    /// for no reason the user caused. The freshness gate reads that as a screen
    /// change and retires the reading — a Reply that quietly answers nothing,
    /// because the phone turned while the cloud was thinking.
    ///
    /// Ignored off the keyboard, for the same reason `claimsKeyboardVisible` is:
    /// the app hosts the same view partway up its own screen, and a fraction
    /// measured there describes nothing the capture process should act on.
    public func updateOwnUIHeightFraction(_ fraction: Double) {
        guard role.claimsKeyboardVisible else { return }
        channel?.updateOwnUIHeightFraction(fraction)
    }

    public func stopConsuming() {
        cancellable = nil
        channel?.stopWatching()
        channel = nil
    }

    /// Turns one verdict into what the strip shows.
    ///
    /// Two mappings here are decisions rather than plumbing. `.unconfirmed` and
    /// `.superseded` both come out as `.watching`: there is a live session and
    /// there is a reading, and the reading is not about what is on screen now,
    /// so the offer is all that may be shown. `.idle` joins them, and that one is
    /// a correction: a frame gap is not a pause, it is a screen that has not
    /// changed *or* a pipeline that has stalled, and rendering it as "paused"
    /// took the Reply button away from a user reading a still conversation on
    /// the strength of a delivery rate nobody has measured. See `frameWindow`.
    ///
    /// **Every ending is reported, including `.stopped`.** It used to map to
    /// `.off`, on the reasoning that the user stopped it on purpose so there was
    /// nothing to say. That reasoning needed the extension to know who stopped
    /// it, and it does not: `broadcastFinished()` carries no reason, so the same
    /// mapping also erased the strip when iOS ended a session for a call or the
    /// lock button — which is the one thing §8.2 forbids. An ending that says
    /// "stopped, restart it in AI Keyboard" after a deliberate stop is
    /// redundant; an ending that says nothing after an involuntary one is wrong.
    private func apply(
        _ verdict: CaptureFreshness.Verdict, reading: ScreenReadingRecord?, status: CaptureStatus?
    ) {
        if self.status != status { self.status = status }

        // A new broadcast is a new chance. Whatever the previous session failed
        // to answer says nothing about this one.
        if let session = status?.sessionID, session != sessionSeenLive {
            lastReadWentUnanswered = false
        }

        let frames = Int(status?.framesSampled ?? 0)

        switch verdict {
        case .noSession:
            publishAbsence()
        case .starting:
            sessionSeenLive = status?.sessionID
            publish(.starting, from: .capture, frames: frames)
        case .paused:
            sessionSeenLive = status?.sessionID
            publish(.paused, from: .capture, frames: frames)
        case .ended(let reason):
            guard isWorthReporting(reason, status: status) else {
                publishAbsence()
                return
            }
            publish(.ended(reason), from: .capture, frames: frames)
        case .idle, .unconfirmed, .superseded:
            sessionSeenLive = status?.sessionID
            publish(.watching, from: .capture, frames: frames)
        case .offerable:
            sessionSeenLive = status?.sessionID
            if let reading {
                publish(.ready(reading.screenContext), from: .capture, frames: frames)
            } else {
                publish(.watching, from: .capture, frames: frames)
            }
        }
    }

    /// The channel has nothing to show: no producer has ever run, the container
    /// is out of reach, or the ending on the page is too old to be news.
    /// `publish` is what keeps a running sample on screen through this.
    private func publishAbsence() {
        publish(.off, from: .none, frames: 0)
    }

    /// Whether an ending is still news. See `endingWorthShowing`: either this
    /// consumer watched the session run, or it stopped recently enough that the
    /// user still believes it is on.
    ///
    /// **`.notConfigured` is retired the moment the thing it names is
    /// configured**, ahead of both of those. It is the one ending whose cause the
    /// user can remove from inside this app, and until this check existed removing
    /// it changed nothing for ten minutes: the Screen Context screen printed
    /// "Screen context can't run yet" in its hero while the card 200 points below
    /// said "Saved. Screen context can start.", and the keyboard withheld the
    /// picker for the same window because `canRestart` is false. That is the first
    /// ten minutes of somebody's first successful setup, which is the worst
    /// available moment to contradict yourself. It self-healed on the next
    /// broadcast, which they could not start.
    private func isWorthReporting(_ reason: ScreenContextEndReason, status: CaptureStatus?) -> Bool {
        guard let status else { return false }
        if reason == .notConfigured, isScreenReadingConfigured() { return false }
        if let sessionSeenLive, sessionSeenLive == status.sessionID { return true }
        return CaptureClock.elapsed(since: status.heartbeatAt) <= Self.endingWorthShowing
    }

    private func publish(_ newState: ScreenContextState, from newSource: Source, frames: Int) {
        // **A capture session takes the screen from a running sample only while
        // it is actually watching.** The guard used to live in `publishAbsence`
        // alone, which covered `.off` and missed the two states that are far more
        // common on a phone that has ever run a broadcast: a `.paused` session,
        // and an `.ended` one still inside `endingWorthShowing`. Either of those
        // overwrote the sample within one 250 ms poll and cancelled its task, so
        // "Play a sample conversation" looked like a button that did nothing.
        //
        // Live still wins, and that half is not negotiable: a real session is the
        // one with a red dot over it and the fiction must never sit on top of it.
        if source == .scripted, newSource != .scripted, !newState.isLive { return }

        // A real session takes the screen off the script rather than racing it.
        if newSource == .capture, task != nil {
            task?.cancel()
            task = nil
        }
        if source != newSource { source = newSource }
        if framesRead != frames { framesRead = frames }
        if newSource == .capture, startedAt == nil { startedAt = Date() }
        if newSource == .none, startedAt != nil { startedAt = nil }
        guard state != newState else { return }
        state = newState
    }
}
