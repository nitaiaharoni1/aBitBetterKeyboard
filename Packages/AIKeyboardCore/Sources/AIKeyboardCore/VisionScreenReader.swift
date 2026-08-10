import CoreGraphics
import Foundation
import Vision

/// Reads a messaging screen with Apple's on-device text recogniser.
///
/// **This path cannot read Hebrew, and that is a property of the OS, not of this
/// code.** `VNRecognizeTextRequest.supportedRecognitionLanguages()` returns 30
/// languages on both iOS and macOS and Hebrew is not among them. Arabic is, so
/// it is not a right-to-left limitation — the Hebrew model simply is not there.
/// Measured over `Bar/screen-context/`: 100% character recall of the expected
/// message on the 12 English screens, 13% on the 10 Hebrew ones, and adding
/// `ar-SA` to `recognitionLanguages` changes nothing at all. See
/// `VisionLanguageTests`.
///
/// So the job here is narrower than it looks: read the screens it can read
/// perfectly, and *know* when it cannot. The second half is the hard one,
/// because the only tool available to detect Hebrew on screen is the tool that
/// is blind to it. `readability` answers it a different way — see there.
///
/// **Vision does not read these screens the same way on iOS as on macOS**, so
/// measure this path on the simulator and treat `harness/run-reader.sh` as the
/// macOS reading of it. Same sources, same pixels, same thresholds, measured
/// 2026-08-08: macOS accepts 9 of the 30 bar images and answers 5, all 5 right;
/// iOS accepts 10 and answers 8, and three of those are wrong — `ml-01` because
/// macOS puts its mean confidence at 0.896, just under the gate, and `wa-07` and
/// `sl-05` because the recogniser puts different lines on the page. `wa-07` is
/// the screen whose only correct answer is silence and iOS answers it; `sl-05`
/// comes back as keyboard key caps. `ScreenContextBarTests` pins the set.
/// The property the routing rests on survives both: zero Hebrew and zero mixed
/// screens are accepted on device either way.
public struct VisionScreenReader: ScreenReader {

    /// Where the recogniser is trusted. Both numbers come from
    /// `Bar/screen-context/harness/coverage.swift` over all 30 images.
    ///
    /// The pair is deliberately conservative. Sending a Hebrew screen down this
    /// path produces a confident, wrong answer in the user's voice; sending an
    /// English screen to the cloud costs a few seconds. At these thresholds 9 of
    /// the 12 English screens stay on device on macOS and 10 do on iOS — see the
    /// platform note above — and **no** Hebrew or mixed screen ever does on
    /// either. Loosening coverage to 0.95 picks up two more English screens (`sl-02` at 0.9583 and `ml-04` at exactly 0.9500) and
    /// one mixed screen with it, which is the wrong trade.
    public struct Thresholds: Sendable {
        public var coverage: Double = 0.97
        public var confidence: Double = 0.90
        public init() {}
    }

    private let thresholds: Thresholds

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    public func read(_ frame: CGImage) async throws -> AIOutput<ScreenReading?> {
        let page = try Self.recognize(frame)
        guard page.isTrustworthy(thresholds) else {
            throw ScreenReadError.notReadableOnDevice
        }
        return AIOutput(try Self.interpret(page), provenance: .onDevice)
    }

    // MARK: - Recognition

    /// One recognised line, in Vision's normalised coordinates: origin at the
    /// bottom left, so a larger `y` is further up the screen.
    struct Line: Sendable {
        let text: String
        let box: CGRect
        let confidence: Double

        var centreX: Double { box.midX }
        var top: Double { box.maxY }
        var bottom: Double { box.minY }
        var height: Double { box.height }
    }

    struct Page: Sendable {
        let lines: [Line]
        /// Fraction of the text-shaped regions on screen that produced a
        /// recognised string.
        let coverage: Double
        let meanConfidence: Double

        func isTrustworthy(_ thresholds: Thresholds) -> Bool {
            coverage >= thresholds.coverage && meanConfidence >= thresholds.confidence
        }
    }

    /// Runs recognition and, alongside it, the readability check.
    ///
    /// `VNDetectTextRectanglesRequest` finds text by *shape*, with no idea what
    /// language it is in, so it sees a Hebrew bubble perfectly well. Recognition
    /// does not. The ratio between them is therefore a direct measurement of
    /// "there is writing here I could not read", which is the question the
    /// router actually needs answered, and it never has to name the script to
    /// answer it.
    static func recognize(_ frame: CGImage) throws -> Page {
        let recognizeText = VNRecognizeTextRequest()
        recognizeText.recognitionLevel = .accurate
        recognizeText.usesLanguageCorrection = true
        recognizeText.automaticallyDetectsLanguage = true

        let findRegions = VNDetectTextRectanglesRequest()

        try VNImageRequestHandler(cgImage: frame, options: [:])
            .perform([recognizeText, findRegions])

        let observations = recognizeText.results ?? []
        let lines: [Line] = observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            return Line(
                text: best.string,
                box: observation.boundingBox,
                confidence: Double(best.confidence))
        }

        let regions = (findRegions.results ?? []).map(\.boundingBox)
        let read = observations.map(\.boundingBox)
        let covered = regions.filter { region in read.contains { overlaps(region, $0) } }.count

        return Page(
            lines: lines,
            coverage: regions.isEmpty ? 1 : Double(covered) / Double(regions.count),
            meanConfidence: lines.isEmpty
                ? 0 : lines.map(\.confidence).reduce(0, +) / Double(lines.count))
    }

    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return false }
        let smaller = min(a.width * a.height, b.width * b.height)
        return intersection.width * intersection.height > 0.3 * smaller
    }

}
