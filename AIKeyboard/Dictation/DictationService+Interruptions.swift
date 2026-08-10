import AVFoundation

extension DictationService {

    // MARK: Interruptions

    func observeInterruptions() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(), queue: .main
            ) { [weak self] note in
                guard
                    let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                    AVAudioSession.InterruptionType(rawValue: raw) == .began
                else { return }
                // Ended without resuming, on purpose. A phone call takes the
                // microphone, and quietly reopening it afterwards would leave a
                // session running that the user believes ended with the call.
                MainActor.assumeIsolated { self?.stop(.interrupted) }
            })

        observers.append(
            center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: AVAudioSession.sharedInstance(), queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(.audioFailed) }
            })
    }
}
