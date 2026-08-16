import XCTest

@testable import AIKeyboardCore

/// The emoji grid, its generated catalogue, and searching it in two languages.
///
/// Every assertion here is written against a *specific* broken build, because
/// three of the four bugs below shipped through a green suite once already. The
/// pattern that catches them: work out what the broken version returns, then
/// assert something only the fixed one produces. `XCTAssertFalse(results.isEmpty)`
/// is true of nearly every ranking bug in this file.
final class EmojiModeTests: XCTestCase {

    // MARK: The catalogue

    /// **The one test standing between a resource that did not copy and a
    /// keyboard whose grid is empty.** `EmojiCatalog` reads `EmojiCatalog.json`
    /// out of `Bundle.module`; if SPM stops embedding it — a missing `resources:`
    /// line in `Package.swift`, a renamed folder — every accessor answers empty
    /// and the panel draws nothing at all, silently.
    func testTheCatalogueLoadsOutOfTheResourceBundle() {
        XCTAssertNil(EmojiCatalog.loadFailure)
        XCTAssertGreaterThan(EmojiCatalog.all.count, 1500)
        XCTAssertEqual(EmojiCatalog.categories.count, 9)
        for category in EmojiCatalog.categories {
            XCTAssertFalse(category.emoji.isEmpty, "\(category.id) is empty")
        }
    }

    /// The catalogue is 1,870 emoji and the panel that preceded it hand-listed
    /// 470, so this rejects a build that quietly fell back to the old list.
    func testTheCatalogueIsTheFullSetRatherThanTheHandPickedOne() {
        XCTAssertGreaterThan(EmojiCatalog.all.count, 1000)
        // Present in the full set, absent from every hand-picked list this
        // replaced.
        for emoji in ["🫎", "🩼", "🛜", "🫏"] {
            XCTAssertTrue(EmojiCatalog.all.contains(emoji), "\(emoji) missing")
        }
    }

    /// **Hebrew is the whole reason search was worth building**, and a generator
    /// that fetched only `annotations/en.xml` would leave the grid searchable in
    /// English and dead in Hebrew — with every English test still passing.
    func testEveryEmojiHasAHebrewNameAndAnEnglishOne() {
        var withoutHebrew: [String] = []
        for emoji in EmojiCatalog.all {
            let names = EmojiCatalog.names(for: emoji)
            if names.count < 2 || names[1].isEmpty { withoutHebrew.append(emoji) }
        }
        XCTAssertEqual(withoutHebrew.count, 0, "no Hebrew name: \(withoutHebrew.prefix(10))")
    }

    /// **An emoji newer than the oldest iOS this package supports draws as a
    /// dotted box.** `Package.swift` floors at iOS 17.0, which shipped Emoji 15.0,
    /// so the generator caps there. These four are Emoji 15.1 and need iOS 17.4;
    /// if they appear, someone raised `MAX_EMOJI_VERSION` without raising the
    /// deployment target, and the grid has tofu in it on a phone nobody here has.
    func testNothingNewerThanTheOldestSupportedIOSIsInTheGrid() {
        for emoji in ["🙂‍↔️", "🍋‍🟩", "🍄‍🟫", "🐦‍🔥"] {
            XCTAssertFalse(EmojiCatalog.all.contains(emoji), "\(emoji) is Emoji 15.1, iOS 17.4+")
        }
    }

    /// Skin-tone variants are excluded deliberately: the panel offers no tone
    /// picker, so they are unreachable, and they would be five sixths of the grid.
    func testSkinTonedVariantsAreNotInTheGrid() {
        let toned = EmojiCatalog.all.filter { emoji in
            emoji.unicodeScalars.contains { (0x1F3FB...0x1F3FF).contains($0.value) }
        }
        XCTAssertEqual(toned.count, 0, "toned: \(toned.prefix(5))")
    }

    // MARK: Search — the bugs it shipped with

