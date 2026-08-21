import Foundation
import os

/// How often the keyboard was asked for and did not arrive, and how long the
/// ones that did arrive took.
///
/// **The question this answers is not the one `KeyboardMemoryPeak` answers.**
/// That record asks whether the keyboard is being killed for memory. This one
/// asks a narrower thing that a device report raised and nothing here could
/// settle: the stock keyboard comes up on the first tap into a field, and
/// tapping the same field again brings ours back. A field that were genuinely
/// ineligible for a third-party keyboard would give the stock one every time, so
/// ours *was* on offer and iOS did not have it ready. Either the process was
/// dead before the tap, or it was alive and lost the race to present.
///
/// **Why this is not the launch counter `KeyboardMemoryPeak` rejected.** That
/// one counted launches against clean exits, and its own doc explains why it
/// separates nothing: iOS tears keyboard extensions down without warning as a
/// matter of course, so "started and never finished" counts an ordinary teardown
/// and a jetsam kill identically. This counts a narrower span that lies entirely
/// *inside* one launch — `viewDidLoad` against `viewDidAppear` — and an ordinary
/// teardown happens after a keyboard has appeared, so it lands in both counters
/// rather than in one. A `loads` above `presentations` is a run that was asked
/// for, began, and never reached the screen, which is exactly the shape the user
/// reported.
///
/// **What it still cannot prove.** iOS may instantiate a controller it never
/// presents for reasons of its own, and nothing here can tell that apart from
/// the failure being looked for. So one point of gap is noise and a persistent
/// ratio is evidence; read `loads` and `presentations` together, never `loads`
/// alone. It also cannot see a launch that died before `viewDidLoad` returned,
/// for the same reason `KeyboardMemoryPeak` cannot catch the killing spike:
/// there is nothing left to write with.
///
/// **The timing half is the more useful half of the two.** `slowestPresentMS`
/// is what a launch race would show up in. A keyboard that presents in twenty
/// milliseconds every time is not losing a race, whatever the counters say, and
/// the search moves back to memory.
///
/// **Scoped to a boot**, for the reason `KeyboardPresence.bootIdentity` sets out
/// at length: `CaptureClock` is nanoseconds since boot, so a stamp from the
/// previous boot reads as freshly written once uptime passes it.
public struct KeyboardLaunchRecord: Codable, Equatable, Sendable {

    /// How many times `viewDidLoad` has run this boot.
    public let loads: Int

    /// How many controller instances have reached the screen this boot.
    ///
    /// **The *first* `viewDidAppear` of each instance, not every one.** iOS keeps
    /// one extension instance alive across fields and across host apps, so a
    /// keyboard used normally appears dozens of times per launch; counting all of
    /// them would put `presentations` an order of magnitude above `loads` and the
    /// comparison this record exists for would mean nothing. Counted this way the
    /// two are the same event seen at its two ends, and the gap between them is
    /// the reading.
    public let presentations: Int

    /// The longest `viewDidLoad` to `viewDidAppear` this boot, in milliseconds.
    /// The number a launch race would show up in.
    public let slowestPresentMS: Double

    /// The most recent one, which is what tells a reader whether the slowest was
    /// a one-off or the normal cost.
    public let lastPresentMS: Double

    /// `CaptureClock` nanoseconds, from the run that last moved this record.
    public let recordedAt: UInt64

    /// Which boot of which device this describes. See
    /// `KeyboardPresence.bootIdentity`.
    public let bootIdentity: UInt64

    public init(
        loads: Int, presentations: Int, slowestPresentMS: Double, lastPresentMS: Double,
        recordedAt: UInt64, bootIdentity: UInt64
    ) {
        self.loads = loads
        self.presentations = presentations
        self.slowestPresentMS = slowestPresentMS
        self.lastPresentMS = lastPresentMS
        self.recordedAt = recordedAt
        self.bootIdentity = bootIdentity
    }

    /// Which of the two moments in a launch is being reported.
    public enum Moment: Sendable, Equatable {
        /// `viewDidLoad`. Carries no duration: nothing has been presented yet.
        case loaded
        /// `viewDidAppear`, and how long it took to get there.
        case presented(millis: Double)
    }

    // MARK: What the record should become

