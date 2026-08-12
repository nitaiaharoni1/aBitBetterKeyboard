import AIKeyboardCore
import AVFoundation

extension DictationService {

    // MARK: The engine

    func startEngine() throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else { throw DictationServiceError.noInput }

        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: AudioFormat.sampleRate,
                channels: 1, interleaved: true),
            let converter = AVAudioConverter(from: inputFormat, to: target)
        else { throw DictationServiceError.noConverter }

        // **The tap appends under `recording`'s own lock and hops to no actor at
        // all.** It used to end with `Task { @MainActor in consume(samples:) }`,
        // one unstructured task per buffer, which is a real defect and not a
        // stylistic one: separate unstructured tasks have no ordering guarantee
        // between them, so a recording could be reassembled with its buffers out
        // of order — audible as stuttering nonsense in anything longer than a
        // word, and invisible to every test here because no test records. The
        // level the UI shows is read from the same lock by the 10 Hz poll, which
        // is more than fast enough for a waveform and means the audio thread
        // publishes nothing.
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) {
            [weak self] incoming, _ in
            guard let self else { return }
            guard
                let converted = AVAudioPCMBuffer(
                    pcmFormat: target,
                    frameCapacity: AVAudioFrameCount(
                        Double(incoming.frameLength) * target.sampleRate / inputFormat.sampleRate)
                        + 1024)
            else { return }

            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return incoming
            }
            // **Apple's transcriber is fed the *untouched* input buffer, not the
            // 16 kHz Int16 one below.** It asks for its own preferred format
            // through `SpeechAnalyzer.bestAvailableAudioFormat`, and converting
            // twice — once to the recording's format, once from that to the
            // analyzer's — would resample resampled audio for no reason. This
            // costs one more conversion on the tap thread and keeps both paths
            // reading from the microphone rather than from each other.
            if #available(iOS 26.0, *), let live = self.live as? LiveTranscriber {
                live.append(incoming)
            }

            guard error == nil, converted.frameLength > 0,
                let channel = converted.int16ChannelData
            else { return }

            self.recording.append(
                UnsafeBufferPointer(start: channel[0], count: Int(converted.frameLength)))
        }

        engine.prepare()
        try engine.start()
    }

    /// **A dropped input route silently ends the recording, so it is watched
    /// for.** Unplugging earbuds, a Bluetooth headset going out of range, or the
    /// system reconfiguring the audio graph all post
    /// `AVAudioEngineConfigurationChange`, and after one the engine has stopped
    /// and the tap on the old input node is gone. Nothing throws. Without this
    /// the session would keep heartbeating, the keyboard would keep saying
    /// "Listening", and every utterance from then on would be four seconds of
    /// nothing — which `SpeechGate` would at least refuse rather than invent
    /// over, but the user would be told they were being heard.
    func observeEngineConfigurationChanges() {
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isRunning else { return }
                    self.engine.inputNode.removeTap(onBus: 0)
                    do {
                        try self.startEngine()
                        Self.log.notice("dictation engine rebuilt after a route change")
                    } catch {
                        self.stop(.audioFailed)
                    }
                }
            })
    }
}
