import XCTest

@testable import AIKeyboardCore

@MainActor
extension EmojiModeTests {
    func testAnOpenEmojiGridAlwaysHasAWayBack() {
        // Emoji ships on the bottom row, and no surface above the grid carries a
        // second one that could close it.
        let layout = KeyboardCustomization.default
        XCTAssertTrue(layout.bottomRow.contains { $0.action == .emoji })
        XCTAssertTrue(KeyboardOverlay.emoji.showsActionRow)
        XCTAssertFalse(
            (layout.cursorRow + layout.barLeading + layout.barTrailing)
                .contains { $0.action == .emoji },
            "an Emoji key above the grid would close it, and there is none")

        // The key reads `אבג` rather than a smiling face while the grid is up, so
        // it says what it does.
        XCTAssertEqual(KeyboardLanguage.hebrew.lettersPlaneLabel, "אבג")
        XCTAssertEqual(KeyboardLanguage.english.lettersPlaneLabel, "ABC")

        // Tapping it really does leave the grid.
        let controller = KeyboardController(target: RecordingTextTarget(), language: .hebrew)
        controller.show(.emoji)
        XCTAssertEqual(controller.overlay, .emoji)
        controller.press(.emoji)
        XCTAssertEqual(
            controller.overlay, KeyboardOverlay.none,
            "the Emoji key on the bottom row has to close the grid it opened")

        // **And the row it sits in is not a row a panel may cover.** This is the
        // assertion the broken build fails and the only one that does — there,
        // the bottom row was inside the panel's own stack and `panelCovers` would
        // have answered true for it. `showsLetterKeys` is unchanged either way,
        // which is exactly why it cannot be the thing asserted on.
        XCTAssertFalse(
            KeyboardView.panelCovers(rowID: KeyboardLayout.RowID.bottom),
            "the grid stands over the key that closes it")
        // The three letter rows, the number row and the symbols plane's fourth row
        // all still go under it.
        for covered in [0, 1, 2, KeyboardLayout.RowID.numbers, KeyboardLayout.RowID.extraSymbols] {
            XCTAssertTrue(KeyboardView.panelCovers(rowID: covered), "row \(covered)")
        }
        XCTAssertFalse(
            KeyboardOverlay.emoji.showsLetterKeys,
            "the letter rows are still the ones a panel replaces")
    }

    // MARK: Skin tones

    /// **Every strip is six spellings of the same emoji, and none of them is
    /// constructed here.** The generator looks each toned sequence up in
    /// `emoji-test.txt` rather than building it from a rule, because the rule is
    /// only how the candidate is *spelled*, not proof that Unicode fully
    /// qualifies it: 👋 takes all five tones and 👨‍👩‍👦 — which has three modifier
    /// bases in it — takes none at all below Emoji 16. A build that derived the
    /// strips instead would put tofu boxes under half the People tab, and the
    /// grid itself would look perfectly fine.
    ///
    /// Asserted by stripping the tone back off and demanding the base returns,
    /// which is what rejects a strip that quietly points at a *different* emoji.
    /// `variants.count == 6` alone is true of that build.
    func testEveryToneStripIsSixSpellingsOfTheSameEmoji() {
        let tonable = EmojiCatalog.all.filter(EmojiCatalog.hasTones)
        XCTAssertGreaterThan(tonable.count, 250, "the strips did not load at all")

        for base in tonable {
            let variants = EmojiCatalog.variants(for: base)
            XCTAssertEqual(variants.count, 6, "\(base) has \(variants.count) variants")
            XCTAssertEqual(variants.first, base, "\(base) does not lead its own strip")
            XCTAssertEqual(Set(variants).count, 6, "\(base) repeats a spelling")

            for variant in variants.dropFirst() {
                XCTAssertTrue(
                    variant.unicodeScalars.contains { Self.toneScalars.contains($0.value) },
                    "\(variant) is in \(base)'s strip wearing no tone")
                // The same emoji underneath: tone modifiers off, and U+FE0F off
                // both sides because applying a tone consumes it — Unicode
                // spells ☝️ toned as ☝🏻, with no variation selector left.
                XCTAssertEqual(
                    Self.skeleton(variant), Self.skeleton(base),
                    "\(variant) is a different emoji from \(base)")
                XCTAssertEqual(
                    EmojiCatalog.untoned(variant), base,
                    "\(variant) does not lead back to \(base)")
            }
        }
    }

