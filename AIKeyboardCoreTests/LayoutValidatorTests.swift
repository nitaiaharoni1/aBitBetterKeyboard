import XCTest

@testable import AIKeyboardCore

/// The rails that stop a user building a keyboard they cannot type on.
///
/// Every assertion here is written to reject the *unguarded* version: each
/// essential is removed on its own, so a missing rail cannot hide behind another
/// one that happens to fire at the same time.
final class LayoutValidatorTests: XCTestCase {

    private func errors(
        _ layout: KeyboardCustomization, showsGlobe: Bool = true
    ) -> [LayoutIssue] {
        LayoutValidator.issues(in: layout, showsGlobe: showsGlobe).filter { $0.severity == .error }
    }

    private func kinds(
        _ layout: KeyboardCustomization, showsGlobe: Bool = true
    ) -> Set<LayoutIssue.Kind> {
        Set(errors(layout, showsGlobe: showsGlobe).map(\.kind))
    }

    func testTheDefaultLayoutIsClean() {
        XCTAssertEqual(LayoutValidator.issues(in: .default, showsGlobe: true), [])
        XCTAssertEqual(LayoutValidator.issues(in: .default, showsGlobe: false), [])
    }

    // MARK: The essentials

    func testRemovingTheSpaceBarIsAnError() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.removeAll { $0.action == .space }
        XCTAssertTrue(kinds(layout).contains(.missingSpace))
    }

    func testRemovingReturnIsAnError() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.removeAll { $0.action == .ret }
        XCTAssertTrue(kinds(layout).contains(.missingReturn))
    }

    func testRemovingThePlaneSwitchIsAnError() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.removeAll { $0.action == .numbersPlane }
        XCTAssertTrue(kinds(layout).contains(.missingPlaneSwitch))
    }

    /// **Delete is deliberately not required in the custom rows.**
    /// `KeyboardLayout` puts it at the end of a letter row, and the letter rows
    /// are not editable, so it is reachable whatever the user does down here.
    /// Requiring it would make the shipped default invalid on first launch.
    func testDeleteIsNotRequiredBecauseTheLetterRowsCarryIt() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.removeAll { $0.action == .backspace }
        XCTAssertEqual(errors(layout), [])
    }

    func testGlobeCannotBeRemovedWhenIOSRequiresIt() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.removeAll { $0.action == .globe }
        XCTAssertTrue(kinds(layout, showsGlobe: true).contains(.missingGlobe))
        XCTAssertFalse(kinds(layout, showsGlobe: false).contains(.missingGlobe))
    }

    /// An essential moved to the cursor row is still present. The rails are about
    /// reachability, not about which row a key stands on.
    func testAnEssentialCountsWhereverItStands() {
        var layout = KeyboardCustomization.default
        let ret = layout.bottomRow.first { $0.action == .ret }!
        layout.bottomRow.removeAll { $0.id == ret.id }
        layout.cursorRow = [ret]
        XCTAssertEqual(errors(layout), [])
    }

    func testASecondSpaceBarIsAnError() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.append(SlotSpec(action: .space, width: .fill))
        XCTAssertTrue(kinds(layout).contains(.duplicateSpace))
    }

    // MARK: Geometry

    func testKeyHeightOutsideTheRangeIsAnError() {
        var layout = KeyboardCustomization.default
        layout.geometry.keyHeight = 90
        XCTAssertTrue(kinds(layout).contains(.geometryOutOfRange))
        layout.geometry.keyHeight = 10
        XCTAssertTrue(kinds(layout).contains(.geometryOutOfRange))
    }

    func testRowSpacingOutsideTheRangeIsAnError() {
        var layout = KeyboardCustomization.default
        layout.geometry.rowSpacing = 40
        XCTAssertTrue(kinds(layout).contains(.geometryOutOfRange))
    }

    func testTheEdgesOfTheRangeAreAllowed() {
        var layout = KeyboardCustomization.default
        layout.geometry.keyHeight = LayoutGeometry.keyHeightRange.lowerBound
        layout.geometry.rowSpacing = LayoutGeometry.rowSpacingRange.upperBound
        XCTAssertEqual(errors(layout), [])
    }

    // MARK: Width

    func testARowWiderThanTheBudgetIsAnError() {
        var layout = KeyboardCustomization.default
        layout.bottomRow =
            (0..<8).map { _ in SlotSpec(action: .text("x"), width: .units(3)) }
            + [
                SlotSpec(action: .space, width: .fill), SlotSpec(action: .ret),
                SlotSpec(action: .numbersPlane), SlotSpec(action: .globe)
            ]
        XCTAssertTrue(kinds(layout).contains(.rowTooWide))
    }

    /// The widest legal row must not trip it. `<=` is the difference between a
    /// rail and an off-by-one that rejects a layout the keyboard can draw.
    func testARowExactlyAtTheBudgetIsAllowed() {
        var layout = KeyboardCustomization.default
        layout.bottomRow = [
            SlotSpec(action: .numbersPlane), SlotSpec(action: .globe),
            SlotSpec(action: .space, width: .fill), SlotSpec(action: .ret)
        ]
        layout.bottomRow += (0..<Int(LayoutValidator.widthBudget) - 4).map { _ in
            SlotSpec(action: .text("x"))
        }
        XCTAssertFalse(kinds(layout).contains(.rowTooWide))
    }

    /// **The budget is the narrowest column count, not the widest, and it was
    /// written the other way round.**
    ///
    /// The unit is inversely proportional to `columns`, so twelve units fits a
    /// twelve-column language (Russian) exactly and overruns a ten-column one
    /// (English, Hebrew) by a fifth of the screen. One layout is shared by all
    /// sixty-four languages, so the tightest bound is the only safe one. Against
    /// the original budget of twelve this row is accepted and runs off the side.
    func testARowThatFitsRussianButNotEnglishIsRejected() {
        var layout = KeyboardCustomization.default
        layout.bottomRow = [
            SlotSpec(action: .numbersPlane), SlotSpec(action: .globe),
            SlotSpec(action: .space, width: .fill), SlotSpec(action: .ret)
        ]
        // Eleven fixed units: inside a twelve-column grid, over a ten-column one.
        layout.bottomRow += (0..<7).map { _ in SlotSpec(action: .text("x")) }

        XCTAssertTrue(
            kinds(layout).contains(.rowTooWide),
            "eleven units fits Russian and overruns English; the rail has to reject it")

        // And the arithmetic the rail stands on: the compiled row really is wider
        // than the English grid it would be drawn in.
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)[3]
        let units = row.keys.reduce(CGFloat(0)) { total, key in
            switch key.width {
            case .unit(let value): return total + value
            case .flexible, .remainderShare: return total + 1
            }
        }
        XCTAssertGreaterThan(
            units, CGFloat(KeyboardLayout.columns(for: .english, plane: .letters)))
    }

    /// The budget has to be the floor of `columns`, whatever that floor is, or the
    /// two drift the next time a language is added.
    func testTheBudgetIsTheNarrowestColumnCountOfAnyLanguage() {
        let narrowest =
            KeyboardLanguage.allCases
            .flatMap { language in
                [KeyboardPlane.letters, .numbers, .symbols].map {
                    KeyboardLayout.columns(for: language, plane: $0)
                }
            }
            .min() ?? 10
        XCTAssertEqual(LayoutValidator.widthBudget, CGFloat(narrowest))
    }

    // MARK: The cost the user cannot see

    /// **The shipped layout must not warn**, or the warning is noise on a screen
    /// the user has not touched yet.
    func testTheShippedLayoutDoesNotCostScreenContext() {
        XCTAssertFalse(
            LayoutValidator.issues(in: .default, showsGlobe: true)
                .contains { $0.kind == .costsScreenContext })
    }

    /// A tall layout warns rather than blocking. Past the measured cliff in
    /// `FrameReduction.Band.maximumOwnUI` the fingerprint band starts eating the
    /// host's own message lines and two conversations collide, so screen context
    /// degrades — but typing does not, so it is the user's trade to make and the
    /// only unacceptable outcome is making it silently.
    func testATallLayoutWarnsThatItCostsScreenContext() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        layout.geometry.keyHeight = LayoutGeometry.keyHeightRange.upperBound

        let issues = LayoutValidator.issues(in: layout, showsGlobe: true)
        XCTAssertTrue(
            issues.contains { $0.kind == .costsScreenContext && $0.severity == .warning },
            "a keyboard past the fingerprint cliff has to say so where the choice is made")
        XCTAssertTrue(
            LayoutValidator.isUsable(layout, showsGlobe: true),
            "it costs screen context and nothing else, so it must not block Done")
    }

    /// The threshold is read from the measured constant, not restated beside it.
    func testTheThresholdTracksTheMeasuredBandCeiling() {
        XCTAssertEqual(
            LayoutValidator.screenContextHeightLimit,
            CGFloat(FrameReduction.Band.maximumOwnUI) * KeyboardGeometry.referenceScreenHeight)
    }

    // MARK: Warnings do not block

    func testALongSnippetWarnsRatherThanBlocks() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.append(SlotSpec(action: .text(String(repeating: "a", count: 40))))
        let issues = LayoutValidator.issues(in: layout, showsGlobe: true)
        XCTAssertTrue(issues.contains { $0.kind == .snippetTooLong && $0.severity == .warning })
        XCTAssertTrue(LayoutValidator.isUsable(layout, showsGlobe: true))
    }

    /// **A row of more than twelve keys is an error, not a warning**, and it is
    /// worth pinning that they cannot both be true. A "this row is crowded"
    /// warning was written and deleted: `SlotWidth.minimumUnits` is a whole key,
    /// so thirteen keys is thirteen units, which is over budget by construction.
    /// The warning could never fire and read as a rail while being unreachable.
    func testTooManyKeysIsTheWidthErrorAndNothingSofter() {
        var layout = KeyboardCustomization.default
        layout.cursorRow = (0..<14).map { _ in SlotSpec(action: .text("x"), width: .fill) }
        XCTAssertTrue(kinds(layout).contains(.rowTooWide))
        XCTAssertFalse(LayoutValidator.isUsable(layout, showsGlobe: true))
    }

    /// A repeat *within* one row. Dictation would not do here any more: it ships
    /// on the action row, so adding it to the bottom row is a duplicate across
    /// rows, which this rule deliberately does not police.
    func testADuplicateActionWarnsRatherThanBlocks() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.append(SlotSpec(action: .punctuation))
        let issues = LayoutValidator.issues(in: layout, showsGlobe: true)
        XCTAssertTrue(issues.contains { $0.kind == .duplicateAction && $0.severity == .warning })
        XCTAssertTrue(LayoutValidator.isUsable(layout, showsGlobe: true))
    }

    /// Every message is shown to the user, so an empty one is a blank line in the
    /// Problems list.
    func testEveryIssueCarriesAMessage() {
        var layout = KeyboardCustomization.default
        layout.bottomRow = []
        layout.geometry.keyHeight = 99
        let issues = LayoutValidator.issues(in: layout, showsGlobe: true)
        XCTAssertFalse(issues.isEmpty)
        XCTAssertFalse(issues.contains { $0.message.isEmpty })
    }

    // MARK: Removal

    func testCanRemoveAnswersTheSameQuestionTheEditorAsks() {
        let globe = KeyboardCustomization.default.bottomRow.first { $0.action == .globe }!
        XCTAssertFalse(
            LayoutValidator.canRemove(globe, from: .default, showsGlobe: true).isAllowed)
        XCTAssertTrue(
            LayoutValidator.canRemove(globe, from: .default, showsGlobe: false).isAllowed)
    }

    func testTheRefusalNamesItsReason() {
        let globe = KeyboardCustomization.default.bottomRow.first { $0.action == .globe }!
        let verdict = LayoutValidator.canRemove(globe, from: .default, showsGlobe: true)
        XCTAssertFalse(verdict.reason.isEmpty)
        XCTAssertTrue(verdict.reason.contains("iOS"))
    }

    /// **Punctuation, not dictation.** Dictation moved to the action row, so a
    /// force-unwrap of it in `bottomRow` is nil — and this crashed the test runner
    /// rather than failing, which stops the whole bundle. The key this wants is any
    /// bottom-row one the validator does not treat as essential.
    func testAnOrdinaryKeyCanBeRemoved() {
        let ordinary = KeyboardCustomization.default.bottomRow.first { $0.action == .punctuation }!
        let verdict = LayoutValidator.canRemove(ordinary, from: .default, showsGlobe: true)
        XCTAssertTrue(verdict.isAllowed)
        XCTAssertTrue(verdict.reason.isEmpty)
    }

    /// **An already-broken layout must not refuse every further edit.** Only
    /// errors the removal *introduces* count, or the user is in a corner they
    /// cannot edit their way out of.
    func testRemovalIsJudgedOnWhatItIntroduces() {
        var broken = KeyboardCustomization.default
        broken.bottomRow.removeAll { $0.action == .ret }
        let ordinary = broken.bottomRow.first { $0.action == .punctuation }!
        XCTAssertFalse(LayoutValidator.isUsable(broken, showsGlobe: true))
        XCTAssertTrue(LayoutValidator.canRemove(ordinary, from: broken, showsGlobe: true).isAllowed)
    }
}
