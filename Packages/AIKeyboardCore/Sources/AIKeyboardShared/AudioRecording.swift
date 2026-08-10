import Foundation

/// The format everything in this feature speaks: 16 kHz, mono, 16-bit signed
/// little-endian PCM.
///
/// **Not a guess and not a default.** `Bar/dictation/` is recorded at exactly
/// this and `Bar/dictation/harness/transcribe.py` uploads it untouched, so every
/// published word error rate was bought with these bytes. A recorder that sends
/// 48 kHz float, or stereo, or AAC, is sending something no corpus in this repo
/// has ever scored.
///
/// It is also cheap in the place that matters: 32 KB a second, so a minute of
/// speech is 1.9 MB of PCM and about 2.6 MB once base64 puts it in a JSON body,
/// under the backend's 8 MB cap with room to spare.
public enum AudioFormat {
    public static let sampleRate = 16_000.0
    public static let channels = 1
    public static let bitsPerSample = 16
    public static let mimeType = "audio/wav"
}

/// Wraps raw PCM in a WAV header.
///
/// Written by hand rather than through `AVAudioFile` because the only consumer
/// is an HTTP body: a file on disk would be a recording of the user's voice
/// sitting in a container that gets backed up, which is the one thing
/// `DictationTranscriptRecord` promises never happens.
public enum WAVEncoder {

    /// 44 bytes: `RIFF` size `WAVE`, then `fmt ` and `data`.
    public static let headerBytes = 44

    public static func encode(
        _ samples: [Int16], sampleRate: Double = AudioFormat.sampleRate,
        channels: Int = AudioFormat.channels
    ) -> Data {
        let bytesPerSample = AudioFormat.bitsPerSample / 8
        let dataBytes = samples.count * bytesPerSample
        let byteRate = Int(sampleRate) * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var data = Data(capacity: headerBytes + dataBytes)
        func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: Int) {
            withUnsafeBytes(of: UInt32(truncatingIfNeeded: value).littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        func append16(_ value: Int) {
            withUnsafeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian) {
                data.append(contentsOf: $0)
            }
        }

        append("RIFF")
        append32(36 + dataBytes)
        append("WAVE")
        append("fmt ")
        append32(16)  // PCM header length
        append16(1)  // PCM, uncompressed
        append16(channels)
        append32(Int(sampleRate))
        append32(byteRate)
        append16(blockAlign)
        append16(AudioFormat.bitsPerSample)
        append("data")
        append32(dataBytes)

        samples.withUnsafeBufferPointer { buffer in
            buffer.baseAddress.map {
                data.append(UnsafeRawPointer($0).assumingMemoryBound(to: UInt8.self), count: dataBytes)
            }
        }
        return data
    }
}

/// One utterance as it accumulates, and the arithmetic that decides whether it
/// is worth sending anywhere.
///
/// **Kept here rather than in the app** so it can be driven from a test with a
/// WAV file instead of a microphone. The `AVAudioEngine` half in `AIKeyboard/`
/// is then only plumbing: convert a buffer, hand the samples here.
///
/// Frame levels are computed as the samples arrive rather than in a second pass
/// over the whole recording, which is what lets the waveform and `SpeechGate`
/// share one measurement and lets a sixty-second utterance be judged without
/// walking a million samples twice.
public final class UtteranceBuffer {

    public private(set) var samples: [Int16] = []
    public private(set) var levels: [Double] = []

    private var pending: [Int16] = []
    private let frameSize: Int
    private let sampleRate: Double
    private let maximumSamples: Int

    public init(
        sampleRate: Double = AudioFormat.sampleRate,
        frameSeconds: Double = SpeechGate.frameSeconds,
        maximumSeconds: Double = SpeechGate.maximumSeconds
    ) {
        self.sampleRate = sampleRate
        self.frameSize = max(1, Int((sampleRate * frameSeconds).rounded()))
        self.maximumSamples = Int(sampleRate * maximumSeconds)
    }

    public var seconds: Double { Double(samples.count) / sampleRate }

