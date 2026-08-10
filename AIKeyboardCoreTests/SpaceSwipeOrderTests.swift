import XCTest

@testable import AIKeyboardCore

// MARK: - A slide to a language

final class SpaceSwipeOrderTests: XCTestCase {

    private let two: [KeyboardLanguage] = [.english, .hebrew]
    private let three: [KeyboardLanguage] = [.english, .hebrew, .arabic]
    /// A long enabled list, and deliberately not the whole catalogue any more.
    /// `KeyboardLanguage.allCases` is sixty-four keyboards and nobody turns on
    /// sixty-four; this is the shape of a list a heavy user builds, which is what
    /// the gesture is measured against.
    private let many = Array(KeyboardLanguage.allCases.prefix(14))

    func testATapMovesNothing() {
        XCTAssertEqual(SpaceSwipe.places(translation: 6, languageCount: 2), 0)
        XCTAssertNil(SpaceSwipe.destination(from: .english, in: two, translation: 6))
    }

    /// Direction is the whole point of a directional gesture: right is forwards
    /// through the user's own order, left is backwards.
    func testRightIsForwardsAndLeftIsBackwards() {
        XCTAssertEqual(SpaceSwipe.destination(from: .hebrew, in: three, translation: 40), .arabic)
        XCTAssertEqual(SpaceSwipe.destination(from: .hebrew, in: three, translation: -40), .english)
    }

    /// **The right-to-left decision, stated as the property that decides it.**
    /// Hebrew, Arabic and Persian mirror the letters plane, and it is tempting to
    /// mirror this gesture with them. Doing so would make one right swipe move
    /// forwards from English and *backwards* from Hebrew, so two identical swipes
    /// would go English → Hebrew → English and the rest of the list could never be
    /// reached by repeating the gesture. The enabled list has one order and does
    /// not flip; neither does the swipe.
    func testTheSameSwipeKeepsMovingForwardsOnARightToLeftKeyboard() {
        let first = SpaceSwipe.destination(from: .english, in: three, translation: 40)
        XCTAssertEqual(first, .hebrew)

        let second = SpaceSwipe.destination(from: .hebrew, in: three, translation: 40)
        XCTAssertEqual(
            second, .arabic,
            """
            The second identical swipe went back to \(second?.displayName ?? "nowhere") — a mirrored \
            gesture oscillates between two languages and leaves the rest of the list unreachable.
            """)
    }

    // MARK: One slide, one language

    /// **The defect this replaced a working gesture to fix.** Travel used to carry
    /// the count: past `activation` every further `step` points was another
    /// language, so a 60-point flick moved one place and the same flick at 140
    /// moved three. Nothing said which before the finger lifted, so the enabled
    /// list was not an order the user could walk. Distance is a threshold now and
    /// nothing else, which is what the sweep below measures.
    func testHowFarTheFingerTravelsChangesNothingOnceTheSlideCounts() {
        for enabled in [two, three, many, KeyboardLanguage.allCases] {
            for points in stride(from: Double(SpaceSwipe.activation), through: 2000.0, by: 1.0) {
                let places = SpaceSwipe.places(
                    translation: CGFloat(points), languageCount: enabled.count)
                XCTAssertEqual(
                    places, 1,
                    "A \(Int(points))-point slide across \(enabled.count) languages moved \(places)")
            }
        }
    }

    /// The property the whole change is for: repeating one gesture walks the
    /// user's own list, in their own order, and comes back round to where it
    /// started after exactly as many slides as they have languages.
    func testRepeatingTheSlideWalksTheListInOrder() {
        var landed = KeyboardLanguage.english
        var walked: [KeyboardLanguage] = []
        for _ in many {
            landed = SpaceSwipe.destination(from: landed, in: many, translation: 90) ?? landed
            walked.append(landed)
        }

        XCTAssertEqual(
            walked, Array(many.dropFirst()) + [.english],
            "Fourteen identical slides did not walk the fourteen enabled languages once each")

        // And the same list backwards, so a slide the wrong way is one slide to
        // undo rather than a hunt.
        for _ in many {
            landed = SpaceSwipe.destination(from: landed, in: many, translation: -90) ?? landed
            walked.removeLast()
            XCTAssertEqual(landed, walked.last ?? .english)
        }
    }

