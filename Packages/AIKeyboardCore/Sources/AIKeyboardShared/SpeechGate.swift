import Foundation

/// Decides, on the device and before any audio is uploaded, whether a recording
/// has a person talking in it.
///
/// **This exists because the model cannot be asked.** The transcription request
/// makes the model answer `speech` — yes or no — before it writes a word, which
/// is the same "decide first" shape `EditScope` uses for Fix and `OutputGuard`
/// for Rewrite, and against the dictation bar it does not work. Four seconds of
/// digital silence come back as `speech: yes` and the sentence *"I'm not sure if
/// I'm going to be able to make it to the meeting."* — reproducibly, in all four
/// prompt variants measured, and the best-scoring of those also invents the same
/// sentence out of stationary noise (`Bar/dictation/ablation/`). A keyboard that
/// types a plausible message nobody said, in the user's own voice, into somebody
/// else's chat is the worst thing this product can do, so the question is
/// answered here instead, by arithmetic that cannot hallucinate.
///
/// **What separates speech from a room, measured on all 39 clips.** Not loudness
/// — `trap-tone` is louder than a third of the corpus. Speech has *gaps*: the
/// silences between words sit far below the peak, while a tone, a fan or a road
/// hum sits at one level for the whole recording. Comparing a quiet frame
/// against the loudest one splits the two sets by a factor of four in both
/// directions:
///
///     36 real clips     quietest/peak  0.012 – 0.21
///     trap-noise                       0.91
///     trap-tone                        0.98
///     trap-silence                     peak is 0
///
/// `SpeechGateTests` re-measures that table from the same WAV files, so a
/// threshold moved without re-measuring fails there.
///
/// **The honest limitation.** Every clip in that corpus is `say` output: studio
/// clean, with true digital silence between the words. A phone in a car has room
/// tone in those gaps, which lifts the quiet frames and pushes a real utterance
/// towards the refusing side. The threshold is set at 0.5 — more than twice the
/// noisiest real clip and nearly half the quietest trap — to leave room for
/// that, and the direction of the remaining error is deliberate: a refusal says
/// "I didn't catch that" and costs the user a second tap, while a false accept
/// can put an invented sentence in their name. It still needs re-measuring
/// against real recordings the first time any exist; see `Bar/dictation/README.md`
/// on what a real corpus needs.
public enum SpeechGate {

    /// 20 ms. Long enough for one pitch period of the lowest human voice, short
    /// enough that a gap between two words spans several frames.
    public static let frameSeconds = 0.02

    /// Below this the loudest frame in the recording is not a voice at anything
    /// like a usable distance. -40 dBFS; the quietest clip in the corpus peaks
    /// at 0.208, twenty times higher.
    public static let peakFloor: Double = 0.01

    /// The quiet-frame-to-peak ratio above which a recording is one steady sound
    /// rather than speech.
    public static let dynamicsCeiling: Double = 0.5

    /// Shorter than this there is no utterance to send. Two frames of speech
    /// and a gap is not a word.
    public static let minimumSeconds = 0.4

    /// The longest single utterance. 16 kHz mono PCM is 32 KB a second, so a
    /// minute is about 2 MB and 2.6 MB once base64 puts it in a JSON body —
    /// which is the real reason for a cap. Dictating for longer than a minute
    /// without pausing is not the case this is protecting against.
    public static let maximumSeconds = 60.0

    /// What the arithmetic found, kept as values so the diagnostics screen and
    /// the tests can show the same numbers the verdict was taken from.
    public struct Reading: Equatable, Sendable {
        public let seconds: Double
        public let peak: Double
        /// The tenth-percentile frame, which is what stands in for "how quiet
        /// does this recording ever get". A minimum would be one unlucky frame;
        /// a median would be the middle of a word.
        public let quietest: Double
        /// `quietest / peak`, or 1 when the recording is completely flat.
        public let dynamics: Double

        public init(seconds: Double, peak: Double, quietest: Double) {
            self.seconds = seconds
            self.peak = peak
            self.quietest = quietest
            self.dynamics = peak > 0 ? quietest / peak : 1
        }
    }

    public enum Verdict: Equatable, Sendable {
        case speech
        /// Nothing loud enough to be a voice.
        case silent
        /// Loud enough, but at one unvarying level: a tone, a fan, a road, a
        /// held note. Not somebody talking.
        case stationary
        case tooShort

        public var isSpeech: Bool { self == .speech }

        /// What the panel says. Never "an error occurred": every one of these is
        /// something the user can fix with one more tap, and the sentence has to
        /// say which tap.
        public var explanation: String {
            switch self {
            case .speech: return ""
            case .silent: return "I didn't hear anything. Check the microphone isn't covered."
            case .stationary: return "I only heard background noise. Try again a bit closer."
            case .tooShort: return "That was too short to make out. Hold on and speak."
            }
        }
    }

    /// The root-mean-square level of one frame, on a 0...1 scale.
    ///
    /// Taken from the samples the recorder already has in hand, frame by frame
    /// as they arrive, so nothing has to keep the whole recording in memory a
    /// second time to answer this — and the same numbers drive the waveform.
    public static func level(of samples: some Collection<Int16>) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for sample in samples {
            let value = Double(sample) / 32768
            sum += value * value
        }
        return (sum / Double(samples.count)).squareRoot()
    }

    /// Splits a buffer into `frameSeconds` frames and levels each one. The
    /// remainder at the end is dropped rather than levelled short, so a partial
    /// frame cannot land in the tenth percentile as an artificially quiet one.
    public static func levels(
        of samples: [Int16], sampleRate: Double, frameSeconds: Double = SpeechGate.frameSeconds
    ) -> [Double] {
        let size = Int((sampleRate * frameSeconds).rounded())
        guard size > 0, samples.count >= size else { return [] }
        return stride(from: 0, through: samples.count - size, by: size).map {
            level(of: samples[$0..<($0 + size)])
        }
    }

    public static func measure(
        levels: [Double], frameSeconds: Double = SpeechGate.frameSeconds
    )
        -> Reading
    {
        guard !levels.isEmpty else { return Reading(seconds: 0, peak: 0, quietest: 0) }
        let sorted = levels.sorted()
        return Reading(
            seconds: Double(levels.count) * frameSeconds,
            peak: sorted[sorted.count - 1],
            quietest: sorted[sorted.count / 10])
    }

    /// The order the three conditions are asked in is load-bearing for what the
    /// user is told, not for what is refused. A recording that is both too short
    /// and silent is reported as silent, because "speak louder" is the useful
    /// half; length is only the answer when there was something to hear.
    public static func verdict(_ reading: Reading) -> Verdict {
        guard reading.peak >= peakFloor else { return .silent }
        guard reading.dynamics < dynamicsCeiling else { return .stationary }
        guard reading.seconds >= minimumSeconds else { return .tooShort }
        return .speech
    }

    public static func verdict(levels: [Double]) -> Verdict { verdict(measure(levels: levels)) }
}
