import Foundation
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

/// Holds the on-device speech gate to the corpus its thresholds came from.
///
/// **This is the test that stops the keyboard typing a sentence nobody said.**
/// The transcription model, asked to report whether it heard anybody talking,
/// answers yes over four seconds of digital silence and writes a fluent invented
/// sentence — measured, reproducibly, across prompt variants
/// (`Bar/dictation/ablation/`). So the question is answered here instead, by
/// arithmetic, before any audio reaches the network. A threshold moved without
/// re-measuring fails below.
///
/// Reads `Bar/dictation/` off the repository rather than a bundle, the way
/// `ScreenContextBarTests` reads the screen-context corpus: the test target has
/// no resources phase, and a simulator process reads the host filesystem.
final class SpeechGateTests: XCTestCase {

    private static let bar = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Bar/dictation")

    private func levels(ofClip file: String) throws -> [Double] {
        let url = Self.bar.appendingPathComponent(file)
        let data = try Data(contentsOf: url)
        let decoded = try XCTUnwrap(WAVDecoder.decode(data), "\(file) did not decode")
        return SpeechGate.levels(of: decoded.samples, sampleRate: decoded.sampleRate)
    }

    private var corpusClips: [String] {
        get throws {
            let truth = try Data(contentsOf: Self.bar.appendingPathComponent("ground-truth.json"))
            let root = try XCTUnwrap(
                JSONSerialization.jsonObject(with: truth) as? [String: Any])
            let clips = try XCTUnwrap(root["clips"] as? [[String: Any]])
            return clips.compactMap { $0["file"] as? String }
        }
    }

    // MARK: The corpus

    /// Every real recording passes. A gate that refuses speech is a feature that
    /// does not work, and it fails in the direction the user notices most.
    func testEveryCorpusClipIsHeardAsSpeech() throws {
        let clips = try corpusClips
        XCTAssertEqual(clips.count, 36, "the corpus changed size; re-measure the thresholds")

        for file in clips {
            let reading = SpeechGate.measure(levels: try levels(ofClip: file))
            XCTAssertEqual(
                SpeechGate.verdict(reading), .speech,
                "\(file) was refused: peak \(reading.peak), quietest \(reading.quietest)")
        }
    }

    /// The margin, not just the verdict.
    ///
    /// **A pass/fail assertion would survive a threshold moved to within a
    /// hair's breadth of the corpus.** The published separation is a factor of
    /// four in both directions and that is what makes the gate survivable on
    /// real, noisier recordings, so the number is asserted rather than the
    /// outcome. If a clip's dynamics ever exceed half the ceiling, the gate is
    /// one noisy room away from refusing real speech and somebody has to know.
    func testTheCorpusSitsWellBelowTheStationaryCeiling() throws {
        var worst = 0.0
        for file in try corpusClips {
            worst = max(worst, SpeechGate.measure(levels: try levels(ofClip: file)).dynamics)
        }
        XCTAssertLessThan(
            worst, SpeechGate.dynamicsCeiling / 2,
            "the noisiest corpus clip is now within 2x of the refusing threshold")
        // The reading this file was written against, so a model of the
        // measurement exists in the test and not only in prose.
        XCTAssertLessThan(worst, 0.25)
    }

    // MARK: The traps

    /// Generated here rather than committed, the same three
    /// `Bar/dictation/harness/transcribe.py` sends: the corpus directory keeps
    /// holding only human-meaningful audio, and a sine wave is reproducible in
    /// four lines.
    private func trap(_ kind: String, seconds: Double = 4) -> [Int16] {
        let rate = 16_000.0
        let count = Int(rate * seconds)
        switch kind {
        case "silence":
            return [Int16](repeating: 0, count: count)
        case "noise":
            // A linear congruential generator, so the trap is the same samples
            // on every machine and every run.
            var state: UInt64 = 12345
            return (0..<count).map { _ in
                state = (1_103_515_245 &* state &+ 12345) % (1 << 31)
                return Int16((Double(state) / Double(1 << 31) - 0.5) * 2000)
            }
        default:
            return (0..<count).map {
                Int16(8000 * sin(2 * .pi * 440 * Double($0) / rate))
            }
        }
    }

    func testDigitalSilenceIsRefused() {
        let levels = SpeechGate.levels(of: trap("silence"), sampleRate: 16_000)
        XCTAssertEqual(SpeechGate.verdict(levels: levels), .silent)
    }

