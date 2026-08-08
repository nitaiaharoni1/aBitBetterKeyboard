import Combine
import Foundation
import os

/// The keyboard's end of the capture channel, polled.
///
/// Four times a second while our keyboard is on screen it takes a snapshot of
/// `CaptureStatus`, applies the freshness gate, and publishes the verdict.
/// Nothing here decides anything on its own: the gate is `CaptureFreshness` and
/// the values are the capture process's.
///
/// **Polling rather than a Darwin notification, on purpose.** A page load four
/// times a second costs nothing and adds at most 250 ms to an operation that
/// takes five seconds. A notification path would add a run-loop dependency and a
/// dropped-message failure mode for no user-visible gain. If latency ever
/// matters, a notification goes *over* the poll as an optimisation, never
/// instead of it.
@MainActor
public final class ScreenContextChannel: ObservableObject {

    public static let shared = ScreenContextChannel()

    /// 4 Hz, the same rate the capture process samples at.
    public static let pollInterval: TimeInterval = 0.25

    @Published public private(set) var verdict: CaptureFreshness.Verdict = .noSession
    @Published public private(set) var status: CaptureStatus?
    @Published public private(set) var reading: ScreenReadingRecord?

    /// The last sequence this keyboard asked for. A record answering an earlier
    /// tap is somebody else's answer.
    @Published public private(set) var requestSequence: UInt64 = 0

    /// Who is watching. It decides exactly one thing, and the doc comment used to
    /// claim it decided more.
    ///
    /// **What it gates: `intent.keyboardVisible`, and nothing else.** The flag
    /// describes a keyboard being on screen, so only the keyboard may write it.
    ///
    /// **What it deliberately does not gate: `intent.readNow`.** The previous
    /// wording said an observer "writes nothing", and the app falsified it: the
    /// app hosts the whole `KeyboardView` — strip, Reply button and all — in
    /// `KeyboardPreview`, which onboarding and the Playground tab both render, so
    /// a Reply tap in the app raises the read sequence from a session started
    /// `as: .observer`. Measured: `intent.readNow` 0 -> 1. The contract is what
    /// changed rather than the code, because a read request is not the lie this
    /// role exists to prevent. `keyboardVisible` is a claim about *this process*
    /// that only the keyboard can make truthfully; `readNow` is the user's own
    /// tap on Reply, which is the whole consent model for a read (§5.1), and it
    /// is the same tap on the same button whichever process is drawing it. See
    /// `requestRead()` for what refusing it would have cost.
    public enum Role: Sendable {
        /// The keyboard extension. It is the thing the flag describes, so it is
        /// the only role allowed to set it.
        case keyboard
        /// The containing app's Screen Context screen, Home, onboarding and the
        /// playground. It reads the same page to show the user what the capture
        /// session is doing, and it never claims the keyboard is visible: an app
        /// saying so would make the producer believe a keyboard that is not
        /// there.
        case observer

        /// The one write this role gates.
        var claimsKeyboardVisible: Bool { self == .keyboard }
    }

    private var reader: CaptureChannelReader?
    private var role: Role = .keyboard
    private var timer: Timer?
    private var lastLogged = ""

    private static let log = Logger(
        subsystem: "com.nitai.aikeyboard", category: "CaptureChannel")

    /// The shared channel opens the App Group container on first use. A reader
    /// passed here roots it somewhere else, which is how `AIKeyboardCoreTests`
    /// drives both ends of a real channel without an App Group entitlement.
    init(reader: CaptureChannelReader? = nil) {
        self.reader = reader
    }

    /// Whether this process can reach the channel at all. False in the keyboard
    /// until the user grants Full Access, which is why screen context is a
    /// Full-Access-only feature end to end and why the strip has to be able to
    /// say so rather than just showing nothing.
    public var isReachable: Bool { CaptureChannel.isReachable }

    // MARK: Lifecycle