    /// **`car` found no car.** CLDR names 🚗 "automobile", so no name rung reaches
    /// it — while "carrot", "card index" and "carp" all matched on a *prefix of a
    /// name word*, and "police car" and "tram car" on a whole word. Ranking an
    /// exact keyword below either buried the actual car under six vehicles and
    /// three unrelated objects.
    ///
    /// Asserted on position rather than presence: the broken build had 🚗 in the
    /// results too, at rank 17, which `contains` would have called a pass.
    func testAnExactKeywordOutranksAWordThatMerelyStartsWithTheQuery() {
        let results = EmojiSearch.results(for: "car")
        let car = results.firstIndex(of: "🚗") ?? Int.max
        let carrot = results.firstIndex(of: "🥕") ?? Int.max
        XCTAssertLessThan(car, carrot, "🥕 beat 🚗: \(results.prefix(8).joined())")
        XCTAssertLessThan(car, 5, "🚗 is not visible in the strip: \(results.prefix(8).joined())")
    }

    /// **`heart` answered with the card suit.** The tiebreak took the shortest
    /// name across *both* locales, so an English query was decided by a Hebrew
    /// name: ♥️'s "קלף לב" is six characters and ❤️'s "לב אדום" is seven, so ♥️ won
    /// a comparison that should have read "red heart" against "heart suit".
    func testTheTiebreakUsesTheNameThatMatchedRatherThanTheShortestOne() {
        let results = EmojiSearch.results(for: "heart")
        XCTAssertEqual(results.first, "❤️", "got \(results.prefix(5).joined())")
    }

    /// Hebrew reaches the same emoji as English, which is the entire point of
    /// bundling CLDR rather than using iOS's English-only Unicode names.
    func testHebrewFindsWhatEnglishFinds() {
        let pairs = [("לב", "❤️"), ("אש", "🔥"), ("פיצה", "🍕"), ("ישראל", "🇮🇱"), ("תודה", "🙏")]
        for (query, expected) in pairs {
            let results = EmojiSearch.results(for: query)
            XCTAssertEqual(results.first, expected, "\(query) gave \(results.prefix(5).joined())")
        }
    }

    /// A query nobody typed must match nothing. An earlier draft returned the
    /// whole catalogue for an empty needle, which drew all 1,870 into the results
    /// strip.
    func testAnEmptyOrUnmatchableQueryReturnsNothing() {
        for query in ["", "   ", "\n", "zzzzzz", "qqqq"] {
            XCTAssertEqual(EmojiSearch.results(for: query), [], "\(query.debugDescription)")
        }
    }

    /// The boost is bounded at two rungs on purpose. An emoji in recents should
    /// win a close call, and must never win against an emoji the query actually
    /// names — or typing `pizza` with 😂 in recents answers 😂.
    ///
    /// **The close call used to be `לב`, and it only worked because of the bug
    /// beside it.** It pinned 🫀 as the empty-recents answer, which is the very
    /// ranking `testHebrewFindsWhatEnglishFinds` and `Bar/emoji/corpus.json` both
    /// say is wrong — a control that is itself the defect. The cat pair is a real
    /// tie nobody disputes: 🐈 is named `cat` and takes rung 0, 🐱 is `cat face`
    /// and takes rung 1, so the boost is the only thing that can reorder them.
    ///
    /// **Written against the boostless build**, because the other half of the
    /// pair is inert: `cat` with recents empty already answers 🐈, so putting 🐈
    /// in recents passes without exercising anything. With `recentBoost` at 0,
    /// 🐱 stays on rung 1 and the first assertion below answers 🐈 and fails,
    /// which is what makes it a test of the boost rather than of the catalogue.
    func testRecentsWinACloseCallAndLoseToAName() {
        let recent = ["😂", "🙏", "❤️", "👍", "🔥"]

        XCTAssertEqual(EmojiSearch.results(for: "cat", recent: ["🐱", "🙏", "👍"]).first, "🐱")
        XCTAssertEqual(EmojiSearch.results(for: "cat").first, "🐈")

        // But a recent emoji does not hijack a query that names another outright.
        XCTAssertEqual(EmojiSearch.results(for: "pizza", recent: recent).first, "🍕")
        XCTAssertEqual(EmojiSearch.results(for: "פיצה", recent: recent).first, "🍕")
    }

    // MARK: The grid's geometry

