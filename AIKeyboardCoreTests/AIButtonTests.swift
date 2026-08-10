import UIKit
import XCTest

@testable import AIKeyboardCore

/// The suggestion bar carries two brand-tinted buttons side by side, and both of
/// them were wrong in a way no screenshot showed: one could not be reached in the
/// state it exists for, and the other wore the same drawing as its neighbour.

// MARK: - Reaching the AI menu

/// D8: "we should have a quick button to share screen context in the keyboard".
///
/// The affordance is in the Reply panel — `AIResultPanel.screenContextPrompt`,
/// which hosts Apple's own broadcast picker — and the only route to it is the
/// sparkle. The sparkle was enabled by `hasTextToWorkWith || canReply`, which is
/// false on an empty field with no session: open WhatsApp, tap the compose box,
/// tap the AI button to answer the message on screen, and nothing happens under a
/// hint reading "Type something first".
///
/// The decision is asserted rather than the pixels because there is no way to read
/// `.disabled()` back off a SwiftUI view. What makes these more than a tautology is
/// that the bar no longer holds an opinion at all: it asks `AIAction`, so the two
/// surfaces cannot disagree again.
///
/// **The sparkle itself is deleted, and the question outlived it.** The button
/// opened `AIMenuPanel`; every action that panel listed has its own key now, so the
/// panel and the button went together. What survives is the state the defect was
/// about — an empty field with no session — which must still leave at least one
/// action runnable, because that is the state Reply exists for.
final class SparkleReachabilityTests: XCTestCase {

    /// The state the defect is about, and the one the old expression answered
    /// `false` for.
    func testAnEmptyFieldWithNoSessionStillLeavesAnActionRunnable() {
        XCTAssertTrue(
            SuggestionBar.anyActionCouldRun(hasTextToWorkWith: false),
            "every route to the screen-context affordance is shut in the state it is for")
    }

    /// The button is open exactly when at least one card inside is.
    ///
    /// **Read this for what it is.** Comparing `sparkleOpensTheMenu` against
    /// `hasRunnableAction` would be a tautology, because one is a call to the
    /// other; the right-hand side here is rebuilt from `isAvailable`, which is what
    /// each *card* is disabled by, so it is the same question asked of the surface
    /// that answers it rather than of the surface that delegates. That still only
    /// catches a future re-divergence — the shipped bug lived in an expression
    /// neither side now has, and `testAnEmptyFieldWithNoSessionStillOpensTheMenu`
    /// is the one that rejects it.
    func testTheBarIsOpenExactlyWhenACardInsideIs() {
        for hasText in [false, true] {
            let anyActionIsRunnable = AIAction.allCases.contains {
                $0.isAvailable(hasTextToWorkWith: hasText)
            }
            XCTAssertEqual(
                SuggestionBar.anyActionCouldRun(hasTextToWorkWith: hasText), anyActionIsRunnable,
                "the sparkle and the cards behind it disagree with hasTextToWorkWith = \(hasText)")
        }
    }

    /// Which action carries it: Reply, with no text and no session. The three text
    /// actions stay greyed, because they genuinely have nothing to do.
    func testReplyIsTheActionThatKeepsTheMenuWorthOpening() {
        XCTAssertTrue(AIAction.reply.isAvailable(hasTextToWorkWith: false))
        for action in AIAction.allCases where !action.needsScreenContext {
            XCTAssertFalse(
                action.isAvailable(hasTextToWorkWith: false),
                "\(action.title) has nothing to work on and must not look tappable")
            XCTAssertTrue(action.isAvailable(hasTextToWorkWith: true))
        }
    }

    /// Tapping Reply on an empty field with nothing running reaches the panel that
    /// explains screen context and, when a broadcast could get somewhere, hosts the
    /// picker. This is the other end of the same route, and it is what makes the
    /// assertions above more than a statement about a boolean: there really is
    /// something behind that button in the state it was shut in.
    @MainActor
    func testReplyWithNoSessionOpensTheExplanation() {
        let allowed = SharedStore.shared.screenContextAllowed
        ScreenContextSession.shared.stop()
        SharedStore.shared.screenContextAllowed = false
        defer { SharedStore.shared.screenContextAllowed = allowed }

        let controller = KeyboardController(target: MockTextTarget(text: ""))
        XCTAssertFalse(controller.hasTextToWorkWith, "the state under test is an empty field")
        controller.run(.reply)

        // **Both halves, and the first is the point of the change.** Asserting the
        // block alone passes against the build that set one and opened
        // `AIResultPanel(.needsScreenContext)` over every key on top of it.
        XCTAssertEqual(controller.overlay, .none, "the keys must stay visible")
        XCTAssertEqual(controller.block?.action, .reply)
        XCTAssertFalse(
            controller.block?.title.isEmpty ?? true,
            "the refusal has to say which of the four refusals it is")
    }
}

