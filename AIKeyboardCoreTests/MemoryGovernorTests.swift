import XCTest
import os

@testable import AIKeyboardCore

/// The capture process's self-protection, and the one way it is allowed to fail.
///
/// A broadcast upload extension is killed by jetsam at roughly 50 MB, and a kill
/// is the worst outcome available: the broadcast ends, no callback fires, and only
/// the user can start another one. Refusing one read is the cheap alternative. The
/// hazard on the other side is a watermark set from a guess that turns out to be
/// below the process's own idle footprint — then every read is refused for the
/// whole session and the feature is off with nothing to act on. Both are here.
///
/// **What this cannot cover.** No broadcast starts in the simulator, so nothing
/// below has ever run inside a process under ReplayKit's cap. What it does prove
/// is that `task_info` answers, and that the policy over it behaves at each
/// boundary. The numbers themselves — the ceiling and the reserve — are
/// unmeasured, and `MemoryGovernor` says so where they are declared.
final class MemoryGovernorTests: XCTestCase {

    private let ceiling = MemoryGovernor.ceilingMB
    private let reserve = MemoryGovernor.readReserveMB

    /// A governor whose footprint is whatever the test says it is.
    private func governor(footprint: @escaping @Sendable () -> Double?) -> MemoryGovernor {
        MemoryGovernor(sample: footprint)
    }

    private func fixed(_ value: Double?) -> MemoryGovernor {
        governor(footprint: { value })
    }

    // MARK: The measurement

    /// The real sampler, not a stub. `phys_footprint` is the number jetsam reads,
    /// and a governor that cannot obtain it is a governor that refuses nothing —
    /// so it matters that the call actually answers on this platform.
    func testTheRealSamplerAnswersWithAPlausibleFootprint() throws {
        let footprint = try XCTUnwrap(
            MemoryGovernor.footprintMB(), "task_info(TASK_VM_INFO) would not answer")

        XCTAssertGreaterThan(footprint, 1, "a running process occupies more than a megabyte")
        XCTAssertLessThan(footprint, 8_192, "and less than eight gigabytes")
    }

    // MARK: The watermark

    func testANormalBaselineLeavesTheWatermarkAtTheCeilingLessTheReserve() {
        let start = fixed(20).begin()

        XCTAssertEqual(start.baselineMB, 20)
        XCTAssertEqual(start.watermarkMB, ceiling - reserve)
        XCTAssertFalse(start.baselineExceedsGuess)
    }

    /// **The property the design asked for by name.**
    ///
    /// §2.4 put the watermark at 35 MB and then said the thing that matters: there
    /// is no measured baseline, and a watermark below the baseline refuses every
    /// read for the whole session — the feature switched off by a guess, with no
    /// event to explain it. So the baseline, which is measured in this process,
    /// raises the watermark rather than being refused by it.
    func testABaselineAboveTheGuessRaisesTheWatermarkRatherThanRefusingEveryRead() {
        let governor = fixed(46)
        let start = governor.begin()

        XCTAssertTrue(start.baselineExceedsGuess)
        XCTAssertEqual(start.watermarkMB, 46 + reserve)
        XCTAssertFalse(
            governor.observe().isRefusing,
            "a session that starts above the guessed watermark still gets its reads")
    }

    /// A sampler that cannot answer permits everything. A governor that cannot
    /// measure has no business refusing, and a failing syscall must not be a way
    /// to switch the feature off.
    func testAnUnmeasurableFootprintRefusesNothing() {
        let governor = fixed(nil)
        let start = governor.begin()

        XCTAssertNil(start.baselineMB)
        XCTAssertEqual(start.watermarkMB, ceiling - reserve)
        XCTAssertFalse(governor.observe().isRefusing)
        XCTAssertFalse(governor.isRefusing)
    }

    // MARK: The refusal

    func testTheRefusalTurnsOnAtTheWatermarkAndOffAgain() {
        let footprint = OSAllocatedUnfairLock(initialState: 20.0)
        let governor = governor(footprint: { footprint.withLock { $0 } })
        governor.begin()

        XCTAssertFalse(governor.observe().isRefusing, "20 MB is well under 40")

        footprint.withLock { $0 = ceiling - reserve }
        XCTAssertFalse(governor.observe().isRefusing, "exactly at the watermark is not above it")

        footprint.withLock { $0 = ceiling - reserve + 0.1 }
        XCTAssertTrue(governor.observe().isRefusing)
        XCTAssertTrue(governor.isRefusing)

        footprint.withLock { $0 = 12 }
        XCTAssertFalse(governor.observe().isRefusing, "pressure that passes lifts the refusal")
    }

    /// The shared page is written on the transition and not four times a second.
    /// `changed` is what `SampleHandler` keys the `setDegraded` write off, so a
    /// governor that reported every sample would put a seqlock transaction on the
    /// 4 Hz path for nothing.
    func testOnlyTheSampleThatFlippedTheAnswerReportsAChange() {
        let footprint = OSAllocatedUnfairLock(initialState: 20.0)
        let governor = governor(footprint: { footprint.withLock { $0 } })
        governor.begin()

        footprint.withLock { $0 = 45 }
        XCTAssertTrue(governor.observe().changed, "off -> on")
        XCTAssertFalse(governor.observe().changed)
        XCTAssertFalse(governor.observe().changed)

        footprint.withLock { $0 = 10 }
        XCTAssertTrue(governor.observe().changed, "on -> off")
        XCTAssertFalse(governor.observe().changed)
    }

    /// A new broadcast re-measures. The extension process is reused across
    /// sessions, so a refusal left over from the last one would refuse the first
    /// read of this one.
    func testANewSessionClearsTheRefusal() {
        let footprint = OSAllocatedUnfairLock(initialState: 20.0)
        let governor = governor(footprint: { footprint.withLock { $0 } })
        governor.begin()

        footprint.withLock { $0 = 45 }
        XCTAssertTrue(governor.observe().isRefusing)

        footprint.withLock { $0 = 18 }
        governor.begin()

        XCTAssertFalse(governor.isRefusing)
        XCTAssertEqual(governor.baselineMB, 18)
    }

    /// `observe()` runs on ReplayKit's delivery queue and `isRefusing` is read
    /// from the same one, but `begin()` runs on the lifecycle callbacks' queue,
    /// which ReplayKit does not document to be the same. Nothing here may tear.
    func testObservingAndBeginningFromTwoQueuesIsSafe() {
        let governor = governor(footprint: { Double.random(in: 10...45) })
        let group = DispatchGroup()

        for _ in 0..<4 {
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                for _ in 0..<500 { _ = governor.observe() }
            }
        }
        DispatchQueue.global(qos: .utility).async(group: group) {
            for _ in 0..<50 { governor.begin() }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 20), .success)
    }
}
