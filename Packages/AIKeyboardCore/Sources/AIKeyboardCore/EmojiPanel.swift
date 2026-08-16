import SwiftUI

/// The emoji grid: one long strip that scrolls sideways, with a row of category
/// keys under it.
///
/// **Sideways, not down, and every category is in the same strip.** The panel it
/// replaced showed one category at a time and scrolled vertically, so reaching
/// Food meant a tap on a tab rather than a swipe — and the tab bar was the only
/// way between categories at all. Laying the whole catalogue out left to right
/// makes the swipe continuous and leaves the tabs as shortcuts rather than as
/// steering.
///
/// **Each category starts on a fresh column.** `padded` fills the tail of a
/// section with blanks so a category boundary is always a column boundary, which
/// is what makes the tab row's highlight computable from the scroll offset alone
/// (see `category(atOffset:)`) instead of needing a geometry read per cell.
///
/// **And the boundary is drawn, because sideways scrolling hides it.** The panel
/// this replaced put one category on screen at a time, so where Food ended was
/// never a question. In a continuous strip, Smileys running into People is five
/// rows of glyphs with nothing between them: the seam is only legible from the
/// tab row's highlight, which the user is not looking at while swiping. A
/// hairline down the leading edge of every section's first column says it in
/// place, and `sectionGap` of air sits on the trailing column of the section
/// before it, so two categories do not touch. The gap is padding, not a column
/// of its own: a tab still scrolls to the first emoji, not to empty space.
public struct EmojiPanel: View {

    @ObservedObject var controller: KeyboardController

    /// The keyboard's own key height, which the category row is modelled on.
    /// Passed in because it is a user setting — `LayoutGeometry.keyHeight` moves
    /// between 36 and 56. What the row is actually drawn at is
    /// `categoryRowHeight(forKeyHeight:)`.
    let keyHeight: CGFloat

    /// How tall the category strip is drawn, given the keyboard's own key height.
    ///
    /// **Six points shorter than a key, and the grid above takes every one of
    /// them.** The panel's own height is fixed — it fills the block the letter
    /// rows occupy and nothing here can change that (see `KeyboardView
    /// .panelCovers(rowID:)`) — so `gridHeight` is whatever this row does not
    /// take, and shortening it is the only way an emoji gets bigger without the
    /// keyboard growing past the 368 pt fingerprint cliff.
    ///
    /// **This row can afford it and the bottom row underneath cannot**, which is
    /// why the two no longer match. Ten tabs and a delete key is a row of
    /// signposts: a tab is aimed at once, deliberately, and a miss scrolls the
    /// strip to the wrong section rather than typing the wrong thing into
    /// somebody's message. The space row below it is keys.
    ///
    /// It does not usually buy a row — at the shipped size the grid goes from 110
    /// to 118 pt against `minimumCellHeight`'s 26, still four — it makes the four
    /// cells taller, which is what `rowCount(forGridHeight:)` says the panel wants
    /// from spare height in the first place.
    ///
    /// **Two clamps, and the upper one is landscape.** The 30 pt floor is for the
    /// shortest keyboard the editor can build; `min(keyHeight, …)` is because
    /// landscape's key is 26 pt (`Theme.Metrics.Landscape.keyHeight`), where a
    /// bare floor would make this row *taller* than the row it is modelled on and
    /// take 4 pt off a grid that is only about 60 pt to begin with. Below 30 pt
    /// the strip simply stays a key tall and gives nothing away.
    ///
    /// **Measured, both what it buys and what it costs.** The grid goes 110 → 118
    /// pt, the cell 27.5 → 29.5, and the emoji itself 21.45 → 23.0, a 7% gain;
    /// the tallest tab glyph at `Theme.Glyph.font(19)` is 25 pt (`fork.knife`,
    /// `lightbulb`), so 38 pt clears every one of them by 13. The cost is the
    /// target: a tab is **34 × 38** on a 402 pt phone and `KeyStyleButton` puts
    /// its `contentShape` on its own frame, so the gap below absorbs nothing and
    /// a low tap misses. Both axes were already under `minTouchTarget` and the
    /// consequence of a miss here is a strip scrolled to the wrong section, not a
    /// character in somebody's message, which is the whole reason this is the row
    /// that pays.
    static func categoryRowHeight(forKeyHeight keyHeight: CGFloat) -> CGFloat {
        min(keyHeight, max(30, keyHeight - 6))
    }