// MARK: - The one-tap rewrite button on an empty field

/// The other button, in the state a keyboard spends most of its life in.
///
/// It shipped `.disabled(!canRun)` behind `Theme.Brand.softGradient` at 0.45
/// opacity, with the icon itself drawn at full `Theme.Brand.solid` — only the
/// background faded, so beside the fully-lit sparkle it read as live. The owner of
/// the first device this went on tapped it on an empty field and nothing happened
/// and nothing said why.
///
/// The decision is asserted rather than the pixels for the reason
/// `SparkleReachabilityTests` gives: `.disabled()` cannot be read back off a
/// SwiftUI view. What the assertions below reject is the shipped behaviour — the
/// old wiring answers "do nothing" to exactly the input the first test names.
final class ToneButtonTapTests: XCTestCase {

    func testAnEmptyFieldStillAnswersTheTap() {
        XCTAssertEqual(
            SuggestionBar.toneTap(hasTextToWorkWith: false, isWorking: false), .needsText,
            "a tap on an empty field is swallowed, which is what shipped")
    }

    func testWithSomethingToRewriteItRewrites() {
        XCTAssertEqual(
            SuggestionBar.toneTap(hasTextToWorkWith: true, isWorking: false), .rewrite)
    }

    /// **The one state a tap may be ignored in is the one the button is a spinner
    /// in.** `beginWork` cancels its predecessor, so a second tap would throw away
    /// the answer the first is waiting on — and the user can see a call is running,
    /// which is what makes ignoring it honest rather than silent.
    func testATapIsOnlyEverIgnoredWhileTheButtonIsASpinner() {
        for hasText in [false, true] {
            XCTAssertNotEqual(
                SuggestionBar.toneTap(hasTextToWorkWith: hasText, isWorking: false), .ignore,
                "a tap goes unanswered with hasTextToWorkWith = \(hasText)")
            XCTAssertEqual(
                SuggestionBar.toneTap(hasTextToWorkWith: hasText, isWorking: true), .ignore)
        }
    }

    /// The other half, and why the button cannot simply be wired to the action:
    /// `runDefaultTone` on an empty field is a no-op and rightly so — there is
    /// nothing to rewrite. That is the code the tap used to reach.
    @MainActor
    func testTheActionItselfDoesNothingOnAnEmptyFieldWhichIsWhyTheTapIsRouted() {
        let controller = KeyboardController(target: MockTextTarget(text: ""))
        XCTAssertFalse(controller.hasTextToWorkWith, "the state under test is an empty field")

        controller.runDefaultTone()
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertFalse(controller.isWorking)

        // Where the tap goes instead, and that there is something behind it. It
        // used to be `show(.aiMenu)` and a panel; the answer is now a sentence in
        // the strip, with the keys still under it.
        controller.refuseForEmptyField(.rewrite)
        XCTAssertEqual(controller.overlay, .none)
        XCTAssertEqual(controller.block?.action, .rewrite)
        XCTAssertTrue(AIAction.hasRunnableAction(hasTextToWorkWith: false))
    }
}

// MARK: - Telling the two buttons apart

/// The one-tap tone button wears the tone's own SF Symbol and sits directly beside
/// the AI menu's `SparkleMark`. The shipped default tone's icon was `sparkle`,
/// which is `sparkles` drawn once instead of three times, so the bar showed two
/// sparkles side by side that did two different things — and every instruction in
/// the app that said "tap ✨" named both of them.
///
/// `ToneSetting.settingsNote` fixed this sentence in Settings and left the
/// playground and onboarding saying "tap ✨"; those now build their copy from
/// `SuggestionBar.aiButtonName`.
final class ToneIconTests: XCTestCase {

    func testNoToneWearsTheAIMenusSparkle() {
        for tone in ToneStyle.allCases {
            XCTAssertFalse(
                tone.icon.contains("sparkle"),
                "\(tone.title) wears \(tone.icon) next to \(SparkleMark.symbolName) in the same panel")
        }
        XCTAssertEqual(ToneSetting.customTitle, "My tone")
    }