    /// **Asked of every row count the panel can be built at, not of one.** The
    /// count used to be a constant and these tests read it; it follows the height
    /// now, because the panel stopped covering the bottom row and landscape's
    /// grid is 60pt tall. Every piece of arithmetic below — the padding blanks,
    /// the seams, the gaps, the column count the tab highlight is derived from —
    /// is counted in multiples of it, so a build that got any of them right at
    /// four and wrong at two would be right in portrait and broken sideways.
    private func everyRowCount(
        _ check: (Int) -> Void, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(EmojiPanel.rowCountRange, 2...5, file: file, line: line)
        for rowCount in EmojiPanel.rowCountRange { check(rowCount) }
    }

    /// **Every category starts on a fresh column**, which is what lets the tab row
    /// work out the selected category from the scroll offset alone instead of a
    /// geometry read per cell. If a section is not a whole number of columns, the
    /// highlight drifts one tab further out with every category passed.
    func testEverySectionIsAWholeNumberOfColumns() {
        everyRowCount { rowCount in
            let sections = EmojiPanel.sections(
                recent: SharedStore.shippedRecentEmoji, rowCount: rowCount)
            for section in sections {
                XCTAssertEqual(
                    section.cells.count % rowCount, 0,
                    "\(section.id) is \(section.cells.count) cells at \(rowCount) rows")
            }
        }
    }

    /// **How many rows fit, and the two ends are the ones that matter.** Portrait
    /// ships a 118pt grid and landscape a 60pt one; the old constant five put a
    /// 12pt cell in the latter. The floor is what is held, so the count gives.
    func testTheRowCountFollowsTheHeightItHasToFillRatherThanAConstant() {
        // Portrait, shipped geometry: 3 letter rows at 44 and 2 gaps at 12 is a
        // 156pt panel, less the 38pt category strip.
        XCTAssertEqual(EmojiPanel.rowCount(forGridHeight: 118), 4)
        // Landscape: 3 rows at 26 and 2 gaps at 4 is 86, less a 26pt strip.
        XCTAssertEqual(EmojiPanel.rowCount(forGridHeight: 60), 2)
        // A number row switched on pays for the fifth back.
        XCTAssertEqual(EmojiPanel.rowCount(forGridHeight: 165), 5)

        // Clamped at both ends: a very tall grid grows its cells rather than
        // thinning them, and a very short one stops at two rather than one.
        XCTAssertEqual(EmojiPanel.rowCount(forGridHeight: 900), 5)
        XCTAssertEqual(EmojiPanel.rowCount(forGridHeight: 20), 2)
        XCTAssertEqual(EmojiPanel.rowCount(forGridHeight: 0), 2)

        // And no configuration the layout model can describe draws a cell under
        // the floor by more than the clamp allows. `LayoutGeometry.keyHeightRange`
        // is 36...56 and `rowSpacingRange` 8...16.
        for keyHeight in stride(from: 36.0, through: 56.0, by: 4) {
            for spacing in stride(from: 8.0, through: 16.0, by: 4) {
                let panel = 3 * keyHeight + 2 * spacing
                let grid = panel - EmojiPanel.categoryRowHeight(forKeyHeight: keyHeight)
                let cell = grid / CGFloat(EmojiPanel.rowCount(forGridHeight: grid))
                XCTAssertGreaterThanOrEqual(
                    cell, EmojiPanel.minimumCellHeight,
                    "key \(keyHeight), spacing \(spacing) gives a \(cell)pt cell")
            }
        }
    }

