import XCTest

@testable import AIKeyboardCore

/// The picker used to name a register and leave the user to imagine it.
/// These assertions fail if a tone ships without a sample, if two tones share
/// a sample, or if Shorter is not actually shorter than Casual.
final class TonePreviewTests: XCTestCase {

    func testEveryToneHasACaptionAndBothSamples() {
        for tone in ToneStyle.allCases {
            XCTAssertFalse(
                tone.previewCaption.isEmpty, "\(tone.title) has no caption")
            XCTAssertFalse(
                tone.previewEnglish.isEmpty, "\(tone.title) has no English sample")
            XCTAssertFalse(
                tone.previewHebrew.isEmpty, "\(tone.title) has no Hebrew sample")
        }
    }

    func testTheSixEnglishSamplesAreAllDifferent() {
        let samples = ToneStyle.allCases.map(\.previewEnglish)
        XCTAssertEqual(
            Set(samples).count, ToneStyle.allCases.count,
            "two tones share an English sample: \(samples)")
    }

    func testTheSixHebrewSamplesAreAllDifferent() {
        let samples = ToneStyle.allCases.map(\.previewHebrew)
        XCTAssertEqual(
            Set(samples).count, ToneStyle.allCases.count,
            "two tones share a Hebrew sample: \(samples)")
    }

    func testEveryHebrewSampleContainsAHebrewLetter() {
        let hebrew: ClosedRange<UInt32> = 0x0590...0x05FF
        for tone in ToneStyle.allCases {
            let hasHebrew = tone.previewHebrew.unicodeScalars.contains {
                hebrew.contains($0.value)
            }
            XCTAssertTrue(
                hasHebrew,
                "\(tone.title) Hebrew sample has no Hebrew letter: \(tone.previewHebrew)")
        }
    }

    func testCaptionsDoNotWearASparkle() {
        for tone in ToneStyle.allCases {
            XCTAssertFalse(
                tone.previewCaption.contains("✦"),
                "\(tone.title) caption wears ✦: \(tone.previewCaption)")
            XCTAssertFalse(
                tone.previewCaption.contains("✨"),
                "\(tone.title) caption wears ✨: \(tone.previewCaption)")
        }
    }

    func testShorterEnglishHasFewerWordsThanCasual() {
        let shorter = wordCount(ToneStyle.shorter.previewEnglish)
        let casual = wordCount(ToneStyle.casual.previewEnglish)
        XCTAssertLessThan(
            shorter, casual,
            "Shorter (\(shorter) words) does not teach against Casual (\(casual) words)")
    }

    func testEveryEnglishSampleKeepsTheLunchAsk() {
        for tone in ToneStyle.allCases {
            let sample = tone.previewEnglish.lowercased()
            let keepsAsk =
                sample.contains("lunch") || sample.contains("12") || sample.contains("tomorrow")
            XCTAssertTrue(
                keepsAsk,
                "\(tone.title) drifted off the meeting request: \(tone.previewEnglish)")
        }
    }

    private func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