    /// The fifteen hundred with no toned form, and the three hundred with one,
    /// asserted by name — so a generator that starts inventing strips is caught
    /// by the picture rather than by a count that could drift either way.
    func testOnlyTheEmojiUnicodeTonesHaveAStrip() {
        for toned in ["👋", "👍", "✌️", "🤝", "🙏", "👩‍💻", "☝️"] {
            XCTAssertTrue(EmojiCatalog.hasTones(toned), "\(toned) lost its tones")
        }
        // A face, an animal, an object and a heart have no skin. The two family
        // sequences are the ones a derived-by-rule build gets wrong: they are
        // built out of people and still have no toned form under Emoji 16.
        for plain in ["😂", "🐶", "🎉", "❤️", "🧑‍🤝‍🧑", "👨‍👩‍👦"] {
            XCTAssertFalse(EmojiCatalog.hasTones(plain), "\(plain) grew a tone strip")
            XCTAssertEqual(EmojiCatalog.variants(for: plain), [])
            // And asking for a tone it does not have hands the emoji back
            // unchanged rather than an empty string or a modifier on its own.
            XCTAssertEqual(EmojiCatalog.toned(plain, .dark), plain)
        }
    }

    /// `toned` and `tone(of:)` are the two halves of one mapping, and the panel
    /// leans on both: one to draw a cell, the other to know which item of a strip
    /// the finger is resting on. A build where they disagree opens every picker
    /// on the plain emoji however the grid is painted.
    func testATonedSpellingRemembersWhichToneItIs() {
        for base in ["👋", "✌️", "👩‍💻"] {
            XCTAssertEqual(EmojiCatalog.tone(of: base), .generic)
            for tone in EmojiSkinTone.allCases {
                let spelled = EmojiCatalog.toned(base, tone)
                XCTAssertEqual(EmojiCatalog.tone(of: spelled), tone, "\(spelled)")
                XCTAssertEqual(EmojiCatalog.untoned(spelled), base, "\(spelled)")
                // Idempotent: the grid hands `toned` whatever it drew last time.
                XCTAssertEqual(EmojiCatalog.toned(spelled, tone), spelled)
            }
        }
        // Nothing this catalogue has never heard of is mangled on the way past.
        XCTAssertEqual(EmojiCatalog.untoned("hello"), "hello")
        XCTAssertEqual(EmojiCatalog.tone(of: "hello"), .generic)
    }

    /// **The raw values are positions in a strip and are persisted**, so a
    /// renumbering would silently repaint every keyboard that had a tone saved.
    func testTheToneRawValuesIndexTheStripTheyAreDrawnFrom() {
        let variants = EmojiCatalog.variants(for: "👋")
        for tone in EmojiSkinTone.allCases {
            XCTAssertEqual(
                variants[tone.rawValue], EmojiCatalog.toned("👋", tone),
                "\(tone) is not item \(tone.rawValue) of the strip")
        }
        XCTAssertEqual(EmojiSkinTone.generic.rawValue, 0)
        XCTAssertEqual(EmojiSkinTone.dark.rawValue, 5)
        // A number from a newer build is a plain emoji, not a crash and not a
        // tone nobody picked.
        XCTAssertEqual(EmojiSkinTone.stored(6), .generic)
        XCTAssertEqual(EmojiSkinTone.stored(-1), .generic)
    }