    /// **The strip of codes on the space bar is a promise, and it used to be one
    /// the gesture did not keep.** `codeStrip` draws the neighbour either side of
    /// the lit code; a distance-scrubbed slide landed several places past it, so
    /// the key advertised a language the swipe skipped. They are the same answer
    /// now, and this is what says so.
    func testTheStripPromisesExactlyWhereTheSlideLands() {
        for active in many {
            let strip = SpaceSwipe.codeStrip(active: active, in: many)
            XCTAssertEqual(strip.count, 3)

            for points in [SpaceSwipe.activation, 90, 200, 600] as [CGFloat] {
                XCTAssertEqual(
                    SpaceSwipe.destination(from: active, in: many, translation: points), strip[2],
                    "From \(active.displayName) the key promised \(strip[2].displayName) to the right")
                XCTAssertEqual(
                    SpaceSwipe.destination(from: active, in: many, translation: -points), strip[0],
                    "From \(active.displayName) the key promised \(strip[0].displayName) to the left")
            }
        }
    }

    // MARK: Ends of the list

    func testTwoLanguagesSwitchOnTheShortestSlideThereIs() {
        XCTAssertEqual(
            SpaceSwipe.destination(
                from: .english, in: two, translation: SpaceSwipe.activation),
            .hebrew)
    }

    /// With two languages every slide, however enthusiastic, means the other one.
    func testALongSlideAcrossTwoLanguagesStillMeansTheOtherOne() {
        XCTAssertEqual(SpaceSwipe.destination(from: .english, in: two, translation: 400), .hebrew)
        XCTAssertEqual(SpaceSwipe.destination(from: .hebrew, in: two, translation: 400), .english)
    }

    func testOneLanguageHasNowhereToGo() {
        XCTAssertEqual(SpaceSwipe.places(translation: 300, languageCount: 1), 0)
        XCTAssertNil(SpaceSwipe.destination(from: .english, in: [.english], translation: 300))
        XCTAssertNil(SpaceSwipe.destination(from: .english, in: [], translation: 300))
    }

    /// A slide never lands back on the language it started from, however long it
    /// is — which a single step gets for free and the distance version had to cap
    /// for, because 5000 points was 270 raw steps and 270 wraps to 0 of 3.
    func testASlideNeverLandsBackWhereItStarted() {
        for points in stride(from: Double(SpaceSwipe.activation), through: 2000.0, by: 1.0) {
            for enabled in [two, three, many, KeyboardLanguage.allCases] {
                for direction in [1.0, -1.0] {
                    let destination = SpaceSwipe.destination(
                        from: .english, in: enabled, translation: CGFloat(points * direction))
                    XCTAssertNotEqual(
                        destination, .english,
                        "A \(Int(points))-point slide across \(enabled.count) languages wrapped back to English"
                    )
                }
            }
        }
    }

    /// The far end of a long list is reached by repeating the gesture rather than
    /// by one long sweep, and the globe key steps the same way — so the two agree
    /// and neither strands a language.
    func testEveryEnabledLanguageIsReachableByRepeatingTheSlide() {
        var landed = KeyboardLanguage.english
        var reached: Set<KeyboardLanguage> = [landed]
        for _ in KeyboardLanguage.allCases {
            landed =
                SpaceSwipe.destination(
                    from: landed, in: KeyboardLanguage.allCases, translation: 60) ?? landed
            reached.insert(landed)
        }

        XCTAssertEqual(
            reached, Set(KeyboardLanguage.allCases),
            "\(Set(KeyboardLanguage.allCases).subtracting(reached).count) languages were unreachable")
    }
}