    /// **How many rows fit, rather than a number.** It was a hardcoded five, on
    /// the argument that five is a floor rather than a taste: four is what the
    /// vertical grid this replaced showed, and the horizontal strip had to beat it
    /// to be worth the change.
    ///
    /// That was decided against one height and then read as if it held at every
    /// height. The panel used to be 208 pt because it covered the letter rows
    /// *and* the space row; it covers only the letter rows now — see
    /// `KeyboardView.panelCovers(rowID:)` — so the grid under the category strip
    /// is 118 pt in portrait and **60 pt in landscape**, where the whole keyboard
    /// is 116. Five rows of a 60 pt grid is a 12 pt cell holding a 9 pt emoji.
    /// Landscape was already the worst case at 18 pt and a fixed count would have
    /// taken it to 15.
    ///
    /// So the cell height is what is held steady and the count is what gives:
    /// every configuration lands between 26 and 32 pt a cell instead of swinging
    /// from 15 to 44. Portrait's default takes four, a number row or a tall
    /// `keyHeight` takes five back, and landscape takes two — which is more emoji
    /// on screen than five rows of specks, because what this panel gives is the
    /// horizontal scroll through all 1,870 in nine sections, and that never
    /// depended on the row count.
    static func rowCount(forGridHeight height: CGFloat) -> Int {
        max(
            Self.rowCountRange.lowerBound,
            min(Self.rowCountRange.upperBound, Int(height / Self.minimumCellHeight)))
    }

    /// The shortest a cell may be before a row is dropped instead. A cell is
    /// square-ish at `targetCellWidth`, and `cell` draws its emoji at 0.78 of the
    /// smaller side, so 26 pt is a 20 pt glyph — the floor at which an emoji is
    /// still a picture rather than a smudge.
    static let minimumCellHeight: CGFloat = 26

    /// Two is not a degenerate case, it is landscape. Five is the ceiling because
    /// a taller grid should grow its emoji, not thin them.
    static let rowCountRange = 2...5

    /// How long a tap keeps its tab orange while the strip is still jumping.
    /// Covers `Theme.Motion.duration` with a little slack, so a still-visible
    /// Recent cell cannot paint Recents orange again before the jump lands.
    static let pinHold: TimeInterval = Theme.Motion.duration + 0.04

    /// What a column wants to be. The real width is this rounded to a whole
    /// number of columns across the panel, so the strip never rests showing a
    /// half-column at the edge of a section.
    static let targetCellWidth: CGFloat = 38

    /// Air between two categories in the strip. On the trailing column of the
    /// section that is ending, so a tab still lands on the next category's first
    /// emoji rather than on the gutter.
    static let sectionGap: CGFloat = Theme.Space.sm

    /// The orange tab. Named by a tap immediately, and by the cell sitting on
    /// the leading edge once the strip has moved. Not derived from a
    /// GeometryReader on the `LazyHGrid` itself: that reader sees the viewport,
    /// so its offset stays 0 and Recents stays selected forever.
    @State private var selectedCategory: String = EmojiCatalog.recentID
    @State private var holdTapUntil: Date = .distantPast

    /// The strip's cells, rebuilt only when the recents change. See the `.task`
    /// in `body` for why this is not a computed property.
    @State private var sections: [Section] = []

    /// **The row count the cells in `sections` were actually laid out for**, which
    /// is not always the one the current height wants. The blanks that pad a
    /// section to a whole column are counted in multiples of it, so drawing a
    /// `LazyHGrid` at a different number would slice columns across section
    /// boundaries for the frame between a rotation and the rebuild. Reading the
    /// count off the data rather than off the geometry keeps the two in step; the
    /// wanted count lives in `rows` and `.task(id:)` closes the gap.
    @State private var sectionRowCount = 0

    /// How many rows the current height wants. Written from the layout pass, and
    /// the only thing `.task(id:)` watches.
    @State private var rows = 0

    private let scrollSpace = "emoji-strip"

    public init(controller: KeyboardController, keyHeight: CGFloat = Theme.Metrics.keyHeight) {
        self.controller = controller
        self.keyHeight = keyHeight
    }

