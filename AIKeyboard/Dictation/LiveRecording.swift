import AIKeyboardCore
import Foundation
import os

/// The one piece of state the audio thread and the main actor both touch.
///
/// **It exists because those are genuinely two threads, and Swift concurrency
/// cannot be used to bridge them here.** An `AVAudioEngine` tap is called on a
/// dedicated audio thread with a hard deadline; the alternatives are to hop to
/// an actor per buffer, which loses ordering (see `DictationService.startEngine`),
/// or to hold a lock for the length of an array append, which is what this does.
/// The same trade is already made in `SharedPage.store`, called from ReplayKit's
/// delivery callback for the same reason.
///
/// `open` is checked inside the lock rather than read from the main actor,
/// because the alternative is a buffer arriving between "stop recording" and the
/// tap noticing — a fragment of the next room's audio on the end of the utterance
/// that was already closed.
final class LiveRecording: @unchecked Sendable {

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
