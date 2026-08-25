import SwiftUI
import XCTest

@testable import AIKeyboardCore

/// Landscape iPhone geometry — NIT-18. Every assertion here has a portrait
/// counterpart it must not disturb: none of these numbers existed before this
/// file, so the load-bearing checks are the ones that pin *portrait* still
/// answering exactly what it answered before `orientation:` was added anywhere.
final class LandscapeGeometryTests: XCTestCase {

    // MARK: Portrait is untouched

    /// The exact figure `LayoutValidator.screenContextHeightLimit` and
    /// `CustomLayoutTests.testTheShippedLayoutStillFitsUnderTheFingerprintCliff`
    /// hold the shipped default to: 58 (banner) + 36 (suggestion bar) + 271 (key
    /// area) = 365, three points under the 368pt cliff. A build that let the new
    /// `orientation` parameter's default silently drift, or that routed portrait
    /// through the landscape branch by mistake, answers 166 here instead — see
    /// `testLandscapeTotalHeightIsExact` below — so this rejects both.
    func testPortraitTotalHeightIsExactAndUnaffectedByTheOrientationParameter() {
        XCTAssertEqual(Theme.Metrics.totalHeight(for: .default), 365, accuracy: 0.001)
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, orientation: .portrait), 365, accuracy: 0.001)
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, showsBanner: true, orientation: .portrait),
            Theme.Metrics.totalHeight(for: .default, showsBanner: true), accuracy: 0.001)
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, showsBanner: false, orientation: .portrait),
            Theme.Metrics.totalHeight(for: .default, showsBanner: false), accuracy: 0.001)
    }

    /// Same figure, one level down: the key area alone, with the banner and
    /// suggestion bar stripped off.
    func testPortraitKeyAreaHeightIsExactAndUnaffectedByTheOrientationParameter() {
        XCTAssertEqual(Theme.Metrics.keyAreaHeight(for: .default), 271, accuracy: 0.001)
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: .default, orientation: .portrait), 271, accuracy: 0.001)
        XCTAssertEqual(Theme.Metrics.keyAreaHeight, 271, accuracy: 0.001)
    }

    /// A roomy portrait layout — both optional rows on, keys at the top of the
    /// editor's range — must answer the same whether or not `orientation:` is
    /// spelled out, so a caller that forgot to pass it through still gets
    /// portrait rather than silently falling back to some other default.
    func testPortraitStillAnswersForANonDefaultLayoutRegardlessOfTheOrientationParameter() {
        var roomy = KeyboardCustomization.default
        roomy.showsNumberRow = true
        roomy.geometry.keyHeight = LayoutGeometry.keyHeightRange.upperBound
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: roomy),
            Theme.Metrics.totalHeight(for: roomy, orientation: .portrait), accuracy: 0.001)
    }

    // MARK: Landscape actually changes something

    /// Before this ticket there was no orientation concept anywhere in
    /// `Theme.Metrics`, so the naive way to satisfy a new `orientation:`
    /// parameter is to accept it and ignore it. That build answers the same
    /// number for both cases; this rejects it.
    func testLandscapeHeightIsShorterThanPortrait() {
        let portrait = Theme.Metrics.totalHeight(for: .default, orientation: .portrait)
        let landscape = Theme.Metrics.totalHeight(for: .default, orientation: .landscape)
        XCTAssertLessThan(landscape, portrait)
    }

    /// The arithmetic in `Theme.Metrics.Landscape`'s doc comment: 3 letter rows
    /// and the bottom row at 26pt, 3 gaps at 4pt, portrait's own 8pt of top and
    /// bottom inset, a 30pt suggestion bar, no banner and no action row.
    func testLandscapeTotalHeightIsExact() {
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, orientation: .landscape), 154, accuracy: 0.001)
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: .default, orientation: .landscape), 124, accuracy: 0.001)
    }

    /// **The 12 pt NIT-114 had to find came out of the row gap and out of
    /// nothing else**, so this states where rather than only how much: a build
    /// that reached 154 by shaving the keys, the bar or the insets passes
    /// `testLandscapeTotalHeightIsExact` and fails here.
    ///
    /// The reason is in `Theme.Metrics.Landscape`: a landscape key is about
    /// 81 × 26, every mistap risk on it is vertical, and `KeyView` puts
    /// `.contentShape(Rectangle())` on the cap's own frame — so the key height
    /// is the whole of the touch target and the gap between two rows is dead
    /// space. Paying the cap out of the gap costs no target a point; paying it
    /// out of the key height costs every one of them.
    func testLandscapeFoundTheHeightInTheGapRatherThanInTheTargets() {
        XCTAssertEqual(Theme.Metrics.Landscape.keyHeight, 26, accuracy: 0.001)
        XCTAssertEqual(Theme.Metrics.Landscape.suggestionBarHeight, 30, accuracy: 0.001)
        XCTAssertEqual(Theme.Metrics.Landscape.rowSpacing, 4, accuracy: 0.001)
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: .default, orientation: .landscape),
            Theme.Metrics.Landscape.keyHeight * 4 + Theme.Metrics.Landscape.rowSpacing * 3
                + Theme.Metrics.topInset + Theme.Metrics.bottomInset,
            accuracy: 0.001,
            "the landscape key area is no longer four rows, three gaps and portrait's own insets")
    }

    /// Landscape never shows the banner, so a live reading or a refusal cannot
    /// grow the constraint the way it does in portrait.
    func testLandscapeIgnoresShowsBanner() {
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, showsBanner: true, orientation: .landscape),
            Theme.Metrics.totalHeight(for: .default, showsBanner: false, orientation: .landscape),
            accuracy: 0.001)
    }

    /// The number row and the action row are dropped outright, not shrunk — a
    /// user who turned both on gets the identical landscape height a user who
    /// never touched the editor gets. If landscape merely scaled the user's rows
    /// down instead of removing them, this height would grow with `roomy`'s.
    func testLandscapeHeightIgnoresTheUsersNumberRowAndActionRow() {
        var roomy = KeyboardCustomization.default
        roomy.showsNumberRow = true
        roomy.geometry.keyHeight = LayoutGeometry.keyHeightRange.upperBound
        roomy.geometry.actionRowHeight = LayoutGeometry.keyHeightRange.upperBound
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: roomy, orientation: .landscape),
            Theme.Metrics.totalHeight(for: .default, orientation: .landscape), accuracy: 0.001)
    }

    /// `landscapeLayout(basedOn:)` is what `keyAreaHeight(for:orientation:)` and
    /// `KeyboardView+Keys`'s `keyGrid` both read, so this is the single point
    /// where a mismatch between the published height and the rows actually drawn
    /// would show up. A roomy input on purpose, so passing the user's own rows
    /// straight through cannot happen to look right the way it would starting
    /// from an already-bare layout.
    func testLandscapeLayoutDropsTheNumberRowAndTheActionRowAndUsesTheCompactGeometry() {
        var roomy = KeyboardCustomization.default
        roomy.showsNumberRow = true
        roomy.geometry.keyHeight = LayoutGeometry.keyHeightRange.upperBound

        let compact = Theme.Metrics.landscapeLayout(basedOn: roomy)

        XCTAssertFalse(compact.showsNumberRow)
        XCTAssertTrue(compact.cursorRow.isEmpty)
        XCTAssertEqual(compact.geometry.keyHeight, Theme.Metrics.Landscape.keyHeight)
        XCTAssertEqual(compact.geometry.bottomRowHeight, Theme.Metrics.Landscape.keyHeight)
        XCTAssertEqual(compact.geometry.rowSpacing, Theme.Metrics.Landscape.rowSpacing)
        XCTAssertEqual(compact.geometry.reach, roomy.geometry.reach)
    }

    // MARK: The fingerprint cap

    /// The cap is a fraction of screen height, not a point budget — see
    /// `FrameReduction.Band.maximumOwnUI`. Checked at the reference landscape
    /// screen (874×402, iPhone 17 Pro rotated), the same device every portrait
    /// number here is measured against.
    func testLandscapeFractionStaysAtOrUnderTheFingerprintCap() {
        let fraction = KeyboardGeometry.ownUIHeightFraction(
            screenHeight: KeyboardGeometry.referenceLandscapeScreenHeight,
            layout: .default,
            orientation: .landscape)
        XCTAssertLessThanOrEqual(fraction, FrameReduction.Band.maximumOwnUI)
    }

    /// Every landscape screen height this keyboard ships to, which is the
    /// portrait *width* of every iPhone the package's iOS 17 floor still
    /// reaches. Kept in step with `frame-hash-landscape.mjs`'s `ALL_DEVICES`,
    /// which renders the same list.
    private static let shippingLandscapeHeights: [(height: CGFloat, phones: String)] = [
        (375, "SE 2/3, XS, 11 Pro, 12 mini, 13 mini"),
        (390, "12, 12 Pro, 13, 13 Pro, 14"),
        (393, "14 Pro, 15, 15 Pro, 16, 16e"),
        (402, "16 Pro, 17, 17 Pro"),
        (414, "XR, 11, XS Max, 11 Pro Max"),
        (428, "12 Pro Max, 13 Pro Max, 14 Plus"),
        (430, "14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus"),
        (440, "16 Pro Max, 17 Pro Max")
    ]

    /// **NIT-114, and the assertion this file did not have.** Every check here
    /// used to be taken at `referenceLandscapeScreenHeight` — 402, one row above
    /// break-even — and that is precisely why a live defect survived two
    /// tickets: the cap is a *fraction* of the landscape screen height and
    /// `Theme.Metrics` spends *points*, so the margin is a different number on
    /// every phone and the reference one is not the phone that binds.
    ///
    /// At the 166 pt landscape keyboard, break-even is `166 / 0.4210526` =
    /// 394.25 pt, so **five of the eight shipping widths were over the cap**:
    /// 375 by 8.1 pt, 390 by 1.8 and 393 by 0.5. Over it,
    /// `FrameReduction.bottomCrop(ownUI:)` clamps and the rows it refuses to
    /// crop are rows of our own keyboard — at 375 that reaches the Reply chip,
    /// whose working animation (now `ControlOrbit`, the sweep when this was
    /// measured) runs for the whole of a read, and
    /// `Bar/screen-context/harness/run-fingerprint-landscape.sh` measured 30 of
    /// 30 frames taking a fresh identity from it. That is a screen reading the
    /// user paid a cloud call for, retired as stale by our own animation.
    ///
    /// So this walks every width rather than the reference one, and 375 is the
    /// row that fails against the 166 pt build.
    func testTheLandscapeKeyboardFitsUnderTheCapOnEveryWidthItShipsTo() {
        for device in Self.shippingLandscapeHeights {
            let fraction = KeyboardGeometry.ownUIHeightFraction(
                screenHeight: device.height, layout: .default, orientation: .landscape)
            let spare = (FrameReduction.Band.maximumOwnUI - fraction) * Double(device.height)
            XCTAssertGreaterThan(
                spare, 0,
                "landscape crosses the fingerprint cap by \(-spare) pt on a \(device.height) pt "
                    + "screen (\(device.phones)); the answer is a shorter keyboard, never a "
                    + "larger cap")
        }
    }

    /// **How much room is actually left on the phone that binds, because the
    /// inequality above hides it.**
    ///
    /// The narrowest landscape screen this ships to is 375 pt
    /// (`Theme.Metrics.Landscape.narrowestScreenHeight`), where the budget is
    /// `0.4210526 × 375` = 157.9 pt against a 154 pt keyboard. That is a margin
    /// of **about 3.9 points** — larger than the 3 pt portrait itself runs on,
    /// and it only grows from here: 10.2 at 390, 15.3 at 402, 31.3 at 440.
    ///
    /// Four points is one row's spacing, not a comfortable budget. Anything
    /// added to the landscape keyboard — a taller bar, a row, a few points of
    /// padding — crosses the cap on this phone first, and crossing it is not a
    /// layout bug: the capture process then crops a band that still contains
    /// part of our own UI, the Reply chip's sweep moves the fingerprint on its
    /// own, and a stale screen reading is offered as fresh. That failure was
    /// measured at 30 of 30 frames on this exact width;
    /// `.claude/rules/screen-context.md` has it.
    ///
    /// So this asserts the margin rather than the inequality. If it fails, the
    /// number in the message tells you exactly how much you have overspent, and
    /// the answer is to make landscape shorter, never to raise the cap. Against
    /// the 166 pt build the margin here is **−8.1**, so both assertions fail.
    func testTheLandscapeMarginOnTheNarrowestPhoneIsAboutFourPoints() {
        let screen = Theme.Metrics.Landscape.narrowestScreenHeight
        XCTAssertEqual(
            screen, Self.shippingLandscapeHeights[0].height,
            "the narrowest phone moved; the constant the geometry is derived from has to move too")
        let fraction = KeyboardGeometry.ownUIHeightFraction(
            screenHeight: screen, layout: .default, orientation: .landscape)
        let spare = (FrameReduction.Band.maximumOwnUI - fraction) * Double(screen)
        XCTAssertEqual(
            spare, 3.89, accuracy: 0.5,
            "the landscape height budget moved; there were about 3.9 points of room on a 375 pt "
                + "screen and now there are \(spare)")
        XCTAssertGreaterThan(
            spare, 0, "landscape now crosses the fingerprint cap on the phone that binds")
    }

    /// The reference phone keeps its own margin recorded, because it is the
    /// device every other number under `Bar/screen-context/` is measured on and
    /// a reader comparing the two should not have to derive one of them.
    func testTheLandscapeMarginOnTheReferencePhoneIsAboutFifteenPoints() {
        let screen = KeyboardGeometry.referenceLandscapeScreenHeight
        let fraction = KeyboardGeometry.ownUIHeightFraction(
            screenHeight: screen, layout: .default, orientation: .landscape)
        let spare = (FrameReduction.Band.maximumOwnUI - fraction) * Double(screen)
        XCTAssertEqual(spare, 15.26, accuracy: 0.5)
        XCTAssertGreaterThan(spare, 0, "landscape now crosses the fingerprint cap")
    }

    /// Raising the cap to fit a taller landscape keyboard was already measured
    /// and rejected in portrait (`.claude/rules/screen-context.md`), so a
    /// landscape build must not lean on a larger cap either — this fails if
    /// `maximumOwnUI` itself ever moves without the landscape budget being
    /// re-derived against it.
    func testLandscapeDoesNotDependOnARaisedCap() {
        XCTAssertEqual(FrameReduction.Band.maximumOwnUI, 368.0 / 874.0, accuracy: 0.0001)
    }

    /// A layout that pushes past the cap in portrait — the editor's own
    /// "roomy" extreme — must not silently fit once the same numbers are read as
    /// landscape's fixed compact geometry instead: landscape's answer is
    /// constant regardless of the input layout, so this is really re-asserting
    /// `testLandscapeHeightIgnoresTheUsersNumberRowAndActionRow`'s point against
    /// the cap directly.
    /// Asked at the narrowest screen rather than the reference one, because that
    /// is the width the cap actually binds on.
    func testARoomyLayoutStillFitsUnderTheCapInLandscape() {
        var roomy = KeyboardCustomization.default
        roomy.showsNumberRow = true
        roomy.geometry.keyHeight = LayoutGeometry.keyHeightRange.upperBound
        let fraction = KeyboardGeometry.ownUIHeightFraction(
            screenHeight: Theme.Metrics.Landscape.narrowestScreenHeight,
            layout: roomy,
            orientation: .landscape)
        XCTAssertLessThanOrEqual(fraction, FrameReduction.Band.maximumOwnUI)
    }

    // MARK: Orientation itself

    func testOrientationFromASizeWiderThanItIsTallIsLandscape() {
        XCTAssertEqual(
            KeyboardGeometry.Orientation(width: 874, height: 402), .landscape)
    }

    func testOrientationFromASizeTallerThanItIsWideIsPortrait() {
        XCTAssertEqual(
            KeyboardGeometry.Orientation(width: 402, height: 874), .portrait)
    }

    /// A perfectly square size is not a shape this product's devices produce,
    /// but the initialiser has to answer something rather than crash; `>` rather
    /// than `>=` means a square reads as portrait, matching the guard in
    /// `KeyboardGeometry.ownUIHeightFraction` that treats "not clearly wider" as
    /// the safer, taller-budget case.
    func testASquareSizeReadsAsPortrait() {
        XCTAssertEqual(KeyboardGeometry.Orientation(width: 500, height: 500), .portrait)
    }

    // MARK: The row landscape sheds moves onto the bar

    /// **The bar has to draw the row it was budgeted, and it drew the portrait
    /// one in both orientations.** `totalHeight(for:showsBanner:orientation:)`
    /// pays `Landscape.suggestionBarHeight` (30) for the strip in landscape while
    /// `SuggestionBar` spelled `Theme.Metrics.suggestionBarHeight` (36) into its
    /// own frame, so the landscape keyboard drew 6 pt more than the height it
    /// asked the host for — on a form whose entire margin against the fingerprint
    /// cap is about 3 pt (`testTheLandscapeMarginAgainstTheCapIsAboutThreePoints`
    /// above).
    ///
    /// The second assertion is what rejects that build rather than the first:
    /// asking for the two numbers separately can pass on a coincidence, but
    /// "bar + key area is exactly the total" cannot — 36 + 136 is 172 against a
    /// published 166. Landscape hosting the action row's controls is free only
    /// because this equation holds, so it is asserted before anything about the
    /// controls themselves.
    func testTheBarDrawsExactlyTheRowLandscapeBudgetedForIt() {
        XCTAssertEqual(
            SuggestionBar.barHeight(for: .landscape),
            Theme.Metrics.Landscape.suggestionBarHeight, accuracy: 0.001)
        XCTAssertEqual(
            SuggestionBar.barHeight(for: .portrait),
            Theme.Metrics.suggestionBarHeight, accuracy: 0.001)

        for orientation in [KeyboardGeometry.Orientation.portrait, .landscape] {
            XCTAssertEqual(
                Theme.Metrics.totalHeight(
                    for: .default, showsBanner: false, orientation: orientation),
                SuggestionBar.barHeight(for: orientation)
                    + Theme.Metrics.keyAreaHeight(for: .default, orientation: orientation),
                accuracy: 0.001,
                "the bar draws a different row from the one the host was told about")
        }
    }

    /// **Everything the bar gained in landscape had to cost the keyboard nothing,
    /// and this is the assertion that says so in points.**
    ///
    /// The two ways to get this wrong both grow the total: giving landscape its
    /// action row back (a sixth row at `Landscape.keyHeight` plus a gap is 30 pt,
    /// so 184), or making the bar taller to fit 40 pt chips (164 at the portrait
    /// 44 × 40). Both are rejected here, and both would also fail
    /// `testTheLandscapeMarginOnTheNarrowestPhoneIsAboutFourPoints`, which is the
    /// point: there was never room for either.
    ///
    /// **This asked `chipSize` and only `chipSize`, which is how NIT-118 got
    /// past it.** `revertButton` carried a hardcoded 44 × 40 with no orientation
    /// guard, `.frame(height:)` does not clip, and the control never touched the
    /// sizing helper — so a 40 pt button drew in a 30 pt row, 5 pt into the host
    /// above and 5 pt onto the 26 pt top key row below, for the one keystroke
    /// after a Fix, Rewrite, Reply or CopyClip paste. It is `controlSizes` that
    /// is walked now, so the assertion covers every control the bar can draw
    /// rather than the ones that opted in.
    func testTheLandscapeActionStripCostsNoHeightAtAll() {
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, orientation: .landscape), 154,
            accuracy: 0.001)
        XCTAssertFalse(
            SuggestionBar.landscapeActions(for: .default).isEmpty,
            "the strip is empty, so 154 is only the height of a keyboard that lost the row")

        let row = SuggestionBar.barHeight(for: .landscape)
        let controls = SuggestionBar.controlSizes(for: .landscape)
        XCTAssertGreaterThan(controls.count, 1, "the walk is back to one control, which is NIT-118")
        for control in controls {
            XCTAssertLessThanOrEqual(
                control.size.height, row,
                "the bar's \(control.name) is \(control.size.height) pt in a \(row) pt row, so it "
                    + "draws past the height the keyboard published")
        }
        // Width is the axis landscape has: every control keeps the full portrait
        // target across and gives up only height.
        for (index, control) in controls.enumerated() {
            XCTAssertEqual(
                control.size.width, SuggestionBar.controlSizes(for: .portrait)[index].size.width,
                "the bar's \(control.name) gave up width, which landscape has plenty of")
        }

        let fraction = KeyboardGeometry.ownUIHeightFraction(
            screenHeight: Theme.Metrics.Landscape.narrowestScreenHeight,
            layout: .default,
            orientation: .landscape)
        XCTAssertLessThanOrEqual(fraction, FrameReduction.Band.maximumOwnUI)
    }

    /// **NIT-118: the undo is a control this bar draws, so it is held to the row
    /// like every other one.**
    ///
    /// It was a hardcoded `.frame(width: 44, height: 40)` built from
    /// `candidates` with no orientation guard. It does not change the published
    /// height, so no fingerprint sweep can see it — what it does is draw 5 pt of
    /// our own UI *above* the height `ownUIHeightFraction` publishes, and cover
    /// the top half of a 26 pt key row, for the one keystroke a revert is live.
    ///
    /// The first assertion is the one that rejects the shipped build: 40 against
    /// a 30 pt row. The second is what stops the repair being a landscape-only
    /// special case that quietly reshapes the portrait button — portrait's chip
    /// is the same 44 × 40 the literal was, so that half must not move at all.
    func testTheUndoFitsTheRowItIsDrawnInAndPortraitIsUntouched() {
        XCTAssertLessThanOrEqual(
            SuggestionBar.revertButtonSize(for: .landscape).height,
            SuggestionBar.barHeight(for: .landscape),
            "the undo draws past the row, into the host above it and the top key row below it")
        XCTAssertEqual(
            SuggestionBar.revertButtonSize(for: .portrait), CGSize(width: 44, height: 40),
            "the portrait undo changed size; this was a landscape sizing fix, not a redesign")
        XCTAssertEqual(
            SuggestionBar.revertButtonSize(for: .landscape),
            SuggestionBar.chipSize(for: .landscape),
            "the undo carries a size of its own again rather than the row's own chip")
    }

    /// **Every control the row carried is on the bar, in the order it carried
    /// them.** The premise first, as `testAPanelIsClosedInLandscapeBecauseNothing
    /// ThereCouldCloseIt` states its own: landscape empties `cursorRow`, so these
    /// five are drawn nowhere else at all.
    ///
    /// Today's build answers an empty array here, which is the whole ticket.
    /// Order is asserted rather than membership because a set would pass against
    /// a strip that shuffled the five under a thumb that had just learned them in
    /// portrait.
    func testTheActionsLandscapeShedsAreCarriedOnTheBarInstead() {
        XCTAssertTrue(
            Theme.Metrics.landscapeLayout(basedOn: .default).cursorRow.isEmpty,
            "landscape keeps the action row, so the bar does not have to carry it")

        XCTAssertEqual(
            SuggestionBar.landscapeActions(for: .default).map(\.action),
            KeyboardCustomization.default.cursorRow.map(\.action))
        XCTAssertEqual(
            SuggestionBar.landscapeActions(for: .default).map(\.action),
            [.copyclip, .fix, .settings, .quickTone, .dictation])
    }

    /// A user is free to put Rewrite in the action row *and* on the trailing end
    /// of the bar: in portrait those are two rows and two controls, and in
    /// landscape they collapse into one strip. A build that simply concatenated
    /// draws the same action twice, side by side.
    func testAnActionAlreadyOnTheBarIsNotDrawnTwiceInLandscape() {
        var layout = KeyboardCustomization.default
        layout.barTrailing = [SlotSpec(action: .reply), SlotSpec(action: .quickTone)]

        let strip = SuggestionBar.landscapeActions(for: layout).map(\.action)

        XCTAssertFalse(strip.contains(.quickTone))
        XCTAssertEqual(strip, [.copyclip, .fix, .settings, .dictation])
    }

    /// **Settings is the only route from this keyboard into the containing app,
    /// so it may not be the thing an orientation drops.**
    ///
    /// **It now ships in the action row, which landscape sheds, so the bar is the
    /// shipped route and not a contingency.** This test was written the other way
    /// round — the gear on the bottom row, the bar carrying it only for a user who
    /// had moved it — and the comment then said "if the gear ever moves back into
    /// the action row by default, the second half of this is what carries it".
    /// That is what happened when it traded seats with Emoji, so the two halves
    /// have swapped: the shipped layout is the one the bar rescues, and the moved
    /// layout is the one the bottom row draws directly.
    ///
    /// `.settings` is deliberately in `landscapeBarActions` and deliberately not
    /// in `barCatalogue`, which is the list of what a user may *choose* to put
    /// there.
    func testSettingsIsReachableInLandscapeWhereverTheUserPutsIt() {
        let landscape = Theme.Metrics.landscapeLayout(basedOn: .default)
        XCTAssertFalse(
            landscape.bottomRow.map(\.action).contains(.settings),
            "the gear is back on the bottom row, so this test is asking the wrong half")
        XCTAssertTrue(
            SuggestionBar.landscapeActions(for: .default).map(\.action).contains(.settings),
            "the gear is in the row landscape sheds and on no other surface")

        var moved = KeyboardCustomization.default
        moved.cursorRow.removeAll { $0.action == .settings }
        moved.bottomRow.append(SlotSpec(action: .settings, width: .units(1.0)))

        XCTAssertTrue(
            Theme.Metrics.landscapeLayout(basedOn: moved).bottomRow.map(\.action)
                .contains(.settings),
            "a user who moved the gear down loses it in landscape")
    }

    /// A key with no glyph draws `questionmark` through `slotButton`'s fallback,
    /// so the comma and question mark the "Power" preset puts in its action row
    /// would come out as two identical unexplained chips. They stay off the bar;
    /// the script's own punctuation key is on the bottom row, which landscape
    /// keeps. `.space` and `.shift` are the same refusal `barCatalogue` already
    /// makes, checked here because this list is a superset of that one and a
    /// superset is the easy place to let one back in.
    func testTheLandscapeStripRefusesWhatTheBarCannotDraw() {
        var layout = KeyboardCustomization.default
        layout.cursorRow = [
            SlotSpec(action: .fix, width: .fill),
            SlotSpec(action: .text(","), width: .fill),
            SlotSpec(action: .space, width: .fill),
            SlotSpec(action: .shift, width: .fill),
            SlotSpec(action: .backspace, width: .fill)
        ]

        XCTAssertEqual(SuggestionBar.landscapeActions(for: layout).map(\.action), [.fix])
    }

    /// **A panel opened in landscape has to keep the chip that closes it on
    /// screen, and the strip alone is not enough to promise that.** Both panels
    /// hide every letter key and landscape draws no search box, so
    /// `landscapePanelControls(for:)` is the surface left on the bar; a build that
    /// listed the strip alone would let a user who keeps Emoji on a bar edge open
    /// the grid from a chip that then stops being drawn, because
    /// `landscapeActions(for:)` deduplicates it out of the strip.
    ///
    /// **The shipped layout is no longer the case this protects, and it is not
    /// exposed either.** Emoji sits on the bottom row now, which the grid covers,
    /// so no chip closes it — `EmojiCategoryRow`'s own `אבג` key does, in both
    /// orientations, and `testAnOpenEmojiGridAlwaysHasAWayBack` is what holds
    /// that. This still answers for the arrangements where a chip is the exit.
    func testEverythingThatCanOpenAPanelInLandscapeIsStillDrawnWhileItIsOpen() {
        var edgeOnly = KeyboardCustomization.default
        edgeOnly.cursorRow = []
        edgeOnly.barTrailing = [SlotSpec(action: .reply), SlotSpec(action: .emoji)]
        XCTAssertTrue(SuggestionBar.landscapeActions(for: edgeOnly).isEmpty)
        XCTAssertTrue(
            SuggestionBar.landscapePanelControls(for: edgeOnly).map(\.action)
                .contains(.emoji),
            "a grid opened from a bar edge has nothing on screen that closes it")

        var inActionRow = KeyboardCustomization.default
        inActionRow.cursorRow = [SlotSpec(action: .emoji, width: .units(1.0))]
        XCTAssertTrue(
            SuggestionBar.landscapePanelControls(for: inActionRow).map(\.action)
                .contains(.emoji),
            "a user who put Emoji back in the action row loses its chip in landscape")
    }

    /// Landscape has about three points of margin, so the one thing in this bar
    /// that grows on its own must not be able to spend them. The words stop at
    /// 70% of the row they are in — and reading that cap off the *portrait*
    /// constant, which is what the single-argument spelling does, lets an
    /// accessibility size draw 25.2 pt of text in a 30 pt row.
    func testACandidateCannotGrowPastTheLandscapeRowAtAnyTextSize() {
        let row = SuggestionBar.barHeight(for: .landscape)
        for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
            XCTAssertLessThanOrEqual(
                SuggestionBar.candidateFontSize(for: size, barHeight: row), row * 0.7)
        }
        XCTAssertGreaterThan(
            SuggestionBar.candidateFontSize(for: .accessibility5),
            SuggestionBar.candidateFontSize(for: .accessibility5, barHeight: row),
            "the landscape cap is not below the portrait one, so it is not being read")
    }

    // MARK: The row landscape sheds is the way out of a panel

    /// **The trap, stated as the two facts that make it one.** Landscape empties
    /// `cursorRow`, and that row carries the only key that closes the emoji grid
    /// or the CopyClip panel; both of those overlays hide every letter key. A
    /// panel opened in portrait and rotated into therefore left a keyboard with
    /// nothing to type on and nothing to close — the search box hands the letters
    /// back but types into its own query, and its ✕ only returns to the panel.
    ///
    /// The first two assertions are the premise rather than the behaviour: if
    /// landscape ever keeps the action row, this test should be deleted along
    /// with the workaround it covers, not adjusted until it passes.
    ///
    /// **The trap now has two answers and this still covers the one it names.**
    /// The suggestion bar carries the Emoji and CopyClip chips in landscape
    /// (`SuggestionBar.landscapeActions(for:)`), and a chip whose panel is open
    /// is lit and closes it, so a keyboard rotated into a panel is no longer
    /// stranded even without this. It stays because it costs nothing and answers
    /// a different question: a rotation is not a request to keep browsing emoji,
    /// and handing the letters straight back is what somebody who has just turned
    /// their phone to type is after. Note what the bar cannot do — the search box
    /// is the one thing landscape gives up, because a query, an alphabet and the
    /// results need three bands and landscape has two.
    @MainActor
    func testAPanelIsClosedInLandscapeBecauseNothingThereCouldCloseIt() {
        XCTAssertTrue(
            Theme.Metrics.landscapeLayout(basedOn: .default).cursorRow.isEmpty,
            "landscape keeps the action row, so this workaround is obsolete")
        XCTAssertFalse(
            KeyboardOverlay.copyclip.showsLetterKeys,
            "the CopyClip panel no longer hides the letters, so rotating into it is not a trap")

        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let controller = KeyboardController(target: MockTextTarget())
        controller.press(.copyclip)
        XCTAssertEqual(controller.overlay, .copyclip)

        controller.closeOverlayForLandscape()

        XCTAssertEqual(
            controller.overlay, .none,
            "the panel survived a rotation into an orientation with no key that closes it")
    }

    /// The same rotation in portrait changes nothing: a panel there has its key
    /// one row up. A build that closed on every orientation read would shut the
    /// grid under the finger of anyone who opened it.
    @MainActor
    func testAPanelIsLeftAloneWhenNothingHasRotated() {
        let before = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = before }
        let controller = KeyboardController(target: MockTextTarget())
        controller.press(.copyclip)

        XCTAssertEqual(
            controller.overlay, .copyclip,
            "opening CopyClip in portrait closed it, so the guard is reading the wrong thing")
    }

    /// **Closing a panel is not closing everything else.** `dismissOverlay` stops
    /// dictation and clears the strip, and a rotation with no panel open must not
    /// reach it: a recording runs with `overlay == .none`, so the guard is what
    /// stands between turning the phone and losing a sentence somebody is still
    /// speaking. `overlay` is `.none` either way here and proves nothing on its
    /// own, so the assertion is on the refusal beside it — which
    /// `clearBannerState()` wipes, and which a guarded build leaves standing.
    @MainActor
    func testRotatingWithNoPanelOpenLeavesTheRestOfTheKeyboardAlone() {
        let controller = KeyboardController(target: MockTextTarget())
        controller.block = BannerState.Block(
            action: .fix, title: "Type something first",
            detail: "Fix works on what you have written.", remedy: BannerState.Block.Remedy.none)
        XCTAssertEqual(controller.overlay, .none)

        controller.closeOverlayForLandscape()

        XCTAssertNotNil(
            controller.block,
            "a rotation with nothing open ran the full panel teardown, which also stops dictation")
    }
}