    public var body: some View {
        GeometryReader { geo in
            let columns = max(1, (geo.size.width / Self.targetCellWidth).rounded())
            let cellWidth = geo.size.width / columns
            let stripHeight = Self.categoryRowHeight(forKeyHeight: keyHeight)
            let gridHeight = max(0, geo.size.height - stripHeight)
            let wanted = Self.rowCount(forGridHeight: gridHeight)
            // The cells on screen divide the height they were built for, not the
            // height that has just been measured. They are the same number every
            // frame except the one after a rotation.
            let cellHeight = gridHeight / CGFloat(max(1, sectionRowCount))

            VStack(spacing: 0) {
                grid(cellWidth: cellWidth, cellHeight: cellHeight)
                    .frame(height: gridHeight)
                    // `initial: true` because the first layout pass *is* the
                    // change: `rows` starts at zero, which builds nothing, and
                    // without this the grid would stay empty until something else
                    // moved.
                    .onChange(of: wanted, initial: true) { _, count in rows = count }

                EmojiCategoryRow(
                    selected: selectedCategory,
                    height: stripHeight,
                    isRightToLeft: controller.language.isRightToLeft,
                    // The section's *first cell*, not the section. `ForEach(sections)`
                    // gives the loop its identity but puts no view on screen with
                    // the category's own id, so `scrollTo("Food")` addressed
                    // nothing and every tab was silently dead.
                    onSelect: { id in
                        selectedCategory = id
                        holdTapUntil = Date().addingTimeInterval(Self.pinHold)
                        scrollTarget = Self.anchorID(forCategory: id)
                    },
                    // `press` rather than `deleteBackward`, for the sound: this is
                    // a key the user pressed, and only `press` speaks for one.
                    onDelete: { controller.press(.backspace) },
                    onDeleteRepeat: { controller.deletePreviousWord() }
                )
            }
        }
        // **Built once per change of the recents, not once per scroll frame.**
        // `sections` is 1,870 cells with an interpolated id each; as a computed
        // property read from `body` it was rebuilt on every `onPreferenceChange`
        // the scroll fired, which is sixty times a second while a finger is moving.
        //
        // `visibleRecentEmoji`, never `recentEmoji`: the latter moves on every
        // pick, which would re-sort the Recent tab under the finger that picked.
        //
        // **Keyed on `rows` as well**, so a rotation rebuilds it: the padding
        // blanks and the seams are counted in multiples of the row count, and a
        // landscape grid two rows tall drawn from cells padded to four is columns
        // sliced across category boundaries.
        .task(id: rows) { rebuildSections(recent: controller.visibleRecentEmoji) }
        .onChange(of: controller.visibleRecentEmoji) { _, recent in
            rebuildSections(recent: recent)
        }
        // Same fill as the letters this grid replaced. `Keys.panel` is the
        // warmer lift the banner uses; painting it here left a cream rectangle
        // inside a grey keyboard.
        .background(Theme.Keys.background)
        // Emoji read left to right regardless of the keyboard language, and so
        // does the strip they sit in: a horizontal `ScrollView` in a right-to-left
        // environment starts at the far end, which would open Hebrew's grid on the
        // flags.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// Rebuilds the cells and records the count they were built for, in one step
    /// so the two can never disagree.
    private func rebuildSections(recent: [String]) {
        guard rows > 0 else { return }
        sections = Self.sections(recent: recent, rowCount: rows)
        sectionRowCount = rows
    }

    /// Set by a tab tap, consumed by the grid's `ScrollViewReader`. A piece of
    /// state rather than a direct call because the reader's proxy only exists
    /// inside the grid's own body.
    @State private var scrollTarget: String?

    // MARK: Grid

    private func grid(cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        let drawnRows = max(1, sectionRowCount)
        let columns = sections.reduce(0) { $0 + $1.cells.count / drawnRows }
        let gaps = sections.reduce(0) { $0 + ($1.cells.contains(where: \.trailsSection) ? 1 : 0) }
        let contentWidth = CGFloat(columns) * cellWidth + CGFloat(gaps) * Self.sectionGap

        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(
                        repeating: GridItem(.fixed(cellHeight), spacing: 0), count: drawnRows),
                    spacing: 0
                ) {
                    ForEach(sections, id: \.id) { section in
                        ForEach(section.cells) { cell in
                            self.cell(cell, width: cellWidth, height: cellHeight)
                                .id(cell.id)
                        }
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
            }
            .coordinateSpace(name: scrollSpace)
            .onPreferenceChange(LeadingEmojiCategoryKey.self) { lead in
                guard let lead else { return }
                let next = Self.selectedCategory(
                    current: selectedCategory, leading: lead.id,
                    holdingTap: Date() < holdTapUntil)
                if next != selectedCategory { selectedCategory = next }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(Theme.Motion.quick) { proxy.scrollTo(target, anchor: .leading) }
                scrollTarget = nil
            }
        }
    }

