import Foundation

// MARK: - Box-average reduction

extension FrameReduction {

    /// Box-averages the cropped band down to `columns` x `rows` greyscale.
    ///
    /// Reads the source exactly once, in row order, and allocates nothing beyond
    /// an 8 KB accumulator — the frame is never copied, scaled into a second
    /// buffer, or converted. That matters here more than it reads: one BGRA
    /// frame at 1206x2622 is 12.6 MB against a ~50 MB cap, so a fingerprint that
    /// needed its own copy of the frame would cost a quarter of the extension's
    /// budget to produce 2 KB.
    ///
    /// - Returns: false, leaving `destination` untouched, if the geometry is not
    ///   something that can be reduced. A refusal, never a zero-filled answer:
    ///   a reduction of nothing hashes to a stable identity that would match
    ///   every other reduction of nothing.
    @discardableResult
    public static func reduce(
        base: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        format: PixelFormat,
        orientation: Orientation = .up,
        bottomCrop: Double = Band.bottom,
        into destination: UnsafeMutableBufferPointer<UInt8>
    ) -> Bool {
        guard destination.count >= sampleCount else { return false }
        guard width >= columns, height >= rows else { return false }
        guard bytesPerRow >= width * format.bytesPerPixel else { return false }

        // For `.up` this is exactly the old row range with every column, so the
        // reduction is byte-identical to the one every measured zero in this file
        // was taken against. The other three orientations move which edge is cut.
        let (bandColumns, band) = bandRect(
            inWidth: width, height: height, orientation: orientation, bottomCrop: bottomCrop)
        let firstRow = band.lowerBound
        let lastRow = band.upperBound
        let bandRows = band.count
        let firstColumn = bandColumns.lowerBound
        let bandWidth = bandColumns.count
        guard bandRows >= rows, bandWidth >= columns else { return false }

        let stride = format.bytesPerPixel

        return withUnsafeTemporaryAllocation(of: UInt32.self, capacity: sampleCount) { sums in
            sums.initialize(repeating: 0)
            defer { sums.deinitialize() }

            return withUnsafeTemporaryAllocation(of: UInt16.self, capacity: bandWidth) { columnOf in
                // Precomputed so the inner loop is a table lookup rather than a
                // multiply and a divide per pixel.
                for x in 0..<bandWidth { columnOf[x] = UInt16(x * columns / bandWidth) }

                for y in firstRow..<lastRow {
                    let destinationRow = (y - firstRow) * rows / bandRows
                    let rowBase = base.advanced(by: y * bytesPerRow)
                    let accumulator = sums.baseAddress! + destinationRow * columns

                    switch format {
                    case .luminance8:
                        let pixels = rowBase.assumingMemoryBound(to: UInt8.self)
                        for x in 0..<bandWidth {
                            accumulator[Int(columnOf[x])] &+= UInt32(pixels[firstColumn + x])
                        }
                    case .bgra8888, .argb8888:
                        let blueOffset = format == .bgra8888 ? 0 : 3
                        let greenOffset = format == .bgra8888 ? 1 : 2
                        let redOffset = format == .bgra8888 ? 2 : 1
                        let pixels = rowBase.assumingMemoryBound(to: UInt8.self)
                        for x in 0..<bandWidth {
                            let pixel = (firstColumn + x) * stride
                            // Rec. 601 luma in integer form: the same
                            // 0.299 / 0.587 / 0.114 the harness uses, scaled by
                            // 256 so the inner loop stays in integers.
                            let luma =
                                77 * UInt32(pixels[pixel + redOffset])
                                + 150 * UInt32(pixels[pixel + greenOffset])
                                + 29 * UInt32(pixels[pixel + blueOffset])
                            accumulator[Int(columnOf[x])] &+= luma >> 8
                        }
                    }
                }

                // Sample counts are the product of the two band widths rather
                // than a second accumulator: the row and column ranges are
                // deterministic, so counting them is arithmetic.
                for row in 0..<rows {
                    let rowSamples = bandRows * (row + 1) / rows - bandRows * row / rows
                    for column in 0..<columns {
                        let columnSamples =
                            bandWidth * (column + 1) / columns - bandWidth * column / columns
                        let samples = rowSamples * columnSamples
                        guard samples > 0 else { return false }
                        let mean = sums[row * columns + column] / UInt32(samples)
                        destination[row * columns + column] = UInt8(min(mean, 255))
                    }
                }
                return true
            }
        }
    }
}
