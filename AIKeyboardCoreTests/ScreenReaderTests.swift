import CoreGraphics
import Speech
import Vision
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

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

/// The third of the three places Apple's on-device stack has no Hebrew — and,
/// until this file, the only one nothing checked.
///
/// `README.md` and `Bar/dictation/README.md` have both asserted "30 locales, none
/// of them `he`" in prose since dictation was measured. `grep -r SpeechTranscriber
/// --include=*.swift` returned nothing: no shipping code and no test anywhere in
/// the repo touched the API, the thirty were described by pattern rather than
/// enumerated, and the reading was taken on macOS rather than here. A number that
/// can only be re-checked by hand is a number that drifts, and two of this repo's
/// prose figures had already drifted before anyone noticed.
///
/// Same standing instruction as `VisionLanguageTests`: a failure here is not a
/// broken test. It is permission to revisit `CloudDictation`, because the reason
/// every transcription in this product is a network call would have gone away —
/// an on-device Hebrew transcriber is the one thing that would make the
/// recording never leave the phone.
///
/// **And writing it turned up why nobody had: the iOS Simulator answers with an
/// empty list.** `SpeechTranscriber.supportedLocales` returns *zero* locales here
/// — the speech assets are simply not installed in the runtime — so the
/// "30 locales, none of them `he`" reading in `README.md` was necessarily taken on
/// macOS, and this bar cannot confirm or refute it. That is worth a skip rather
/// than a silent pass: an empty list satisfies "does not contain Hebrew"
/// perfectly, and a green test asserting nothing is worse than no test, because
/// it looks like evidence. The same trap as `availability == .available` on a
/// simulator that then throws `ModelManagerError 1026`.
final class SpeechLanguageTests: XCTestCase {