    private func cell(_ cell: Cell, width: CGFloat, height: CGFloat) -> some View {
        Group {
            if let emoji = cell.emoji {
                Button {
                    controller.insertEmoji(emoji)
                } label: {
                    Text(emoji)
                        // Against the shorter side, so the glyph stays inside its cell
                        // on a Compact layout where the rows are 28pt tall.
                        .font(.system(size: min(width, height) * 0.78))
                        .frame(width: width, height: height)
                        .contentShape(Rectangle())
                }
                .pressable(scale: 0.85)
                .accessibilityLabel(EmojiCatalog.names(for: emoji).first ?? emoji)
            } else {
                // The tail of a section, keeping the next one on a fresh column.
                Color.clear.frame(width: width, height: height)
            }
        }
        // Outside the button and with no vertical inset: the rule has to scale
        // with nothing when a finger presses the emoji next to it, and the five
        // cells of a column have to join into one unbroken line rather than a
        // dashed one. The hairline is still an overlay; the gap is padding on
        // the column that is ending, so it does not become a column the tab
        // highlight could land on.
        .overlay(alignment: .leading) {
            if cell.leadsSection {
                Rectangle().fill(Self.ruleTint).frame(width: 1)
            }
        }
        .padding(.trailing, cell.trailsSection ? Self.sectionGap : 0)
        // The orange tab follows whichever cell is sitting on the leading edge,
        // not a GeometryReader on the grid. A `LazyHGrid`'s own background is
        // the viewport, so that offset stayed 0 and Recents stayed selected.
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: LeadingEmojiCategoryKey.self,
                    value: VisibleCategory(
                        id: cell.categoryID,
                        minX: geo.frame(in: .named(scrollSpace)).minX))
            }
        }
    }

    /// The seam between two sections in the strip.
    ///
    /// The category row used to draw one too, before delete and the tabs stopped
    /// being the same object — a mark separating two things that already look
    /// nothing alike is noise. See `EmojiCategoryRow`.
    static let ruleTint = Theme.Keys.secondaryLabel.opacity(0.18)

    /// The touch answer for a capless `KeyStyleButton` — the category tabs. Same
    /// idiom as `ruleTint` a shade up, and it lives here rather than on the
    /// button because **Swift has no static stored properties on a generic
    /// type** and `KeyStyleButton` is generic over its label.
    static let pressWash = Theme.Keys.secondaryLabel.opacity(0.22)

    // MARK: Sections

    struct Cell: Identifiable, Equatable {
        let id: String
        let categoryID: String
        let emoji: String?
        /// Whether this cell wears the seam on its leading edge. True for a whole
        /// first column — every cell with an index under `rowCount`, blanks
        /// included, so a section shorter than one column still rules its full
        /// height — and false for the first section that has any cells at all.
        var leadsSection = false
        /// Whether this cell wears the gap on its trailing edge. True for the
        /// last column of a section that has another non-empty section after it,
        /// so two categories do not run into each other, and false for the last
        /// section on the strip, which has only the edge of the panel beyond it.
        var trailsSection = false
    }

    struct Section: Equatable {
        let id: String
        let cells: [Cell]
    }

    /// Recent first, then the catalogue, each padded out to a whole number of
    /// columns.
    ///
    /// Static so the view can cache it in `@State` while tests still ask for it
    /// directly — a `@State` array is empty until a body has been evaluated, and
    /// a test that read one would be measuring nothing.
    static func sections(recent: [String], rowCount: Int) -> [Section] {
        // **The first section holding anything wears no seam.** A rule marks a
        // boundary between two sections, and the leading edge of the strip has
        // only the edge of the panel on its other side. Asked of the cells rather
        // than hardcoded to Recent, because on a fresh install `recent` is empty
        // and Smileys is what opens the grid.
        var result = [
            section(id: EmojiCatalog.recentID, emoji: recent, rule: false, rowCount: rowCount)
        ]
        var anythingBefore = !recent.isEmpty
        for category in EmojiCatalog.categories {
            result.append(
                section(
                    id: category.id, emoji: category.emoji, rule: anythingBefore,
                    rowCount: rowCount))
            anythingBefore = anythingBefore || !category.emoji.isEmpty
        }
        return result.enumerated().map { index, section in
            let hasFollowing = result[(index + 1)...].contains { !$0.cells.isEmpty }
            guard hasFollowing, !section.cells.isEmpty else { return section }
            var cells = section.cells
            for i in (cells.count - rowCount)..<cells.count {
                cells[i].trailsSection = true
            }
            return Section(id: section.id, cells: cells)
        }
    }

    /// The cell a category tab scrolls to: the first one in that section. Spelled
    /// once, here, because it has to agree exactly with the ids `section` mints.
    static func anchorID(forCategory id: String) -> String { "\(id)-0" }

    private static func section(id: String, emoji: [String], rule: Bool, rowCount: Int) -> Section {
        var cells = emoji.enumerated().map {
            Cell(
                id: "\(id)-\($0.offset)", categoryID: id, emoji: $0.element,
                leadsSection: rule && $0.offset < rowCount)
        }
        let remainder = cells.count % rowCount
        if remainder != 0 {
            for blank in 0..<(rowCount - remainder) {
                // The blank's index in the *section*, not in the padding: Recent
                // with three emoji in it is one column of three glyphs and two
                // blanks, and the seam has to run past all five.
                let index = cells.count
                cells.append(
                    Cell(
                        id: "\(id)-blank-\(blank)", categoryID: id, emoji: nil,
                        leadsSection: rule && index < rowCount))
            }
        }
        return Section(id: id, cells: cells)
    }

    /// Which category sits at the leading edge, from the scroll offset alone.
    ///
    /// Exact because every section is a whole number of columns wide: the column
    /// under the left edge is `offset / cellWidth`, and the sections' column counts
    /// say which one owns it. A geometry read per cell would answer the same
    /// question and would go quiet the moment a category is wider than the screen,
    /// which most of them are.
    static func category(
        atOffset offset: CGFloat, cellWidth: CGFloat, in sections: [Section], rowCount: Int
    )
        -> String
    {
        guard cellWidth > 0, rowCount > 0, !sections.isEmpty else { return EmojiCatalog.recentID }
        let column = Int(max(0, offset) / cellWidth)
        var consumed = 0
        for section in sections {
            consumed += section.cells.count / rowCount
            if column < consumed { return section.id }
        }
        return sections.last?.id ?? EmojiCatalog.recentID
    }

    /// The cell that owns the strip's leading edge: the one covering x = 0.
    /// Among cells that have scrolled past the edge (`minX <= 0`), that is the
    /// one closest to zero. Recents at −80 and Smileys at 0 therefore names
    /// Smileys, which is the case the offset-from-the-grid-background never saw.
    static func nearerTheLeadingEdge(
        _ a: VisibleCategory, _ b: VisibleCategory
    )
        -> VisibleCategory
    {
        switch (a.minX <= 0, b.minX <= 0) {
        case (true, true): return a.minX >= b.minX ? a : b
        case (true, false): return a
        case (false, true): return b
        case (false, false): return a.minX <= b.minX ? a : b
        }
    }

    /// A tap names the orange tab immediately. Visible cells must not paint
    /// Recents back on until the jump has landed (or the hold has expired).
    static func selectedCategory(current: String, leading: String, holdingTap: Bool) -> String {
        if holdingTap, leading != current { return current }
        return leading
    }

    struct VisibleCategory: Equatable {
        var id: String
        var minX: CGFloat
    }
}