    /// **The category strip is shorter than the key it is modelled on, and the
    /// grid above it takes every point.** The panel's own height is fixed by
    /// `KeyboardView.panelCovers(rowID:)`, so this is the only way an emoji gets
    /// bigger without the keyboard growing past the fingerprint cliff.
    ///
    /// The equal-height strip is the build these reject, so `lessThan` is what
    /// does the work — comparing the grid to `panel - strip` is true of any strip
    /// height at all, including the old one.
    func testTheCategoryStripIsShorterThanAKeySoTheGridIsTaller() {
        let key = Theme.Metrics.keyHeight
        let strip = EmojiPanel.categoryRowHeight(forKeyHeight: key)
        XCTAssertLessThan(strip, key, "the strip is still a full key tall")

        // What the shipped panel actually measures: three letter rows and two
        // gaps, less the strip. Four rows either way — the height buys taller
        // cells rather than a fifth row, which is what `rowCount` says spare
        // height is for.
        let panel = key * 3 + Theme.Metrics.rowSpacing * 2
        let grid = panel - strip
        XCTAssertEqual(EmojiPanel.rowCount(forGridHeight: grid), 4)
        XCTAssertGreaterThan(
            grid / 4, (panel - key) / 4,
            "the cells did not grow, so the strip gave nothing away")

        // **Landscape is the clamp, not the rule.** Its key is 26pt, under the
        // 30pt floor, and a bare floor would draw a strip *taller* than the row
        // it is modelled on out of a panel that is only about 86pt.
        XCTAssertEqual(
            EmojiPanel.categoryRowHeight(forKeyHeight: Theme.Metrics.Landscape.keyHeight),
            Theme.Metrics.Landscape.keyHeight,
            "landscape's strip grew instead of staying put")
        // And the shortest keyboard the editor can build stops at the floor
        // rather than following the key down.
        XCTAssertEqual(
            EmojiPanel.categoryRowHeight(
                forKeyHeight: LayoutGeometry.keyHeightRange.lowerBound), 30)
    }

    /// **`123` on the bottom row is drawn under an open grid, and for the whole
    /// life of that arrangement it did nothing a user could see.** The row is
    /// deliberately outside the panel's stack (`panelCovers(rowID:)`), so the key
    /// stayed tappable and moved `plane` behind the grid — redrawing rows nobody
    /// could see while the emoji sat exactly where they were.
    ///
    /// Asserting on `plane` alone passes against the broken build, which is the
    /// trap here: the plane always moved. The overlay is what has to close.
    @MainActor
    func testTappingNumbersFromTheEmojiGridLeavesTheGrid() {
        // Opening the clip list reads the pasteboard into the App Group, which
        // this simulator hands the test target for real. Same guard every test
        // in `CopyClipModeTests` carries.
        let clips = SharedStore.shared.copyclipRecord
        defer { SharedStore.shared.copyclipRecord = clips }
        let controller = KeyboardController(target: MockTextTarget())
        controller.show(.emoji)
        XCTAssertEqual(controller.overlay, .emoji)

        controller.press(.plane(.numbers, label: "123"))
        XCTAssertEqual(controller.plane, .numbers)
        XCTAssertEqual(
            controller.overlay, KeyboardOverlay.none,
            "the digits arrived behind the grid that was covering them")

        // **The CopyClip list is answered by the same line**, and it has to be:
        // `KeyboardView.dropsBottomRow` only drops this key when the key that
        // closes the list is in the action row, so a user who moved CopyClip down
        // here would otherwise meet the same invisible switch.
        controller.show(.copyclip)
        controller.press(.plane(.numbers, label: "123"))
        XCTAssertEqual(
            controller.overlay, KeyboardOverlay.none,
            "the digits arrived behind the clip list")

        // **Search is the exception and it is deliberate.** The plane switch falls
        // through `consumeForEmojiSearch` so a query can be typed in either
        // alphabet, and closing the box would be the plane key deleting what had
        // been typed into it. Both search states put the letters back, which is
        // the property the branch is actually asked about.
        for search in [KeyboardOverlay.emojiSearch, .copyclipSearch] {
            controller.show(search)
            controller.press(.plane(.letters, label: "ABC"))
            XCTAssertEqual(controller.plane, .letters)
            XCTAssertEqual(
                controller.overlay, search,
                "the plane switch closed the search box it was typed into")
        }
    }

