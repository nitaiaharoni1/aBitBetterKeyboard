import AIKeyboardCore
import AVFoundation
import Combine
import Foundation
import os

/// Holds the microphone for the keyboard, because the keyboard cannot.
///
/// **The whole design is forced by one error code.** A keyboard extension that
/// calls `AVAudioSession.setActive(true)` for recording gets 561145187,
/// `cannotStartRecording`, with Full Access granted and the microphone entitled —
/// Apple's custom-keyboard guidance lists "No access to microphone and speaker"
/// under the keyboard sandbox and open access adds Location, Contacts, a shared
/// container, network and iCloud, never the microphone. So the microphone lives
/// here, in the containing app, and the keyboard reads a transcript across the
/// App Group. That is what Wispr Flow ships on iOS and it is the shape this repo
/// already runs for screen context.
///
/// **The same error code is why there is a session at all rather than a button.**
/// An app in the background cannot *begin* recording; an app whose recording
/// session is already active keeps it across a switch, under the `audio`
/// background mode. So the user starts a session here, in the foreground, and
/// the keyboard then opens and closes utterances inside a session that is
/// already live. Nothing in the keyboard can launch this app — `UIApplication`
/// is unavailable to extensions and the responder-chain `openURL` workaround is
/// explicitly disallowed — so when no session is running the keyboard says so
/// and says where to go, rather than pretending.
///
/// **What has actually run.** The channel, the gate, the encoder and the
/// transcription are exercised by tests and by `Bar/dictation/`. The
/// `AVAudioEngine` half below has not been run on a device by anyone, and a
/// simulator cannot settle it: background audio, jetsam and interruption are
/// device behaviours. `Scripts/prove-dictation.sh` is what turns that into a
/// measurement when a phone is available.
@MainActor
public final class DictationService: ObservableObject {

    public static let shared = DictationService()

    // MARK: Published state

    @Published public private(set) var isRunning = false
    @Published public private(set) var phase: DictationPhase = .idle
    @Published public private(set) var level: Double = 0
    @Published public private(set) var lastTranscript = ""
    @Published public private(set) var lastError = ""
    @Published public private(set) var utterances = 0
    @Published public private(set) var refusedNoSpeech = 0
    @Published public private(set) var endReason: DictationEndReason = .notEnded
    @Published public private(set) var expiresAt: Date?

    // MARK: Machinery

    private let engine = AVAudioEngine()
    private var writer: DictationChannelWriter?
    /// Shared with the audio thread. See `LiveRecording`.
    private let recording = LiveRecording()
    private var openUtterance: UInt64 = 0
    private var recordingStartedAt: UInt64 = 0
    private var sessionID = UUID()
    private var timer: Timer?
    private var transcribing: Task<Void, Never>?
    /// How many transcriptions are in flight. A count rather than a flag because
    /// two can overlap — see `close(utterance:)` — and the first to finish must
    /// not report the session idle while the second is still running.
    private var inFlight = 0
    private var observers: [NSObjectProtocol] = []

    /// **Monotonic, not the wall clock.** `expiresAt` below is a `Date` for the
    /// countdown this screen draws; the decision to end the session is taken
    /// against `CaptureClock`, for the reason that clock exists at all — a clock
    /// the user can set is a clock that can hold a microphone open past the limit
    /// they chose, or close it early. The keyboard reads the same monotonic value
    /// out of the shared page.
    private var expiresAtMonotonic: UInt64 = 0

