import AIKeyboardShared
import CoreMedia
import CoreVideo
import ImageIO
import ReplayKit
import os

/// The capture shutter, with a phone line.
///
/// ReplayKit kills a broadcast upload extension at roughly 50 MB and one BGRA
/// frame at this device's resolution is about 12.6 MB
/// (`.claude/docs/replaykit-contract.md`), so the rule this class is built around
/// is that no frame outlives the callback it arrived in and no frame is ever
/// copied. The pixel buffer is locked read-only, reduced in place to 2,048
/// greyscale samples, and unlocked before the callback returns; the 2 KB
/// reduction lives on the stack for the length of `FrameFingerprint.make` and is
/// never written anywhere, because at 32x64 it is a bad picture but it is still a
/// picture.
///
/// **One frame in sixty thousand leaves.** A read happens on exactly one
/// condition: `intent.readNow` went up, which is the user tapping Reply. Then
/// this callback downscales that one frame and encodes it — CPU-bounded work
/// that allocates one reusable buffer, `FrameScaler` — and hands ~66 KB of JPEG
/// to `ScreenReadService`, which does the five-second cloud call on its own
/// serial queue and publishes text. The callback returns without waiting, which
/// is what keeps the fingerprint advancing during a read and is the whole reason
/// `CaptureFreshness` condition 3 can confirm a reading at all.
///
/// This target links `AIKeyboardShared` and **must never link `AIKeyboardCore`**:
/// that target imports SwiftUI and UIKit from a dozen files, and dragging both
/// into a process with a ~50 MB ceiling buys nothing.
///
/// Nothing in this file can be exercised in the iOS Simulator. That runtime ships
/// no `replayd`, so the extension compiles, links and embeds there and is never
/// called; a verdict about frames arriving can only come from a device log.
final class SampleHandler: RPBroadcastSampleHandler {

    static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "Broadcast")

    /// ReplayKit delivers up to 60 fps. The capture design samples at ~4 Hz, so
    /// 56 of every 60 frames are dropped before anything touches them.
    static let sampleIntervalMilliseconds = 250
    static let sampleInterval = Duration.milliseconds(sampleIntervalMilliseconds)

    /// Sampled frames between progress lines: 16 at 4 Hz is one line every ~4 s.
    static let logEvery = 16

    let clock = ContinuousClock()

    /// The App Group half. Nil when the container is out of reach, and the
    /// extension keeps running rather than failing: capture with nobody
    /// listening is useless but it is not a crash, and the keyboard's own
    /// `storage=processLocal` is where the user-visible diagnosis belongs.
    let channel = CaptureChannelWriter()
    var heartbeat: DispatchSourceTimer?

    /// The self-protection half. Sampled once per sampled frame, so a read is
    /// measured against a footprint at most 250 ms old, and it writes
    /// `CaptureStatus.degraded` only when the answer changes. See `MemoryGovernor`
    /// for why the watermark is bounded below by this process's own baseline
    /// rather than by the design's placeholder.
    let memory = MemoryGovernor()

    /// The read, and the one downscale buffer it is served from.
    ///
    /// Built at `broadcastStarted` rather than here, so the backend URL is read
    /// from the shared store when the session starts: the user can set it in the
    /// app between two broadcasts, and a service built at process launch would
    /// answer "not set up" for the rest of the session. Assigned before the first
    /// frame can arrive and never cleared, for the reason `broadcastFinished`
    /// gives. Nil when the container is out of reach, because a reading nobody
    /// can collect is a cloud call spent for nothing.
    ///
    /// Behind a lock for the same reason `CaptureChannelWriter.intentPage` and
    /// `CaptureChannelReader.statusPage` are, and it is the third instance of the
    /// identical mistake in this codebase.
    ///
    /// It is assigned in `broadcastStarted`, on whatever queue ReplayKit runs the
    /// lifecycle callbacks, and read in `serveReadRequest` on the delivery queue.
    /// ReplayKit documents nothing about those being the same queue. The
    /// extension is **reused across broadcasts** — `CaptureChannel`'s own doc
    /// comment says so and `testANewSessionPublishesAgain` proves it — so a
    /// second `broadcastStarted` arriving while a delivery callback from the
    /// previous session is still running is an ordinary event, not a contrived
    /// one, and it reassigns this reference underneath that callback.
    ///
    /// A pointer-sized store happens to be atomic on arm64 and
    /// `CaptureFreshness`'s session check would refuse anything a stale service
    /// published, so the blast radius was a wasted cloud call rather than wrong
    /// text. That is an argument for it having been survivable, not for it having
    /// been correct: the guarantee here is Swift's memory model, which says
    /// nothing about either.
    let reads = OSAllocatedUnfairLock<ScreenReadService?>(initialState: nil)
    let scaler = FrameScaler()

    // Mutated from ReplayKit's delivery queue by `processSampleBuffer`, and from
    // whatever queue ReplayKit uses for the lifecycle callbacks by
    // `broadcastStarted`, `broadcastResumed` and `broadcastFinished`. ReplayKit
    // does not document those to be the same queue, so this is not the
    // single-queue invariant an earlier version of this comment claimed.
    //
    // Left unsynchronised deliberately, and only because of what these are: no
    // frame is delivered before `broadcastStarted` or while paused, and the
    // values are read solely to log.
    //
    // The counters the *keyboard* reads do not live here — they live in the
    // shared page, which this class writes from three threads: the delivery
    // queue through `recordFrame` and `recordDelivery`, the heartbeat timer's
    // `.utility` queue through `heartbeat()`, and the lifecycle callbacks
    // through `setPaused` and `end`. A seqlock alone would not have made that
    // safe: two overlapping transactions can settle the sequence even over a
    // half-written body, lose an update and move the published frame identity
    // backwards, or flip the sequence's parity and wedge the channel for the
    // rest of the session. `SharedPage` serialises the three with a lock, and
    // the sequence number is what keeps the *reading* process lock-free.
    var lastSampledAt: ContinuousClock.Instant?
    var framesDelivered = 0
    var framesSampled = 0
    var lastOrientation: CGImagePropertyOrientation?
    var hasLoggedFormat = false

    // Lifecycle overrides are in SampleHandler+Lifecycle.swift.
    // Heartbeat, delivery, and read-request handling are in SampleHandler+Delivery.swift.
    // Frame helpers are in SampleHandler+FrameHelpers.swift.
}