    /// The tab row's highlight, computed from how far the strip has been swiped.
    /// **Every category tab was silently dead.** `ForEach(sections, id: \.id)`
    /// gives the loop its identity but puts no view on screen carrying the
    /// category's own id, so `scrollTo("Food")` addressed nothing at all and the
    /// tabs did not move the strip. Nothing about the panel looked wrong: the row
    /// drew, the highlight moved, and the grid stayed exactly where it was.
    ///
    /// Asserted by demanding the anchor is a real cell, which is the only thing
    /// `ScrollViewReader` can actually find.
    func testEveryCategoryTabScrollsToACellThatExists() {
        everyRowCount { rowCount in
            let sections = EmojiPanel.sections(
                recent: SharedStore.shippedRecentEmoji, rowCount: rowCount)
            let cellIDs = Set(sections.flatMap { $0.cells.map(\.id) })

            for id in [EmojiCatalog.recentID] + EmojiCatalog.categories.map(\.id) {
                let anchor = EmojiPanel.anchorID(forCategory: id)
                XCTAssertTrue(
                    cellIDs.contains(anchor),
                    "\(id) scrolls to \(anchor) at \(rowCount) rows, which is not a cell")
            }
            // And the bug's own spelling: the bare category id is *not* addressable.
            XCTAssertFalse(cellIDs.contains("Food"))
        }
    }

    /// **The seam between two categories, which the sideways strip otherwise
    /// hides.** One category running into the next is five rows of glyphs with
    /// nothing between them, so the boundary is only readable from the tab row's
    /// highlight — which nobody is looking at while their thumb is moving.
    ///
    /// Asserted on the whole first column rather than on "some cell is ruled",
    /// because the obvious build marks cell zero alone: that draws a fifth of a
    /// hairline against the top row and reads as a stray tick, not a divider.
    func testTheSeamRunsDownEverySectionBoundaryButNotTheStripsOwnEdge() {
        everyRowCount { rowCount in
            let sections = EmojiPanel.sections(
                recent: SharedStore.shippedRecentEmoji, rowCount: rowCount)

            // Nothing to the left of Recent but the edge of the panel.
            XCTAssertFalse(sections[0].cells.contains(where: \.leadsSection))

            for section in sections.dropFirst() {
                let ruled = section.cells.enumerated().filter { $0.element.leadsSection }
                    .map(\.offset)
                XCTAssertEqual(ruled, Array(0..<rowCount), "\(section.id) at \(rowCount) rows")
            }

            // And on a fresh install the list of recents is empty, so the section
            // that opens the grid — and wears no seam — is Smileys, not Recent.
            let fresh = EmojiPanel.sections(recent: [], rowCount: rowCount)
            XCTAssertTrue(fresh[0].cells.isEmpty)
            XCTAssertFalse(fresh[1].cells.contains(where: \.leadsSection))
            XCTAssertTrue(fresh[2].cells.prefix(rowCount).allSatisfy(\.leadsSection))
        }
    }

    /// **Two categories used to run into each other.** The seam is a 1pt overlay
    /// that costs no layout, so Smileys' last 😀 sat against People's first 👋
    /// with nothing but that hairline between them. The gap is padding on the
    /// trailing column of the section that is ending — not a column of its own,
    /// or a tab would land on empty space, and not on the next section's leading
    /// edge, or tapping Food would open on a gutter.
    func testAGapSitsBetweenTwoCategoriesNotBeforeTheFirstOrAfterTheLast() {
        everyRowCount { rowCount in
            let sections = EmojiPanel.sections(
                recent: SharedStore.shippedRecentEmoji, rowCount: rowCount)

            XCTAssertFalse(
                sections.last!.cells.contains(where: \.trailsSection),
                "the last category has only the panel edge beyond it")

            let bounded = sections.dropLast().filter { !$0.cells.isEmpty }
            XCTAssertFalse(bounded.isEmpty)
            for section in bounded {
                let lastColumn = section.cells.suffix(rowCount)
                XCTAssertTrue(
                    lastColumn.allSatisfy(\.trailsSection),
                    "\(section.id) last column should carry the gap at \(rowCount) rows")
                let earlier = section.cells.dropLast(rowCount)
                XCTAssertFalse(
                    earlier.contains(where: \.trailsSection),
                    "\(section.id) earlier columns should not")
            }

            // Empty Recent is not a section that ends, so Smileys — the first
            // category that actually draws — must not open with a gutter.
            let fresh = EmojiPanel.sections(recent: [], rowCount: rowCount)
            XCTAssertTrue(fresh[0].cells.isEmpty)
            XCTAssertFalse(fresh[1].cells.prefix(rowCount).contains(where: \.trailsSection))
            XCTAssertTrue(fresh[1].cells.suffix(rowCount).allSatisfy(\.trailsSection))
        }
    }