    /// The one the model gets wrong in the other direction: at the best-scoring
    /// prompt variant it transcribed this as *"I'm not sure if I'm going to be
    /// able to make it to the meeting today."*
    func testStationaryNoiseIsRefused() {
        let levels = SpeechGate.levels(of: trap("noise"), sampleRate: 16_000)
        XCTAssertEqual(SpeechGate.verdict(levels: levels), .stationary)
    }

    /// Louder than a third of the corpus, and still not somebody talking. This
    /// is why the gate is not a loudness threshold.
    func testALoudSteadyToneIsRefused() {
        let samples = trap("tone")
        let levels = SpeechGate.levels(of: samples, sampleRate: 16_000)
        XCTAssertGreaterThan(
            SpeechGate.measure(levels: levels).peak, SpeechGate.peakFloor * 10,
            "the tone must be loud, or this test proves nothing a silence test does not")
        XCTAssertEqual(SpeechGate.verdict(levels: levels), .stationary)
    }

    func testAClipTooShortToBeAWordIsRefused() throws {
        let data = try Data(
            contentsOf: Self.bar.appendingPathComponent("audio/en-01.wav"))
        let decoded = try XCTUnwrap(WAVDecoder.decode(data))
        // A fifth of a second of real speech, which is loud and varied and still
        // not an utterance.
        let clipped = Array(decoded.samples.prefix(Int(decoded.sampleRate * 0.2)))
        let levels = SpeechGate.levels(of: clipped, sampleRate: decoded.sampleRate)
        XCTAssertEqual(SpeechGate.verdict(levels: levels), .tooShort)
    }

    // MARK: Buffer and encoder

    func testTheEncoderRoundTripsThroughItsOwnDecoder() {
        let samples: [Int16] = (0..<1000).map { Int16(truncatingIfNeeded: $0 * 31) }
        let decoded = WAVDecoder.decode(WAVEncoder.encode(samples))
        XCTAssertEqual(decoded?.samples, samples)
        XCTAssertEqual(decoded?.sampleRate, AudioFormat.sampleRate)
    }

    /// The corpus is written by macOS `say`, not by this encoder, so decoding it
    /// is what proves the decoder handles a WAV somebody else wrote — the
    /// round-trip above would pass against two matching bugs.
    func testTheDecoderReadsAWavItDidNotWrite() throws {
        let data = try Data(contentsOf: Self.bar.appendingPathComponent("audio/he-01.wav"))
        let decoded = try XCTUnwrap(WAVDecoder.decode(data))
        XCTAssertEqual(decoded.sampleRate, 16_000)
        // ground-truth.json says 4.876s.
        XCTAssertEqual(Double(decoded.samples.count) / decoded.sampleRate, 4.876, accuracy: 0.01)
    }

    /// The cap is what keeps a forgotten microphone from becoming a 20 MB body.
    func testTheBufferStopsAtTheMaximumLength() {
        let buffer = UtteranceBuffer()
        let oneSecond = [Int16](repeating: 1000, count: 16_000)
        for _ in 0..<Int(SpeechGate.maximumSeconds) + 10 { buffer.append(oneSecond) }
        XCTAssertTrue(buffer.isFull)
        XCTAssertEqual(buffer.seconds, SpeechGate.maximumSeconds, accuracy: 0.01)
    }

    /// The buffer's own verdict has to agree with the file it was fed, or the
    /// recorder and this test are measuring two different things.
    func testTheBufferAgreesWithTheGateOnARealClip() throws {
        let data = try Data(contentsOf: Self.bar.appendingPathComponent("audio/mix-02.wav"))
        let decoded = try XCTUnwrap(WAVDecoder.decode(data))
        let buffer = UtteranceBuffer(sampleRate: decoded.sampleRate)
        // In chunks, the way an audio tap delivers them, so a bug in the frame
        // boundaries shows up here rather than only on a device.
        for chunk in stride(from: 0, to: decoded.samples.count, by: 1024) {
            buffer.append(decoded.samples[chunk..<min(chunk + 1024, decoded.samples.count)])
        }
        XCTAssertEqual(buffer.verdict, .speech)
        XCTAssertEqual(buffer.seconds, Double(decoded.samples.count) / decoded.sampleRate, accuracy: 0.05)
    }
}
