import AIKeyboardCore
import Foundation
import os

/// A stand-in producer for the capture channel, so the cross-process proof has a
/// second process on this machine.
///
/// **This is not the shutter and it is not shipped behaviour.** It runs only
/// under `-uiTestCaptureChannel` and it exists because the real producer cannot
/// be run here at all: the iOS Simulator runtime ships no `replayd`, so no
/// broadcast session ever starts and `AIKeyboardBroadcast` is never launched.
/// What it does run is the *real* `CaptureChannelWriter` and the *real*
/// `FrameFingerprint`, over synthetic frames, so what the keyboard extension
/// reads on the other side is produced by the shipping code path rather than by
/// a hand-written file.
///
/// The script that reads the verdict is `Scripts/prove-capture-channel.sh`, and
/// the verdict comes from the *keyboard's* log lines, never from this side's: a
/// process always sees its own writes, so a producer reporting what it wrote
/// proves nothing about whether anyone else can see it.
///
/// The timeline it drives, deliberately, is the one the freshness gate exists
/// for:
///
/// 1. Publish frames of screen A at 4 Hz, with the status-bar band changing on
///    every frame the way a clock does. The identity must not move.
/// 2. When the keyboard reports itself visible, publish a reading of screen A.
///    The keyboard should find it offerable.
/// 3. Five seconds later, switch to screen B — the user changing conversation.
///    The keyboard should find the same reading superseded, and that transition
///    is the thing being proved.
final class CaptureChannelProbe {

    static let shared = CaptureChannelProbe()

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "CaptureChannel")

    /// Matches the capture design's sample rate.
    private static let tickInterval: TimeInterval = 0.25
    /// How long the reading stays current before the conversation changes.
    private static let switchAfter: TimeInterval = 5

    private let width = 320
    private let height = 640

    private var writer: CaptureChannelWriter?
    private var timer: Timer?
    private var tick = 0
    private var screen = 0
    private var keyboardFirstSeenAt: Date?
    private var session: UUID?
    private var sessionStartedAt: UInt64 = 0

    private init() {}

    func start() {
        guard timer == nil else { return }
        guard let writer = CaptureChannelWriter() else {
            Self.log.error("channel-probe could not reach the App Group container")
            return
        }
        self.writer = writer
        sessionStartedAt = CaptureClock.now()
        session = writer.begin(now: sessionStartedAt)

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            self?.step()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        step()
    }

    private func step() {
        guard let writer, let session else { return }
        tick += 1

        // The conversation changes once the consumer has had time to see the
        // reading it is about, which is what makes the superseded verdict on the
        // other side an event rather than a race.
        if let seen = keyboardFirstSeenAt, screen == 0,
            Date().timeIntervalSince(seen) > Self.switchAfter
        {
            screen = 1
        }

        let fingerprint = frame(screen: screen, chrome: tick)
        writer.recordFrame(fingerprint)
        if tick % 4 == 0 { writer.heartbeat() }

        // `keyboardVisible` is only believed when it was written during this
        // session. The keyboard extension is killed rather than dismissed often
        // enough that a stale `1` outlives its process, and a probe that
        // believed it would publish its reading before anyone was watching and
        // then retire it before the consumer ever saw it — which is exactly the
        // false pass this check exists to avoid.
        let intent = writer.intent()
        let keyboardIsHere =
            intent?.isKeyboardVisible == true && (intent?.keyboardVisibleAt ?? 0) >= sessionStartedAt
        if keyboardFirstSeenAt == nil, keyboardIsHere {
            keyboardFirstSeenAt = Date()
            let now = CaptureClock.now()
            let record = ScreenReadingRecord(
                sessionID: session,
                requestSequence: intent?.readNow ?? 0,
                frameIdentity: fingerprint.identity,
                capturedAt: now,
                readAt: now,
                provenance: "cloud",
                sender: "Maya",
                message: "Are we still on for 6?",
                language: KeyboardLanguage.english.rawValue)
            try? writer.publish(record)
            Self.log.notice(
                """
                channel-probe published session=\(session.uuidString, privacy: .public) \
                identity=\(String(fingerprint.identity.hexString.prefix(16)), privacy: .public)
                """
            )
        }

        if tick % 4 == 0 {
            Self.log.notice(
                """
                channel-probe wrote session=\(session.uuidString, privacy: .public) \
                screen=\(self.screen, privacy: .public) \
                identity=\(String(fingerprint.identity.hexString.prefix(16)), privacy: .public)
                """
            )
        }
    }

    /// One synthetic screen, fingerprinted by the shipping reduction.
    ///
    /// `chrome` paints into the top band the design crops away, the way a status
    /// bar clock ticks over. The identity must be blind to it — if it were not,
    /// every frame would retire the reading and the keyboard would never reach
    /// `offerable` at all, so this doubles as an assertion.
    private func frame(screen: Int, chrome: Int) -> FrameFingerprint {
        var pixels = [UInt8](repeating: 128, count: width * height)
        let band = FrameReduction.bandRows(inHeight: height)

        for row in 0..<10 {
            for x in 0..<width where (x + chrome) % 8 < 4 { pixels[row * width + x] = 240 }
        }

        // The "newest message": a block low in the band, in a different place
        // and a different shade per screen.
        let top = band.upperBound - 60 - screen * 40
        for y in top..<(top + 30) {
            for x in 40..<(240 - screen * 60) {
                pixels[y * width + x] = UInt8(40 + screen * 120)
            }
        }

        return pixels.withUnsafeBytes {
            FrameFingerprint.make(
                base: $0.baseAddress!, width: width, height: height, bytesPerRow: width,
                format: .luminance8)!
        }
    }
}
