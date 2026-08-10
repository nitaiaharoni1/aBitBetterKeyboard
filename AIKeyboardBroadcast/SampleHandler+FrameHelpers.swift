import AIKeyboardShared
import CoreMedia
import CoreVideo
import ImageIO
import ReplayKit

// MARK: - Frame helpers
//
// Static utilities that read a CMSampleBuffer without holding it: orientation
// extraction, pixel-format routing, fingerprinting, and logging helpers. Split
// from SampleHandler to keep the lifecycle and delivery code readable on its own.

extension SampleHandler {

    // MARK: Orientation

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
    static func band(
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

    static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation? {
        let attachment = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        )
        guard let raw = attachment as? NSNumber else { return nil }
        return CGImagePropertyOrientation(rawValue: raw.uint32Value)
    }

    // MARK: Fingerprinting

    /// Reduces the frame to its fingerprint while it is locked, and returns
    /// having copied nothing.
    ///
    /// `CVPixelBufferLockBaseAddress(.readOnly)` maps the frame that already
    /// exists rather than allocating one, and the unlock is paired on every exit
    /// including the failures. Nothing survives this function except 40 bytes of
    /// hash.
    static func fingerprint(
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

    // MARK: Logging helpers

    static func name(of orientation: CGImagePropertyOrientation?) -> String {
        guard let orientation else { return "absent" }
        switch orientation {
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        default: return "raw\(orientation.rawValue)"
        }
    }

    static func fourCharCode(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? "\(code)"
    }
}
