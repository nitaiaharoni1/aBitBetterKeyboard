import Foundation

/// One read of the memory ledger jetsam kills on.
///
/// **Why the peak is read from the kernel rather than sampled.** A keyboard
/// extension is killed for memory with no crash log, no signal and no callback;
/// iOS simply puts the user back on the keyboard they had before. Catching that
/// by polling means guessing where the spike is and sampling often enough to
/// land on it, and a spike between two samples is invisible.
/// `ledger_phys_footprint_peak` is the kernel's own high-water mark on the same
/// ledger `phys_footprint` reports, so one read at any later moment reports a
/// peak reached at any earlier one. There is nothing to schedule and nothing to
/// miss.
///
/// **`task_vm_info` is versioned, and reading past what the kernel filled is
/// reading uninitialised memory.** `task_info` takes the count as in/out and
/// returns how many `natural_t` it actually wrote; the header names the
/// thresholds as `TASK_VM_INFO_REV*_COUNT`, which are `sizeof` macros and do not
/// import into Swift. So each field carries its own threshold, derived from its
/// own offset, and the threshold is the count through the end of *that field*
/// rather than through the end of its revision. Measured identically on macOS 26
/// and the iOS 26 Simulator: 38 units through `phys_footprint`, 44 through
/// `ledger_phys_footprint_peak`, 86 through `limit_bytes_remaining`.
///
/// Two of those coincide with the header's own arithmetic and one deliberately
/// does not. `phys_footprint` is the whole of rev1 and `limit_bytes_remaining`
/// is the last field of rev4, so 38 and 86 are `REV1_COUNT` and `REV4_COUNT`
/// exactly. `ledger_phys_footprint_peak` is the *first* of the twenty-one
/// ledgers rev3 added, so its own threshold is 44 where `REV3_COUNT` is 84.
/// Asking for 84 would refuse the field over twenty later ledgers nothing here
/// reads. `MemoryReadingTests` pins all three against the header.
///
/// **`headroomMB` has never once answered here, and that is the reason it
/// shipped.** `limit_bytes_remaining` reads 0 on macOS 26 and 0 on the iOS 26
/// Simulator, because neither applies a jetsam footprint limit to the process
/// asking. A device does apply one to a keyboard extension, and a device is the
/// only place this can be known — which is the whole point of putting the field
/// in a record the phone writes and the app reads. Zero is reported as nil
/// rather than as zero headroom: a process with no bytes left is already dead,
/// so a literal zero is the kernel declining to answer.
///
/// The alternative to `headroomMB` was to compare the peak against a constant
/// ceiling, the way `MemoryGovernor.ceilingMB` does at 50 MB. That constant is
/// documented as a guess from developer-forum reports, and a measurement
/// compared against a guess inherits the guess. Headroom needs no ceiling at
/// all: it is small exactly when the process is close to dying, whatever the
/// limit turns out to be.
public struct MemoryReading: Equatable, Sendable {

    /// `phys_footprint` in megabytes. The number jetsam reads.
    public let footprintMB: Double

    /// `ledger_phys_footprint_peak` in megabytes: the highest this process has
    /// ever been, not the highest anybody sampled. Nil on a kernel too old to
    /// fill the field.
    public let peakMB: Double?

    /// `limit_bytes_remaining` in megabytes: how much further this process may
    /// grow. Nil when the kernel did not answer, which so far is everywhere it
    /// has been asked. See the type's note.
    public let headroomMB: Double?

    public init(footprintMB: Double, peakMB: Double?, headroomMB: Double?) {
        self.footprintMB = footprintMB
        self.peakMB = peakMB
        self.headroomMB = headroomMB
    }

    /// This process, right now, or nil if the kernel would not answer at all.
    ///
    /// One `task_info` call and no allocation, so it is cheap enough to sit on a
    /// path that runs whenever the keyboard appears.
    public static func current() -> MemoryReading? {
        var info = task_vm_info_data_t()
        var count = Self.fullCount
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS, count >= Self.unitsThroughFootprint else { return nil }

        return MemoryReading(
            footprintMB: Double(info.phys_footprint) / bytesPerMB,
            peakMB: count >= Self.unitsThroughPeak
                ? Double(info.ledger_phys_footprint_peak) / bytesPerMB : nil,
            // Zero is the kernel declining, not a process with nothing left.
            headroomMB: count >= Self.unitsThroughHeadroom && info.limit_bytes_remaining > 0
                ? Double(info.limit_bytes_remaining) / bytesPerMB : nil)
    }

    private static let bytesPerMB = 1_048_576.0

    private static let fullCount = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

    /// How many `natural_t` the kernel must have filled for a field at this key
    /// path to hold a value. Nil for a field the importer gives no offset for,
    /// which is treated as never available rather than as always.
    private static func units<T>(
        through key: KeyPath<task_vm_info_data_t, T>
    )
        -> mach_msg_type_number_t
    {
        guard let offset = MemoryLayout<task_vm_info_data_t>.offset(of: key) else { return .max }
        return mach_msg_type_number_t(
            (offset + MemoryLayout<T>.size) / MemoryLayout<natural_t>.size)
    }

    static let unitsThroughFootprint = units(through: \task_vm_info_data_t.phys_footprint)
    static let unitsThroughPeak = units(through: \task_vm_info_data_t.ledger_phys_footprint_peak)
    static let unitsThroughHeadroom = units(through: \task_vm_info_data_t.limit_bytes_remaining)
}
