import SwiftUI
import XCTest

@testable import AIKeyboardCore

/// The glyph on a key, a suggestion, and a banner sentence all grow with the
/// user's Dynamic Type setting; none of the three fixed boxes they sit in —
/// the key, the 36pt suggestion bar, the 58pt banner — grows with them.
/// `Theme.DynamicType.scale` is the one ratio all three read; `KeyView.
/// scaledGlyphSize`, `SuggestionBar.candidateFontSize` and `ActionBanner.
/// badgeFontSize` / `sentenceFontSize` are where each ceiling is decided.
///
/// **Every scaling function under test takes its Dynamic Type size as an
/// explicit parameter rather than reading `@Environment` internally**,
/// because this target renders nothing — a `KeyView`, `SuggestionBar` or
/// `ActionBanner` built directly here only ever sees the environment's
/// default (`.large`), the same way `AlternatesPopupTests` already builds a
/// `KeyView` and reads its computed properties with no host around it.
/// Reading two different sizes off one box is only possible because the math
/// is a pure function of its parameters, not of `self`.
final class DynamicTypeScalingTests: XCTestCase {

    // MARK: The shared ratio

    /// Today's build has no `Theme.DynamicType` at all — every font size in
    /// this keyboard is a bare `.system(size:)` constant — so this is the
    /// first thing that has to exist before anything else here can, and the
    /// baseline every shipped size was tuned against must not move.
    func testTheDefaultSizeScalesToExactlyOne() {
        XCTAssertEqual(Theme.DynamicType.scale(for: .large), 1)
    }

    /// Apple's own Body scale, in points: 14/15/16/17/19/21/23 through the
    /// seven standard sizes, then 28/33/40/47/53 through the five
    /// accessibility sizes. Asserted against the ratio to 17, not against a
    /// re-typed table, so a typo here cannot agree with a typo in `Theme`.
    func testTheScaleMatchesApplesPublishedBodyTable() {
        let points: [DynamicTypeSize: CGFloat] = [
            .xSmall: 14, .small: 15, .medium: 16, .large: 17,
            .xLarge: 19, .xxLarge: 21, .xxxLarge: 23,
            .accessibility1: 28, .accessibility2: 33, .accessibility3: 40,
            .accessibility4: 47, .accessibility5: 53
        ]
        for (size, point) in points {
            XCTAssertEqual(
                Theme.DynamicType.scale(for: size), point / 17, accuracy: 0.001,
                "\(size) should scale to \(point)/17")
        }
    }

