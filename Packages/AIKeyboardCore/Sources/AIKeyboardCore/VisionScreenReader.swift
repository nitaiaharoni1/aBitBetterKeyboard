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
/// iOS accepts 10 and answers 7, and three of those are wrong — `ml-01` because
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
    /// either. Loosening coverage to 0.95 picks up one more English screen and
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

    // MARK: - Interpretation

    /// Bands of the screen that are never message content. Fractions of screen
    /// height, measured from the bottom in Vision's coordinates, off the
    /// 1206×2622 frames in `Bar/screen-context/`.
    private enum Band {
        /// Clock, battery, signal. Measured at y 0.94–0.96.
        static let statusBar = 0.935
        /// Contact name, back button, call buttons. Measured at y 0.88–0.93.
        /// The contact name lives here and is the only place a one-to-one chat
        /// prints who you are talking to, so this band is read rather than
        /// merely skipped.
        static let navigationBar = 0.86
        /// Composer, and the keyboard when it is up.
        static let composer = 0.085
    }

    /// How close to an edge a line has to sit to count as hugging it.
    ///
    /// Side is read from the margins rather than from the line's centre because
    /// a long line in a one-sided layout crosses the middle of the screen and a
    /// centre test then calls it outgoing. Measured on Slack, where the message
    /// body runs x 0.15–0.89 and every centre-based reading was wrong.
    private enum Margin {
        static let left = 0.12
        static let right = 0.92
    }

    /// Two different refusals, and conflating them cost the user two screens.
    ///
    /// `nil` means *there is nothing here worth replying to* — a readable
    /// conversation whose newest incoming message is a voice note. That is an
    /// answer, and the router must not second-guess it.
    ///
    /// `throw .notReadableOnDevice` means *I could not read this*, which is a
    /// question for the cloud. Returning nil for that case made
    /// `RoutedScreenReader` treat "I cannot see" as "nothing is there", and the
    /// session showed the user nothing on `sl-01` and `sl-03` — plain answerable
    /// English that the cloud reader transcribes correctly. `ScreenContextBarTests`
    /// pins both screens.
    static func interpret(_ page: Page) throws -> ScreenReading? {
        let contact = navigationTitle(in: page)

        let body = page.lines
            .filter { $0.bottom > Band.composer && $0.top < Band.navigationBar }
            .sorted { $0.top > $1.top }

        let bubbles = group(body)
        // A conversation this path can read has two sides to it. Slack, Teams
        // and mail threads print every message flush against the same margin
        // and put the author on a label above it, so there is no geometry left
        // to say who sent what — the reader would have to understand the app's
        // layout rather than its shape. That is a failure to read, not a screen
        // with nothing on it.
        guard isTwoSided(bubbles) else { throw ScreenReadError.notReadableOnDevice }
        // The newest incoming message is the last one on the screen that is not
        // the user's own. Walking from the bottom rather than picking the most
        // answerable-looking bubble is the whole of it: every wrong answer
        // measured on this bar was a bubble one to four positions too early.
        //
        // No incoming bubble at all on a two-sided screen is genuinely nothing
        // to reply to, not a failure to read.
        guard let newest = bubbles.last(where: { !$0.isOutgoing }) else { return nil }

        let message = newest.text
        guard !message.isEmpty else { return nil }

        // A voice note's waveform recognises as glyph soup — one real frame
        // came back as "▶・二二ー・リリーー 0:47" — and a bubble holding an image
        // or a sticker does much the same. Requiring a script this keyboard can
        // actually reply in throws all of that out without needing to know what
        // drew it.
        let scripts = LanguageDetector.scripts(in: message)
        guard scripts.contains(.latin) || scripts.contains(.hebrew) else { return nil }
        return ScreenReading(
            sender: newest.sender ?? contact ?? "",
            message: message,
            language: scripts.contains(.hebrew) ? .hebrew : .english,
            scripts: scripts)
    }

    struct Bubble {
        var lines: [Line]
        var isOutgoing: Bool
        /// A group chat prints a name above each incoming bubble. A one-to-one
        /// chat prints none, and the contact name in the navigation bar is the
        /// answer instead.
        var sender: String?

        var text: String {
            lines.map(\.text)
                .filter { !isTimestamp($0) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        }
    }

    /// Splits the conversation into bubbles by vertical gap and by which edge
    /// they hug.
    ///
    /// Side is decided from where the *box* sits, never from how the text inside
    /// it is aligned. That distinction only bites on screens this path refuses
    /// anyway — a Hebrew message is right-aligned inside a left-hand bubble —
    /// but encoding it here keeps the rule in one place for when the cloud
    /// reader is compared against it.
    static func group(_ lines: [Line]) -> [Bubble] {
        // Grouping is by vertical adjacency alone. Side is decided afterwards,
        // for the whole bubble, because a bubble's short last line ("lot to
        // commit to.") hugs no margin at all and would otherwise split away
        // from the sentence it belongs to.
        var groups: [[Line]] = []
        // Sorted here rather than relied upon: grouping compares each line
        // against the one above it, so unordered input silently merges the
        // whole conversation into a single bubble instead of failing.
        for line in lines.sorted(by: { $0.top > $1.top }) {
            if let last = groups.last?.last, last.bottom - line.top < line.height * 0.9 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { lines in
            Bubble(lines: lines, isOutgoing: hugsRight(lines), sender: nil)
        }
        .map(stripSenderLabel)
    }

    /// The user's own bubbles reach the trailing margin and start well inside
    /// the leading one. Everyone else's do the opposite.
    private static func hugsRight(_ lines: [Line]) -> Bool {
        let leftmost = lines.map(\.box.minX).min() ?? 0
        let rightmost = lines.map(\.box.maxX).max() ?? 0
        return rightmost > Margin.right && leftmost > Margin.left
    }

    /// True when the screen puts messages against both margins, which is what
    /// makes side readable at all.
    static func isTwoSided(_ bubbles: [Bubble]) -> Bool {
        let touchesLeading = bubbles.contains { bubble in
            (bubble.lines.map(\.box.minX).min() ?? 1) < Margin.left
        }
        return touchesLeading && bubbles.contains { $0.isOutgoing }
    }

    /// A short line sitting at the head of an incoming bubble, on its own, is a
    /// sender label rather than the first line of the message.
    private static func stripSenderLabel(_ bubble: Bubble) -> Bubble {
        var bubble = bubble
        guard !bubble.isOutgoing, bubble.lines.count > 1, let first = bubble.lines.first else {
            return bubble
        }
        let looksLikeName =
            first.text.count <= 24 && !first.text.hasSuffix(".") && !first.text.hasSuffix("?")
            && first.box.width < (bubble.lines.dropFirst().map(\.box.width).max() ?? 0) * 0.8
        if looksLikeName {
            bubble.sender = stripTrailingTime(first.text)
            bubble.lines.removeFirst()
        }
        return bubble
    }

    /// The widest line in the navigation band is the contact name.
    ///
    /// The back button is excluded by position rather than by content: it is
    /// pinned to the leading edge and its label is whatever screen you came
    /// from, so it reads as "< Chats" in Telegram and "<12" in Messages, where
    /// the 12 is an unread badge. Both were returned as the sender before this
    /// filter existed.
    private static func navigationTitle(in page: Page) -> String? {
        page.lines
            .filter { $0.bottom >= Band.navigationBar && $0.top <= Band.statusBar }
            .filter { $0.box.minX >= Margin.left && !isStatusLike($0.text) }
            .max { $0.box.width < $1.box.width }
            .map { stripTrailingTime($0.text) }
    }

    /// A sender label often carries the time beside the name — "Tom Aldridge
    /// 9:30 AM". The name is the part worth keeping.
    private static func stripTrailingTime(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        while let last = words.last, isTimestamp(last) || last == "AM" || last == "PM" {
            words.removeLast()
        }
        return (words.isEmpty ? text : words.joined(separator: " "))
            .trimmingCharacters(in: .whitespaces)
    }

    private static func isStatusLike(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered == "online" || lowered == "active now" || lowered.hasPrefix("last seen")
            || lowered.hasPrefix("typing")
    }
}

/// A bubble timestamp is chrome; a time *inside* the message is not. The
/// difference is that the timestamp is a line of its own.
private func isTimestamp(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.count <= 8 else { return false }
    let digitsAndSeparators = CharacterSet(charactersIn: "0123456789:.AMPamp ")
    return !trimmed.isEmpty
        && trimmed.unicodeScalars.allSatisfy(digitsAndSeparators.contains)
        && trimmed.contains(":")
}