    /// True once the cap is reached, which the recorder reads as "close this
    /// utterance now" rather than as an error. Sixty seconds of held-down
    /// dictation is a user who has forgotten they are recording.
    public var isFull: Bool { samples.count >= maximumSamples }

    /// The most recent frame's level, for the waveform. Zero before the first
    /// full frame arrives.
    public private(set) var level: Double = 0

    public func append(_ incoming: some Collection<Int16>) {
        guard !isFull else { return }
        let room = maximumSamples - samples.count
        let taken = incoming.count <= room ? Array(incoming) : Array(incoming.prefix(room))
        samples.append(contentsOf: taken)

        pending.append(contentsOf: taken)
        while pending.count >= frameSize {
            let frame = pending.prefix(frameSize)
            let value = SpeechGate.level(of: frame)
            levels.append(value)
            level = value
            pending.removeFirst(frameSize)
        }
    }

    public func reset() {
        samples.removeAll(keepingCapacity: true)
        levels.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        level = 0
    }

    public var reading: SpeechGate.Reading {
        SpeechGate.measure(levels: levels)
    }

    public var verdict: SpeechGate.Verdict { SpeechGate.verdict(reading) }

    public func wav() -> Data { WAVEncoder.encode(samples, sampleRate: sampleRate) }
}

// MARK: - Reading a WAV back

/// Decodes the 16-bit PCM WAVs this project records and the ones
/// `Bar/dictation/` ships.
///
/// **Exists for the tests, and says so.** Nothing in the shipping path reads a
/// WAV — the recorder produces samples and encodes them once. `SpeechGateTests`
/// needs the reverse to hold the shipping thresholds against the same 39 files
/// the thresholds were derived from, and a gate proved only against synthetic
/// arrays is a gate proved against nothing.
public enum WAVDecoder {

    public struct Decoded: Sendable {
        public let samples: [Int16]
        public let sampleRate: Double
    }

    public static func decode(_ input: Data) -> Decoded? {
        // **Copied into an array first, because `Data` is not reliably
        // zero-indexed.** A `Data` that came from slicing another one keeps the
        // parent's indices, so `data[0]` traps and every offset below would be
        // wrong by the slice's origin. Nothing in this repo passes a slice today,
        // which is exactly the kind of thing that stays true until it does not,
        // and the failure mode is a crash rather than a wrong answer.
        let data = [UInt8](input)
        guard data.count > WAVEncoder.headerBytes,
            data[0..<4].elementsEqual(Array("RIFF".utf8)),
            data[8..<12].elementsEqual(Array("WAVE".utf8))
        else { return nil }

        func uint32(at offset: Int) -> Int {
            Int(
                UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16
                    | UInt32(data[offset + 3]) << 24)
        }
        func uint16(at offset: Int) -> Int { Int(UInt16(data[offset]) | UInt16(data[offset + 1]) << 8) }

        // Walk the chunks rather than assuming a 44-byte header: `say` writes a
        // plain one, but a file that picked up a `LIST` chunk on the way here
        // would decode as noise if the offsets were hardcoded.
        var offset = 12
        var sampleRate = AudioFormat.sampleRate
        var bits = 16
        while offset + 8 <= data.count {
            let identifier = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = uint32(at: offset + 4)
            let body = offset + 8
            if identifier == "fmt ", body + 16 <= data.count {
                sampleRate = Double(uint32(at: body + 4))
                bits = uint16(at: body + 14)
            } else if identifier == "data" {
                let end = min(data.count, body + size)
                guard bits == 16, end > body else { return nil }
                var samples = [Int16]()
                samples.reserveCapacity((end - body) / 2)
                var index = body
                while index + 1 < end {
                    samples.append(Int16(bitPattern: UInt16(data[index]) | UInt16(data[index + 1]) << 8))
                    index += 2
                }
                return Decoded(samples: samples, sampleRate: sampleRate)
            }
            offset = body + size + (size % 2)
        }
        return nil
    }
}