    /// The record that should replace `existing`.
    ///
    /// Pure, and the whole policy lives here rather than beside the file I/O, so
    /// it can be tested without a container — the same split `KeyboardMemoryPeak
    /// .merge` is written under, and for the same reason.
    ///
    /// **Not optional, where that one is**, and the difference is real rather
    /// than an oversight. `KeyboardMemoryPeak` is folded in on every appearance
    /// and usually finds its peak already correct, so nil is what keeps it from
    /// writing a file that would say the same thing. Every call to this one is a
    /// launch event that has just happened, so there is no case where nothing
    /// moved and an optional would only be a nil branch nobody can reach.
    ///
    /// **Counters only climb inside a boot** and a record from another boot is
    /// replaced outright, however high its counts, because it describes a
    /// different experiment. `slowestPresentMS` follows the same rule the peak
    /// does: the excursion is the reading, so a later, faster launch must not
    /// delete it.
    public static func merge(
        _ moment: Moment, into existing: KeyboardLaunchRecord?,
        now: UInt64 = CaptureClock.now(), bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> KeyboardLaunchRecord {
        let base: KeyboardLaunchRecord
        if let existing, existing.bootIdentity == bootIdentity {
            base = existing
        } else {
            base = KeyboardLaunchRecord(
                loads: 0, presentations: 0, slowestPresentMS: 0, lastPresentMS: 0,
                recordedAt: now, bootIdentity: bootIdentity)
        }

        switch moment {
        case .loaded:
            return KeyboardLaunchRecord(
                loads: base.loads + 1, presentations: base.presentations,
                slowestPresentMS: base.slowestPresentMS, lastPresentMS: base.lastPresentMS,
                recordedAt: now, bootIdentity: bootIdentity)
        case .presented(let millis):
            // Negative would mean the clock went backwards, which
            // `CLOCK_MONOTONIC_RAW` does not do; clamped anyway so a bad
            // reading cannot make the slowest launch look instant.
            let taken = max(0, millis)
            return KeyboardLaunchRecord(
                loads: base.loads, presentations: base.presentations + 1,
                slowestPresentMS: max(base.slowestPresentMS, taken), lastPresentMS: taken,
                recordedAt: now, bootIdentity: bootIdentity)
        }
    }

    // MARK: Where it lives

    static let fileName = "keyboard-launch.json"

    /// Nil in the keyboard until the user grants Full Access, which is the same
    /// signal `KeyboardPresence.url` and `KeyboardMemoryPeak.url` rest on.
    public static var url: URL? {
        SharedContainer.url?.appendingPathComponent(fileName)
    }

    // MARK: Reading

    /// The record the keyboard left, or nil.
    ///
    /// Nil means the keyboard has not run with Full Access since this shipped.
    /// It is not a reading of zero and must not be rendered as one.
    public static func load() -> KeyboardLaunchRecord? {
        guard let url else { return nil }
        return load(from: url)
    }

    /// Reads from a path of the caller's choosing. Public for the reason
    /// `KeyboardMemoryPeak.load(from:)` is: `AIKeyboardCoreTests` carries no App
    /// Group entitlement, so a test against the singleton would prove nothing —
    /// and on the simulator it would write into the container the app and
    /// keyboard actually share.
    public static func load(from url: URL) -> KeyboardLaunchRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(KeyboardLaunchRecord.self, from: data)
    }

    // MARK: Writing

    /// Folds one moment into the stored record, and logs it either way.
    ///
    /// **Call it off the main thread**, which for `.loaded` is not a preference
    /// but the point: this instrument exists to measure the launch path, and a
    /// synchronous file write on that path would be measuring itself.
    @discardableResult
    public static func record(
        _ moment: Moment, now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> KeyboardLaunchRecord? {
        switch moment {
        case .loaded:
            log.notice("launch loaded")
        case .presented(let millis):
            log.notice("launch presented after \(String(format: "%.0f", millis), privacy: .public)ms")
        }
        guard let url else { return nil }
        return record(moment, at: url, now: now, bootIdentity: bootIdentity)
    }

    /// Writes to a path of the caller's choosing. See `load(from:)` for why this
    /// is public.
    @discardableResult
    public static func record(
        _ moment: Moment, at url: URL, now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> KeyboardLaunchRecord? {
        let existing = load(from: url)
        let merged = merge(moment, into: existing, now: now, bootIdentity: bootIdentity)

        guard let data = try? JSONEncoder().encode(merged),
            (try? data.write(
                to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]))
                != nil
        else {
            log.error("launch record write failed at \(url.lastPathComponent, privacy: .public)")
            return existing
        }
        return merged
    }

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "KeyboardLaunch")
}
