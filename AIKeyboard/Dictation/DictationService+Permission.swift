import AVFoundation

extension DictationService {

    // MARK: Permission

    public var microphoneAuthorized: Bool {
        AVAudioApplication.shared.recordPermission == .granted
    }

    public var microphoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    public func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
