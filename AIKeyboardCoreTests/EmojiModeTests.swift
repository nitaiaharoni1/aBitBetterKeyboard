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
    func testRecentsWinACloseCallAndLoseToAName() {
        let recent = ["😂", "🙏", "❤️", "👍", "🔥"]

        // 🫀 is named exactly "לב"; ❤️ is "לב אדום". Without the boost the
        // anatomical heart wins, which is not what anybody typing לב wants.
        XCTAssertEqual(EmojiSearch.results(for: "לב", recent: recent).first, "❤️")
        XCTAssertEqual(EmojiSearch.results(for: "לב").first, "🫀")

        // But a recent emoji does not hijack a query that names another outright.
        XCTAssertEqual(EmojiSearch.results(for: "pizza", recent: recent).first, "🍕")
        XCTAssertEqual(EmojiSearch.results(for: "פיצה", recent: recent).first, "🍕")
    }

    // MARK: The grid's geometry

    /// **Every category starts on a fresh column**, which is what lets the tab row
    /// work out the selected category from the scroll offset alone instead of a
    /// geometry read per cell. If a section is not a whole number of columns, the
    /// highlight drifts one tab further out with every category passed.
    func testEverySectionIsAWholeNumberOfColumns() {
        for section in EmojiPanel.sections(recent: SharedStore.shippedRecentEmoji) {
            XCTAssertEqual(
                section.cells.count % EmojiPanel.rowCount, 0,
                "\(section.id) is \(section.cells.count) cells")
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
        let sections = EmojiPanel.sections(recent: SharedStore.shippedRecentEmoji)
        let cellIDs = Set(sections.flatMap { $0.cells.map(\.id) })

        for id in [EmojiCatalog.recentID] + EmojiCatalog.categories.map(\.id) {
            let anchor = EmojiPanel.anchorID(forCategory: id)
            XCTAssertTrue(cellIDs.contains(anchor), "\(id) scrolls to \(anchor), which is not a cell")
        }
        // And the bug's own spelling: the bare category id is *not* addressable.
        XCTAssertFalse(cellIDs.contains("Food"))
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
        let sections = EmojiPanel.sections(recent: SharedStore.shippedRecentEmoji)

        // Nothing to the left of Recent but the edge of the panel.
        XCTAssertFalse(sections[0].cells.contains(where: \.leadsSection))

        for section in sections.dropFirst() {
            let ruled = section.cells.enumerated().filter { $0.element.leadsSection }.map(\.offset)
            XCTAssertEqual(ruled, Array(0..<EmojiPanel.rowCount), section.id)
        }

        // And on a fresh install the list of recents is empty, so the section
        // that opens the grid — and wears no seam — is Smileys, not Recent.
        let fresh = EmojiPanel.sections(recent: [])
        XCTAssertTrue(fresh[0].cells.isEmpty)
        XCTAssertFalse(fresh[1].cells.contains(where: \.leadsSection))
        XCTAssertTrue(fresh[2].cells.prefix(EmojiPanel.rowCount).allSatisfy(\.leadsSection))
    }

    /// **Two categories used to run into each other.** The seam is a 1pt overlay
    /// that costs no layout, so Smileys' last 😀 sat against People's first 👋
    /// with nothing but that hairline between them. The gap is padding on the
    /// trailing column of the section that is ending — not a column of its own,
    /// or a tab would land on empty space, and not on the next section's leading
    /// edge, or tapping Food would open on a gutter.
    func testAGapSitsBetweenTwoCategoriesNotBeforeTheFirstOrAfterTheLast() {
        let sections = EmojiPanel.sections(recent: SharedStore.shippedRecentEmoji)

        XCTAssertFalse(
            sections.last!.cells.contains(where: \.trailsSection),
            "the last category has only the panel edge beyond it")

        let bounded = sections.dropLast().filter { !$0.cells.isEmpty }
        XCTAssertFalse(bounded.isEmpty)
        for section in bounded {
            let lastColumn = section.cells.suffix(EmojiPanel.rowCount)
            XCTAssertTrue(
                lastColumn.allSatisfy(\.trailsSection),
                "\(section.id) last column should carry the gap")
            let earlier = section.cells.dropLast(EmojiPanel.rowCount)
            XCTAssertFalse(
                earlier.contains(where: \.trailsSection),
                "\(section.id) earlier columns should not")
        }

        // Empty Recent is not a section that ends, so Smileys — the first
        // category that actually draws — must not open with a gutter.
        let fresh = EmojiPanel.sections(recent: [])
        XCTAssertTrue(fresh[0].cells.isEmpty)
        XCTAssertFalse(
            fresh[1].cells.prefix(EmojiPanel.rowCount).contains(where: \.trailsSection))
        XCTAssertTrue(
            fresh[1].cells.suffix(EmojiPanel.rowCount).allSatisfy(\.trailsSection))
    }

    func testTheSelectedTabFollowsTheScrollOffset() {
        let sections = EmojiPanel.sections(recent: SharedStore.shippedRecentEmoji)
        let width: CGFloat = 40
        func tab(at offset: CGFloat) -> String {
            EmojiPanel.category(atOffset: offset, cellWidth: width, in: sections)
        }

        XCTAssertEqual(tab(at: 0), EmojiCatalog.recentID)
        // Negative offsets happen: a rubber-band drag past the leading edge.
        XCTAssertEqual(tab(at: -120), EmojiCatalog.recentID)

        // One column past the end of Recent is the first real category.
        let recentColumns = sections[0].cells.count / EmojiPanel.rowCount
        XCTAssertEqual(tab(at: CGFloat(recentColumns) * width), EmojiCatalog.categories[0].id)

        // Past the end of everything, the last tab stays lit rather than the
        // computation running off the end of the list.
        XCTAssertEqual(tab(at: 999_999), EmojiCatalog.categories.last?.id)
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
}