    func testTheSelectedTabFollowsTheScrollOffset() {
        everyRowCount { rowCount in
            let sections = EmojiPanel.sections(
                recent: SharedStore.shippedRecentEmoji, rowCount: rowCount)
            let width: CGFloat = 40
            func tab(at offset: CGFloat) -> String {
                EmojiPanel.category(
                    atOffset: offset, cellWidth: width, in: sections, rowCount: rowCount)
            }

            XCTAssertEqual(tab(at: 0), EmojiCatalog.recentID)
            // Negative offsets happen: a rubber-band drag past the leading edge.
            XCTAssertEqual(tab(at: -120), EmojiCatalog.recentID)

            // One column past the end of Recent is the first real category.
            let recentColumns = sections[0].cells.count / rowCount
            XCTAssertEqual(
                tab(at: CGFloat(recentColumns) * width), EmojiCatalog.categories[0].id,
                "at \(rowCount) rows")

            // Past the end of everything, the last tab stays lit rather than the
            // computation running off the end of the list.
            XCTAssertEqual(tab(at: 999_999), EmojiCatalog.categories.last?.id)
        }
    }

    /// **The Recent tab stayed orange after every other category was opened.**
    /// Offset-from-the-grid-background reports 0 for a `LazyHGrid` (the
    /// viewport, not the content), so `category(atOffset:)` kept answering
    /// Recent. The orange tab follows the cell that actually sits on the
    /// leading edge.
    func testTheOrangeTabFollowsTheCellOnTheLeadingEdgeNotAlwaysRecent() {
        let recent = EmojiPanel.VisibleCategory(id: EmojiCatalog.recentID, minX: 0)
        let smileys = EmojiPanel.VisibleCategory(id: "Smileys", minX: 80)
        let food = EmojiPanel.VisibleCategory(id: "Food", minX: 400)

        XCTAssertEqual(
            EmojiPanel.nearerTheLeadingEdge(recent, smileys).id,
            EmojiCatalog.recentID)
        XCTAssertEqual(
            EmojiPanel.nearerTheLeadingEdge(smileys, food).id,
            "Smileys")

        // Scrolled so Smileys owns the left edge: Recent is gone (minX < 0 and
        // no longer covering 0), Smileys is sitting on 0.
        let recentGone = EmojiPanel.VisibleCategory(id: EmojiCatalog.recentID, minX: -80)
        let smileysAtEdge = EmojiPanel.VisibleCategory(id: "Smileys", minX: 0)
        XCTAssertEqual(
            EmojiPanel.nearerTheLeadingEdge(recentGone, smileysAtEdge).id,
            "Smileys",
            "Recent must not stay selected once another category owns the edge")

        // A tap names Food before the strip has moved. The hold must not let
        // a still-visible Recent cell overwrite it.
        XCTAssertEqual(
            EmojiPanel.selectedCategory(
                current: "Food", leading: EmojiCatalog.recentID, holdingTap: true),
            "Food")
        XCTAssertEqual(
            EmojiPanel.selectedCategory(
                current: "Food", leading: "Smileys", holdingTap: false),
            "Smileys")
    }

    // MARK: The way out

    /// **An open grid has to keep a way back to the letters on screen, and since
    /// Emoji and the gear traded seats the Emoji key on the bottom row is the only
    /// one.**
    ///
    /// Written against the specific broken build, which is a straight seat swap
    /// and nothing else: Emoji to the bottom row, the gear to the action row, and
    /// `KeyboardView+Keys` still drawing the bottom row inside the panel's stack.
    /// Every assertion here except the last passes against that build, and it
    /// shipped a keyboard whose emoji grid could not be closed at all. Nothing
    /// else notices — `showsLetterKeys` hid the row without knowing what was in
    /// it, `LayoutValidator` has no opinion about a key that is present but
    /// covered, and the landscape strip tests only ask about the bar.
    ///
    /// The last assertion is the one that rejects it, and it is deliberately not
    /// "the bottom row contains Emoji" — that was true of the broken build too.
    /// It is that the bottom row is *drawn* while the grid is open.
    @MainActor
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
}
