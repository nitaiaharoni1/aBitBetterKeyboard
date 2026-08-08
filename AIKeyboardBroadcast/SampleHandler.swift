import CoreMedia
import ImageIO
import ReplayKit
import os

/// The capture shutter. It receives frames and reads nothing.
///
/// ReplayKit kills a broadcast upload extension at roughly 50 MB and one BGRA
/// frame at this device's resolution is about 12.6 MB
/// (`.claude/docs/replaykit-contract.md`), so the rule this class is built around
/// is that no frame outlives the callback it arrived in. Nothing here fetches the
/// `CVPixelBuffer` at all: the only things read off a sample are its format
/// description and its orientation attachment, and the only state kept between
/// callbacks is counters.
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

    // Mutated from ReplayKit's delivery queue by `processSampleBuffer`, and from
    // whatever queue ReplayKit uses for the lifecycle callbacks by
    // `broadcastStarted`, `broadcastResumed` and `broadcastFinished`. ReplayKit
    // does not document those to be the same queue, so this is not the
    // single-queue invariant an earlier version of this comment claimed.
    //
    // Left unsynchronised deliberately, and only because of what these are: no
    // frame is delivered before `broadcastStarted` or while paused, and the
    // values are read solely to log. The moment anything publishes them —
    // `CaptureStatus` is the planned consumer — they need real synchronisation,
    // and a torn counter would then be a wrong number shown to the user rather
    // than a wrong number in a log line.
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
        Self.log.notice(
            "broadcast started intervalMs=\(Self.sampleIntervalMilliseconds, privacy: .public)"
        )
    }

    override func broadcastPaused() {
        Self.log.notice("broadcast paused")
    }

    override func broadcastResumed() {
        // Delivery restarts from a cold gate: the next frame is always sampled
        // rather than measured against an instant from before the pause.
        lastSampledAt = nil
        Self.log.notice("broadcast resumed")
    }

    override func broadcastFinished() {
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
        if let last = lastSampledAt, now - last < Self.sampleInterval { return }
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

        if framesSampled % Self.logEvery == 0 {
            Self.log.notice(
                """
                video progress delivered=\(self.framesDelivered, privacy: .public) \
                sampled=\(self.framesSampled, privacy: .public)
                """
            )
        }
    }

    // MARK: - Reading a sample without holding it

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