    /// `ownUIHeightFraction` is how much of the screen our keyboard is covering,
    /// which the producer needs so it can leave our own animating panel out of
    /// the frame fingerprint. Only the keyboard role publishes it, for the same
    /// reason it is the only role that claims to be visible: the app hosts the
    /// same view in a scroll view halfway up its own screen, and a fraction
    /// measured there would describe nothing.
    public func startWatching(as role: Role = .keyboard, ownUIHeightFraction: Double = 0) {
        guard timer == nil else { return }
        self.role = role
        if reader == nil { reader = CaptureChannelReader() }
        if role.claimsKeyboardVisible {
            reader?.setKeyboardVisible(true, ownUIHeightFraction: ownUIHeightFraction)
        }
        poll()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopWatching() {
        timer?.invalidate()
        timer = nil
        if role.claimsKeyboardVisible { reader?.setKeyboardVisible(false) }
        lastLogged = ""
    }

    /// Raises `intent.readNow`. The record that answers this tap carries the
    /// number this returns; anything else is the answer to a previous one.
    ///
    /// **Not gated by `role`, on purpose.** The app hosts the same keyboard in
    /// onboarding and the playground, so this is reached from an `.observer`
    /// session, and the two ways of "fixing" that are worse than the truth.
    /// Refusing the write would make Reply do nothing at all in the playground —
    /// the same class of silent no-op as the sample button — and it would do it
    /// while telling the user the wrong reason, because a zero here surfaces as
    /// "the keyboard cannot reach screen context, it needs Full Access". What the
    /// tap actually causes is a read of whatever is on screen, which in the app's
    /// case is the app; that is exactly what the strip above the button offers.
    @discardableResult
    public func requestRead() -> UInt64 {
        guard let reader else { return 0 }
        requestSequence = reader.requestRead()
        return requestSequence
    }

    /// Records one secure-field decision in the page this process owns. See
    /// `SecureField` for why the count is split in two, and why silence is
    /// counted whether or not it refused.
    public func countSecureDecision(refused: Bool, unanswered: Bool) {
        reader?.countSecureDecision(refused: refused, unanswered: unanswered)
    }

    // MARK: The poll

    /// One page load and one pass of the gate.
    ///
    /// Internal rather than private for two callers that must not wait for the
    /// timer: `ScreenContextSession` polls here at the instant Reply is tapped
    /// and again while it waits for the answer, so a decision about what is on
    /// screen is never taken against a snapshot up to 250 ms old, and the tests
    /// step it by hand instead of racing a run loop.
    func poll() {
        guard let reader else {
            verdict = .noSession
            return
        }

        let now = CaptureClock.now()
        // Three answers, not two: a page that will not settle is a producer that
        // died holding a seqlock transaction open, and it is reported as an ending
        // with a restart rather than as no session at all.
        let statusReading = reader.status()
        status = statusReading.status

        let record = reader.reading()
        reading = record

        if let record {
            verdict = CaptureFreshness.evaluate(record: record, reading: statusReading, now: now)
        } else {
            verdict = CaptureFreshness.evaluate(reading: statusReading, now: now)
        }

        report(status: statusReading.status, record: record)
    }

    /// One log line per change of what this process can see.
    ///
    /// This is the observable the cross-process proof reads, and it has to be
    /// emitted by the *consuming* process to prove anything: a process always
    /// sees its own writes, so a unit test — or the writer logging what it
    /// wrote — shows nothing about whether the two are sharing a page.
    /// `Scripts/prove-capture-channel.sh` greps for the `channel-watch` prefix
    /// and the OS stamps each line with the process that emitted it.
    private func report(status: CaptureStatus?, record: ScreenReadingRecord?) {
        let storage = CaptureChannel.isReachable ? "appGroup" : "processLocal"
        let session = status?.sessionID?.uuidString ?? "none"
        let identity = status.map { $0.currentFrameIdentity.hexString } ?? "none"
        let sampled = status?.framesSampled ?? 0
        let sender = record?.sender ?? "none"
        let line =
            "channel-watch storage=\(storage) session=\(session) "
            + "identity=\(String(identity.prefix(16))) sampled=\(sampled) "
            + "verdict=\(Self.name(of: verdict)) reading=\(sender)"

        guard line != lastLogged else { return }
        lastLogged = line
        Self.log.notice("\(line, privacy: .public)")
    }

    private static func name(of verdict: CaptureFreshness.Verdict) -> String {
        switch verdict {
        case .offerable: return "offerable"
        case .ended(let reason): return "ended:\(reason)"
        case .starting: return "starting"
        case .paused: return "paused"
        case .idle: return "idle"
        case .unconfirmed: return "unconfirmed"
        case .superseded: return "superseded"
        case .noSession: return "noSession"
        }
    }
}

// MARK: - Record to keyboard types

extension ScreenReadingRecord {
    /// The record carries `KeyboardLanguage.rawValue` rather than the enum.
    ///
    /// Not a linkage constraint any more — `KeyboardLanguage` moved into
    /// `AIKeyboardShared` and the capture process links it. It stays a string for
    /// decode robustness: the record is a file format written by one process and
    /// read by another that may be a different build, and an unknown case must
    /// degrade to a default rather than fail the whole decode and lose a reading
    /// the user is waiting on.
    public var keyboardLanguage: KeyboardLanguage {
        KeyboardLanguage(rawValue: language) ?? .english
    }

    /// What the strip shows. `appName` and `appIcon` stay empty: this design has
    /// no live signal for which app is on screen — `broadcastAnnotatedWithApplicationInfo:`
    /// names the *first* app of the session and only from a Control Center start
    /// — and a stale app name beside a fresh message is worse than no app name.
    public var screenContext: ScreenContext {
        ScreenContext(
            appName: "", appIcon: "", sender: sender, message: message,
            language: keyboardLanguage)
    }
}
