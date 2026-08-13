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
            .dictation, .emoji, .quickTone, .cursorLeft, .cursorRight,
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

    /// **The punctuation key is not `text(".")`, and the difference is the hold
    /// strip and a language.** A literal full stop looks identical on the cap and
    /// silently loses the long presses and the script's own mark, which is exactly
    /// the substitution somebody will make while reading the row.
    func testThePunctuationKeyKeepsItsLongPressMarks() {
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: .default)[3]
        let key = row.keys.first { $0.addressableID == KeyboardLayout.punctuationKeyID }
        XCTAssertNotNil(key)
        XCTAssertFalse(key?.alternates.isEmpty ?? true, "the long-press marks are gone")
        XCTAssertEqual(
            key?.alternates, ["!", "@", "#", ",", "?"],
            "the strip is not ! @ # , . ? with the stop on the cap")
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
            .settings, .emoji, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard
        ]
        let labels = caps.map(\.accessibilityLabel)
        XCTAssertEqual(Set(labels).count, caps.count, "two caps share a label: \(labels)")
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    /// Distinct ids for the same reason: `KeySpec.identifier(for:)` derives from
    /// the cap, and a collision is a `ForEach` with duplicate identity.
    func testNewCapsHaveDistinctSpecIDs() {
        let caps: [KeyCap] = [
            .settings, .emoji, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard
        ]
        XCTAssertEqual(Set(caps.map { KeySpec($0).id }).count, caps.count)
    }

    func testTheNewCapsAreFunctionKeys() {
        for cap in [
            KeyCap.settings, .emoji, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard
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
    /// **The progress bar is the third, and it is in every form of this.** It was
    /// two rows until a model call stopped drawing a banner and started drawing a
    /// three-point line above the candidates instead; that line's height is
    /// reserved whether or not anything is running, so a call starting cannot move
    /// the keyboard under a thumb.
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
    /// The margin is zero, which is the point. Adding the three-point progress bar
    /// meant taking three points off the banner (72 → 69); a future row, a taller
    /// key or a bigger banner has to be paid for the same way, and this is what
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

    /// Omitting the banner shortens the live height by exactly that row.
    func testOmittingTheBannerShortensTheLiveHeightByTheBanner() {
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default, showsBanner: true)
                - Theme.Metrics.totalHeight(for: .default, showsBanner: false),
            Theme.Metrics.bannerHeight,
            accuracy: 0.001)
    }

    /// A live recording grows the hairline, and that growth is paid while the
    /// banner is down — so the fingerprint cliff, which is the banner-on total,
    /// is not crossed.
    func testARecordingGrowsTheHairlineWithoutCrossingTheFingerprintCliff() {
        let recording = Theme.Metrics.totalHeight(
            for: .default, showsBanner: false, isRecording: true)
        let idle = Theme.Metrics.totalHeight(
            for: .default, showsBanner: false, isRecording: false)
        XCTAssertEqual(
            recording - idle,
            Theme.Metrics.recordingWaveformHeight - Theme.Metrics.progressBarHeight,
            accuracy: 0.001)
        XCTAssertLessThan(
            recording, Theme.Metrics.totalHeight(for: .default),
            "a recording without a banner must stay under the tallest form")
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
}

// KeySpec.characterValue extension lives in CustomLayoutCompilerTests.swift.