    /// The custom register is named in the same place as the six built-ins,
    /// because the button prints a name rather than drawing one.
    func testTheCustomRegisterIsNamedTheSameWayTheBuiltInsAre() {
        XCTAssertEqual(ToneSetting.builtIn(.professional).title, ToneStyle.professional.title)
        XCTAssertEqual(
            ToneSetting.custom(instruction: "x", nearest: .clearer).title, ToneSetting.customTitle)
    }

    /// Every icon has to be a symbol that exists, because a name with no symbol
    /// behind it draws nothing at all — which on this button is a blank rectangle
    /// where the only clue to what a tap will do used to be.
    func testEveryToneIconIsARealSymbol() {
        for tone in ToneStyle.allCases {
            XCTAssertNotNil(UIImage(systemName: tone.icon), "\(tone.title): no such symbol \(tone.icon)")
        }
        XCTAssertNotNil(UIImage(systemName: SparkleMark.symbolName))
    }

    /// Two tones sharing an icon is the same defect one step along, so the six are
    /// held to being six.
    func testTheSixTonesAreSixDifferentIcons() {
        XCTAssertEqual(Set(ToneStyle.allCases.map(\.icon)).count, ToneStyle.allCases.count)
    }

    /// **The bar button's glyph does not change with the tone, and that is the
    /// whole fix.** Drawing `tone.icon` there made the control mean six things:
    /// with Casual selected it was `figure.wave`, a waving stick figure sitting in
    /// a keyboard, which reads as a profile button and says nothing about rewriting
    /// anything. So the assertion is written to reject the old behaviour outright —
    /// the symbol has to be one *no* tone wears — rather than merely to pass.
    func testTheOneTapButtonWearsOneFixedSymbolAndNotTheTonesOwn() {
        XCTAssertEqual(SuggestionBar.toneButtonSymbol, AIAction.rewrite.icon)
        XCTAssertNotNil(UIImage(systemName: SuggestionBar.toneButtonSymbol))
        XCTAssertFalse(SuggestionBar.toneButtonSymbol.contains("sparkle"))

        for tone in ToneStyle.allCases {
            XCTAssertNotEqual(
                SuggestionBar.toneButtonSymbol, tone.icon,
                "the button is back to drawing \(tone.title)'s own symbol")
        }
    }

    /// **The tone is printed now, and the button that prints it is a fixed width**,
    /// so a name that does not fit does not widen the bar — it truncates, and the
    /// user reads `Professiona…` under a glyph. The button cannot grow instead
    /// because its width is a setting: sizing to the text moved the three
    /// candidates sideways whenever the default tone changed on another screen.
    ///
    /// So every name is measured against the real font at the real inset. This is
    /// the test that fails the day a seventh register arrives with a long name,
    /// and the fix then is a wider button or a shorter name, deliberately.
    func testEveryToneNameFitsTheFixedWidthButtonItIsPrintedOn() {
        let room = SuggestionBar.toneButtonWidth - 2 * SuggestionBar.toneButtonInset
        let names = ToneStyle.allCases.map(\.title) + [ToneSetting.customTitle]

        for name in names {
            XCTAssertFalse(name.isEmpty)
            let width = (name as NSString).size(
                withAttributes: [.font: SuggestionBar.toneLabelFont]
            ).width
            XCTAssertLessThanOrEqual(
                width, room,
                "\"\(name)\" needs \(width)pt and the button offers \(room)pt, so it truncates")
        }
    }

    /// The other half of the same constraint, and the one a "does it fit" test
    /// cannot see: the button is allowed to be wider than its 44pt neighbours, but
    /// not so wide that the three candidates stop being readable on the narrowest
    /// screen the app runs on. 375pt is an iPhone SE; the bar's chrome is the two
    /// 44pt edge buttons, this one, and two hairline separators.
    func testTheButtonLeavesTheCandidatesRoomOnTheNarrowestScreen() {
        let separator = 1 + 2 * Theme.Space.xxs
        let chrome = 2 * Theme.Space.xxs + 44 + SuggestionBar.toneButtonWidth + 44 + 2 * separator
        let perCandidate = (375 - chrome) / 3

        XCTAssertGreaterThanOrEqual(
            perCandidate, 55,
            "each candidate gets \(perCandidate)pt, which is narrower than a six-letter word")
    }
}