    /// **A finger that opened the strip and lifted without moving must change
    /// nothing**, and the naive build gets this wrong in a way that is invisible
    /// until it repaints the whole grid: the strip is centred on the *cell*, so a
    /// thumb that has not moved is sitting over the middle of it — item 3 of 6,
    /// medium skin tone, which nobody aimed at.
    ///
    /// Asserted at a location that really is over another item, because
    /// `indexOnLift` at the rest item's own coordinates passes against the bug.
    func testLiftingWithoutSlidingKeepsTheToneTheGridAlreadyHad() {
        let origin = CGPoint(x: 100, y: 40)
        let middle = CGPoint(x: origin.x + 38 * 3.5, y: 50)
        XCTAssertEqual(
            EmojiTonePicker.index(at: middle, origin: origin, itemWidth: 38, count: 6), 3,
            "the middle of a six-item strip is where a standing finger is")

        for rest in 0..<6 {
            XCTAssertEqual(
                EmojiTonePicker.indexOnLift(
                    translation: CGSize(width: 2, height: -1), location: middle, origin: origin,
                    itemWidth: 38, count: 6, restIndex: rest),
                rest,
                "a 2pt wobble picked item 3 over the resting item \(rest)")
        }

        // And a real slide does choose: the same point, reached by moving.
        XCTAssertEqual(
            EmojiTonePicker.indexOnLift(
                translation: CGSize(width: 60, height: 0), location: middle, origin: origin,
                itemWidth: 38, count: 6, restIndex: 0),
            3)
    }

    /// A finger that runs off the end of the strip picks the end of it, not an
    /// index that is off the array. `variants[picked]` is a real subscript on the
    /// lift.
    func testSlidingPastEitherEndOfTheStripStaysOnIt() {
        let origin = CGPoint(x: 100, y: 40)
        for x: CGFloat in [-4000, 0, 99] {
            XCTAssertEqual(
                EmojiTonePicker.index(
                    at: CGPoint(x: x, y: 50), origin: origin, itemWidth: 38, count: 6),
                0, "x \(x)")
        }
        for x: CGFloat in [329, 4000] {
            XCTAssertEqual(
                EmojiTonePicker.index(
                    at: CGPoint(x: x, y: 50), origin: origin, itemWidth: 38, count: 6),
                5, "x \(x)")
        }
    }

