import Foundation

extension ScreenContextSession {

    // MARK: - The scripted demo

    /// The sample timeline the app's playground runs on: start-up, then frames
    /// arriving, then a message worth replying to.
    ///
    /// **This is a demo and the app labels it as one.** Nothing here touches the
    /// capture channel and no screen is read. It yields to a real session the
    /// moment one appears.
    ///
    /// Refused while a capture session is watching, and `canPlaySample` is how
    /// the app says so in words instead of leaving a button that does nothing.
    /// The old guard was `!state.isLive`, which refused for a second reason it
    /// never explained: a paused or recently-ended capture session left `state`
    /// non-live but `source == .capture`, and the sample it did start was then
    /// overwritten by the next poll.
    public func start() {
        guard canPlaySample else { return }
        Feedback.actionPress()
        startedAt = Date()
        framesRead = 0
        source = .scripted
        state = .starting

        task?.cancel()
        task = nil

        // A reader is attached, so frames arrive through
        // `submit(_:appName:appIcon:)` and the session waits for them. Running
        // the scripted timeline alongside a real reader would drop the sample
        // context on top of a real reading two seconds in, which is exactly what
        // `ScreenContextBarTests` drives.
        guard reader == nil else {
            state = .watching
            return
        }

        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: MockScreenContext.startupDelay)
            guard !Task.isCancelled, let self else { return }
            state = .watching

            try? await Task.sleep(for: MockScreenContext.firstReadDelay)
            guard !Task.isCancelled else { return }
            framesRead = 34
            state = .ready(MockScreenContext.sample(at: sampleIndex))

            // Keep the frame counter moving so the session reads as live.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                framesRead += 30
            }
        }
    }

    /// Stops the scripted demo. A real broadcast is stopped by the user, in
    /// Apple's own UI, and nothing in this process can end one — which is why
    /// the strip offers this only while the demo is what is running.
    public func stop() {
        Feedback.modifierPress()
        task?.cancel()
        task = nil
        state = .off
        source = .none
        startedAt = nil
        framesRead = 0
    }

    /// Stands in for the user moving to a different conversation.
    public func advanceToNextSample() {
        guard state.isLive, source == .scripted else { return }
        sampleIndex += 1
        state = .ready(MockScreenContext.sample(at: sampleIndex))
    }
}