    /// 10 Hz. The keyboard's button has to feel immediate, a page load costs
    /// nothing, and it is also how often the level the waveform draws is read off
    /// the audio thread — see `LiveRecording`.
    private static let pollInterval: TimeInterval = 0.1

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "Dictation")

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

    // MARK: The engine

    private func startEngine() throws {
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
    private func observeEngineConfigurationChanges() {
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

    // MARK: The poll

    private func startPolling() {
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var lastHeartbeat: UInt64 = 0

    private func poll() {
        guard isRunning, let writer else { return }
        let now = CaptureClock.now()

        // 1 Hz, independent of everything else in this method. It is the only
        // signal that separates "this app is running" from "this app was
        // jetsammed with `phase` still saying listening".
        if CaptureClock.elapsed(since: lastHeartbeat, now: now) >= CaptureClock.nanoseconds(1) {
            writer.heartbeat(now: now)
            lastHeartbeat = now
        }

        if expiresAtMonotonic > 0, now >= expiresAtMonotonic {
            stop(.expired)
            return
        }

        // One read of the audio thread's state per poll, and the only one.
        let reading = recording.reading()
        level = reading.level
        writer.setLevel(reading.level)
        if reading.isFull, openUtterance > 0 {
            // Sixty seconds is somebody who has forgotten they are recording, so
            // it closes as if they had tapped Insert rather than discarding what
            // they said.
            Self.log.notice("utterance \(self.openUtterance) hit the length cap")
            close(utterance: openUtterance)
            return
        }

        guard let request = writer.request() else { return }

        // The dead-man's switch. A keyboard extension is killed rather than
        // dismissed all the time, and an utterance left open by one is a
        // microphone recording for nobody.
        if openUtterance > 0, !request.isKeyboardAlive(now: now) {
            Self.log.notice("dropping utterance \(self.openUtterance): the keyboard stopped answering")
            drop()
            return
        }

        if request.cancelUtterance >= openUtterance, openUtterance > 0 {
            drop()
            return
        }

        if request.utterance > openUtterance, request.wantsRecording(now: now) {
            open(utterance: request.utterance, at: now)
            return
        }

        if openUtterance > 0, request.stopUtterance >= openUtterance {
            close(utterance: openUtterance)
        }
    }

    private func open(utterance: UInt64, at now: UInt64) {
        recording.begin()
        openUtterance = utterance
        recordingStartedAt = now
        phase = .listening
        writer?.setPhase(.listening, utterance: utterance)
    }

    private func drop() {
        recording.discard()
        openUtterance = 0
        phase = .idle
        writer?.setPhase(.idle)
    }

    private func close(utterance: UInt64) {
        guard openUtterance == utterance, let writer else { return }
        openUtterance = 0
        phase = .transcribing
        writer.setPhase(.transcribing, utterance: utterance)
        writer.count(\.utterances)
        utterances += 1

        // One transaction, so the length, the verdict and the bytes cannot come
        // from three different moments while the tap is still delivering.
        let taken = recording.end()
        let seconds = taken.seconds
        let verdict = taken.verdict
        let recordedAt = recordingStartedAt
        // Stamped now, not when the answer comes back. See `publish`.
        let session = sessionID

        // **The gate runs before the upload, not after it.** Four seconds of
        // silence come back from the model as a fluent invented sentence — see
        // `SpeechGate` — so a recording with nothing in it must never reach the
        // network at all. It is also the cheaper order: no bytes, no call, no
        // wait.
        guard verdict.isSpeech else {
            writer.count(\.refusedNoSpeech)
            refusedNoSpeech += 1
            level = 0
            phase = .idle
            writer.setPhase(.idle)
            publish(
                DictationTranscriptRecord(
                    sessionID: session, utterance: utterance, outcome: .nothing, text: "",
                    detail: verdict.explanation, recordedAt: recordedAt,
                    completedAt: CaptureClock.now(), seconds: seconds))
            return
        }

        let audio = taken.audio
        level = 0
        let languages = SharedStore.shared.enabledLanguages

        // **Not cancelled, and the previous one is not either.** An earlier
        // version cancelled any in-flight transcription here, which is wrong in
        // the one case it matters: somebody dictating two sentences quickly would
        // have the first silently dropped, and the keyboard that asked for it
        // would wait for a record nobody was going to publish. Both run; the
        // records carry their own utterance numbers and the keyboard takes the
        // one it asked for.
        transcribing = Task { [weak self] in
            await self?.transcribe(
                audio: audio, session: session, utterance: utterance, seconds: seconds,
                recordedAt: recordedAt, languages: languages)
        }
    }

    private func transcribe(
        audio: Data, session: UUID, utterance: UInt64, seconds: Double, recordedAt: UInt64,
        languages: [KeyboardLanguage]
    ) async {
        inFlight += 1
        defer {
            inFlight -= 1
            if inFlight == 0 {
                phase = .idle
                writer?.setPhase(.idle)
            }
        }

        // `isReady` as well as `configured()`: a build ships a backend address, so
        // `configured()` alone is true on a fresh install and this would upload the
        // recording before finding out there is no token to send with it. Failing
        // here costs the user a message instead of their audio.
        guard BackendTransport.isReady(), let transport = BackendTransport.configured() else {
            fail(
                session: session, utterance: utterance, recordedAt: recordedAt, seconds: seconds,
                detail: AIEngineError.cloudNotConfigured.message)
            return
        }

        do {
            let output = try await CloudDictation(transport: transport)
                .transcribe(audio, languages: languages)
            guard !Task.isCancelled else { return }
            lastTranscript = output.value.text
            lastError = ""
            publish(
                DictationTranscriptRecord(
                    sessionID: session, utterance: utterance, outcome: .transcribed,
                    text: output.value.text, languages: output.value.languages,
                    recordedAt: recordedAt, completedAt: CaptureClock.now(), seconds: seconds))
        } catch {
            guard !Task.isCancelled else { return }
            let detail = (error as? AIEngineError)?.message ?? error.localizedDescription
            // `.empty` is what the transcriber throws when the model heard
            // nothing after all — the second layer behind `SpeechGate`, and it
            // reads to the user as "I didn't catch that", not as a failure.
            let outcome: DictationOutcome = (error as? AIEngineError) == .empty ? .nothing : .failed
            if outcome == .failed { writer?.count(\.failures) }
            fail(
                session: session, utterance: utterance, recordedAt: recordedAt, seconds: seconds,
                detail: detail, outcome: outcome)
        }
    }

    private func fail(
        session: UUID, utterance: UInt64, recordedAt: UInt64, seconds: Double, detail: String,
        outcome: DictationOutcome = .failed
    ) {
        lastError = detail
        publish(
            DictationTranscriptRecord(
                sessionID: session, utterance: utterance, outcome: outcome, text: "",
                detail: detail, recordedAt: recordedAt, completedAt: CaptureClock.now(),
                seconds: seconds))
    }

    /// Every path out of an utterance publishes something, including the ones
    /// that produced no text.
    ///
    /// **A request that produced nothing must not produce silence.** The
    /// keyboard is sitting on a spinner waiting for a record carrying its own
    /// number; a failure that says nothing is indistinguishable from an app that
    /// is no longer running, and the user is told the wrong thing about a
    /// microphone that is working. `ScreenReadingRecord` carries the same rule
    /// and it was learned there first.
    private func publish(_ record: DictationTranscriptRecord) {
        // **A transcription outlives the session it was recorded in, and the
        // window is real.** `stop()` cancels only the newest in-flight call, and
        // `DictationChannelWriter.publish` refuses only while the channel is
        // *ended* — so a user who stops a session and starts another one inside
        // the two-or-so seconds a transcription takes reopens that gate, and the
        // old answer lands in the new session carrying an utterance number the
        // new session may reach. That is a sentence from before, inserted into
        // whatever they are typing now. The session is stamped on the record at
        // the moment the recording closed, and compared here.
        guard record.sessionID == sessionID else {
            Self.log.notice("dropped a transcript belonging to a session that has ended")
            return
        }
        do {
            try writer?.publish(record)
        } catch {
            Self.log.notice("transcript dropped: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Interruptions

    private func observeInterruptions() {
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

/// The one piece of state the audio thread and the main actor both touch.
///
/// **It exists because those are genuinely two threads, and Swift concurrency
/// cannot be used to bridge them here.** An `AVAudioEngine` tap is called on a
/// dedicated audio thread with a hard deadline; the alternatives are to hop to
/// an actor per buffer, which loses ordering (see `startEngine`), or to hold a
/// lock for the length of an array append, which is what this does. The same
/// trade is already made in `SharedPage.store`, called from ReplayKit's delivery
/// callback for the same reason.
///
/// `open` is checked inside the lock rather than read from the main actor,
/// because the alternative is a buffer arriving between "stop recording" and the
/// tap noticing — a fragment of the next room's audio on the end of the utterance
/// that was already closed.
private final class LiveRecording: @unchecked Sendable {

    private let lock = OSAllocatedUnfairLock()
    private var buffer = UtteranceBuffer()
    private var open = false
    private var lastLevel: Double = 0

    func begin() {
        lock.lock()
        defer { lock.unlock() }
        buffer.reset()
        lastLevel = 0
        open = true
    }

    /// Closes the recording and hands back everything the caller needs to decide
    /// what to do with it, in one transaction — so the length, the verdict and
    /// the bytes cannot come from three different moments.
    func end() -> (audio: Data, seconds: Double, verdict: SpeechGate.Verdict) {
        lock.lock()
        defer {
            buffer.reset()
            lock.unlock()
        }
        open = false
        return (buffer.wav(), buffer.seconds, buffer.verdict)
    }

    func discard() {
        lock.lock()
        defer { lock.unlock() }
        open = false
        buffer.reset()
    }

    /// **Nothing is kept between utterances, and the level still moves.** The
    /// microphone is open for the whole session, so a buffer that accumulated
    /// while nothing was being dictated would be a recording of the user made
    /// without them asking — and would hit the sixty-second cap within a minute
    /// of idling. Measuring the arriving samples directly gives the keyboard's
    /// waveform something live to draw without keeping a single sample.
    func append(_ samples: UnsafeBufferPointer<Int16>) {
        lock.lock()
        defer { lock.unlock() }
        if open {
            buffer.append(samples)
            lastLevel = buffer.level
        } else {
            lastLevel = SpeechGate.level(of: samples)
        }
    }

    /// The level, and whether the cap has been reached. Read by the 10 Hz poll,
    /// which is fast enough for a waveform and means the audio thread publishes
    /// nothing and touches no actor.
    func reading() -> (level: Double, isFull: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (lastLevel, open && buffer.isFull)
    }
}

enum DictationServiceError: Error, LocalizedError {
    case noInput
    case noConverter

    var errorDescription: String? {
        switch self {
        case .noInput: return "no audio input is available"
        case .noConverter: return "the input format cannot be converted to 16 kHz mono"
        }
    }
}