    /// **The strip has to stay inside the emoji panel, it has to be reachable,
    /// and it must not sit under the finger holding the cell.**
    ///
    /// Three failures this rejects, and the third is the one that shipped in the
    /// first draft. A letter's accent strip may hang over the suggestion bar
    /// because the keyboard draws both; this one is drawn by the panel and is
    /// simply cut off, so the top row — where "above the cell" is off the panel
    /// entirely — has to flip below. **Flipping below and clamping is not enough
    /// on its own**: the *bottom* row has nothing under it, so the clamp drags
    /// the strip back up onto the cell the finger is on, and the picker is
    /// hidden by the thumb that opened it. `EmojiTonePicker.origin` takes the
    /// roomier side when neither fits, which puts that case above the fingertip.
    ///
    /// Swept over every geometry `LayoutGeometry` can describe rather than over
    /// one panel, because the counterexample is a *landscape* one: 30 points of
    /// room above the bottom row, 26 below, and a 34 pt strip that fits in
    /// neither. `Bar` cannot help here — there is no corpus for a popup — so the
    /// sweep is the measurement.
    func testTheToneStripStaysInsideThePanelAndOffTheFingerHoldingIt() {
        let configs = toneConfigs()

        var overlapping = 0
        for config in configs {
            // The panel is three letter rows and two gaps; see
            // `KeyboardView.panelCovers(rowID:)`.
            let panelHeight = config.key * 3 + config.spacing * 2
            let gridHeight = panelHeight - EmojiPanel.categoryRowHeight(forKeyHeight: config.key)
            let rows = EmojiPanel.rowCount(forGridHeight: gridHeight)
            let cellHeight = gridHeight / CGFloat(rows)
            let columns = max(1, (config.width / EmojiPanel.targetCellWidth).rounded())
            let cellWidth = config.width / columns
            let surface = CGSize(width: config.width, height: panelHeight)
            let item = EmojiTonePicker.item(
                cellWidth: cellWidth, cellHeight: cellHeight, count: 6, surface: surface)
            let size = CGSize(width: item.width * 6, height: item.height)

            for row in 0..<rows {
                for column in [0, Int(columns) / 2, Int(columns) - 1] {
                    let anchor = CGRect(
                        x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight,
                        width: cellWidth, height: cellHeight)
                    let origin = EmojiTonePicker.origin(
                        anchor: anchor, size: size, surface: surface)
                    let context =
                        "\(config.name) key \(config.key) gap \(config.spacing) "
                        + "width \(config.width) row \(row)/\(rows) column \(column)"

                    XCTAssertGreaterThanOrEqual(origin.x, 0, context)
                    XCTAssertGreaterThanOrEqual(origin.y, 0, context)
                    XCTAssertLessThanOrEqual(
                        origin.x + size.width, surface.width + 0.001, context)
                    XCTAssertLessThanOrEqual(
                        origin.y + size.height, surface.height + 0.001, context)

                    // **The one a clamped strip fails.** The finger is on the
                    // middle of the cell it held, so that point is the one the
                    // strip may never cover.
                    let fingertip = anchor.midY
                    XCTAssertFalse(
                        origin.y <= fingertip && fingertip <= origin.y + size.height,
                        "the strip is under the finger that opened it: \(context)")

                    // And every one of the six can be landed on: the hit test at
                    // an item's own centre names that item, wherever the strip
                    // was pushed to.
                    for index in 0..<6 {
                        let centre = CGPoint(
                            x: origin.x + (CGFloat(index) + 0.5) * item.width, y: origin.y + 1)
                        XCTAssertEqual(
                            EmojiTonePicker.index(
                                at: centre, origin: origin, itemWidth: item.width, count: 6),
                            index, "item \(index) is not reachable: \(context)")
                    }

                    let overlap =
                        min(origin.y + size.height, anchor.maxY) - max(origin.y, anchor.minY)
                    if overlap > 0.001 { overlapping += 1 }
                }
            }
        }

        // Portrait clears the cell outright at every row of every row count; the
        // only overlap in the whole sweep is landscape's bottom row, where
        // nothing fits either side. Asserted as a number so a change that starts
        // covering cells in portrait is a failure rather than a shrug.
        XCTAssertEqual(overlapping, 3, "the strip started landing on cells it should clear")
    }

    private func toneConfigs() -> [(name: String, key: CGFloat, spacing: CGFloat, width: CGFloat)] {
        var configs: [(name: String, key: CGFloat, spacing: CGFloat, width: CGFloat)] = [
            ("landscape", Theme.Metrics.Landscape.keyHeight, 4, 736)]
        for key in stride(from: LayoutGeometry.keyHeightRange.lowerBound,
                          through: LayoutGeometry.keyHeightRange.upperBound, by: 4) {
            for spacing in stride(from: LayoutGeometry.rowSpacingRange.lowerBound,
                                  through: LayoutGeometry.rowSpacingRange.upperBound, by: 4) {
                for width in [320, 402, 430] as [CGFloat] {
                    configs.append(("portrait", key, spacing, width))
                }
            }
        }
        return configs
    }

    /// **Six items wider than the panel would put the darkest tone off the edge,
    /// where no finger can land on it** — a picker with a choice in it that
    /// cannot be chosen. The narrow case is not hypothetical: the layout editor
    /// builds keyboards this panel has to fit inside.
    func testTheToneStripShrinksRatherThanRunningOffANarrowPanel() {
        let narrow = CGSize(width: 180, height: 150)
        let item = EmojiTonePicker.item(
            cellWidth: 38, cellHeight: 30, count: 6, surface: narrow)
        XCTAssertLessThanOrEqual(item.width * 6, narrow.width)
        XCTAssertGreaterThan(item.width, 0)

        // A roomy panel keeps the readable size, and the item is never smaller
        // than a category tab in the axis the finger is not sliding along.
        let roomy = EmojiTonePicker.item(
            cellWidth: 38, cellHeight: 29.5, count: 6, surface: CGSize(width: 402, height: 156))
        XCTAssertEqual(roomy.width, 38)
        XCTAssertGreaterThanOrEqual(roomy.height, 34)
    }

