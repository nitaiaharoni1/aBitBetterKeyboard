import AIKeyboardShared
import CoreMedia
import CoreVideo
import ImageIO
import ReplayKit
import os

/// The capture shutter. It fingerprints frames and reads nothing.
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

    // Mutated from ReplayKit's delivery queue by `processSampleBuffer`, and from
    // whatever queue ReplayKit uses for the lifecycle callbacks by
    // `broadcastStarted`, `broadcastResumed` and `broadcastFinished`. ReplayKit
    // does not document those to be the same queue, so this is not the
    // single-queue invariant an earlier version of this comment claimed.
    //
    // Left unsynchronised deliberately, and only because of what these are: no
    // frame is delivered before `broadcastStarted` or while paused, and the
    // values are read solely to log. The counters the *keyboard* reads do not
    // live here — they live in the shared page behind a seqlock, so a torn read
    // is a retry rather than a wrong number shown to the user.
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
        startHeartbeat()

        Self.log.notice(
            """
            broadcast started intervalMs=\(Self.sampleIntervalMilliseconds, privacy: .public) \
            channel=\(self.channel == nil ? "unreachable" : "open", privacy: .public) \
            session=\(session?.uuidString ?? "none", privacy: .public)
            """
        )
    }

    override func broadcastPaused() {
        channel?.setPaused(true)
        Self.log.notice("broadcast paused")
    }

    override func broadcastResumed() {
        // Delivery restarts from a cold gate: the next frame is always sampled
        // rather than measured against an instant from before the pause.
        lastSampledAt = nil
        channel?.setPaused(false)
        Self.log.notice("broadcast resumed")
    }

    override func broadcastFinished() {
        stopHeartbeat()
        channel?.end(.userStopped)
        Self.log.notice(
            """
            broadcast finished delivered=\(self.framesDelivered, privacy: .public) \
            sampled=\(self.framesSampled, privacy: .public)
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

        // Orientation rides as an attachment, not as a property of the image, and
        // a landscape frame read as portrait is read sideways.
        let orientation = Self.orientation(of: sampleBuffer)
        if orientation != lastOrientation {
            lastOrientation = orientation
            Self.log.notice(
                "video orientation=\(Self.name(of: orientation), privacy: .public)"
            )
        }

        if !hasLoggedFormat, let format = sampleBuffer.formatDescription {
            hasLoggedFormat = true
            let size = CMVideoFormatDescriptionGetDimensions(format)
            let subType = CMFormatDescriptionGetMediaSubType(format)
            Self.log.notice(
                """
                video first-frame \(size.width, privacy: .public)x\
                \(size.height, privacy: .public) format=\
                \(Self.fourCharCode(subType), privacy: .public)
                """
            )
        }

        let fingerprint = Self.fingerprint(of: sampleBuffer)
        if let fingerprint {
            channel?.recordFrame(fingerprint)
        } else {
            // A frame we could not fingerprint is a frame the freshness gate
            // must not treat as evidence, so delivery is recorded and the
            // identity is left alone rather than being cleared or guessed.
            channel?.recordDelivery()
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

    // MARK: - Reading a sample without holding it

    /// Reduces the frame to its fingerprint while it is locked, and returns
    /// having copied nothing.
    ///
    /// `CVPixelBufferLockBaseAddress(.readOnly)` maps the frame that already
    /// exists rather than allocating one, and the unlock is paired on every exit
    /// including the failures. Nothing survives this function except 40 bytes of
    /// hash.
    private static func fingerprint(of sampleBuffer: CMSampleBuffer) -> FrameFingerprint? {
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
            bytesPerRow: bytesPerRow, format: format)
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
