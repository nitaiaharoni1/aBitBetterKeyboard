import AIKeyboardCore
import Foundation
import os

/// A stand-in recorder for the dictation channel, so the cross-process proof has
/// a second process on this machine.
///
/// **This is not the microphone and it is not shipped behaviour.** It runs only
/// under `-uiTestDictationChannel`. What it runs is the *real*
/// `DictationChannelWriter` — the same session lifecycle, the same heartbeat, the
/// same seqlock pages, the same atomic transcript publish `DictationService`
/// uses — driven from the same 10 Hz poll, with two things replaced:
///
///   - **the microphone**, by a fixed sentence, because a UI test cannot speak
///     and a simulator's audio input is the host Mac's;
///   - **the transcriber**, by returning that sentence, because a network call
///     would make the proof depend on a backend being configured.
///
/// So it proves the half that cannot be proved in one process: that a keyboard
/// extension in its own sandbox opens an utterance, a *different* process sees
/// it, and the transcript that process publishes comes back. `SpeechGate`,
/// `CloudDictation` and the `AVAudioEngine` plumbing are proved elsewhere — by
/// `SpeechGateTests` against the real corpus, by `Bar/dictation/`, and on a
/// device by nothing yet, which `Scripts/prove-dictation.sh` says out loud.
///
/// The verdict comes from the *keyboard's* log lines, never from this side's: a
/// process always sees its own writes.
final class DictationChannelProbe: @unchecked Sendable {

    static let shared = DictationChannelProbe()

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "Dictation")

    /// The same rate `DictationService` polls at.
    private static let tickInterval: TimeInterval = 0.1

    /// Hebrew carrying English loanwords, because that is the sentence this
    /// product exists for and the one a right-to-left layout bug shows up in.
    /// Matched exactly by `Scripts/prove-dictation.sh`.
    static let sentence = "בוא נעשה sync על ה-roadmap של Q3"

    private let queue = DispatchQueue(label: "com.nitai.aikeyboard.dictation-probe")
    private var writer: DictationChannelWriter?
    private var sessionID = UUID()
    private var timer: DispatchSourceTimer?
    private var heartbeat: DispatchSourceTimer?
    private var openUtterance: UInt64 = 0
    private var openedAt: UInt64 = 0

    private init() {}

    func start() {
        queue.async { [self] in
            guard let writer = DictationChannelWriter() else {
                Self.log.error("dictation-probe could not reach the shared container")
                return
            }
            self.writer = writer
            sessionID = writer.begin(seconds: 600, microphoneAuthorized: true)
            Self.log.notice(
                "dictation-probe started session=\(self.sessionID.uuidString, privacy: .public)")

            let heartbeat = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            heartbeat.schedule(deadline: .now(), repeating: 1)
            heartbeat.setEventHandler { [weak self] in self?.writer?.heartbeat() }
            heartbeat.resume()
            self.heartbeat = heartbeat

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: Self.tickInterval)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            self.timer = timer
        }
    }

    /// The recorder's own loop, minus the audio: open on request, close on stop,
    /// abandon when the keyboard stops answering.
    private func tick() {
        guard let writer, let request = writer.request() else { return }
        let now = CaptureClock.now()

        // A level that moves, so the keyboard's waveform is driven by this page
        // rather than by a local animation — which is a thing the proof can see.
        writer.setLevel(openUtterance > 0 ? 0.2 + 0.5 * abs(sin(Double(now % 1_000_000_000) / 1e8)) : 0)

        if openUtterance > 0, !request.isKeyboardAlive(now: now) {
            openUtterance = 0
            writer.setPhase(.idle)
            Self.log.notice("dictation-probe dropped an utterance: the keyboard went quiet")
            return
        }

        if request.utterance > openUtterance, request.wantsRecording(now: now) {
            openUtterance = request.utterance
            openedAt = now
            writer.setPhase(.listening, utterance: openUtterance)
            return
        }

        guard openUtterance > 0, request.stopUtterance >= openUtterance else { return }
        let utterance = openUtterance
        openUtterance = 0
        writer.setPhase(.transcribing, utterance: utterance)
        writer.count(\.utterances)

        // A beat of latency, because a transcription that returns instantly
        // would hide any state the panel enters while it waits.
        queue.asyncAfter(deadline: .now() + 0.4) { [self] in
            try? writer.publish(
                DictationTranscriptRecord(
                    sessionID: sessionID, utterance: utterance, text: Self.sentence,
                    languages: "he,en", provenance: "probe", recordedAt: openedAt,
                    completedAt: CaptureClock.now(), seconds: 2.0))
            writer.setPhase(.idle)
            Self.log.notice("dictation-probe published utterance \(utterance)")
        }
    }
}
