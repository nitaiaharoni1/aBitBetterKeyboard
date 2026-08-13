import XCTest

@testable import AIKeyboardCore

/// The layout model, the key caps it compiles to, and the rows that come out.
///
/// The load-bearing test here is `testTheDefaultCompilesToTodaysRows`: this whole
/// feature is only safe because the shipped default compiles to exactly what the
/// keyboard drew before it existed.
final class CustomLayoutTests: XCTestCase {

    // MARK: The model

    func testDefaultRoundTripsThroughJSON() throws {
        let original = KeyboardCustomization.default
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(KeyboardCustomization.self, from: data), original)
    }

    /// `SlotAction.text` carries a payload and every other case does not, which is
    /// the shape a synthesised `Codable` is most likely to get wrong. One of each.
    func testEveryActionRoundTrips() throws {
        let actions: [SlotAction] = [
            .shift, .backspace, .numbersPlane, .symbolsPlane, .globe, .settings, .space, .ret,
            .dictation, .emoji, .quickTone, .cursorLeft, .cursorRight, .deleteForward,
            .hideKeyboard, .text(".com")
        ]
        let data = try JSONEncoder().encode(actions)
        XCTAssertEqual(try JSONDecoder().decode([SlotAction].self, from: data), actions)
    }

    /// Two commas on one row is a layout the user is allowed to build, so identity
    /// cannot be derived from the action.
    func testTwoSlotsWithTheSameActionHaveDifferentIDs() {
        XCTAssertNotEqual(SlotSpec(action: .text(",")).id, SlotSpec(action: .text(",")).id)
    }

    /// **Dictation is deliberately not here.** It moved to the action row, and a
    /// key that appears in two rows at once is a duplicate the validator cannot
    /// see, because it only checks for repeats *within* a row.
    func testTheDefaultBottomRow() {
        XCTAssertEqual(
            KeyboardCustomization.default.bottomRow.map(\.action),
            [.numbersPlane, .settings, .space, .punctuation, .ret])
        XCTAssertFalse(
            KeyboardCustomization.default.bottomRow.contains { $0.action == .dictation },
            "dictation is on the action row; two of it is one too many")
    }

    /// Nothing the default ships appears in two rows at once.
    func testNoActionAppearsInTwoRowsOfTheDefault() {
        let layout = KeyboardCustomization.default
        let all =
            (layout.bottomRow + layout.cursorRow + layout.barLeading + layout.barTrailing)
            .map(\.action)
            .filter { if case .text = $0 { return false } else { return true } }
        XCTAssertEqual(Set(all).count, all.count, "an action ships in two places: \(all)")
    }

    /// **The punctuation key is not `text(".")`, and the difference is four marks
    /// and a language.** A literal full stop looks identical on the cap and
    /// silently loses the long presses and the script's own mark, which is exactly
    /// the substitution somebody will make while reading the row.
    func testThePunctuationKeyKeepsItsLongPressMarks() {
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: .default)[3]
        let key = row.keys.first { $0.addressableID == KeyboardLayout.punctuationKeyID }
        XCTAssertNotNil(key)
        XCTAssertFalse(key?.alternates.isEmpty ?? true, "the four long-press marks are gone")
    }

    /// Arabic writes its comma and question mark differently, and the cap follows.
    func testThePunctuationKeyFollowsTheScript() {
        let arabic = KeyboardLayout.rows(
            for: .arabic, plane: .letters, showsGlobe: true, customization: .default)[3]
        let key = arabic.keys.first { $0.addressableID == KeyboardLayout.punctuationKeyID }
        XCTAssertEqual(key?.alternates, KeyboardLayout.punctuationKey(for: .arabic).alternates)
    }

    /// **The full stop is on the bottom row of every plane**, and it used to be
    /// dropped on two of them because the row above already carries all five
    /// marks. It is the one key a thumb finds without looking, so switching to
    /// numbers put the return key where the full stop had been.
    ///
    /// Asserted with the *whole* compiled keyboard rather than the bottom row
    /// alone, because the thing that made this look unsafe is a collision: the
    /// numbers plane draws a `char-.` on its punctuation row and this key on the
    /// row below, and two keys with one id is a `ForEach` with duplicate identity.
    /// They do not collide — this one answers to `punctuation` — and the second
    /// half of this test is what proves it rather than the comment.
    func testThePunctuationKeyIsOnEveryPlane() {
        for plane in [KeyboardPlane.letters, .numbers, .symbols] {
            let rows = KeyboardLayout.rows(
                for: .english, plane: plane, showsGlobe: true, customization: .default)
            let keys = rows.flatMap(\.keys)
            XCTAssertTrue(
                keys.contains { $0.addressableID == KeyboardLayout.punctuationKeyID },
                "\(plane) has no full stop on its bottom row")
            XCTAssertEqual(
                Set(keys.map(\.id)).count, keys.count,
                "\(plane) draws two keys with one id")
        }
    }

    func testDefaultGeometryMatchesTheShippedMetrics() {
        XCTAssertEqual(KeyboardCustomization.default.geometry.keyHeight, Theme.Metrics.keyHeight)
        XCTAssertEqual(KeyboardCustomization.default.geometry.rowSpacing, Theme.Metrics.rowSpacing)
        XCTAssertEqual(KeyboardCustomization.default.geometry.reach, .full)
    }

    func testRowCountFollowsTheOptionalRows() {
        // From a bare base rather than from the shipped default, which now turns
        // the extra row on itself.
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = false
        layout.cursorRow = []
        XCTAssertEqual(layout.rowCount, 4)
        layout.showsNumberRow = true
        XCTAssertEqual(layout.rowCount, 5)
        layout.cursorRow = [SlotSpec(action: .cursorLeft)]
        XCTAssertEqual(layout.rowCount, 6)
    }

    func testWidthIsClampedBothWays() {
        XCTAssertEqual(SlotWidth.clampedUnits(99), .units(SlotWidth.maximumUnits))
        XCTAssertEqual(SlotWidth.clampedUnits(0.1), .units(SlotWidth.minimumUnits))
        XCTAssertEqual(SlotWidth.clampedUnits(1.5), .units(1.5))
    }

    // MARK: Caps

    /// Every action must compile to a cap, or a key the user can add is a key the
    /// keyboard cannot draw.
    func testEveryCatalogueActionHasAKeyCap() {
        for action in SlotAction.catalogue + [.space] {
            XCTAssertNotNil(action.keyCap(language: .english), "\(action) has no cap")
        }
    }

    func testEveryActionHasANonEmptyTitle() {
        for action in SlotAction.catalogue + [.space] {
            XCTAssertFalse(action.title.isEmpty, "\(action) has no title")
        }
    }

    /// Each new cap needs a distinct accessibility label: that string is the only
    /// thing a VoiceOver user has to tell two icon keys apart.
    func testNewCapsHaveDistinctAccessibilityLabels() {
        let caps: [KeyCap] = [
            .settings, .emoji, .quickTone, .cursorLeft, .cursorRight, .deleteForward, .hideKeyboard
        ]
        let labels = caps.map(\.accessibilityLabel)
        XCTAssertEqual(Set(labels).count, caps.count, "two caps share a label: \(labels)")
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    /// Distinct ids for the same reason: `KeySpec.identifier(for:)` derives from
    /// the cap, and a collision is a `ForEach` with duplicate identity.
    func testNewCapsHaveDistinctSpecIDs() {
        let caps: [KeyCap] = [
            .settings, .emoji, .quickTone, .cursorLeft, .cursorRight, .deleteForward, .hideKeyboard
        ]
        XCTAssertEqual(Set(caps.map { KeySpec($0).id }).count, caps.count)
    }

    func testTheNewCapsAreFunctionKeys() {
        for cap in [
            KeyCap.settings, .emoji, .quickTone, .cursorLeft, .cursorRight, .deleteForward,
            .hideKeyboard
        ] {
            XCTAssertTrue(cap.isFunctionKey, "\(cap) should not be treated as a character key")
        }
    }

    // Compiled-layout tests live in CustomLayoutCompilerTests.swift.

    // MARK: Presets

    func testThereAreFivePresetsWithUniqueIDs() {
        XCTAssertEqual(LayoutPreset.all.count, 5)
        XCTAssertEqual(Set(LayoutPreset.all.map(\.id)).count, 5)
    }

    func testEveryPresetValidatesClean() {
        for preset in LayoutPreset.all {
            let errors = LayoutValidator.issues(in: preset.customization)
                .filter { $0.severity == .error }
            XCTAssertEqual(errors, [], "\(preset.id): \(errors.map(\.message))")
        }
    }

    func testEveryPresetNamesItself() {
        for preset in LayoutPreset.all {
            XCTAssertEqual(preset.customization.preset, preset.id)
            XCTAssertEqual(preset.customization.basedOn, preset.id)
            XCTAssertFalse(preset.name.isEmpty)
            XCTAssertFalse(preset.summary.isEmpty)
        }
    }

    func testDefaultPresetIsTheShippedDefault() {
        XCTAssertEqual(LayoutPreset.named("default")?.customization, .default)
    }

    func testPowerTurnsOnBothOptionalRows() {
        let power = LayoutPreset.named("power")!.customization
        XCTAssertTrue(power.showsNumberRow)
        XCTAssertFalse(power.cursorRow.isEmpty)
    }

    /// One-handed is a geometry toggle, not a preset. If that ever drifts, this
    /// fails and the design decision gets revisited rather than quietly lost.
    func testNoPresetIsOneHanded() {
        XCTAssertTrue(LayoutPreset.all.allSatisfy { $0.customization.geometry.reach == .full })
    }

    func testAnUnknownPresetNameAnswersNil() {
        XCTAssertNil(LayoutPreset.named("nope"))
    }

    /// **The Bulgarian check.** A row over budget does not fail, it runs off the
    /// side of the screen, so every preset is measured against every language's
    /// own column count.
    func testEveryPresetFitsEveryLanguage() {
        for preset in LayoutPreset.all {
            for language in KeyboardLanguage.allCases {
                for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                    let rows = KeyboardLayout.rows(
                        for: language, plane: plane, showsGlobe: true,
                        customization: preset.customization)
                    let columns = CGFloat(KeyboardLayout.columns(for: language, plane: plane))
                    for row in rows {
                        let units = totalUnits(of: row)
                        XCTAssertLessThanOrEqual(
                            units + row.sideInsetUnits * 2, columns + 0.001,
                            "\(preset.id)/\(language.rawValue)/\(plane) row \(row.id) is \(units) wide against \(columns)"
                        )
                    }
                }
            }
        }
    }

    // MARK: The bar

    /// **The bar ships empty, and that is a decision rather than an oversight.**
    /// Emoji, one-tap rewrite and the AI menu moved into the action row, so the
    /// bar is three candidates edge to edge. Both ends stay editable.
    func testTheDefaultBarIsEmptyAndBothEndsStayEditable() {
        XCTAssertTrue(KeyboardCustomization.default.barLeading.isEmpty)
        XCTAssertTrue(KeyboardCustomization.default.barTrailing.isEmpty)
        XCTAssertFalse(SuggestionBar.barCatalogue.isEmpty)
    }

    /// A space bar or a shift key 46 points tall above the letters is not a layout
    /// anybody meant to build.
    func testTheBarOffersASubsetOfTheCatalogue() {
        XCTAssertTrue(Set(SuggestionBar.barCatalogue).isSubset(of: Set(SlotAction.catalogue)))
        XCTAssertFalse(SuggestionBar.barCatalogue.contains(.space))
        XCTAssertFalse(SuggestionBar.barCatalogue.contains(.shift))
        XCTAssertFalse(SuggestionBar.barCatalogue.contains(.backspace))
        XCTAssertFalse(SuggestionBar.barCatalogue.contains(.deleteForward))
        for action in [SlotAction.emoji, .quickTone] {
            XCTAssertTrue(SuggestionBar.barCatalogue.contains(action), "\(action) is missing")
        }
    }

    /// **Every preset keeps a route to every AI action.**
    ///
    /// That is what the sparkle key used to buy for the two presets that spend the
    /// action row on something else: "Power" fills it with arrows and punctuation,
    /// and "AI first" moves things into the bottom row, so a single `.aiMenu` slot
    /// was their only way in. `AIMenuPanel` is deleted and the slot went with it, so
    /// both carry real Reply keys now.
    ///
    /// **Asserting that the sparkle is gone would pass against the broken build**
    /// this is written for — the one where it was deleted and "Power" was left with
    /// no way to reach Reply at all, silently, because nothing in the type system
    /// notices a preset losing a feature. So this asserts reachability rather than
    /// absence, per preset, by name.
    func testEveryPresetReachesEveryAIAction() {
        for preset in LayoutPreset.all {
            let layout = preset.customization
            let actions = Set(
                (layout.barLeading + layout.barTrailing + layout.bottomRow + layout.cursorRow)
                    .map(\.action))
            XCTAssertTrue(
                actions.contains(.reply),
                "\(preset.id) has no way to reach Reply, which is the action with no substitute")
            XCTAssertTrue(
                actions.contains(.fix) || actions.contains(.quickTone),
                "\(preset.id) has no way to reach a text action")
        }
    }

    // MARK: Height

    /// The space bar is a thumb target; the digits are not. Three points move
    /// from the numbers row onto space, and they must move as a pair: growing
    /// space alone would cross the 368 pt fingerprint cliff, shrinking digits
    /// alone would leave a gap above the space bar.
    ///
    /// **The equal-height keyboard is the bug these assert against.** Comparing
    /// each row to `keyHeight ± rowHeightBias` is true of a zero bias as well,
    /// so the less/greater checks are what fail when nothing moved.
    func testTheNumbersRowPaysForTheTallerSpaceRow() throws {
        let layout = KeyboardCustomization.default
        let letters = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: false, customization: layout)
        let numbers = KeyboardLayout.rows(
            for: .english, plane: .numbers, showsGlobe: false, customization: layout)

        let letterRow = try XCTUnwrap(letters.first { $0.id == 0 })
        let letterSpace = try XCTUnwrap(
            letters.first { $0.id == KeyboardLayout.RowID.bottom })
        let numberRow = try XCTUnwrap(numbers.first { $0.id == 0 })
        let numberSpace = try XCTUnwrap(
            numbers.first { $0.id == KeyboardLayout.RowID.bottom })
        let brackets = try XCTUnwrap(numbers.first { $0.id == 1 })

        let letterHeight = letterRow.drawnHeight(
            keyHeight: Theme.Metrics.keyHeight, rowSpacing: Theme.Metrics.rowSpacing)
        let fitted = slidingKeyHeight(for: numbers, layout: layout, plane: .numbers)
        let numberHeight = numberRow.drawnHeight(
            keyHeight: fitted, rowSpacing: Theme.Metrics.rowSpacing)
        let bracketHeight = brackets.drawnHeight(
            keyHeight: fitted, rowSpacing: Theme.Metrics.rowSpacing)
        let spaceOnLetters = letterSpace.drawnHeight(
            keyHeight: Theme.Metrics.keyHeight, rowSpacing: Theme.Metrics.rowSpacing)
        let spaceOnNumbers = numberSpace.drawnHeight(
            keyHeight: Theme.Metrics.keyHeight, rowSpacing: Theme.Metrics.rowSpacing)

        XCTAssertGreaterThan(
            Theme.Metrics.rowHeightBias, 0,
            "a zero bias is the old equal-height keyboard")
        XCTAssertEqual(letterHeight, Theme.Metrics.keyHeight, accuracy: 0.001)
        XCTAssertEqual(spaceOnLetters, Theme.Metrics.keyHeight, accuracy: 0.001)
        XCTAssertLessThan(numberHeight, letterHeight)
        XCTAssertLessThan(numberHeight, bracketHeight)
        XCTAssertGreaterThan(spaceOnNumbers, spaceOnLetters)
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: layout),
            drawnKeyArea(layout, plane: .numbers), accuracy: 0.001,
            "the transfer grew or shrank the numbers plane")
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: layout),
            drawnKeyArea(layout, plane: .symbols), accuracy: 0.001,
            "tapping #+= changed the key-area height")
    }

    /// Same pair on the letters plane once the optional number row is on, so
    /// turning it on cannot change the height of anything already there.
    func testTheOptionalNumberRowPaysForTheTallerSpaceRow() throws {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: false, customization: layout)
        let numbers = try XCTUnwrap(
            rows.first { $0.id == KeyboardLayout.RowID.numbers })
        let space = try XCTUnwrap(
            rows.first { $0.id == KeyboardLayout.RowID.bottom })
        XCTAssertLessThan(numbers.heightBias, 0)
        XCTAssertGreaterThan(space.heightBias, 0)
        XCTAssertEqual(numbers.heightBias + space.heightBias, 0, accuracy: 0.001)
    }

    /// The host asks for `keyAreaHeight`, and `KeyboardView` pins the grid to
    /// that. Biases must cancel so the drawn letters grid still fills that frame;
    /// 123 / `#+=` must fit in it too.
    func testTheHostHeightMatchesWhatTheGridDraws() throws {
        let layouts = [
            KeyboardCustomization.default,
            try XCTUnwrap(LayoutPreset.named("power")).customization,
            try XCTUnwrap(LayoutPreset.named("compact")).customization
        ]
        for layout in layouts {
            XCTAssertEqual(
                Theme.Metrics.keyAreaHeight(for: layout),
                drawnKeyArea(layout, plane: .letters), accuracy: 0.001,
                "row height biases no longer cancel; the host would clip or grow")
        }
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: .default),
            drawnKeyArea(.default, plane: .numbers), accuracy: 0.001,
            "123 does not fit in the letters-plane host")
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: .default),
            drawnKeyArea(.default, plane: .symbols), accuracy: 0.001,
            "#+= does not fit in the letters-plane host")
    }

    func testAFourRowGridReproducesTheShippedHeight() {
        var fourRows = KeyboardCustomization.default
        fourRows.showsNumberRow = false
        fourRows.cursorRow = []
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: fourRows),
            Theme.Metrics.keyHeight * 4 + Theme.Metrics.rowSpacing * 3
                + Theme.Metrics.topInset + Theme.Metrics.bottomInset,
            accuracy: 0.001)
    }

    /// The number row is worth exactly one key plus one gap, which the old
    /// hardcoded `* 4` could not say.
    func testEachOptionalRowAddsOneRowOfHeight() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = false
        layout.cursorRow = []
        let base = Theme.Metrics.keyAreaHeight(for: layout)
        let oneRow = layout.geometry.keyHeight + layout.geometry.rowSpacing

        layout.showsNumberRow = true
        XCTAssertEqual(Theme.Metrics.keyAreaHeight(for: layout) - base, oneRow, accuracy: 0.001)

        layout.cursorRow = [SlotSpec(action: .cursorLeft)]
        XCTAssertEqual(
            Theme.Metrics.keyAreaHeight(for: layout) - base, oneRow * 2, accuracy: 0.001)
    }

    func testRoomyIsTallerThanCompact() {
        XCTAssertGreaterThan(
            Theme.Metrics.keyAreaHeight(for: LayoutPreset.named("roomy")!.customization),
            Theme.Metrics.keyAreaHeight(for: LayoutPreset.named("compact")!.customization))
    }

    /// The tallest total is the key area plus the three constant rows above it —
    /// that is what the fingerprint crop and the layout editor's ceiling both
    /// read. The live host height can omit the banner; see
    /// `totalHeight(for:showsBanner:)`.
    ///
    /// **The progress bar is the third, and the banner-on form still uses the
    /// three-point hairline.** The live banner-off height reserves the taller
    /// waveform slot instead; see `testTheWaveformSlotIsReservedWhileTheBannerIsDown`.
    func testTheTotalIsTheKeyAreaPlusTheThreeConstantRows() {
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default),
            Theme.Metrics.keyAreaHeight(for: .default)
                + Theme.Metrics.bannerHeight + Theme.Metrics.progressBarHeight
                + Theme.Metrics.suggestionBarHeight,
            accuracy: 0.001)
    }

    /// **The shipped keyboard sits exactly on the measured fingerprint cliff, with
    /// nothing left over, and this is the assertion that says so out loud.**
    ///
    /// `FrameReduction.Band.maximumOwnUI` is `368/874`: past 368 points the band
    /// the capture process fingerprints starts eating the host's own message lines
    /// and two conversations stop being told apart. `LayoutValidator` warns a
    /// *user* who builds a layout past it, which is their trade to make — but the
    /// default is not a choice anybody made in the editor, and it must never cross
    /// silently.
    ///
    /// The margin is zero, which is the point. A taller key or a bigger banner
    /// has to be paid for by shrinking something else, and this is what
    /// fails when it is not.
    func testTheShippedLayoutStillFitsUnderTheFingerprintCliff() {
        XCTAssertLessThanOrEqual(
            Theme.Metrics.totalHeight(for: .default),
            LayoutValidator.screenContextHeightLimit,
            "the shipped keyboard now costs screen context on every read")
        XCTAssertFalse(
            LayoutValidator.issues(in: .default)
                .contains { $0.kind == .costsScreenContext },
            "the default layout warns about itself")
    }

    /// Omitting the banner also swaps the three-point hairline for the reserved
    /// waveform slot, so the live height drops by the banner minus that extra
    /// twenty-one points rather than by the banner alone.
    func testOmittingTheBannerShortensTheLiveHeightByTheBanner() {
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, showsBanner: true)
                - Theme.Metrics.totalHeight(for: .default, showsBanner: false),
            Theme.Metrics.bannerHeight + Theme.Metrics.progressBarHeight
                - Theme.Metrics.recordingWaveformHeight,
            accuracy: 0.001)
    }

    /// The waveform slot is reserved while the banner is down, so opening the
    /// microphone cannot move the keys. Paid out of the banner-off budget: the
    /// fingerprint cliff is the banner-on total, which this slot does not reach.
    func testTheWaveformSlotIsReservedWhileTheBannerIsDown() {
        let live = Theme.Metrics.totalHeight(for: .default, showsBanner: false)
        XCTAssertEqual(
            live - Theme.Metrics.keyAreaHeight(for: .default)
                - Theme.Metrics.suggestionBarHeight,
            Theme.Metrics.recordingWaveformHeight,
            accuracy: 0.001)
        XCTAssertLessThan(
            live, Theme.Metrics.totalHeight(for: .default),
            "the reserved waveform slot must stay under the tallest form")
    }

    /// Across layouts, the tallest-form total still differs only by the key area.
    func testOnlyTheLayoutChangesTheTotalHeight() {
        let compact = LayoutPreset.named("compact")!.customization
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default) - Theme.Metrics.totalHeight(for: compact),
            Theme.Metrics.keyAreaHeight(for: .default) - Theme.Metrics.keyAreaHeight(for: compact),
            accuracy: 0.001)
    }

    /// The no-argument spellings still answer for the shipped layout, so nothing
    /// that called them before this feature had to change.
    func testTheConstantSpellingsStillAnswerForTheDefault() {
        XCTAssertEqual(Theme.Metrics.keyAreaHeight, Theme.Metrics.keyAreaHeight(for: .default))
        XCTAssertEqual(Theme.Metrics.totalHeight(), Theme.Metrics.totalHeight(for: .default))
    }

    /// How tall a sliding key is on this plane, matching `KeyboardView+Keys`.
    private func slidingKeyHeight(
        for rows: [KeyRow], layout: KeyboardCustomization, plane: KeyboardPlane
    ) -> CGFloat {
        let sliding = rows.filter {
            $0.id != KeyboardLayout.RowID.cursor && $0.id != KeyboardLayout.RowID.bottom
        }
        guard plane != .letters else { return layout.geometry.keyHeight }
        return Theme.Metrics.fittedKeyHeight(
            slidingRows: sliding.count,
            referenceRows: 3 + (layout.showsNumberRow ? 1 : 0),
            keyHeight: layout.geometry.keyHeight,
            rowSpacing: layout.geometry.rowSpacing)
    }

    /// The whole key area a plane paints, including the action row and insets —
    /// the number `KeyboardView` pins its grid to.
    private func drawnKeyArea(_ layout: KeyboardCustomization, plane: KeyboardPlane) -> CGFloat {
        let rows = KeyboardLayout.rows(
            for: .english, plane: plane, showsGlobe: false, customization: layout)
        let spacing = layout.geometry.rowSpacing
        let slidingBase = slidingKeyHeight(for: rows, layout: layout, plane: plane)
        let keys = rows.reduce(CGFloat(0)) { total, row in
            let base =
                (row.id == KeyboardLayout.RowID.bottom
                    || row.id == KeyboardLayout.RowID.cursor)
                ? layout.geometry.keyHeight : slidingBase
            return total + row.drawnHeight(keyHeight: base, rowSpacing: spacing)
        }
        return keys + spacing * CGFloat(max(0, rows.count - 1))
            + Theme.Metrics.topInset + Theme.Metrics.bottomInset
    }
}

// KeySpec.characterValue extension lives in CustomLayoutCompilerTests.swift.