    /// A larger category must never scale to a smaller ratio than a smaller
    /// one — the whole point of the setting is that it only ever grows text.
    func testTheScaleNeverDecreasesAcrossTheOrderedSizes() {
        let ordered: [DynamicTypeSize] = [
            .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3, .accessibility4,
            .accessibility5
        ]
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(
                Theme.DynamicType.scale(for: pair.0), Theme.DynamicType.scale(for: pair.1))
        }
    }

    // MARK: Key caps grow, the key does not

    /// The exact case the design turns on: at `AX3` the glyph is strictly
    /// larger than at the shipped default, while `width` and `height` — the
    /// key's own box — are the identical two numbers in both calls. Today's
    /// build has no `dynamicTypeSize` parameter on this function at all
    /// (`characterFontSize` is `min(base, width * 0.78)`), so this fails to
    /// compile against it, and would fail numerically against a version that
    /// dropped the `Theme.DynamicType.scale` factor.
    func testAKeyCapGrowsAtAX3WhileTheKeysOwnBoxDoesNotChange() {
        let width: CGFloat = 34
        let height: CGFloat = 43
        let atDefault = KeyView.scaledGlyphSize(
            base: 25, dynamicTypeSize: .large, width: width, height: height)
        let atAX3 = KeyView.scaledGlyphSize(
            base: 25, dynamicTypeSize: .accessibility3, width: width, height: height)
        XCTAssertGreaterThan(atAX3, atDefault)
        // The default itself is untouched: this is exactly what
        // `characterFontSize` computed before Dynamic Type existed
        // (`min(base, width * 0.78)`, and 25 < 34 * 0.78).
        XCTAssertEqual(atDefault, 25)
    }

    /// AX5 is the size the issue names as the whole point, and it must not
    /// clip or truncate: the glyph is capped at a fraction of the key's own
    /// height and width rather than left to overflow either one. A build
    /// that scaled without a ceiling would return roughly `25 * 53/17 ≈ 78`
    /// here — nearly double the key's own height.
    func testAKeyCapNeverGrowsPastItsOwnBoxEvenAtAX5() {
        let width: CGFloat = 100
        let height: CGFloat = 43
        let atAX5 = KeyView.scaledGlyphSize(
            base: 25, dynamicTypeSize: .accessibility5, width: width, height: height)
        XCTAssertLessThanOrEqual(atAX5, width * 0.78)
        XCTAssertLessThanOrEqual(atAX5, height * KeyView.characterHeightCeiling)
        // The ceiling is the binding constraint here (a wide, ordinary-height
        // key), proving growth actually saturates rather than the `min`
        // happening to pick the unscaled base.
        XCTAssertEqual(atAX5, height * KeyView.characterHeightCeiling, accuracy: 0.01)
    }

    /// The ceiling has to hold across every height the layout editor allows
    /// (`LayoutGeometry.keyHeightRange`, 36...56), not only the shipped
    /// default: a user who sized their own keys taller is exactly the user
    /// this feature is for.
    func testTheHeightCeilingHoldsAcrossTheEditableKeyHeightRange() {
        for height in [
            LayoutGeometry.keyHeightRange.lowerBound, 43, LayoutGeometry.keyHeightRange.upperBound
        ] {
            let atAX5 = KeyView.scaledGlyphSize(
                base: 25, dynamicTypeSize: .accessibility5, width: 100, height: height)
            XCTAssertLessThanOrEqual(atAX5, height, "a glyph taller than its own key at \(height)pt")
        }
    }

    /// A compressed row must not shrink because of Dynamic Type, only fail to
    /// grow. The numbers/symbols plane squeezes a fourth row into the letters
    /// plane's three-row block (`Theme.Metrics.fittedKeyHeight`), which ships
    /// at roughly 29pt against a 43pt letter key — under `base *
    /// characterHeightCeiling` (25 * 0.75 ≈ 18.75) even before Dynamic Type
    /// touches it. A version that applied the height ceiling with no floor at
    /// `base` returns *less* than `base` here at the system default, which
    /// this test caught before it shipped: it is a regression against
    /// today's digit keys, not a Dynamic Type behaviour at all.
    func testACompressedRowDoesNotShrinkAtTheSystemDefault() {
        let fittedHeight = Theme.Metrics.fittedKeyHeight(
            slidingRows: 4, referenceRows: 3, keyHeight: 43, rowSpacing: 12)
        XCTAssertLessThan(
            fittedHeight, 43 * KeyView.characterHeightCeiling,
            "the fixture should exercise the compressed case")
        let atDefault = KeyView.scaledGlyphSize(
            base: 25, dynamicTypeSize: .large, width: 100, height: fittedHeight)
        XCTAssertEqual(atDefault, 25)
    }

    /// The instance property actually drawn in `KeyView.body` has to agree
    /// with the pure function above at the values it was built with, or the
    /// two sharing a name proves nothing about the view. English is `.latin`
    /// (base 25); the environment on a directly-constructed `KeyView`
    /// defaults to `.large`, the same way `reduceMotion` already does on
    /// every other `KeyView` test in this target.
    func testCharacterFontSizeAgreesWithTheStaticFormulaAtItsOwnBoxAndScript() throws {
        let spec = try XCTUnwrap(
            KeyboardLayout.rows(for: .english, plane: .letters)
                .flatMap(\.keys)
                .first { $0.cap == .character("a") },
            "English has no a key")
        let view = KeyView(
            spec: spec, width: 34, height: 43, language: .english, shift: .off,
            onPress: { _, _ in })
        XCTAssertEqual(
            view.characterFontSize,
            KeyView.scaledGlyphSize(base: 25, dynamicTypeSize: .large, width: 34, height: 43))
    }

    // MARK: Suggestion bar

    /// The bar's fixed 36pt row is untouched by Dynamic Type — only the text
    /// inside it grows, up to 70% of that row. Today's build has no
    /// `candidateFontSize` function at all; the candidate `Text` is a bare
    /// 17pt constant.
    func testACandidateGrowsWithDynamicTypeButStaysInsideTheFixedBar() {
        let atDefault = SuggestionBar.candidateFontSize(for: .large)
        let atAX3 = SuggestionBar.candidateFontSize(for: .accessibility3)
        XCTAssertEqual(atDefault, 17)
        XCTAssertGreaterThan(atAX3, atDefault)
        XCTAssertLessThanOrEqual(atAX3, Theme.Metrics.suggestionBarHeight * 0.7)
        // The row itself must not have moved: it is fixed by the frame
        // fingerprint (`.claude/rules/suggestion-bar.md`), not by text size.
        XCTAssertEqual(Theme.Metrics.suggestionBarHeight, 36)
    }

    // MARK: Action banner

    /// A badge label (the leading tag, a sender, an options label) grows but
    /// saturates at `Theme.Glyph.lightFloor` well before AX5 — it is a
    /// secondary label, not the sentence the banner exists to show.
    func testABadgeLabelGrowsButSaturatesAtTheLightFloor() {
        let atDefault = ActionBanner.badgeFontSize(base: 8, dynamicTypeSize: .large)
        let atAX2 = ActionBanner.badgeFontSize(base: 8, dynamicTypeSize: .accessibility2)
        let atAX5 = ActionBanner.badgeFontSize(base: 8, dynamicTypeSize: .accessibility5)
        XCTAssertEqual(atDefault, 8)
        XCTAssertGreaterThan(atAX2, atDefault)
        XCTAssertEqual(atAX5, Theme.Glyph.lightFloor)
    }

    /// The banner's own sentence gets more room than a badge, but
    /// `Theme.Metrics.bannerHeight` (58, fixed for the screen-context
    /// fingerprint) still bounds it: growth is capped at 3pt over the
    /// shipped size rather than following the full Dynamic Type ratio, which
    /// at AX5 would be roughly 3x — enough to push the banner's worst case
    /// (a title over two lines of detail) well past 58pt.
    func testTheBannerSentenceGrowsButStaysWellUnderTheFixedBannerHeight() {
        let atDefault = ActionBanner.sentenceFontSize(base: 13, dynamicTypeSize: .large)
        let atAX3 = ActionBanner.sentenceFontSize(base: 13, dynamicTypeSize: .accessibility3)
        let atAX5 = ActionBanner.sentenceFontSize(base: 13, dynamicTypeSize: .accessibility5)
        XCTAssertEqual(atDefault, 13)
        XCTAssertGreaterThan(atAX3, atDefault)
        XCTAssertEqual(atAX3, atAX5, "growth should already have saturated by AX3")
        XCTAssertEqual(atAX5, 16)
        // The screen-context ceiling this banner is built under must not move.
        XCTAssertEqual(Theme.Metrics.bannerHeight, 58)
    }

    // MARK: Captions under action keys

    /// `KeyView.actionLabel`'s caption (Emoji, CopyClip, Rewrite as X...) and
    /// the tone button's own caption both draw with this font. It grows and
    /// saturates at the same `Theme.Glyph.lightFloor` every other badge does,
    /// while the unscaled constant every other reader (`ControlActivity`,
    /// `AIButtonTests`) still measures against stays fixed at 9.
    func testTheActionKeyCaptionFontGrowsAndSaturatesAtTheLightFloor() {
        let atDefault = SuggestionBar.toneLabelFont(for: .large)
        let atAX2 = SuggestionBar.toneLabelFont(for: .accessibility2)
        XCTAssertEqual(atDefault.pointSize, 9)
        XCTAssertGreaterThan(atAX2.pointSize, atDefault.pointSize)
        XCTAssertLessThanOrEqual(atAX2.pointSize, Theme.Glyph.lightFloor)
        XCTAssertEqual(SuggestionBar.toneLabelFont.pointSize, 9)
    }

    // MARK: The space bar's own label

    /// **The one-language space bar drew its name *smaller* than the shipped
    /// build, at the system default type size, on any short bottom row.**
    /// `nameFontSize` was `min(15 * typeScale, height * 0.4)` with no floor, and
    /// `height` is the bottom row's key height, which the layout editor drags
    /// down to `LayoutGeometry.keyHeightRange`'s 36. At 36 the ceiling is 14.4,
    /// so at `.large`, where `typeScale` is 1 and this must resolve to exactly
    /// 15, it resolved to 14.4. Dynamic Type is not allowed to make anything
    /// smaller than the build without it.
    ///
    /// The whole editable range is swept rather than just the floor, because
    /// the break is at 37.5 and a test pinned to one end would pass against a
    /// fix that only moved the boundary.
    func testTheSpaceBarNameNeverShrinksBelowItsShippedSizeAtTheDefault() {
        for height in stride(
            from: LayoutGeometry.keyHeightRange.lowerBound,
            through: LayoutGeometry.keyHeightRange.upperBound, by: 1)
        {
            let size = KeyView.spaceBarNameFontSize(height: height, dynamicTypeSize: .large)
            XCTAssertGreaterThanOrEqual(
                size, 15,
                "a \(height)pt bottom row drew the language name at \(size), under the shipped 15")
        }
    }

    /// It still grows, and it is still bounded by the key it sits in, so the
    /// floor above did not turn into "ignore the height entirely".
    func testTheSpaceBarNameStillGrowsWithDynamicTypeAndStaysBounded() {
        let tall = LayoutGeometry.keyHeightRange.upperBound
        let atDefault = KeyView.spaceBarNameFontSize(height: tall, dynamicTypeSize: .large)
        let atAX3 = KeyView.spaceBarNameFontSize(height: tall, dynamicTypeSize: .accessibility3)
        XCTAssertGreaterThan(atAX3, atDefault, "the name did not grow with Dynamic Type")
        XCTAssertLessThanOrEqual(
            atAX3, max(15, tall * 0.4), "the name grew past the room its own key has")
    }
}
