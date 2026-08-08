import Accelerate
import AIKeyboardShared
import CoreGraphics
import CoreVideo
import Foundation

/// Turns the frame ReplayKit is holding into the ~66 KB that leaves the device,
/// with one reusable buffer and no full-size copy.
///
/// **The arithmetic this class exists for.** A broadcast upload extension is
/// killed at roughly 50 MB and one BGRA frame at 1206x2622 is 12.2 MiB, which is
/// already mapped by the time `processSampleBuffer` is called
/// (`.claude/docs/replaykit-contract.md`). So nothing here allocates a second
/// full-size image: the source is read where ReplayKit put it, and the only
/// allocation is the half-size destination, made once per session on the first
/// read and overwritten in place by every read after it.
///
/// | Buffer | 1206x2622 source | When |
/// |---|---|---|
/// | destination, 602x1310 ARGB | **3.0 MiB** | both formats |
/// | scaled luma, 602x1310 | 0.75 MiB | 420f only |
/// | scaled chroma, 301x655 | 0.38 MiB | 420f only |
/// | the JPEG handed to the read | ~66 KB median, ~98 KB p90 | both |
///
/// A BGRA session therefore costs 3.0 MiB from the first Reply tap onwards and a
/// 420f session 4.1 MiB — but a 420f frame is 4.6 MiB where a BGRA one is 12.2,
/// so 420f is the cheaper case overall by 7 MiB. Nothing is allocated at all in a
/// session where the user never taps Reply.
///
/// **Half, and the factor is measured.** R5 asked whether halving the frame
/// costs the cloud reader accuracy, because every published score on
/// `Bar/screen-context/` was taken at the native 1206x2622. Settled 2026-08-08 by
/// running that harness as a 2x2 — 1206x2622 and 602x1310, PNG and JPEG q0.70,
/// two runs a cell minimum, same prompt, same schema, same model. It does not:
///
/// | Sent | bytes med / p90 | exact | sender | language | traps |
/// |---|---|---|---|---|---|
/// | 1206x2622 PNG, the bar's config | 250 / 341 KB | 18/30 | 26/30 | 28/30 | 0 |
/// | 602x1310 PNG | 207 / 288 KB | 17/30 | 28/30 | 29/30 | 1 |
/// | 1206x2622 JPEG q0.70 | 176 / 254 KB | 18-19/30 | 28/30 | 28/30 | 0 |
/// | **602x1310 JPEG q0.70, what this class sends** | **66 / 98 KB** | 18-19/30 | **29-30/30** | **30/30** | 0 |
///
/// No axis moves by more than one between full and half, and at the format that
/// actually ships the half-size frame is *ahead* on sender and keyboard
/// language. It is also 74% smaller than the PNG the bar scored. So `scale`
/// stays at 2; `1` sends the frame at the bar's resolution for 176 KB median
/// instead of 66 KB and no destination buffer at all, and buys nothing.
///
/// Two caveats the bar's own README carries in full. The totals hide churn —
/// eleven of thirty frames change verdict between the two PNG sizes, four of
/// them for the better — so re-measure per entry rather than by total. And the
/// served model moves between days: two runs of one configuration minutes apart
/// disagree on two of thirty, runs a day apart on roughly a third, and there is
/// no dated version to pin against. Which is why the table above was taken with
/// all four cells in one sitting.
///
/// **Landscape is unhandled and that is deliberate rather than forgotten.**
/// Orientation rides as a sample attachment, `SampleHandler` logs it, and nothing
/// here rotates. What ReplayKit actually delivers — format, size, orientation and
/// rate — is R1 in the capture design and has no device measurement, so a
/// rotation written against a guess would be a second guess on top of the first.
///
/// **It costs more than a sideways JPEG, and that half was undocumented.** The
/// same untouched orientation reaches `FrameFingerprint`, whose crop band assumes
/// row 0 of the buffer is the physical top of the screen. If a rotated buffer's
/// rows do not run that way, the band that is supposed to hold the status bar and
/// exclude our own keyboard holds neither — which can reintroduce the exact
/// failure the own-UI exclusion was built to fix (our shimmer moving the identity
/// on every frame, so the freshness gate discards the reading the user paid for),
/// or crop real message content into the discarded region. `ownUIHeightFraction`
/// compounds it: the keyboard measures it once when it appears and never again,
/// so a rotation while a read is in flight leaves the record's band and the next
/// frame's band disagreeing, which reads as a screen change that never happened.
/// Neither is guesswork worth writing blind; both are on the device checklist in
/// `Scripts/measure-on-device.sh`, and a rotated frame is the first thing to look
/// at once frames exist at all.
final class FrameScaler {