    /// **The picked tone is the whole grid's, and it survives the extension being
    /// killed** — which iOS does whenever the host app changes field. A tone held
    /// in memory alone is a tone the user picks again every few minutes.
    @MainActor
    func testAPickedToneIsRememberedForTheWholeGrid() {
        let store = SharedStore.shared
        let tone = store.emojiSkinTone
        let recents = store.recentEmoji
        defer {
            store.emojiSkinTone = tone
            store.recentEmoji = recents
        }

        store.emojiSkinTone = .generic
        let controller = KeyboardController(target: RecordingTextTarget())
        XCTAssertEqual(controller.emojiSkinTone, .generic)

        controller.setEmojiSkinTone(.mediumDark)
        XCTAssertEqual(controller.emojiSkinTone, .mediumDark)
        // Through the store, not just the published copy: this is the assertion
        // a build that only set the property passes nothing of.
        XCTAssertEqual(store.storedEmojiSkinTone, .mediumDark)

        // A fresh controller is what the next launch of the extension is.
        let relaunched = KeyboardController(target: RecordingTextTarget())
        XCTAssertEqual(relaunched.emojiSkinTone, .mediumDark)
        XCTAssertEqual(EmojiCatalog.toned("👋", relaunched.emojiSkinTone), "👋🏾")
    }

    /// **Recents record the untoned spelling, and the document gets the toned
    /// one.** Storing what was inserted would leave the Recent tab holding five
    /// spellings of the same wave after five holds, and would strand somebody
    /// else's tone there the moment the user went back to plain — a tab whose
    /// whole job is muscle memory, showing emoji the grid no longer draws.
    ///
    /// Asserted on the tab having *one* entry, because "Recents contains a wave"
    /// is true of the broken build too.
    @MainActor
    func testRecentsRecordOneWaveHoweverManyTonesArePickedFromIt() {
        let store = SharedStore.shared
        let tone = store.emojiSkinTone
        let recents = store.recentEmoji
        defer {
            store.emojiSkinTone = tone
            store.recentEmoji = recents
        }
        store.recentEmoji = []

        let target = RecordingTextTarget()
        let controller = KeyboardController(target: target)
        for picked in EmojiSkinTone.allCases {
            controller.insertEmoji(EmojiCatalog.toned("👋", picked))
        }

        XCTAssertEqual(
            controller.recentEmoji.filter { EmojiCatalog.untoned($0) == "👋" }.count, 1,
            "recents: \(controller.recentEmoji)")
        XCTAssertEqual(controller.recentEmoji.first, "👋")
        XCTAssertFalse(
            controller.recentEmoji.contains { EmojiCatalog.tone(of: $0) != .generic },
            "a tone modifier reached the Recent tab: \(controller.recentEmoji)")
        // The document, though, got exactly what each cell was showing.
        XCTAssertEqual(
            target.inserted, EmojiSkinTone.allCases.map { EmojiCatalog.toned("👋", $0) })
    }

    // MARK: Helpers

