import Accelerate
import AIKeyboardShared
import CoreGraphics

// MARK: - Buffer management and JPEG encoding

extension FrameScaler {

    /// The destination size: half of the source in each dimension, rounded down
    /// to even so a 4:2:0 chroma plane divides exactly.
    static func target(width: Int, height: Int) -> (width: Int, height: Int) {
        ((width / scale) & ~1, (height / scale) & ~1)
    }

    /// Frees every buffer.
    ///
    /// Private, and reached only from `deinit` and from a source that changed
    /// size, because there is no safe caller for it from another queue:
    /// `processSampleBuffer` may be inside `jpeg(from:)` when a lifecycle
    /// callback arrives, and freeing the destination underneath it is a crash
    /// rather than a saving. The buffers therefore live as long as this object,
    /// which lives as long as the extension process.
    func release() {
        for buffer in [destination, luma, chroma] {
            if let data = buffer?.data { free(data) }
        }
        destination = nil
        luma = nil
        chroma = nil
        size = (0, 0)
    }

    /// Allocates the destination, once, for the first frame's dimensions. A
    /// source that changes size mid-session — a rotation, or an iPad split view —
    /// reallocates rather than scaling into the wrong shape.
    func prepare(width: Int, height: Int) -> Bool {
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
    func preparePlanes() -> Bool {
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

    func conversionInfo(fullRange: Bool) -> vImage_YpCbCrToARGB? {
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
    static func encode(_ buffer: vImage_Buffer, byteOrder: CGBitmapInfo) -> Data? {
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
