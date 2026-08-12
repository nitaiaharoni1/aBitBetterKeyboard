import AIKeyboardCore
import AVFoundation
import Foundation

extension DictationService {

    // MARK: Session lifecycle

    /// Starts a session. **Must be called with the app in the foreground** — see
    /// the note above; from the background this is the 561145187 that shaped the
    /// whole design.
    @discardableResult
    public func start(minutes: Int) async -> Bool {
        guard !isRunning else { return true }

        guard await requestMicrophone() else {
            endReason = .microphoneDenied
            lastError = DictationEndReason.microphoneDenied.explanation
            return false
        }

        guard let writer = DictationChannelWriter() else {
            lastError =
                "AI Keyboard can't reach its shared storage, so the keyboard would never see the transcript."
            return false
        }
        self.writer = writer

        do {
            let session = AVAudioSession.sharedInstance()
            // `.record` rather than `.playAndRecord`: nothing here plays, and
            // `.playAndRecord` would duck and interrupt whatever the user is
            // listening to for the whole session, not just while they speak.
            // `.measurement` turns off the processing that flattens speech, and
            // `.allowBluetooth` is what lets somebody dictate through the
            // earbuds they are already wearing.
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
            try session.setActive(true, options: [])
        } catch {
            endReason = .audioFailed
            lastError = "The microphone couldn't be opened: \(error.localizedDescription)"
            Self.log.error("audio session failed \(error.localizedDescription, privacy: .public)")
            return false
        }

        do {
            try startEngine()
        } catch {
            try? AVAudioSession.sharedInstance().setActive(false)
            endReason = .audioFailed
            lastError = "The microphone couldn't be started: \(error.localizedDescription)"
            return false
        }

        sessionID = UUID()
        let seconds = Double(minutes) * 60
        writer.begin(
            sessionID: sessionID, seconds: seconds, microphoneAuthorized: true)

        isRunning = true
        phase = .idle
        endReason = .notEnded
        lastError = ""
        expiresAt = seconds > 0 ? Date().addingTimeInterval(seconds) : nil
        expiresAtMonotonic = writer.state()?.expiresAt ?? 0
        observeInterruptions()
        observeEngineConfigurationChanges()
        startPolling()
        prepareLiveTranscription()
        Self.log.notice("dictation session started id=\(self.sessionID.uuidString, privacy: .public)")
        return true
    }

    public func stop(_ reason: DictationEndReason = .stoppedByUser) {
        guard isRunning else { return }
        isRunning = false
        phase = .idle
        level = 0
        endReason = reason
        expiresAt = nil
        expiresAtMonotonic = 0

        transcribing?.cancel()
        transcribing = nil
        // **Apple's transcriber goes too.** It holds a loaded speech model and an
        // open analyzer; the session is ending, so there is nothing left for it to
        // transcribe and nobody to read it. Cancelled rather than finished, because
        // a clean finish waits for the analyzer to drain and the answer has nowhere
        // to go — `writer.end(_:)` below sets `hasEnded` and deletes `partial.json`.
        endLiveTranscription(finishing: false)
        timer?.invalidate()
        timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])

        recording.discard()
        openUtterance = 0
        writer?.end(reason)
        Self.log.notice("dictation session ended reason=\(String(describing: reason), privacy: .public)")
    }
}