    static let toneScalars: Set<UInt32> = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]

    /// The emoji with every tone modifier and every variation selector taken
    /// off — what two spellings of the same picture have in common.
    static func skeleton(_ emoji: String) -> [UInt32] {
        emoji.unicodeScalars.map(\.value).filter {
            !toneScalars.contains($0) && $0 != 0xFE0F
        }
    }

    // MARK: A strip whose cell is gone

    /// **The grid stops scrolling while a strip is open, on purpose, so a strip
    /// nobody can close is a grid nobody can scroll.** Every path that clears
    /// `EmojiPanel.tonePicker` lives in `EmojiPickCell` and is guarded on that
    /// cell still owning it, so an owner that is no longer on the strip has no
    /// writer at all and `scrollDisabled` stays on until the panel is closed.
    ///
    /// The broken version returns the picker unchanged, which is why the
    /// assertion is `XCTAssertNil` rather than anything about the contents.
    func testAStripWhoseCellIsNoLongerOnTheGridDoesNotSurviveARebuild() {
        let sections = EmojiPanel.sections(recent: [], rowCount: 4)
        let orphan = picker(owner: "People-999999")

        XCTAssertNil(EmojiPanel.pickerSurviving(orphan, in: sections))
    }

    /// The control the test above needs: a function that always answered nil
    /// would pass it, and would close every tone strip the instant a rebuild
    /// touched the grid.
    ///
    /// **The cell is found by looking for one that holds an emoji, not by taking
    /// `sections.first?.cells.first`.** With `recent: []` the first section is
    /// Recent with *zero* cells — `0 % rowCount` is 0, so it is not even padded —
    /// and that spelling unwrapped nil and failed this test for a reason that had
    /// nothing to do with what it is checking. A padding blank would be just as
    /// wrong: it carries no emoji, so it never gets an `EmojiPickCell` and can
    /// never own a strip.
    func testAStripWhoseCellIsStillThereSurvivesARebuild() throws {
        let sections = EmojiPanel.sections(recent: [], rowCount: 4)
        let live = try XCTUnwrap(
            sections.flatMap(\.cells).first(where: { $0.emoji != nil })?.id)
        let open = picker(owner: live)

        XCTAssertEqual(EmojiPanel.pickerSurviving(open, in: sections)?.owner, live)
    }

    /// **Recents is the list that actually moves, and the row count is not.**
    ///
    /// This test replaced one asserting that a rebuild at a different row count
    /// renumbers cells. It does not: `section(_:)` mints `"\(id)-\(offset)"` from
    /// the position within the category's own emoji array, which no row count
    /// touches. Only the padding blanks move, and a blank has no emoji, so it gets
    /// no `EmojiPickCell` and can never own a strip. Rotation was never the hazard.
    ///
    /// What moves is Recents. Hold the fourth entry and let the list shrink, and
    /// `"Recent-3"` stops existing under an open strip, which nothing but that
    /// cell could have closed.
    func testAStripOnARecentThatFellOffTheListDoesNotSurvive() {
        let four = EmojiPanel.sections(
            recent: ["\u{1F600}", "\u{1F602}", "\u{1F970}", "\u{1F60E}"], rowCount: 4)
        let held = "\(EmojiCatalog.recentID)-3"
        XCTAssertNotNil(
            EmojiPanel.pickerSurviving(picker(owner: held), in: four),
            "Recent-3 has to exist while four emoji are in Recents, or this proves nothing")

        let one = EmojiPanel.sections(recent: ["\u{1F600}"], rowCount: 4)
        XCTAssertNil(EmojiPanel.pickerSurviving(picker(owner: held), in: one))
    }

    /// The row count is explicitly *not* a hazard, pinned so nobody re-adds a
    /// guard for it or re-derives the wrong reason for this one.
    func testTheRowCountDoesNotRenumberAnEmojiCell() {
        let four = EmojiPanel.sections(recent: [], rowCount: 4)
        let three = EmojiPanel.sections(recent: [], rowCount: 3)

        let realIDsAtThree = Set(
            three.flatMap { $0.cells }.filter { $0.emoji != nil }.map(\.id))
        let renumbered = four.flatMap { $0.cells }
            .filter { $0.emoji != nil }
            .map(\.id)
            .filter { !realIDsAtThree.contains($0) }

        XCTAssertEqual(renumbered, [], "row count moved an emoji cell id: \(renumbered.prefix(5))")
    }

    /// A strip with the shape the panel actually builds. Only `owner` is read by
    /// `pickerSurviving`; the rest is filled so the value is a real one rather
    /// than a stub that could drift from the type.
    private func picker(owner: String) -> EmojiTonePicker {
        EmojiTonePicker(
            owner: owner,
            variants: EmojiCatalog.variants(for: "\u{1F44B}"),
            restIndex: 0,
            selected: 0,
            anchor: CGRect(x: 0, y: 0, width: 38, height: 29),
            item: CGSize(width: 38, height: 34))
    }

}