/// The category sitting on the leading edge of the emoji strip, from the
/// visible cells themselves. A GeometryReader on the `LazyHGrid` reports the
/// viewport and stays at offset 0, which is why Recents stayed orange.
struct LeadingEmojiCategoryKey: PreferenceKey {
    static var defaultValue: EmojiPanel.VisibleCategory? { nil }
    static func reduce(
        value: inout EmojiPanel.VisibleCategory?,
        nextValue: () -> EmojiPanel.VisibleCategory?
    ) {
        guard let next = nextValue() else { return }
        guard let current = value else {
            value = next
            return
        }
        value = EmojiPanel.nearerTheLeadingEdge(current, next)
    }
}

// MARK: - Category row

/// The row under the grid: a category per tab, delete pinned at the end.
///
/// **The tabs are not keys, and drawing them as keys is what made this row
/// unreadable.** Ten warm-white caps, two shadows each, butted at zero gap and
/// bleeding into both edges of the panel — on a 402pt phone that is 35.5pt of
/// card per tab, and the eye reads one slab of chrome rather than ten shortcuts.
/// **Spacing cannot fix it**: matching the key rows above (3pt inset, 6pt gaps)
/// leaves each tab 28.3pt, a 19pt glyph inside a shadowed card, which is more
/// crowded and not less. So the chrome goes instead. A tab is a bare glyph on the
/// panel and gets 34pt to itself, and the row's only fill is the selected one —
/// which is also the point, because a tinted card standing among nine white cards
/// was the weakest possible way to say the one thing this row exists to say.
///
/// **The selected tab is a filled brand pill, and the wash it replaced is a trap
/// worth naming.** Tinting a card 14% works because the card is doing the work;
/// take the cards away and the tint is alone, and a `Brand.solid` glyph on a 14%
/// `Brand.solid` wash measures 2.3:1 in orange — under the 3:1 floor, and *below*
/// the 5.18:1 the nine unselected tabs get for free. The highlight was the least
/// legible thing in the row it was highlighting. `Brand.action` under
/// `Text.onBrand` is 3.64:1 at worst and 5.35 at best across the four palettes.
///
/// **Delete keeps its cap, and that is now the whole of "this one is
/// different".** Every other control here scrolls the grid; this one edits the
/// user's text. That used to be carried by a 1pt hairline, because the tabs and
/// delete were the same object with different fills — with the tabs bare, being
/// the row's one keycap says it outright, and the hairline is gone with the
/// reason for it.
///
/// **There is still no `אבג` key here, and the reason has changed.** It used to
/// be that the Emoji key in the action row said `אבג` while the grid was open,
/// and two keys a thumb's width apart doing one job is what this row had before.
/// Emoji has since moved to the bottom row — see `KeyboardCustomization.default`
/// — and the answer is the same because the bottom row is no longer covered:
/// `KeyboardView+Keys` draws it outside the panel's own stack, so `123`, the
/// space bar, the full stop and return stay under the grid, and the Emoji key
/// among them reads `אבג`. That is the iOS arrangement. Adding one here would
/// put two ways back on screen at once, ten points apart, and cost the ten tabs
/// five points of width each to do it.
struct EmojiCategoryRow: View {