    /// The locales, or an explicit refusal to pretend. Returns nil after
    /// skipping, so each test reads as one straight line.
    private func supportedLocales() async throws -> [String] {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("SpeechTranscriber is iOS 26; this deployment predates it")
        }
        let identifiers = await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
        guard !identifiers.isEmpty else {
            throw XCTSkip(
                """
                SpeechTranscriber lists no locales at all here, which is a property of \
                the simulator runtime rather than an answer about Hebrew. Run this on a \
                device to settle README.md's "30 locales, none of them he".
                """)
        }
        return identifiers
    }

    func testSpeechTranscriberCannotTranscribeHebrew() async throws {
        let identifiers = try await supportedLocales()
        XCTAssertFalse(
            identifiers.contains { $0.lowercased().hasPrefix("he") },
            """
            SpeechTranscriber now lists Hebrew. Dictation is mocked partly because \
            it did not: \(identifiers)
            """)
    }

    /// The locale list itself, recorded rather than asserted.
    ///
    /// Deliberately not pinned by count, for the reason `VisionLanguageTests` does
    /// not pin Vision's thirty either: a count is the part of a claim most likely
    /// to move for reasons nobody cares about, and this repo has had three prose
    /// counts go stale already. Printing it means one run of the suite on a device
    /// enumerates the thirty that `Bar/dictation/README.md` only describes by
    /// pattern.
    func testTheSupportedLocalesAreOnTheRecord() async throws {
        let identifiers = try await supportedLocales()
        print("SpeechTranscriber.supportedLocales (\(identifiers.count)): \(identifiers)")
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

    /// **The fallback used to answer `.english` for every script that was not
    /// Hebrew, and an Arabic screen came back "reply in English".** This is the
    /// half of the widening that works whatever the model says, because it is
    /// reached whenever the model does not say `hebrew` or `english` — which is
    /// every answer the current prompt can produce for a screen in a third
    /// script, since the prompt only offers it those two words.
    func testAThirdScriptIsNoLongerCalledEnglish() {
        XCTAssertEqual(CloudScreenReader.parse(["message": "مرحبا كيف حالك"])?.language, .arabic)
        XCTAssertEqual(CloudScreenReader.parse(["message": "привет как дела"])?.language, .russian)
        XCTAssertEqual(CloudScreenReader.parse(["message": "Καλημέρα"])?.language, .greek)
        XCTAssertEqual(CloudScreenReader.parse(["message": "नमस्ते"])?.language, .hindi)
        // And the model's own word is taken when it volunteers one, which is the
        // half that needs the prompt widened before it can ever fire.
        XCTAssertEqual(
            CloudScreenReader.parse(["message": "مرحبا", "language": "persian"])?.language, .persian)
    }

    /// **The English and Hebrew answers are the ones that must not have moved**,
    /// because `Bar/screen-context/cloud_outputs.json` was recorded against them
    /// and `ScreenContextBarTests` replays it. Every value the prompt can produce,
    /// against a message in each script the corpus contains.
    func testEnglishAndHebrewParseExactlyAsTheyDidBefore() {
        let messages = ["hello there", "שלום", "מעולה, ראית את ה-deck?", "123 😅"]
        let answers = ["hebrew", "english", "mixed", "", "Hebrew", "latin"]
        for message in messages {
            for answer in answers {
                let expected: KeyboardLanguage =
                    switch answer {
                    case "hebrew": .hebrew
                    case "english": .english
                    default: LanguageDetector.scripts(in: message).contains(.hebrew) ? .hebrew : .english
                    }
                XCTAssertEqual(
                    CloudScreenReader.parse(["message": message, "language": answer])?.language,
                    expected,
                    "\(message) / \(answer) parses differently from the build the corpus was recorded against"
                )
            }
        }
    }

    /// The rule both readers share. Latin is not evidence of a language, and the
    /// catalogue's order is what keeps Hebrew winning over Arabic in a message
    /// that somehow carries both.
    func testTheKeyboardThatAnswersIsPickedOffTheCatalogue() {
        XCTAssertEqual(KeyboardLanguage.answering([.latin]), .english)
        XCTAssertEqual(KeyboardLanguage.answering([]), .english)
        XCTAssertEqual(KeyboardLanguage.answering([.other]), .english)
        XCTAssertEqual(KeyboardLanguage.answering([.latin, .hebrew]), .hebrew)
        XCTAssertEqual(KeyboardLanguage.answering([.hebrew, .arabic]), .hebrew)
        XCTAssertEqual(KeyboardLanguage.answering([.latin, .arabic]), .arabic)
        XCTAssertEqual(KeyboardLanguage.answering([.cyrillic]), .russian)
        XCTAssertEqual(KeyboardLanguage.answering([.devanagari]), .hindi)
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

    /// A readable two-sided conversation, built out of lines rather than pixels,
    /// so `interpret` can be asked what it does with a page the gate already
    /// trusted. Coverage and confidence are handed in at 1: this exercises the
    /// mapping, and the gate itself is measured against `Bar/screen-context/` by
    /// `ScreenContextBarTests`, which is deliberately untouched here.
    private func page(_ incoming: String) -> VisionScreenReader.Page {
        VisionScreenReader.Page(
            lines: [
                line("Sent it over.", x: 0.42, width: 0.54, y: 0.717),
                line(incoming, x: 0.04, width: 0.60, y: 0.63)
            ],
            coverage: 1,
            meanConfidence: 1)
    }

    /// **Arabic was refused on device for no reason.** Vision's 30 recognition
    /// languages include Arabic — `VisionLanguageTests` pins that — so a screen it
    /// read at full coverage and confidence is answerable, and the Latin-or-Hebrew
    /// test above it threw the reading away as "nothing to reply to". The keyboard
    /// that opens has to be Arabic too: a build that widens the guard and leaves
    /// the mapping alone answers an Arabic message in English.
    func testAnArabicScreenIsReadRatherThanDiscarded() throws {
        let reading = try XCTUnwrap(
            VisionScreenReader.interpret(page("هل يمكنك مراجعة الملف؟")),
            "an Arabic screen this recogniser read perfectly was dropped")
        XCTAssertEqual(reading.message, "هل يمكنك مراجعة الملف؟")
        XCTAssertEqual(reading.language, .arabic)
        XCTAssertEqual(reading.scripts, [.arabic])
    }

    /// The two the corpus is scored on, unchanged.
    func testEnglishAndHebrewStillMapTheWayTheyDid() throws {
        XCTAssertEqual(
            try VisionScreenReader.interpret(page("Can you take the standup?"))?.language, .english)
        XCTAssertEqual(try VisionScreenReader.interpret(page("אפשר להזיז את הפגישה?"))?.language, .hebrew)
        XCTAssertEqual(
            try VisionScreenReader.interpret(page("ראית את ה-deck?"))?.language, .hebrew,
            "a code-switched message answers in Hebrew")
    }

    /// And the reason the guard existed in the first place still holds: a voice
    /// note's waveform recognises as glyph soup, and there is nothing to reply to.
    func testAWaveformIsStillNothingToReplyTo() throws {
        XCTAssertNil(try VisionScreenReader.interpret(page("▶・二二ー・リリーー 0:47")))
        XCTAssertNil(try VisionScreenReader.interpret(page("0:47")))
    }
}
