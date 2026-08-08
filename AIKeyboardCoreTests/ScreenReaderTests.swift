import CoreGraphics
import Vision
import XCTest

@testable import AIKeyboardCore

/// Pins the constraint the whole screen-context design is built around.
///
/// If one of these ever fails because Apple shipped Hebrew recognition, that is
/// not a broken test — it is permission to delete most of `CloudScreenReader`'s
/// reason for existing, and `README.md` and `RoutedScreenReader` both need
/// revisiting with it.
final class VisionLanguageTests: XCTestCase {

    func testVisionCannotRecognizeHebrew() throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let languages = try request.supportedRecognitionLanguages()

        XCTAssertFalse(
            languages.contains { $0.lowercased().hasPrefix("he") },
            """
            Vision now lists Hebrew. The routing in RoutedScreenReader exists \
            only because it did not: \(languages)
            """)
    }

    /// Not a right-to-left limitation, which is worth pinning separately so
    /// nobody "fixes" the router by assuming RTL is the problem.
    func testVisionDoesRecognizeArabic() throws {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let languages = try request.supportedRecognitionLanguages()

        XCTAssertTrue(languages.contains { $0.lowercased().hasPrefix("ar") })
    }
}

final class CloudScreenReaderParsingTests: XCTestCase {

    func testParsesAReading() {
        let reading = CloudScreenReader.parse([
            "sender": "שרה כהן - עבודה",
            "message": "מעולה. אז אנחנו סוגרים על פגישה ביום שלישי ב-10:30 במשרד?",
            "script": "hebrew",
            "language": "hebrew"
        ])

        XCTAssertEqual(reading?.sender, "שרה כהן - עבודה")
        XCTAssertEqual(reading?.language, .hebrew)
        XCTAssertEqual(reading?.scripts, [.hebrew])
    }

    /// The model reporting nothing is an answer, not a failure: the newest
    /// incoming message was a voice note, and replying to the text above it
    /// would answer something the user already answered.
    func testEmptyMessageIsNothingToReplyTo() {
        XCTAssertNil(CloudScreenReader.parse([:]))
        XCTAssertNil(CloudScreenReader.parse(["sender": "Priya Raman", "message": "  "]))
    }

    /// The two questions disagree on exactly the sentences this product exists
    /// for, so the model's `language` is trusted over a fresh character count.
    func testCodeSwitchedMessageOpensTheHebrewKeyboard() {
        let reading = CloudScreenReader.parse([
            "message": "מעולה. רוצה לעבור על ה-architecture לפני שאנחנו מתחילים?",
            "script": "mixed",
            "language": "hebrew"
        ])

        XCTAssertEqual(reading?.language, .hebrew)
        XCTAssertEqual(reading?.scripts, [.hebrew, .latin])
    }

    /// A backend that answers without a language field still has to route.
    func testFallsBackToScriptWhenLanguageIsMissing() {
        XCTAssertEqual(CloudScreenReader.parse(["message": "שלום"])?.language, .hebrew)
        XCTAssertEqual(CloudScreenReader.parse(["message": "hello"])?.language, .english)
    }
}

final class VisionScreenReaderGeometryTests: XCTestCase {

    /// Vision's coordinates: origin bottom left, so a larger y is further up.
    private func line(
        _ text: String, x: Double, width: Double, y: Double, height: Double = 0.02
    ) -> VisionScreenReader.Line {
        VisionScreenReader.Line(
            text: text,
            box: CGRect(x: x, y: y, width: width, height: height),
            confidence: 1)
    }

    func testSideIsReadFromMarginsNotFromTheCentre() {
        // A one-sided layout: every line starts at the same leading margin and
        // the long one crosses the middle of the screen. Judging by centre
        // called this outgoing, which was wrong on every Slack screen.
        let bubbles = VisionScreenReader.group([
            line("Anyone still merging into main this morning?", x: 0.15, width: 0.74, y: 0.63)
        ])

        XCTAssertEqual(bubbles.count, 1)
        XCTAssertFalse(bubbles[0].isOutgoing)
    }

    func testOutgoingBubbleReachesTheTrailingMargin() {
        let bubbles = VisionScreenReader.group([
            line("Thanks for writing it up. Two years is a", x: 0.25, width: 0.70, y: 0.337),
            line("lot to commit to.", x: 0.25, width: 0.31, y: 0.312)
        ])

        XCTAssertEqual(bubbles.count, 1, "adjacent lines are one bubble")
        XCTAssertTrue(bubbles[0].isOutgoing)
    }

    /// A short final line hugs no margin at all. Deciding side per bubble rather
    /// than per line is what keeps it attached to its own sentence.
    func testShortTrailingLineStaysWithItsBubble() {
        let bubbles = VisionScreenReader.group([
            line("Good. I will look at the numbers", x: 0.25, width: 0.58, y: 0.199),
            line("tonight.", x: 0.25, width: 0.14, y: 0.171)
        ])

        XCTAssertEqual(bubbles[0].text, "Good. I will look at the numbers tonight.")
    }

    /// A bubble timestamp is chrome. A time inside the message is not, and the
    /// difference is that the timestamp is a line of its own.
    func testBubbleTimestampIsDroppedButATimeInTheTextIsKept() {
        let bubbles = VisionScreenReader.group([
            line("Can you sanity check the numbers", x: 0.04, width: 0.63, y: 0.128),
            line("before I reply to them on Thursday?", x: 0.04, width: 0.64, y: 0.103),
            line("9:03", x: 0.69, width: 0.06, y: 0.081)
        ])

        XCTAssertEqual(
            bubbles[0].text,
            "Can you sanity check the numbers before I reply to them on Thursday?")

        let withTime = VisionScreenReader.group([
            line("shall we say 10:30 at the office?", x: 0.04, width: 0.60, y: 0.128)
        ])
        XCTAssertTrue(withTime[0].text.contains("10:30"))
    }

    /// Slack and mail threads print every message against the same margin, so
    /// there is no geometry left to say who sent what. Refusing routes it to
    /// the cloud instead of putting the wrong name on a reply.
    func testOneSidedLayoutIsRefused() {
        let oneSided = VisionScreenReader.group([
            line("Ana Delgado", x: 0.15, width: 0.36, y: 0.66),
            line("Anyone still merging into main?", x: 0.15, width: 0.74, y: 0.635)
        ])
        XCTAssertFalse(VisionScreenReader.isTwoSided(oneSided))

        let twoSided = VisionScreenReader.group([
            line("Right, here it is.", x: 0.04, width: 0.36, y: 0.673),
            line("Go ahead, I'm reading.", x: 0.42, width: 0.54, y: 0.717)
        ])
        XCTAssertTrue(VisionScreenReader.isTwoSided(twoSided))
    }
}
