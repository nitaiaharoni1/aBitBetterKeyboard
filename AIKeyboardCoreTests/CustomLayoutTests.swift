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
            .shift, .backspace, .numbersPlane, .symbolsPlane, .globe, .space, .ret,
            .dictation, .emoji, .aiMenu, .quickTone, .cursorLeft, .cursorRight,
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
            [.numbersPlane, .globe, .space, .punctuation, .ret])
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

    /// All five marks are already on the row above, and a second `char-.` on one
    /// plane is a `ForEach` with duplicate identity.
    func testThePunctuationKeyIsDroppedOffTheLettersPlane() {
        for plane in [KeyboardPlane.numbers, .symbols] {
            let rows = KeyboardLayout.rows(
                for: .english, plane: plane, showsGlobe: true, customization: .default)
            XCTAssertFalse(
                rows.flatMap(\.keys)
                    .contains { $0.addressableID == KeyboardLayout.punctuationKeyID },
                "\(plane)")
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
        let caps: [KeyCap] = [.emoji, .aiMenu, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard]
        let labels = caps.map(\.accessibilityLabel)
        XCTAssertEqual(Set(labels).count, caps.count, "two caps share a label: \(labels)")
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    /// Distinct ids for the same reason: `KeySpec.identifier(for:)` derives from
    /// the cap, and a collision is a `ForEach` with duplicate identity.
    func testNewCapsHaveDistinctSpecIDs() {
        let caps: [KeyCap] = [.emoji, .aiMenu, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard]
        XCTAssertEqual(Set(caps.map { KeySpec($0).id }).count, caps.count)
    }

    func testTheNewCapsAreFunctionKeys() {
        for cap in [KeyCap.emoji, .aiMenu, .quickTone, .cursorLeft, .cursorRight, .hideKeyboard] {
            XCTAssertTrue(cap.isFunctionKey, "\(cap) should not be treated as a character key")
        }
    }

    // MARK: Compiling

    /// **The letter rows are untouched by customization, in every language and on
    /// every plane.** This is the load-bearing test of the whole feature.
    ///
    /// It used to compare the *whole* compiled keyboard against the pre-feature
    /// one, which was the right check for as long as the default was a no-op. The
    /// default deliberately changed — dictation moved to the action row and the
    /// bar was emptied — so that comparison now pins a product decision rather
    /// than an invariant. What must never change is this: whatever the user does,
    /// the three rows that come out of `letterLayouts` come out unaltered.
    func testCustomizationNeverTouchesTheLetterRows() {
        var wild = KeyboardCustomization.default
        wild.showsNumberRow = true
        wild.bottomRow = [
            SlotSpec(action: .numbersPlane), SlotSpec(action: .globe),
            SlotSpec(action: .space, width: .fill), SlotSpec(action: .ret)
        ]
        wild.cursorRow = [SlotSpec(action: .text("x"), width: .fill)]

        for language in KeyboardLanguage.allCases {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                let stock = KeyboardLayout.rows(for: language, plane: plane)
                for layout in [KeyboardCustomization.default, wild] {
                    let compiled = KeyboardLayout.rows(
                        for: language, plane: plane, showsGlobe: true, customization: layout)
                    // The stock rows appear in order, unaltered, somewhere in the
                    // compiled set: after the number row when there is one.
                    let offset = (layout.showsNumberRow && plane == .letters) ? 1 : 0
                    for (index, row) in stock.enumerated() {
                        let mine = compiled[index + offset]
                        XCTAssertEqual(
                            row.keys.map(\.cap), mine.keys.map(\.cap), "\(language) \(plane)")
                        XCTAssertEqual(
                            row.keys.map(\.width), mine.keys.map(\.width), "\(language) \(plane)")
                        XCTAssertEqual(
                            row.sideInsetUnits, mine.sideInsetUnits, "\(language) \(plane)")
                    }
                }
            }
        }
    }

    /// The compiled bottom row is exactly what the model describes, in order.
    func testTheBottomRowCompilesToWhatTheModelSays() {
        let layout = KeyboardCustomization.default
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true,
            customization: layout)[KeyboardLayout.RowID.bottom]
        XCTAssertEqual(row.keys.count, layout.bottomRow.count)
        XCTAssertEqual(
            row.keys.map(\.width),
            layout.bottomRow.map { spec in
                switch spec.width {
                case .fill: return KeyWidth.flexible
                case .units(let value): return KeyWidth.unit(value)
                }
            })
    }


    func testEveryRowHasAUniqueID() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        layout.cursorRow = [SlotSpec(action: .cursorLeft), SlotSpec(action: .cursorRight)]
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
    }

    func testTheNumberRowSitsAboveTheLetters() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(
            rows.first?.keys.compactMap(\.characterValue),
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
    }

    /// Arabic and Persian do not write their digits with the same glyphs, and
    /// `KeyboardLanguage.digits` already knows.
    func testTheNumberRowUsesTheLanguagesOwnDigits() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = true
        let rows = KeyboardLayout.rows(
            for: .arabic, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(
            rows.first?.keys.compactMap(\.characterValue).joined(), KeyboardLanguage.arabic.digits)
    }

    /// The digits are already the top row of the numbers plane; drawing them twice
    /// is not a feature.
    func testTheNumberRowIsNotDrawnOnTheNumbersPlane() {
        var layout = KeyboardCustomization.default
        layout.showsNumberRow = false
        let without = KeyboardLayout.rows(
            for: .english, plane: .numbers, showsGlobe: true, customization: layout).count
        layout.showsNumberRow = true
        let with = KeyboardLayout.rows(
            for: .english, plane: .numbers, showsGlobe: true, customization: layout).count
        // The digits are already the top row here; drawing them twice is not a
        // feature. Compared rather than counted, because the default also ships an
        // action row and an absolute count pins two decisions at once.
        XCTAssertEqual(with, without)
    }

    func testTheCursorRowSitsBelowTheBottomRow() {
        var layout = KeyboardCustomization.default
        layout.cursorRow = [SlotSpec(action: .cursorLeft), SlotSpec(action: .cursorRight)]
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertEqual(rows.last?.keys.map(\.cap), [.cursorLeft, .cursorRight])
    }

    /// The layout stores the globe; iOS decides whether it is drawn.
    func testTheGlobeKeyDropsOutWhenTheSystemDoesNotWantIt() {
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: false, customization: .default)
        XCTAssertFalse(rows.flatMap(\.keys).contains { $0.cap == .globe })
    }

    /// The plane key is resolved at draw time, so it says where it goes *back* to.
    func testTheBottomRowSwitchesBackFromTheNumbersPlane() {
        let rows = KeyboardLayout.rows(
            for: .hebrew, plane: .numbers, showsGlobe: true, customization: .default)
        // Addressed by id, not by `last`: the default ships an action row below
        // the bottom one, so `rows.last` stopped being the bottom row.
        XCTAssertTrue(
            rows[KeyboardLayout.RowID.bottom].keys.map(\.cap)
                .contains(.plane(.letters, label: KeyboardLanguage.hebrew.lettersPlaneLabel)))
    }

    /// **A plane key must go somewhere it is not, on every plane it is drawn on.**
    /// `.symbolsPlane` used to resolve to the letters plane from letters and to
    /// the symbols plane from symbols, so a symbols key the user placed themselves
    /// drew, pressed and switched to the plane already showing on two planes out
    /// of three.
    func testAPlaneKeyNeverTargetsThePlaneItIsStandingOn() {
        for action in [SlotAction.numbersPlane, .symbolsPlane] {
            for plane in [KeyboardPlane.letters, .numbers, .symbols] {
                var layout = KeyboardCustomization.default
                layout.bottomRow = [
                    SlotSpec(action: action), SlotSpec(action: .numbersPlane),
                    SlotSpec(action: .globe), SlotSpec(action: .space, width: .fill),
                    SlotSpec(action: .ret)
                ]
                let rows = KeyboardLayout.rows(
                    for: .english, plane: plane, showsGlobe: true, customization: layout)
                guard case .plane(let destination, _) = rows[3].keys[0].cap else {
                    return XCTFail("\(action) on \(plane) is not a plane key")
                }
                XCTAssertNotEqual(
                    destination, plane,
                    "\(action) on the \(plane) plane switches to the plane it is already on")
            }
        }
    }

    func testTheSymbolsKeyReachesTheSymbolsPlaneFromLetters() {
        var layout = KeyboardCustomization.default
        layout.bottomRow[0] = SlotSpec(action: .symbolsPlane, width: .units(1.3))
        let rows = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)
        XCTAssertTrue(
            rows[KeyboardLayout.RowID.bottom].keys.map(\.cap)
                .contains(.plane(.symbols, label: "#+=")))
    }

    /// A key has to stay addressable by a test and a screen reader *and* be unique
    /// on its row. Both halves, in one assertion.
    func testCompiledKeysKeepAnAddressableIDAndAUniqueOne() {
        var layout = KeyboardCustomization.default
        layout.bottomRow.append(SlotSpec(action: .text(",")))
        layout.bottomRow.append(SlotSpec(action: .text(",")))
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: layout)[3]

        let commas = row.keys.filter { $0.cap == .character(",") }
        XCTAssertEqual(commas.count, 2)
        XCTAssertNotEqual(commas[0].id, commas[1].id, "two keys with one ForEach identity")
        XCTAssertTrue(commas.allSatisfy { $0.addressableID == "char-," })
    }

    func testTheDefaultBottomRowKeepsItsShippedIdentifiers() {
        let row = KeyboardLayout.rows(
            for: .english, plane: .letters, showsGlobe: true, customization: .default)[3]
        XCTAssertEqual(
            row.keys.map(\.addressableID),
            ["plane-123", "globe", "space", KeyboardLayout.punctuationKeyID, "return"])
    }

    /// A key that was never compiled from a slot has no suffix to strip.
    func testAnOrdinaryKeysAddressableIDIsItsID() {
        XCTAssertEqual(KeySpec(.space).addressableID, "space")
        XCTAssertEqual(KeySpec(.character("a")).addressableID, "char-a")
    }

    // MARK: Presets

    func testThereAreFivePresetsWithUniqueIDs() {
        XCTAssertEqual(LayoutPreset.all.count, 5)
        XCTAssertEqual(Set(LayoutPreset.all.map(\.id)).count, 5)
    }

    func testEveryPresetValidatesClean() {
        for preset in LayoutPreset.all {
            let errors = LayoutValidator.issues(in: preset.customization, showsGlobe: true)
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
                        let units = row.keys.reduce(CGFloat(0)) { total, key in
                            switch key.width {
                            case .unit(let value): return total + value
                            // A stretcher still needs somewhere to stand.
                            case .flexible, .remainderShare: return total + 1
                            }
                        }
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
        for action in [SlotAction.emoji, .aiMenu, .quickTone] {
            XCTAssertTrue(SuggestionBar.barCatalogue.contains(action), "\(action) is missing")
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

    /// The total is the key area plus the two constant rows above it. This used to
    /// check that the context strip was added only while a session was live;
    /// `bannerHeight` replaced it precisely so the keyboard stops changing height
    /// under the user's thumb, so the property worth pinning is the opposite one.
    func testTheTotalIsTheKeyAreaPlusTheTwoConstantRows() {
        XCTAssertEqual(
            Theme.Metrics.totalHeight(for: .default),
            Theme.Metrics.keyAreaHeight(for: .default)
                + Theme.Metrics.bannerHeight + Theme.Metrics.suggestionBarHeight,
            accuracy: 0.001)
    }

    /// The layout is the only thing that moves the total now.
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

extension KeySpec {
    fileprivate var characterValue: String? {
        if case .character(let value) = cap { return value }
        return nil
    }
}