    /// The divisor applied to both dimensions before the frame is encoded.
    static let scale = 2

    /// One destination, reused. `nil` until the first read.
    private var destination: vImage_Buffer?
    /// The 4:2:0 intermediates. Allocated only if a frame arrives in that format.
    private var luma: vImage_Buffer?
    private var chroma: vImage_Buffer?
    private var size = (width: 0, height: 0)

    /// Generated once, because it is a matrix multiply's worth of setup and the
    /// answer never changes.
    private var conversion: vImage_YpCbCrToARGB?
    private var conversionIsFullRange = false

    deinit { release() }

    /// Frees every buffer.
    ///
    /// Private, and reached only from `deinit` and from a source that changed
    /// size, because there is no safe caller for it from another queue:
    /// `processSampleBuffer` may be inside `jpeg(from:)` when a lifecycle
    /// callback arrives, and freeing the destination underneath it is a crash
    /// rather than a saving. The buffers therefore live as long as this object,
    /// which lives as long as the extension process.
    private func release() {
        for buffer in [destination, luma, chroma] {
            if let data = buffer?.data { free(data) }
        }
        destination = nil
        luma = nil
        chroma = nil
        size = (0, 0)
    }

    /// The frame, downscaled and JPEG-encoded, or nil if it could not be read.
    ///
    /// Locks read-only, so ReplayKit's buffer is mapped rather than copied, and
    /// unlocks on every exit including the failures. Nothing survives the call
    /// except the returned `Data`.
    func jpeg(from pixelBuffer: CVPixelBuffer) -> Data? {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_32BGRA:
            // BGRA in memory reads as a little-endian word with alpha in the top
            // byte, and the alpha of a screen recording is opaque, so it is
            // skipped rather than un-premultiplied.
            return interleaved(pixelBuffer, byteOrder: .byteOrder32Little)
        case kCVPixelFormatType_32ARGB:
            return interleaved(pixelBuffer, byteOrder: .byteOrder32Big)
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return biplanar(pixelBuffer, fullRange: false)
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            return biplanar(pixelBuffer, fullRange: true)
        default:
            return nil
        }
    }

    // MARK: - The two formats

    private func interleaved(_ pixelBuffer: CVPixelBuffer, byteOrder: CGBitmapInfo) -> Data? {
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard prepare(width: width, height: height), var out = destination else { return nil }
        var source = vImage_Buffer(
            data: base, height: vImagePixelCount(height), width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(pixelBuffer))

        guard
            vImageScale_ARGB8888(&source, &out, nil, vImage_Flags(kvImageHighQualityResampling))
                == kvImageNoError
        else { return nil }

        return Self.encode(out, byteOrder: byteOrder)
    }

    /// 4:2:0, scaled plane by plane and converted afterwards.
    ///
    /// Order matters for memory rather than for quality: converting first would
    /// need a full-size ARGB buffer, which is the 12.2 MiB this whole class
    /// exists to avoid. Scaling the two planes first makes the conversion's
    /// output the destination that already exists.
    private func biplanar(_ pixelBuffer: CVPixelBuffer, fullRange: Bool) -> Data? {
        guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
            let lumaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
            let chromaBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else { return nil }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

        guard prepare(width: width, height: height), preparePlanes(),
            var out = destination, var lumaOut = luma, var chromaOut = chroma,
            var info = conversionInfo(fullRange: fullRange)
        else { return nil }

        var lumaIn = vImage_Buffer(
            data: lumaBase, height: vImagePixelCount(height), width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
        var chromaIn = vImage_Buffer(
            data: chromaBase,
            height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)),
            width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)),
            rowBytes: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))

        let flags = vImage_Flags(kvImageHighQualityResampling)
        guard vImageScale_Planar8(&lumaIn, &lumaOut, nil, flags) == kvImageNoError,
            vImageScale_CbCr8(&chromaIn, &chromaOut, nil, flags) == kvImageNoError
        else { return nil }

        // ARGB in memory, so the CGImage below reads it big-endian with the
        // alpha byte skipped.
        var order: [UInt8] = [0, 1, 2, 3]
        guard
            vImageConvert_420Yp8_CbCr8ToARGB8888(
                &lumaOut, &chromaOut, &out, &info, &order, 255, vImage_Flags(kvImageNoFlags))
                == kvImageNoError
        else { return nil }

        return Self.encode(out, byteOrder: .byteOrder32Big)
    }

    // MARK: - Buffers

    /// The destination size: half of the source in each dimension, rounded down
    /// to even so a 4:2:0 chroma plane divides exactly.
    static func target(width: Int, height: Int) -> (width: Int, height: Int) {
        ((width / scale) & ~1, (height / scale) & ~1)
    }

    /// Allocates the destination, once, for the first frame's dimensions. A
    /// source that changes size mid-session — a rotation, or an iPad split view —
    /// reallocates rather than scaling into the wrong shape.
    private func prepare(width: Int, height: Int) -> Bool {
        let target = Self.target(width: width, height: height)
        guard target.width > 0, target.height > 0 else { return false }
        if let destination, size == target, destination.data != nil { return true }

        release()
        var buffer = vImage_Buffer()
        guard
            vImageBuffer_Init(
                &buffer, vImagePixelCount(target.height), vImagePixelCount(target.width), 32,
                vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else { return false }
        destination = buffer
        size = target
        return true
    }

    /// The two 4:2:0 intermediates, sized off the destination. Only a session
    /// that receives that format ever pays for them.
    private func preparePlanes() -> Bool {
        if luma != nil, chroma != nil { return true }

        var lumaBuffer = vImage_Buffer()
        var chromaBuffer = vImage_Buffer()
        guard
            vImageBuffer_Init(
                &lumaBuffer, vImagePixelCount(size.height), vImagePixelCount(size.width), 8,
                vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else { return false }
        guard
            vImageBuffer_Init(
                &chromaBuffer, vImagePixelCount(size.height / 2), vImagePixelCount(size.width / 2),
                16, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else {
            free(lumaBuffer.data)
            return false
        }
        luma = lumaBuffer
        chroma = chromaBuffer
        return true
    }

    private func conversionInfo(fullRange: Bool) -> vImage_YpCbCrToARGB? {
        if let conversion, conversionIsFullRange == fullRange { return conversion }

        // Rec. 709 with the range the buffer's own format constant declares.
        // Getting the range wrong washes the picture out rather than failing, so
        // the two constants are read from the pixel format rather than assumed.
        var range =
            fullRange
            ? vImage_YpCbCrPixelRange(
                Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255, YpMax: 255,
                YpMin: 0, CbCrMax: 255, CbCrMin: 0)
            : vImage_YpCbCrPixelRange(
                Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235, CbCrRangeMax: 240, YpMax: 235,
                YpMin: 16, CbCrMax: 240, CbCrMin: 16)

        var info = vImage_YpCbCrToARGB()
        guard
            vImageConvert_YpCbCrToARGB_GenerateConversion(
                kvImage_YpCbCrToARGBMatrix_ITU_R_709_2, &range, &info, kvImage420Yp8_CbCr8,
                kvImageARGB8888, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        else { return nil }

        conversion = info
        conversionIsFullRange = fullRange
        return info
    }

    // MARK: - Out

    /// Wraps the destination in a `CGImage` and encodes it.
    ///
    /// The data provider does not own the bytes and does not free them: the image
    /// exists only for the length of the encode below, and the buffer it points
    /// at outlives it and is reused by the next read.
    private static func encode(_ buffer: vImage_Buffer, byteOrder: CGBitmapInfo) -> Data? {
        guard let data = buffer.data else { return nil }
        let bytes = buffer.rowBytes * Int(buffer.height)
        guard
            let provider = CGDataProvider(
                dataInfo: nil, data: data, size: bytes, releaseData: { _, _, _ in })
        else { return nil }

        let info = CGBitmapInfo(
            rawValue: byteOrder.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        guard
            let image = CGImage(
                width: Int(buffer.width), height: Int(buffer.height), bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: buffer.rowBytes,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }

        // `CloudScreenReader`'s own encoder at its own default quality, so the
        // capture process and the in-app playground put the same bytes on the
        // wire. The bar scored this quality at this size — that used to be an
        // assumption and is now the last row of the table above.
        return CloudScreenReader.encode(image)
    }
}
