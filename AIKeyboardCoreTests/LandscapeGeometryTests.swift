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
    /// and the bottom row at 26pt, 3 gaps at 8pt, portrait's own 8pt of top and
    /// bottom inset, a 30pt suggestion bar, no banner and no action row.
    func testLandscapeTotalHeightIsExact() {
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, orientation: .landscape), 166, accuracy: 0.001)
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: .default, orientation: .landscape), 136, accuracy: 0.001)
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

    /// **How much room is actually left, because the inequality above hides it.**
    /// Landscape totals 166 pt of a 402 pt screen, which is 0.4129 against a cap
    /// of 368/874 = 0.4211. That is a margin of about 0.0081, and 0.0081 of 402
    /// pt is **roughly 3 points**.
    ///
    /// Three points is one row's spacing, not a comfortable budget. Anything
    /// added to the landscape keyboard — a taller bar, a row, a few points of
    /// padding — crosses the cap, and crossing it is not a layout bug: the
    /// capture process then crops a band that still contains part of our own UI,
    /// our shimmer moves the fingerprint on its own, and a stale screen reading
    /// is offered as fresh. That failure was measured at 30 of 30 frames once
    /// already; `.claude/rules/screen-context.md` has it.
    ///
    /// So this asserts the margin rather than the inequality. If it fails, the
    /// number in the message tells you exactly how much you have overspent, and
    /// the answer is to make landscape shorter, never to raise the cap.
    func testTheLandscapeMarginAgainstTheCapIsAboutThreePoints() {
        let screen = KeyboardGeometry.referenceLandscapeScreenHeight
        let fraction = KeyboardGeometry.ownUIHeightFraction(
            screenHeight: screen, layout: .default, orientation: .landscape)
        let spare = (FrameReduction.Band.maximumOwnUI - fraction) * Double(screen)
        XCTAssertEqual(
            spare, 3.26, accuracy: 0.5,
            "the landscape height budget moved; there were about 3 points of room and now there are \(spare)")
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
    func testARoomyLayoutStillFitsUnderTheCapInLandscape() {
        var roomy = KeyboardCustomization.default
        roomy.showsNumberRow = true
        roomy.geometry.keyHeight = LayoutGeometry.keyHeightRange.upperBound
        let fraction = KeyboardGeometry.ownUIHeightFraction(
            screenHeight: KeyboardGeometry.referenceLandscapeScreenHeight,
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
}
