import XCTest

@testable import AIKeyboardCore

// MARK: - Saying the gesture is there

/// **A gesture nobody can find is a gesture nobody has.** The swipe worked from
/// the day it shipped and the owner of the first phone it went on had to be told
/// it existed: the space bar was captioned "space" — "רווח" in Hebrew — and
/// nothing else on the keyboard mentioned it. `announceLanguage` names the
/// language for 1.4s *after* a switch and `LanguageCallout` names it *during* a
/// slide, and both of those are feedback for somebody who already knows.
final class SpaceBarAffordanceTests: XCTestCase {

    /// The state the owner was in: two languages, finger nowhere near the key. The
    /// strip has to name the language that is on **and** the one that is not, which
    /// is the half the first fix missed — a caption reading "עברית" says where you
    /// are and nothing about where the chevrons go.
    func testAtTwoLanguagesTheSpaceBarNamesBothAndSaysItSlides() {
        let strip = SpaceSwipe.codeStrip(active: .hebrew, in: [.english, .hebrew])
        XCTAssertEqual(strip, [.english, .hebrew])
        XCTAssertEqual(strip.map { $0.shortName }, ["EN", "עב"])
        XCTAssertTrue(SpaceSwipe.showsSlideAffordance(languageCount: 2))
        XCTAssertFalse(SpaceSwipe.slideHint(languageCount: 2).isEmpty)
    }

    /// With one language there is nowhere to slide, so the strip and the chevrons
    /// both go and the key is a plain space bar. An affordance for a gesture that
    /// cannot move is worse than none.
    func testWithOneLanguageItIsAnOrdinarySpaceBar() {
        for language in [KeyboardLanguage.hebrew, .english] {
            XCTAssertEqual(SpaceSwipe.codeStrip(active: language, in: [language]), [])
        }
        XCTAssertEqual(SpaceSwipe.codeStrip(active: .english, in: []), [])
        XCTAssertFalse(SpaceSwipe.showsSlideAffordance(languageCount: 1))
        XCTAssertEqual(SpaceSwipe.slideHint(languageCount: 1), "")
    }

    /// Two and three fit whole, so nothing is hidden and the order is the order a
    /// slide moves through.
    func testUpToThreeLanguagesAreAllPrinted() {
        let three: [KeyboardLanguage] = [.english, .hebrew, .french]
        for active in three {
            XCTAssertEqual(
                SpaceSwipe.codeStrip(active: active, in: three), three,
                "at three languages the strip should be the whole list")
        }
    }

    /// **Past three the strip is a window, and the property that matters is that it
    /// is the window the gesture actually moves to** — asked of `language`, which
    /// is the code that moves it, rather than of a second copy of the arithmetic.
    /// A strip that named a neighbour a swipe does not reach would be a worse lie
    /// than no strip at all.
    func testPastThreeTheStripIsTheNeighboursTheGestureReaches() {
        let enabled: [KeyboardLanguage] = [.english, .hebrew, .french, .german, .greek]
        for active in enabled {
            let strip = SpaceSwipe.codeStrip(active: active, in: enabled)
            XCTAssertEqual(strip.count, 3, "\(active) got a strip of \(strip.count)")
            XCTAssertEqual(
                strip[0], SpaceSwipe.language(from: active, in: enabled, places: -1),
                "the left code is not where a left swipe from \(active) lands")
            XCTAssertEqual(
                strip[1], active, "the lit code is not the language in use at \(active)")
            XCTAssertEqual(
                strip[2], SpaceSwipe.language(from: active, in: enabled, places: 1),
                "the right code is not where a right swipe from \(active) lands")
        }
    }

    /// Every language ships a code short enough to sit two or three abreast on a
    /// key that is a little over half the keyboard wide. Nothing enforces this in
    /// the catalogue, and one long entry would push the strip into
    /// `minimumScaleFactor` and shrink the whole row.
    func testEveryLanguageCodeIsShortEnoughToPrintThreeAbreast() {
        for language in KeyboardLanguage.allCases {
            XCTAssertFalse(language.shortName.isEmpty, "\(language.rawValue) has no short name")
            XCTAssertLessThanOrEqual(
                language.shortName.count, 3,
                "\(language.rawValue) prints \(language.shortName) on the space bar")
        }
    }

    /// **The chevrons and the gesture have to agree at every list length**, or the
    /// keyboard is either promising a slide that does nothing or hiding one that
    /// works. `places` is the code that actually moves the language, asked with a
    /// travel far past `activation`, so this is the affordance checked against the
    /// behaviour rather than against itself.
    func testTheAffordanceAppearsExactlyWhenTheGestureCanMove() {
        for count in 0...KeyboardLanguage.allCases.count {
            let moves =
                SpaceSwipe.places(translation: SpaceSwipe.activation + 300, languageCount: count) != 0
            XCTAssertEqual(
                SpaceSwipe.showsSlideAffordance(languageCount: count), moves,
                "\(count) enabled languages: the space bar and the gesture disagree")
        }
    }
}
