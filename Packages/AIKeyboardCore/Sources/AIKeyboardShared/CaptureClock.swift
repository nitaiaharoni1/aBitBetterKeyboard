import Foundation

// MARK: - Clock

/// The one clock both ends of the channel read.
///
/// `CLOCK_MONOTONIC_RAW` rather than a wall clock, and the difference is not
/// pedantry. Every timestamp in `CaptureStatus` is compared against *now* in a
/// different process to decide whether a reading may be shown, so a clock the
/// user or NTP can move is a clock that can make a forty-second-old reading look
/// fresh. This one cannot be set, is shared by every process on the machine, and
/// (unlike `CLOCK_UPTIME_RAW`) keeps counting while the device sleeps, so a phone
/// that spent ten minutes in a pocket comes back with a stale channel rather
/// than a live-looking one.
///
/// It resets at boot, which is handled by the session identifier rather than by
/// the clock: a page left over from before a reboot carries a session no live
/// reader recognises, and `CaptureFreshness` refuses a timestamp that is in the
/// future anyway.
public enum CaptureClock {

    public static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) }

    public static func nanoseconds(_ seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }

    /// Elapsed nanoseconds, saturating at zero. A `then` in the future is not a
    /// small age, it is a lie — from a stale page, a reboot, or a torn read —
    /// and callers get `.max` so every freshness window rejects it.
    public static func elapsed(since then: UInt64, now: UInt64 = CaptureClock.now()) -> UInt64 {
        then == 0 ? .max : (now >= then ? now - then : .max)
    }
}

// MARK: - UUID words

extension UUID {
    var words: (UInt64, UInt64) {
        let bytes = uuid
        var high: UInt64 = 0
        var low: UInt64 = 0
        withUnsafeBytes(of: bytes) { raw in
            for index in 0..<8 { high = (high << 8) | UInt64(raw[index]) }
            for index in 8..<16 { low = (low << 8) | UInt64(raw[index]) }
        }
        return (high, low)
    }

    init(high: UInt64, low: UInt64) {
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 { bytes[index] = UInt8((high >> (8 * (7 - index))) & 0xff) }
        for index in 0..<8 { bytes[8 + index] = UInt8((low >> (8 * (7 - index))) & 0xff) }
        self.init(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}
