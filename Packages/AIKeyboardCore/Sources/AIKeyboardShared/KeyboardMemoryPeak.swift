import Foundation
import os

/// How close the keyboard has come to being killed for memory, left where the
/// containing app can read it.
///
/// **The evidence has to be written before the death, because there is none
/// after it.** iOS kills a keyboard extension that crosses its footprint limit
/// with no crash log, no signal, no exception and no callback — it puts the user
/// back on the keyboard they had before, and from the developer's side nothing
/// happened. So the keyboard writes what it knows while it is alive, into the
/// App Group container, and the app reads it later. Same shape as
/// `KeyboardPresence`, for the same reason: there is no API that answers the
/// question, and a file the extension left behind is the only thing that can.
///
/// **What this can prove and what it cannot.** It can prove the keyboard reached
/// a given footprint, and — if `MemoryReading.headroomMB` ever answers on a
/// device — how much room it had left when it did. That is enough to settle the
/// question it was built for: a keyboard whose peak sits at half its headroom is
/// not the one being killed, and the search moves elsewhere.
///
/// It cannot catch the spike that does the killing. The record is written when
/// the keyboard appears, when it goes away, and when iOS sends a memory warning;
/// a kill lands between two of those and takes the task's own ledger with it. A
/// launch counter would not fix that either, because iOS tears keyboard
/// extensions down without warning as a matter of course, so "started and never
/// finished" counts ordinary teardowns and jetsam kills the same way and
/// separates nothing. The honest instrument is the high-water mark at the
/// moments we are certainly alive, and a memory warning — which is the one
/// signal iOS does send ahead of a kill.
///
/// **`warnings` is the highest-signal field here and the cheapest.** iOS sends
/// `didReceiveMemoryWarning` when the process is under pressure, and a keyboard
/// that has never received one is a keyboard that has never been close. A count
/// above zero is direct evidence of the thing being looked for, in one `Int`.
///
/// **Scoped to a boot, and reset at the next one.** `peakMB` accumulates upwards
/// and `headroomMB` downwards across every run of the keyboard in one boot, so
/// one excursion to the ceiling is kept rather than averaged away by the
/// ordinary visits either side of it. Across a boot it starts again: memory
/// pressure is a property of what else the phone was doing, a peak from last
/// week describes an experiment nobody can reproduce, and `recordedAt` is a
/// monotonic clock that is meaningless against another boot anyway — the trap
/// `KeyboardPresence.bootIdentity` documents at length.
public struct KeyboardMemoryPeak: Codable, Equatable, Sendable {

    /// The highest `ledger_phys_footprint_peak` any run of the keyboard has
    /// reported this boot.
    public let peakMB: Double

    /// The smallest `limit_bytes_remaining` any run has reported this boot, or
    /// nil if the kernel has never answered. Nil is the expected value until
    /// this is read on a device; see `MemoryReading`.
    public let headroomMB: Double?

    /// How many memory warnings iOS has sent the keyboard this boot.
    public let warnings: Int

    /// `CaptureClock` nanoseconds, from the run that last moved this record.
    /// Comparable only against a *now* from the same boot.
    public let recordedAt: UInt64

    /// Which boot of which device this describes. See
    /// `KeyboardPresence.bootIdentity`, which is the same value read the same
    /// way and carries the full reasoning.
    public let bootIdentity: UInt64

    public init(
        peakMB: Double, headroomMB: Double?, warnings: Int, recordedAt: UInt64, bootIdentity: UInt64
    ) {
        self.peakMB = peakMB
        self.headroomMB = headroomMB
        self.warnings = warnings
        self.recordedAt = recordedAt
        self.bootIdentity = bootIdentity
    }

    // MARK: What the record should become

