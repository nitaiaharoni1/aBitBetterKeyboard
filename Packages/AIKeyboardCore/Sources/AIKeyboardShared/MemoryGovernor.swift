import Foundation
import os

/// The capture process's own footprint, and the one thing it does about it.
///
/// **Why this exists at all.** A broadcast upload extension is killed by jetsam at
/// roughly 50 MB (`.claude/docs/replaykit-contract.md`), and a kill is the worst
/// available outcome: it ends the broadcast, iOS calls no callback on the way out,
/// and only the user can start another one. Refusing a single read is a five-word
/// apology; being killed is the feature gone until the user notices. So the
/// extension measures itself before it spends the memory a read costs, and says so
/// through `CaptureStatus.degraded` when it will not.
///
/// **The metric is `phys_footprint` from `task_info(TASK_VM_INFO)`** — the number
/// jetsam itself reads, not `resident_size`, and the same one
/// `Bar/screen-context/harness/memory.swift` samples. Shared with that probe by
/// eye rather than by import, because the probe must stay outside every target.
///
/// **The watermark is a guess bounded by a measurement, and that is the whole
/// design.** Two of the three numbers are guesses:
///
/// | Number | Where it comes from |
/// |---|---|
/// | `ceilingMB`, 50 | Developer-forum reports of the jetsam cap. In no header on this machine. R2 in the design's open-questions table: unmeasured. |
/// | `readReserveMB`, 10 | 3.0 MB for `FrameScaler`'s downscale destination and ~0.07 MB of JPEG, which are arithmetic, plus the 4-8 MB `URLSession` and TLS are guessed at (R7). |
/// | `baselineMB` | Measured, in this process, at `broadcastStarted`. |
///
/// A watermark of `ceiling - reserve` = 40 MB follows from the first two. The
/// design named 35 MB as a placeholder and then said the thing that matters: if
/// the process's baseline is already above the watermark, every read is refused
/// for the whole session and the feature is off with nothing in the UI that
/// explains it well enough to act on. **A guess must not overrule a measurement**,
/// so the watermark is `max(ceiling - reserve, baseline + reserve)`: on a normal
/// session it is 40 MB, and on a session that starts above that it moves up
/// instead of refusing everything, and the baseline is logged — which is the
/// number Phase 3 of the design is trying to obtain in the first place.
///
/// A sampler that cannot answer (`task_info` failing) permits everything. A
/// governor that cannot measure has no business refusing.
///
/// Lives in `AIKeyboardShared` rather than in `AIKeyboardBroadcast/` — where §11
/// of the design put it — for one reason: `AIKeyboardCoreTests` can reach this
/// target and cannot reach an app extension, and a self-protection rule that is
/// only exercised on a device is a rule nobody has run.
public final class MemoryGovernor: @unchecked Sendable {

    /// The jetsam cap, in megabytes. **Unmeasured**; see the type's note.
    public static let ceilingMB: Double = 50

    /// What one read is assumed to cost above the footprint it starts from.
    /// Part arithmetic, part guess; see the type's note.
    public static let readReserveMB: Double = 10

    /// `phys_footprint` in megabytes, or nil if the kernel would not answer.
    public static func footprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576.0
    }

    /// What `begin()` measured, for the log line that is the point of it.
    public struct Start: Equatable, Sendable {
        public let baselineMB: Double?
        public let watermarkMB: Double
        /// True when the baseline pushed the watermark above `ceiling - reserve`,
        /// which means the guessed ceiling has been contradicted by this process.
        public let baselineExceedsGuess: Bool
    }

    /// One sample.
    public struct Observation: Equatable, Sendable {
        public let footprintMB: Double?
        /// Whether a read would be refused right now.
        public let isRefusing: Bool
        /// True only on the sample that flipped `isRefusing`, so the caller writes
        /// the shared page on the transition rather than four times a second.
        public let changed: Bool
    }

    private struct State {
        var watermarkMB = MemoryGovernor.ceilingMB - MemoryGovernor.readReserveMB
        var baselineMB: Double?
        var isRefusing = false
    }

    private let sample: @Sendable () -> Double?
    private let state = OSAllocatedUnfairLock(initialState: State())
    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "Broadcast")

    /// The sampler is injectable so the policy can be tested without having to
    /// allocate 40 MB inside a test process to prove the comparison works.
    public init(sample: @escaping @Sendable () -> Double? = MemoryGovernor.footprintMB) {
        self.sample = sample
    }

    /// Records this session's baseline and sets the watermark from it.
    ///
    /// Called from `broadcastStarted`, before the first frame can arrive.
    @discardableResult
    public func begin() -> Start {
        let baseline = sample()
        let floor = Self.ceilingMB - Self.readReserveMB
        let watermark = max(floor, (baseline ?? 0) + Self.readReserveMB)

        state.withLock {
            $0 = State(watermarkMB: watermark, baselineMB: baseline, isRefusing: false)
        }

        let start = Start(
            baselineMB: baseline, watermarkMB: watermark,
            baselineExceedsGuess: watermark > floor)
        Self.log.notice(
            """
            memory baseline=\(baseline.map { String(format: "%.1f", $0) } ?? "unmeasurable", privacy: .public) \
            watermark=\(String(format: "%.1f", watermark), privacy: .public) \
            ceiling=\(String(format: "%.0f", Self.ceilingMB), privacy: .public)
            """
        )
        if start.baselineExceedsGuess {
            Self.log.error(
                """
                memory baseline is above the guessed watermark; the governor stands \
                off rather than refusing every read this session
                """
            )
        }
        return start
    }

    /// Samples the footprint and says whether a read may go ahead.
    ///
    /// Cheap enough for the 4 Hz sample path: one `task_info` call and an
    /// uncontended lock, no allocation.
    @discardableResult
    public func observe() -> Observation {
        let footprint = sample()
        return state.withLock { state in
            // No measurement means no refusal. The alternative is a feature
            // switched off by a failing syscall.
            let refusing = footprint.map { $0 > state.watermarkMB } ?? false
            let changed = refusing != state.isRefusing
            state.isRefusing = refusing
            return Observation(footprintMB: footprint, isRefusing: refusing, changed: changed)
        }
    }

    /// The last observation's verdict, without taking a new sample. `observe()`
    /// runs on every sampled frame, so at read time this is at most one sample
    /// interval old and costs nothing.
    public var isRefusing: Bool { state.withLock { $0.isRefusing } }

    public var watermarkMB: Double { state.withLock { $0.watermarkMB } }

    public var baselineMB: Double? { state.withLock { $0.baselineMB } }
}
