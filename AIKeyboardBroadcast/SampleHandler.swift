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

    private static let log = Logger(subsystem: "com.nitai.aikeyboard", category: "Broadcast")

    /// ReplayKit delivers up to 60 fps. The capture design samples at ~4 Hz, so
    /// 56 of every 60 frames are dropped before anything touches them.
    private static let sampleIntervalMilliseconds = 250
    private static let sampleInterval = Duration.milliseconds(sampleIntervalMilliseconds)

    /// Sampled frames between progress lines: 16 at 4 Hz is one line every ~4 s.
    private static let logEvery = 16

    private let clock = ContinuousClock()

    /// The App Group half. Nil when the container is out of reach, and the
    /// extension keeps running rather than failing: capture with nobody
    /// listening is useless but it is not a crash, and the keyboard's own
    /// `storage=processLocal` is where the user-visible diagnosis belongs.
    private let channel = CaptureChannelWriter()
    private var heartbeat: DispatchSourceTimer?

    /// The self-protection half. Sampled once per sampled frame, so a read is
    /// measured against a footprint at most 250 ms old, and it writes
    /// `CaptureStatus.degraded` only when the answer changes. See `MemoryGovernor`
    /// for why the watermark is bounded below by this process's own baseline
    /// rather than by the design's placeholder.
    private let memory = MemoryGovernor()

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
    private let reads = OSAllocatedUnfairLock<ScreenReadService?>(initialState: nil)
    private let scaler = FrameScaler()

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
    private var lastSampledAt: ContinuousClock.Instant?
    private var framesDelivered = 0
    private var framesSampled = 0
    private var lastOrientation: CGImagePropertyOrientation?
    private var hasLoggedFormat = false

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        lastSampledAt = nil
        framesDelivered = 0
        framesSampled = 0
        lastOrientation = nil
        hasLoggedFormat = false

        let session = channel?.begin()
        let budget = memory.begin()
        startHeartbeat()

        // Seeded with the intent page as it stands right now, so a Reply tap
        // from a session that ended an hour ago cannot fire a read against
        // whatever happens to be on screen when this one starts.
        if let channel, let session {
            let service = ScreenReadService.standard(channel: channel)
            service.begin(session: session, intent: channel.intent())
            reads.withLock { $0 = service }
        }

        // Into the page as well as the log: the app can show it, and a device
        // that never gets near a Mac still answers R2c.
        channel?.recordFootprint(baselineMB: budget.baselineMB, currentMB: nil)

        Self.log.notice(
            """
            broadcast started intervalMs=\(Self.sampleIntervalMilliseconds, privacy: .public) \
            channel=\(self.channel == nil ? "unreachable" : "open", privacy: .public) \
            reader=\(self.reads.withLock { $0 }?.canRead == true ? "cloud" : "none", privacy: .public) \
            session=\(session?.uuidString ?? "none", privacy: .public) \
            baselineMB=\(budget.baselineMB.map { String(format: "%.1f", $0) } ?? "unmeasurable", privacy: .public) \
            watermarkMB=\(String(format: "%.1f", budget.watermarkMB), privacy: .public)
            """
        )

        // Two ways this session can be switched on and be incapable of the one
        // thing it exists for, both of which are known here, before a single frame
        // is sampled. Neither used to be reported: the extension captured happily,
        // the strip offered "Reply can read this screen", and the user found out
        // twelve seconds after a tap — or never, because with no channel the
        // keyboard shows no strip at all while iOS shows a recording indicator.
        guard let channel else {
            // The container is the diagnosis *and* the only way to deliver one, so
            // there is nothing to record: whatever this session observed, nobody
            // would ever read it. All that is left is to take the recording
            // indicator down instead of capturing a screen no process can collect.
            Self.log.error("broadcast refused: the shared container is out of reach")
            finishBroadcastWithError(
                Self.error(
                    // Outside `ScreenContextEndReason`'s raw values on purpose:
                    // this is the one refusal that has no reason in the enum,
                    // because the page a reason would be written to is exactly
                    // what is missing.
                    code: 100,
                    message: "Screen context could not reach AI Keyboard's shared storage.",
                    recovery: "Open AI Keyboard once, then start screen context again."))
            return
        }

        // The decision itself is `ScreenContextEndReason.refusalToStart`, in
        // `AIKeyboardShared`, because nothing can test a decision written inline
        // in an app extension no simulator ever launches. What is here is the I/O.
        if let refusal = ScreenContextEndReason.refusalToStart(
            canRead: reads.withLock({ $0 })?.canRead == true)
        {
            // Recorded *and* signalled. The page is what the keyboard's strip and
            // the app's Screen Context screen read; finishing the broadcast is what
            // takes the recording indicator down. Neither depends on the other
            // working, which matters because only one of the two has ever run.
            channel.end(refusal)
            stopHeartbeat()
            Self.log.error(
                "broadcast refused reason=\(refusal.rawValue, privacy: .public)")
            finishBroadcastWithError(
                Self.error(
                    code: Int(refusal.rawValue),
                    message: refusal.explanation,
                    recovery: refusal.recovery))
        }
    }

    /// The `NSError` handed to `finishBroadcastWithError:`.
    ///
    /// **What this is verified to do is stop the broadcast**, which the header
    /// states plainly: *"Calling this method will stop the broadcast and deliver
    /// the error back to the broadcasting app through RPBroadcastControllerDelegate's
    /// broadcastController:didFinishWithError: method."* This app has no
    /// `RPBroadcastController` — sessions start from `RPSystemBroadcastPickerView`
    /// — so that delivery goes nowhere this code can observe, and whether iOS puts
    /// the message in front of the user is **not** something the SDK promises or
    /// that anything here has measured. The sentence rides along because it costs
    /// nothing; the load-bearing half is the page, wherever there is a page.
    private static func error(code: Int, message: String, recovery: String) -> NSError {
        NSError(
            domain: "com.nitai.aikeyboard.broadcast", code: code,
            userInfo: [
                NSLocalizedDescriptionKey: message,
                NSLocalizedRecoverySuggestionErrorKey: recovery
            ])
    }

    override func broadcastPaused() {
        channel?.setPaused(true)
        channel?.recordPause(resumed: false)
        Self.log.notice("broadcast paused")
    }

    override func broadcastResumed() {
        // Delivery restarts from a cold gate: the next frame is always sampled
        // rather than measured against an instant from before the pause.
        lastSampledAt = nil
        channel?.setPaused(false)
        channel?.recordPause(resumed: true)
        Self.log.notice("broadcast resumed")
    }

    override func broadcastFinished() {
        stopHeartbeat()
        // Neither the reader nor the downscale buffer is torn down here, and that
        // is deliberate: ReplayKit does not document this callback to be on the
        // delivery queue, so releasing either could free memory a frame in flight
        // is still using. The process ends within moments of this, which is a
        // better collector than a race. A read already in flight keeps its own
        // JPEG and publishes a record the freshness gate refuses, because the
        // page it is measured against now carries an ending.
        //
        // `.stopped`, not `.userStopped`. This callback takes no argument and
        // `RPBroadcastSampleHandler` has no callback anywhere that carries an
        // `NSError`, so the extension is told *that* the broadcast finished and
        // never why — see `ScreenContextEndReason`. Writing "the user stopped it"
        // here was a claim nothing had checked, and the keyboard acted on it by
        // hiding the strip.
        //
        // **`.noFrames` is the one thing this side does know**, and it is the
        // difference between "you stopped it" and "ReplayKit never handed us the
        // screen" — R1, unmeasured on hardware, and the single most likely shape
        // of a broadcast that runs and does nothing. Counted off the shared page
        // rather than off `framesDelivered`: that counter is written on the
        // delivery queue and read here on ReplayKit's lifecycle queue, which are
        // not documented to be the same, and it was left unsynchronised only
        // because nothing keyed a decision off it. The page's counter is written
        // under `SharedPage`'s lock and read back through the seqlock.
        let delivered = channel?.status()?.framesDelivered ?? 0
        channel?.end(ScreenContextEndReason.ending(framesDelivered: delivered))
        Self.log.notice(
            """
            broadcast finished delivered=\(self.framesDelivered, privacy: .public) \
            sampled=\(self.framesSampled, privacy: .public) \
            published=\(delivered, privacy: .public)
            """
        )
    }

    /// Fires only when the broadcast was started from Control Center, and names
    /// the *first* application used during it, never the current one
    /// (`RPBroadcastExtension.h`). Logged as history; it is not a live signal and
    /// nothing may key a decision off it.
    override func broadcastAnnotated(withApplicationInfo applicationInfo: [AnyHashable: Any]) {
        let bundleID = applicationInfo[RPApplicationInfoBundleIdentifierKey] as? String
        Self.log.notice("broadcast annotated firstApp=\(bundleID ?? "unknown", privacy: .public)")
    }

    // MARK: - Heartbeat

    /// 1 Hz, on its own queue, and it writes `heartbeatAt` and nothing else.
    ///
    /// Separate from frame delivery because they are separate failures: a wedged
    /// handler keeps the process alive while frames stop, and a keyboard that
    /// could not tell those apart would show a live-looking strip over a dead
    /// pipeline. `CaptureFreshness` conditions 1 and 2 are the two halves.
    private func startHeartbeat() {
        stopHeartbeat()
        guard let channel else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1.0, leeway: .milliseconds(200))
        timer.setEventHandler { channel.heartbeat() }
        timer.resume()
        heartbeat = timer
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    // MARK: - Delivery

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        switch sampleBufferType {
        case .video:
            // The pool drains anything CoreMedia autoreleased before the callback
            // returns, so a sample cannot sit in the process's pool waiting for a
            // runloop turn that a delivery queue never takes.
            autoreleasepool { sampleVideo(sampleBuffer) }
        case .audioApp, .audioMic:
            // Dropped on purpose rather than fallen through: audio arrives far
            // more often than video and this extension reads neither.
            return
        @unknown default:
            return
        }
    }

    private func sampleVideo(_ sampleBuffer: CMSampleBuffer) {
        framesDelivered &+= 1

        let now = clock.now
        if let last = lastSampledAt, now - last < Self.sampleInterval {
            // Not sampled, but delivery is alive and the keyboard's second
            // liveness condition is watching for exactly that.
            channel?.recordDelivery()
            return
        }
        lastSampledAt = now
        framesSampled &+= 1

        // One `task_info` call per sampled frame — 4 Hz, no allocation — and the
        // shared page is written only when the answer flips, so the status screen
        // reflects the refusal without a seqlock transaction four times a second.
        let footprint = memory.observe()
        channel?.recordFootprint(baselineMB: nil, currentMB: footprint.footprintMB)
        if footprint.changed {
            channel?.setDegraded(footprint.isRefusing)
            Self.log.notice(
                """
                memory degraded=\(footprint.isRefusing, privacy: .public) \
                footprintMB=\(footprint.footprintMB.map { String(format: "%.1f", $0) } ?? "unmeasurable", privacy: .public)
                """
            )
        }

        // Orientation rides as an attachment, not as a property of the image, and
        // a landscape frame read as portrait is read sideways.
        let orientation = Self.orientation(of: sampleBuffer)
        if orientation != lastOrientation {
            lastOrientation = orientation
            // `CGImagePropertyOrientation` is 1...8, so a byte holds it. Clamped
            // rather than truncated so a value outside that range arrives as 255
            // — visibly wrong — instead of wrapping into a different, plausible
            // orientation.
            channel?.recordOrientation(
                Self.band(for: orientation), raw: UInt8(clamping: orientation?.rawValue ?? 0))
            Self.log.notice(
                "video orientation=\(Self.name(of: orientation), privacy: .public)"
            )
        }

        if !hasLoggedFormat, let format = sampleBuffer.formatDescription {
            hasLoggedFormat = true
            let size = CMVideoFormatDescriptionGetDimensions(format)
            let subType = CMFormatDescriptionGetMediaSubType(format)
            channel?.recordFrameFormat(
                width: Int(size.width), height: Int(size.height), pixelFormat: subType)
            Self.log.notice(
                """
                video first-frame \(size.width, privacy: .public)x\
                \(size.height, privacy: .public) format=\
                \(Self.fourCharCode(subType), privacy: .public)
                """
            )
        }

        // One clock reading for the identity and for anything read off this
        // frame, so the record's `capturedAt` is the same instant the page
        // publishes as `currentFrameSampledAt` rather than a few microseconds
        // after it.
        let sampledAt = CaptureClock.now()
        // One page load for both halves of this frame. The crop it carries is
        // our own keyboard's region, which the fingerprint must leave out: our
        // panel repaints its shimmer at 60 Hz for the whole five seconds of a
        // read, and inside the band that moved the identity on every sample and
        // made the freshness gate refuse the reading the tap had just paid for.
        let intent = channel?.intent()
        let fingerprint = Self.fingerprint(
            of: sampleBuffer,
            orientation: Self.band(for: orientation),
            bottomCrop: intent?.frameBottomCrop ?? FrameReduction.Band.bottom)
        if let fingerprint {
            channel?.recordFrame(fingerprint, now: sampledAt)
            serveReadRequest(
                sampleBuffer, intent: intent, identity: fingerprint.identity, sampledAt: sampledAt)
        } else {
            // A frame we could not fingerprint is a frame the freshness gate
            // must not treat as evidence, so delivery is recorded and the
            // identity is left alone rather than being cleared or guessed. It is
            // also not a frame to read: a reading whose identity nothing can
            // confirm could never be shown.
            channel?.count(\.fingerprintFailures)
            channel?.recordDelivery(now: sampledAt)
        }

        if framesSampled % Self.logEvery == 0 {
            Self.log.notice(
                """
                video progress delivered=\(self.framesDelivered, privacy: .public) \
                sampled=\(self.framesSampled, privacy: .public) \
                fingerprinted=\(fingerprint != nil, privacy: .public)
                """
            )
        }
    }

    // MARK: - The read

    /// Answers a raised request with this frame, if there is one to answer.
    ///
    /// Everything here is bounded work on the delivery queue: a page load, a
    /// downscale into a buffer that already exists, and a JPEG encode. The
    /// five-second part is the call `ScreenReadService.start` schedules on its
    /// own queue, and this returns without it.
    ///
    /// **The encode has never been measured on this path.** The "under 0.2 MB
    /// above process base" figure this comment used to quote came from a bare
    /// CLI process in the iOS Simulator encoding a PNG, which the design records
    /// as a floor rather than a measurement. The shipping path is a vImage ARGB
    /// buffer into `CGImageDestination`, inside a broadcast extension, on a
    /// device — three differences, any of which could matter against a ~50 MB
    /// cap. `MemoryGovernor` is what stands between this and jetsam until R2 and
    /// R7 are measured on hardware.
    private func serveReadRequest(
        _ sampleBuffer: CMSampleBuffer, intent: CaptureIntent?, identity: FrameIdentity,
        sampledAt: UInt64
    ) {
        // Read once, under the lock, and work with that reference for the rest
        // of this frame. Re-reading per use would let a `broadcastStarted` land
        // between the claim and the answer, so a ticket taken from one session's
        // service could be failed against another's.
        guard let channel, let reads = reads.withLock({ $0 }),
            let ticket = reads.claim(
                intent: intent, identity: identity, capturedAt: sampledAt)
        else { return }

        // The memory refusal is taken *after* the ticket, not before it. Refusing
        // earlier would leave `intent.readNow` unclaimed, so the next frame would
        // try again and the one after that, and the keyboard — which is already
        // waiting on that sequence — would sit through its full twelve seconds and
        // then be told nothing answered. A claimed request is always answered,
        // here with the reason.
        guard !memory.isRefusing else {
            channel.count(\.refusedMemory)
            reads.fail(
                ticket,
                detail: "Screen context is low on memory and did not read the screen.")
            Self.log.error(
                "read refused: footprint is above the watermark, request=\(ticket.sequence, privacy: .public)"
            )
            return
        }

        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let jpeg = scaler.jpeg(from: buffer)
        else {
            // The request is answered rather than dropped. The keyboard is
            // already waiting on this sequence, and twelve seconds of silence is
            // the one outcome this pipeline is not allowed to produce.
            reads.fail(ticket, detail: "The screen could not be prepared for reading.")
            Self.log.error("read gave up: the frame could not be downscaled or encoded")
            return
        }

        reads.start(ticket, jpeg: jpeg)
    }

    // MARK: - Reading a sample without holding it

    /// Reduces the frame to its fingerprint while it is locked, and returns
    /// having copied nothing.
    ///
    /// `CVPixelBufferLockBaseAddress(.readOnly)` maps the frame that already
    /// exists rather than allocating one, and the unlock is paired on every exit
    /// including the failures. Nothing survives this function except 40 bytes of
    /// hash.
    /// Which edge of the buffer the top of the screen is on.
    ///
    /// The crop band is a claim about the screen — drop its top 14% of chrome and
    /// everything from the top of our own keyboard down, fingerprint the middle —
    /// and that claim only survives the translation into buffer rows while the
    /// buffer is the right way up. An
    /// absent attachment means ReplayKit told us nothing, and `.up` is the right
    /// reading of silence here: it is what every portrait frame is, and it is the
    /// behaviour every measured number in `FrameFingerprint` was taken against.
    ///
    /// The four `CGImagePropertyOrientation` cases that involve a mirror
    /// (`upMirrored` and friends) do not arise from a screen capture and are read
    /// as their unmirrored twins rather than refused, because refusing would mean
    /// no fingerprint at all, and no fingerprint means no read.
    private static func band(
        for orientation: CGImagePropertyOrientation?
    )
        -> FrameReduction.Orientation
    {
        switch orientation {
        case .down, .downMirrored: return .down
        case .left, .leftMirrored: return .left
        case .right, .rightMirrored: return .right
        default: return .up
        }
    }

    private static func fingerprint(
        of sampleBuffer: CMSampleBuffer,
        orientation: FrameReduction.Orientation,
        bottomCrop: Double
    )
        -> FrameFingerprint?
    {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let format: FrameReduction.PixelFormat
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_32BGRA: format = .bgra8888
        case kCVPixelFormatType_32ARGB: format = .argb8888
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            // The luma plane on its own. Chroma is not read at all: the
            // reduction is greyscale, so the 1.6 MB of CbCr is work nobody
            // needs.
            format = .luminance8
        default:
            return nil
        }

        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        let planar = CVPixelBufferIsPlanar(buffer)
        let base =
            planar
            ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
            : CVPixelBufferGetBaseAddress(buffer)
        guard let base else { return nil }

        let width = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer)
        let height =
            planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        let bytesPerRow =
            planar
            ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            : CVPixelBufferGetBytesPerRow(buffer)

        return FrameFingerprint.make(
            base: UnsafeRawPointer(base), width: width, height: height,
            bytesPerRow: bytesPerRow, format: format, orientation: orientation,
            bottomCrop: bottomCrop)
    }

    private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation? {
        let attachment = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        )
        guard let raw = attachment as? NSNumber else { return nil }
        return CGImagePropertyOrientation(rawValue: raw.uint32Value)
    }

    private static func name(of orientation: CGImagePropertyOrientation?) -> String {
        guard let orientation else { return "absent" }
        switch orientation {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        default: return "raw\(orientation.rawValue)"
        }
    }

    private static func fourCharCode(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
    }
}