    let selected: String
    /// `EmojiPanel.categoryRowHeight(forKeyHeight:)`, which is shorter than the
    /// key it is modelled on so the grid above can be taller.
    let height: CGFloat
    let isRightToLeft: Bool
    let onSelect: (String) -> Void
    let onDelete: () -> Void
    let onDeleteRepeat: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(id: EmojiCatalog.recentID, icon: EmojiCatalog.recentIcon)
            ForEach(EmojiCatalog.categories) { category in
                tab(id: category.id, icon: category.icon)
            }

            // Pinned at the end and never scrolled, exactly as delete is pinned on
            // every letter row. See `.claude/rules/keyboard-layout.md`.
            //
            // **It repeats, and that is not a nicety.** `SuggestionBar.barCatalogue`
            // excludes delete from the bar's edges for exactly this reason: the
            // accelerating repeat is wired into `KeyView`, so a delete drawn
            // anywhere else "would delete once per tap and look broken beside the
            // real one". This row replaces the letters while it is up, so it *is*
            // the only delete on screen — a one-character-per-tap version of it
            // would be the whole of deleting for as long as the grid is open.
            KeyStyleButton(
                width: 42, height: height, repeats: true,
                repeatAction: onDeleteRepeat,
                // No `Feedback` call of its own: `deleteBackward` already fires
                // one per character, and the button's own press haptic on top of
                // it made a single tap buzz twice.
                feedback: nil,
                // The same cap the real delete key wears, so the row's one
                // editing control matches it exactly.
                restingCap: Theme.Keys.functionSoft,
                capKind: .soft,
                glyphColor: Theme.Keys.labelOnFunction,
                action: onDelete
            ) {
                Image(systemName: KeyCap.backspaceSymbol(isRightToLeft: isRightToLeft))
                    .font(Theme.Glyph.font(19))
            }
            // Air between the last tab and the one key in the row, so the flags
            // glyph is not standing on delete's cap. This is what the hairline
            // used to occupy, spent on separation instead of on a mark.
            .padding(.leading, Theme.Space.xs)
            .accessibilityLabel("Delete")
        }
        .frame(height: height)
        // **The margin the row never had.** Every other row on this keyboard is
        // inset from the panel edge and this one ran to the glass on both sides,
        // which is most of why it read as crowded even before the caps. A gap
        // rather than `sideInset`, because the tabs are bare: their own glyphs
        // sit centred in the slot, so the edge to line up with is the rhythm of
        // the keys above, not their 3pt inset.
        .padding(.horizontal, Theme.Metrics.keySpacing)
    }

    private func tab(id: String, icon: String) -> some View {
        let isSelected = selected == id
        return KeyStyleButton(
            width: nil, height: height, isSelected: isSelected,
            // Capless: see the note on the row. The selected tab is the row's one
            // filled pill and takes white on it; the rest are quiet secondary
            // graphite straight on the panel.
            drawsCap: false,
            glyphColor: isSelected ? Theme.Text.onBrand : Theme.Keys.secondaryLabel,
            action: { onSelect(id) }
        ) {
            Image(systemName: icon)
                .font(Theme.Glyph.font(19))
                .foregroundStyle(isSelected ? Theme.Text.onBrand : Theme.Keys.secondaryLabel)
        }
        // `KeyStyleButton` holds press `@State`. Without a new identity when
        // the orange pill moves, it can keep the `isSelected` it was created
        // with — Recents, on first appear.
        .id("\(id)-\(isSelected)")
        .accessibilityLabel(id)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A button that presses like a key, and wears a cap only if it is one.
///
/// The keyboard's own controls — `123`, delete, shift — are drawn by `KeyView`,
/// which is built around a `KeySpec` and a `KeyCap`. The emoji panel's controls
/// are neither, so this carries the same rules rather than inventing a second
/// look: `Theme.Radius.key` corners, the graphite glyph under a finger, and the
/// keycap depth — contact line and ambient lift, settled a point on press —
/// drawn from `KeyView`'s own recipe (`capKind`), so the panel and the keys
/// cannot drift.
///
/// **Three callers, and they want different halves of it.** The panel's delete is
/// a key and takes all of it, on the soft graphite cap the real delete key wears.
/// A category tab is a shortcut, not a key, and takes `drawsCap: false` — corners
/// and press behaviour without the cap, because ten caps in that row read as one
/// slab of chrome. See `EmojiCategoryRow`. CopyClip's undo is a key that is off
/// more often than it is on, and takes `isDisabled`.
struct KeyStyleButton<Label: View>: View {

    /// Nil spreads the button across the space left over, which is how the tabs
    /// divide the row.
    let width: CGFloat?
    let height: CGFloat
    var isSelected = false
    /// Whether holding it keeps firing. Only delete does.
    var repeats = false
    /// The hold tick, when it is not the tap. Delete uses this so a hold
    /// removes a word while a tap still removes a character.
    var repeatAction: (() -> Void)? = nil
    /// The press haptic, or nil for a control whose action already fires one.
    var feedback: (() -> Void)? = Feedback.modifierPress
    /// Whether this is drawn as a keycap at all — a fill at rest, and the contact
    /// line and ambient lift under it. False for the category tabs, which are
    /// glyphs on the panel: see `EmojiCategoryRow` for the arithmetic that
    /// decided it. A capless button still answers a finger, with `pressWash`
    /// under it for as long as the touch is down, so the tap is confirmed
    /// without the button carrying that weight at rest.
    var drawsCap = true
    /// The cap worn at rest. Ignored when `drawsCap` is false.
    var restingCap: Color = Theme.Keys.card
    /// Which keycap recipe the depth comes from — delete's soft graphite is
    /// `.soft`. Ignored when `drawsCap` is false, which is the only other caller.
    var capKind: KeyView.CapKind = .letter
    /// The glyph's colour at rest. Under a finger the fill goes to the pressed
    /// state and the glyph flips to `Theme.Keys.label`, exactly as `KeyView`'s do.
    var glyphColor: Color = Theme.Keys.label
    /// Whether this control has anything to do right now.
    ///
    /// **The cap stays and only the label fades**, which is the answer
    /// `KeyView.disabledLabelOpacity` already gives for Fix and Rewrite over an
    /// empty field: fading the whole key punches a hole in a row whose evenness is
    /// most of how it reads. And **the gesture guards itself** rather than
    /// trusting `.disabled()`, for the reason `KeyView.acceptsTouches` exists —
    /// this is a raw `DragGesture` on a `ZStack` and reads `\.isEnabled` nowhere,
    /// so whether the framework stops it is a detail that has moved across
    /// releases, and being wrong about it gives a dim key that answers anyway.
    /// `.disabled()` is applied as well, because that is what VoiceOver reads.
    var isDisabled = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false
    @State private var repeater = KeyRepeater.wordDelete()

    /// True for as long as a touch is on this key, and **the only signal that
    /// survives a cancelled gesture** — SwiftUI does not call `onEnded` when a
    /// touch is cancelled by a banner or a Control Centre pull, so `onEnded` alone
    /// would leave the repeat loop deleting into whatever is focused next. The
    /// same reasoning, and the same fix, as `KeyView.isTouching`.
    @GestureState private var isTouching = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(fill)
                .shadow(
                    color: drawsCap ? KeyView.contactShadow(for: capKind) : .clear,
                    radius: 0, x: 0,
                    y: isPressed ? KeyView.pressContactY : KeyView.restContactY
                )
                .shadow(
                    color: drawsCap ? KeyView.ambientShadow(for: capKind) : .clear,
                    radius: isPressed ? KeyView.pressAmbientRadius : KeyView.restAmbientRadius,
                    x: 0, y: isPressed ? KeyView.pressAmbientY : KeyView.restAmbientY
                )
            label()
                // `&& !isSelected`: the flip exists because a pressed cap goes
                // pale and a graphite glyph is what stays legible on it. The
                // selected tab does not go pale — it keeps its brand fill through
                // the press — so flipping there would put graphite on orange.
                .foregroundStyle(isPressed && !isSelected ? Theme.Keys.label : glyphColor)
                .opacity(isDisabled ? KeyView.disabledLabelOpacity : 1)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .offset(y: isPressed ? KeyView.pressTravel : 0)
        .animation(Theme.Motion.press, value: isPressed)
        .animation(Theme.Motion.quick, value: isSelected)
        .contentShape(Rectangle())
        .gesture(press)
        .onChange(of: isTouching) { _, touching in
            if !touching { endPress() }
        }
        // A raw gesture is invisible to VoiceOver, so the tap is restated as an
        // action. Same rule the layout editor is built on: every gesture has a
        // non-gesture route.
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            feedback?()
            action()
        }
        .disabled(isDisabled)
    }

    /// Fires on finger-down rather than on lift, which is what makes a key feel
    /// immediate — `KeyView.pressGesture` for the same reason.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { _ in
                guard !isDisabled, !isPressed else { return }
                isPressed = true
                feedback?()
                action()
                if repeats { repeater.start(repeatAction ?? action) }
            }
            .onEnded { _ in endPress() }
    }

    private func endPress() {
        isPressed = false
        repeater.stop()
    }

    private var fill: Color {
        // **Selected is a filled brand cap, whole — the 14% wash it replaced was
        // measured at 2.3:1 under its own glyph.** The wash worked while the tabs
        // were cards, because the *card* carried the signal and the tint only
        // coloured it. With the cards gone it had to carry the signal alone and
        // could not: a `Brand.solid` glyph on a 14% `Brand.solid` wash is 2.3:1 in
        // orange, 2.58 in pink, 2.59 in blue — under the 3:1 floor, and below the
        // 5.18:1 of the nine *unselected* tabs beside it. The one tab that has to
        // stand out was the hardest to see in the row. `Brand.action` under
        // `Text.onBrand` is 3.64 / 5.35 / 5.17, and 13.34 light and 4.80 dark in
        // monochrome. This is the same mistake `KeyView.capKind` already records
        // making — "a 14% brand wash over whatever cap the key already had ...
        // read as a slightly pink key" — and the same fix.
        //
        // It is tested before the press, so re-tapping the category you are
        // already in does not strobe the pill away under the finger.
        if isSelected { return Theme.Brand.action }
        // **A capless press has to be a wash, and both of the named colours that
        // look right are traps.** A cap answers a finger by going pale, which
        // needs a cap to go pale *from*; a bare glyph has only the keyboard
        // background under it. `Theme.Keys.functionPressed` is 0xFFFEFA on
        // 0xE2E4E8, a pale cap on a pale field — and `Theme.Keys.card` is *the
        // same colour* in light mode (both 0xFFFEFA), so reaching for it changes
        // nothing where the problem is and costs contrast in the dark, where
        // 0x2E3435 on 0x1E2122 is closer than the 0x54595B it replaced. Only a
        // wash off the label tint moves the right way in both: it darkens the
        // light field and lightens the dark one, because the label does.
        if isPressed { return drawsCap ? Theme.Keys.functionPressed : EmojiPanel.pressWash }
        return drawsCap ? restingCap : .clear
    }
}