    /// The record that should replace `existing`, or **nil when nothing moved**.
    ///
    /// Pure, and the whole policy lives here rather than beside the file I/O, so
    /// it can be tested without a container. Nil is what keeps the keyboard from
    /// writing on every appearance: the peak only climbs, so the ordinary visit
    /// finds it already correct and does nothing.
    ///
    /// **A peak is never lowered inside a boot.** That is the one rule the
    /// record exists to keep — the interesting reading is the excursion, and a
    /// later, calmer visit overwriting it with a smaller number would delete the
    /// only evidence there was. A record from another boot is replaced outright,
    /// however high its peak, because it describes a different experiment.
    public static func merge(
        _ reading: MemoryReading, into existing: KeyboardMemoryPeak?, warning: Bool,
        now: UInt64 = CaptureClock.now(), bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> KeyboardMemoryPeak? {
        // The kernel's own high-water mark when it answers. Where it does not,
        // the current footprint is a floor under the peak and is better than
        // nothing, since the peak is by definition at least this.
        let observed = reading.peakMB ?? reading.footprintMB

        guard let existing, existing.bootIdentity == bootIdentity else {
            return KeyboardMemoryPeak(
                peakMB: observed, headroomMB: reading.headroomMB, warnings: warning ? 1 : 0,
                recordedAt: now, bootIdentity: bootIdentity)
        }

        let peak = max(existing.peakMB, observed)
        let headroom = [existing.headroomMB, reading.headroomMB].compactMap { $0 }.min()
        let warnings = existing.warnings + (warning ? 1 : 0)

        guard
            peak > existing.peakMB || headroom != existing.headroomMB
                || warnings != existing.warnings
        else { return nil }

        return KeyboardMemoryPeak(
            peakMB: peak, headroomMB: headroom, warnings: warnings, recordedAt: now,
            bootIdentity: bootIdentity)
    }

    // MARK: Where it lives

    static let fileName = "keyboard-memory-peak.json"

    /// Nil in the keyboard until the user grants Full Access, which is the same
    /// signal `KeyboardPresence.url` rests on. No Full Access, no record, and
    /// the app says so rather than showing a zero.
    public static var url: URL? {
        SharedContainer.url?.appendingPathComponent(fileName)
    }

    // MARK: Reading

    /// The record the keyboard left, or nil.
    ///
    /// Nil means the keyboard has not run with Full Access since this shipped.
    /// It is not a reading of zero and must not be rendered as one.
    public static func load() -> KeyboardMemoryPeak? {
        guard let url else { return nil }
        return load(from: url)
    }

    /// Reads from a path of the caller's choosing. Public for the reason
    /// `KeyboardPresence.load(from:)` is: `AIKeyboardCoreTests` carries no App
    /// Group entitlement, so a test against the singleton would prove nothing.
    public static func load(from url: URL) -> KeyboardMemoryPeak? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(KeyboardMemoryPeak.self, from: data)
    }

    // MARK: Writing

    /// Folds one reading into the stored record, and logs it either way.
    ///
    /// Returns the record now on disk, or nil if there is nowhere to write —
    /// which in the keyboard means Full Access is off.
    ///
    /// **Call it off the main thread.** The log line is the part that always
    /// survives, because it needs no container and no permission; the file is
    /// what lets the phone's owner read this without a Mac.
    @discardableResult
    public static func record(
        _ reading: MemoryReading, warning: Bool = false, now: UInt64 = CaptureClock.now(),
        bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> KeyboardMemoryPeak? {
        log.notice(
            """
            memory footprint=\(String(format: "%.1f", reading.footprintMB), privacy: .public) \
            peak=\(reading.peakMB.map { String(format: "%.1f", $0) } ?? "unavailable", privacy: .public) \
            headroom=\(reading.headroomMB.map { String(format: "%.1f", $0) } ?? "unanswered", privacy: .public) \
            warning=\(warning, privacy: .public)
            """
        )
        guard let url else { return nil }
        return record(reading, warning: warning, at: url, now: now, bootIdentity: bootIdentity)
    }

    /// Writes to a path of the caller's choosing. See `load(from:)` for why this
    /// is public.
    @discardableResult
    public static func record(
        _ reading: MemoryReading, warning: Bool = false, at url: URL,
        now: UInt64 = CaptureClock.now(), bootIdentity: UInt64 = KeyboardPresence.bootIdentity
    ) -> KeyboardMemoryPeak? {
        let existing = load(from: url)
        guard
            let merged = merge(
                reading, into: existing, warning: warning, now: now, bootIdentity: bootIdentity)
        else { return existing }

        guard let data = try? JSONEncoder().encode(merged),
            (try? data.write(
                to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]))
                != nil
        else {
            log.error("memory peak write failed at \(url.lastPathComponent, privacy: .public)")
            return existing
        }
        return merged
    }

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "KeyboardMemory")
}
