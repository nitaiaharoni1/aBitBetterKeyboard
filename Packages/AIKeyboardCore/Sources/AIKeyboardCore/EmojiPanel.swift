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
/// place. It is an overlay, not a column of its own, so `category(atOffset:)`
/// still counts the same columns.
public struct EmojiPanel: View {

    @ObservedObject var controller: KeyboardController

    /// The keyboard's own key height, so the category row is the same size as the
    /// bottom row it is modelled on. Passed in because it is a user setting —
    /// `LayoutGeometry.keyHeight` moves between 36 and 56.
    let keyHeight: CGFloat

    /// Five, and it is a floor rather than a taste. Four is what the old vertical
    /// grid showed, and the strip has to beat it to be worth the change.
    static let rowCount = 5

    /// What a column wants to be. The real width is this rounded to a whole
    /// number of columns across the panel, so the strip never rests showing a
    /// half-column at the edge of a section.
    static let targetCellWidth: CGFloat = 38

    @State private var scrollOffset: CGFloat = 0

    /// The strip's cells, rebuilt only when the recents change. See the `.task`
    /// in `body` for why this is not a computed property.
    @State private var sections: [Section] = []

    private let scrollSpace = "emoji-strip"

    public init(controller: KeyboardController, keyHeight: CGFloat = Theme.Metrics.keyHeight) {
        self.controller = controller
        self.keyHeight = keyHeight
    }

    public var body: some View {
        GeometryReader { geo in
            let columns = max(1, (geo.size.width / Self.targetCellWidth).rounded())
            let cellWidth = geo.size.width / columns
            let gridHeight = max(0, geo.size.height - keyHeight)
            let cellHeight = gridHeight / CGFloat(Self.rowCount)

            VStack(spacing: 0) {
                grid(cellWidth: cellWidth, cellHeight: cellHeight)
                    .frame(height: gridHeight)

                EmojiCategoryRow(
                    selected: Self.category(
                        atOffset: scrollOffset, cellWidth: cellWidth, in: sections),
                    height: keyHeight,
                    // The section's *first cell*, not the section. `ForEach(sections)`
                    // gives the loop its identity but puts no view on screen with
                    // the category's own id, so `scrollTo("Food")` addressed
                    // nothing and every tab was silently dead.
                    onSelect: { scrollTarget = Self.anchorID(forCategory: $0) },
                    // `press` rather than `deleteBackward`, for the sound: this is
                    // a key the user pressed, and only `press` speaks for one.
                    onDelete: { controller.press(.backspace) }
                )
            }
        }
        // **Built once per change of the recents, not once per scroll frame.**
        // `sections` is 1,870 cells with an interpolated id each; as a computed
        // property read from `body` it was rebuilt on every `onPreferenceChange`
        // the scroll fired, which is sixty times a second while a finger is moving.
        .task { sections = Self.sections(recent: controller.recentEmoji) }
        .onChange(of: controller.recentEmoji) { _, recent in
            sections = Self.sections(recent: recent)
        }
        // The panel is a surface of its own over the key rows, so it wears the
        // warm panel colour rather than the keyboard's background; the category
        // row's card caps are read against it.
        .background(Theme.Keys.panel)
        // Emoji read left to right regardless of the keyboard language, and so
        // does the strip they sit in: a horizontal `ScrollView` in a right-to-left
        // environment starts at the far end, which would open Hebrew's grid on the
        // flags.
        .environment(\.layoutDirection, .leftToRight)
    }

    /// Set by a tab tap, consumed by the grid's `ScrollViewReader`. A piece of
    /// state rather than a direct call because the reader's proxy only exists
    /// inside the grid's own body.
    @State private var scrollTarget: String?

    // MARK: Grid

    private func grid(cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(
                    rows: Array(
                        repeating: GridItem(.fixed(cellHeight), spacing: 0), count: Self.rowCount),
                    spacing: 0
                ) {
                    ForEach(sections, id: \.id) { section in
                        ForEach(section.cells) { cell in
                            self.cell(cell, width: cellWidth, height: cellHeight)
                                .id(cell.id)
                        }
                    }
                }
                .background {
                    // The whole of the scroll tracking. One reader for the strip,
                    // not one per cell: with sections padded to whole columns the
                    // offset alone says which category is at the leading edge.
                    GeometryReader { inner in
                        Color.clear.preference(
                            key: EmojiScrollOffsetKey.self,
                            value: -inner.frame(in: .named(scrollSpace)).minX)
                    }
                }
            }
            .coordinateSpace(name: scrollSpace)
            .onPreferenceChange(EmojiScrollOffsetKey.self) { scrollOffset = $0 }
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
        // dashed one. An overlay so the seam costs no layout — the column maths
        // in `category(atOffset:)` is what the tab highlight rides on.
        .overlay(alignment: .leading) {
            if cell.leadsSection {
                Rectangle().fill(Self.ruleTint).frame(width: 1)
            }
        }
    }

    /// The seam between two sections in the strip.
    ///
    /// The category row used to draw one too, before delete and the tabs stopped
    /// being the same object — a mark separating two things that already look
    /// nothing alike is noise. See `EmojiCategoryRow`.
    static let ruleTint = Theme.Keys.secondaryLabel.opacity(0.18)

    // MARK: Sections

    struct Cell: Identifiable, Equatable {
        let id: String
        let emoji: String?
        /// Whether this cell wears the seam on its leading edge. True for a whole
        /// first column — every cell with an index under `rowCount`, blanks
        /// included, so a section shorter than one column still rules its full
        /// height — and false for the first section that has any cells at all.
        var leadsSection = false
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
    static func sections(recent: [String]) -> [Section] {
        // **The first section holding anything wears no seam.** A rule marks a
        // boundary between two sections, and the leading edge of the strip has
        // only the edge of the panel on its other side. Asked of the cells rather
        // than hardcoded to Recent, because on a fresh install `recent` is empty
        // and Smileys is what opens the grid.
        var result = [section(id: EmojiCatalog.recentID, emoji: recent, rule: false)]
        var anythingBefore = !recent.isEmpty
        for category in EmojiCatalog.categories {
            result.append(section(id: category.id, emoji: category.emoji, rule: anythingBefore))
            anythingBefore = anythingBefore || !category.emoji.isEmpty
        }
        return result
    }

    /// The cell a category tab scrolls to: the first one in that section. Spelled
    /// once, here, because it has to agree exactly with the ids `section` mints.
    static func anchorID(forCategory id: String) -> String { "\(id)-0" }

    private static func section(id: String, emoji: [String], rule: Bool) -> Section {
        var cells = emoji.enumerated().map {
            Cell(
                id: "\(id)-\($0.offset)", emoji: $0.element,
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
                        id: "\(id)-blank-\(blank)", emoji: nil,
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
        atOffset offset: CGFloat, cellWidth: CGFloat, in sections: [Section]
    )
        -> String
    {
        guard cellWidth > 0, !sections.isEmpty else { return EmojiCatalog.recentID }
        let column = Int(max(0, offset) / cellWidth)
        var consumed = 0
        for section in sections {
            consumed += section.cells.count / rowCount
            if column < consumed { return section.id }
        }
        return sections.last?.id ?? EmojiCatalog.recentID
    }
}

/// How far the strip has been swiped, in points.
struct EmojiScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
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
/// panel, and the row's only fill is the selected one — which is also the point,
/// because a tinted card standing among nine white cards was the weakest possible
/// way to say the one thing this row exists to say.
///
/// **Delete keeps its cap, and that is now the whole of "this one is
/// different".** Every other control here scrolls the grid; this one edits the
/// user's text. That used to be carried by a 1pt hairline, because the tabs and
/// delete were the same object with different fills — with the tabs bare, being
/// the row's one keycap says it outright, and the hairline is gone with the
/// reason for it.
///
/// **There is no `אבג` key here.** The way back to the letters is the Emoji key
/// in the action row, which says `אבג` while the grid is open — see
/// `KeyView.label`. Two keys doing one job, a thumb's width apart, is what this
/// row had before.
struct EmojiCategoryRow: View {

    let selected: String
    let height: CGFloat
    let onSelect: (String) -> Void
    let onDelete: () -> Void

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
                Image(systemName: "delete.left")
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
            // Capless: see the note on the row. The selected tab's glyph goes
            // brand with its fill; the rest are quiet secondary graphite
            // straight on the panel.
            drawsCap: false,
            glyphColor: isSelected ? Theme.Brand.solid : Theme.Keys.secondaryLabel,
            action: { onSelect(id) }
        ) {
            Image(systemName: icon)
                .font(Theme.Glyph.font(19))
        }
        .accessibilityLabel(id)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A button that looks and presses like a key.
///
/// The keyboard's own controls — `123`, delete, shift — are drawn by `KeyView`,
/// which is built around a `KeySpec` and a `KeyCap`. A category tab is neither,
/// so this carries the same rules rather than inventing a second look: a resting
/// cap like every key now wears (`restingCap` — warm white card for the tabs,
/// soft graphite for delete), the letter-white cap and the graphite glyph under
/// a finger, `Theme.Radius.key` corners, and the same keycap depth — contact line
/// and ambient lift, settled a point on press — drawn from
/// `KeyView`'s own recipe (`capKind`), so the panel and the keys cannot drift.
struct KeyStyleButton<Label: View>: View {

    /// Nil spreads the button across the space left over, which is how the tabs
    /// divide the row.
    let width: CGFloat?
    let height: CGFloat
    var isSelected = false
    /// Whether holding it keeps firing. Only delete does.
    var repeats = false
    /// The press haptic, or nil for a control whose action already fires one.
    var feedback: (() -> Void)? = Feedback.modifierPress
    /// Whether this is drawn as a keycap at all — a fill at rest, and the contact
    /// line and ambient lift under it. False for the category tabs, which are
    /// glyphs on the panel: see `EmojiCategoryRow` for the arithmetic that
    /// decided it. A capless button still answers a finger, with the warm white
    /// card appearing under it for as long as the touch is down, so the tap is
    /// confirmed without the button carrying that weight at rest.
    var drawsCap = true
    /// The cap worn at rest. Ignored when `drawsCap` is false.
    var restingCap: Color = Theme.Keys.card
    /// Which keycap recipe the depth comes from: the tabs' warm white cards are
    /// `.letter`, delete's soft graphite is `.soft`.
    var capKind: KeyView.CapKind = .letter
    /// The glyph's colour at rest. Under a finger the cap goes light and the
    /// glyph flips to `Theme.Keys.label`, exactly as `KeyView`'s do.
    var glyphColor: Color = Theme.Keys.label
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var isPressed = false
    @State private var repeater = KeyRepeater()

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
                    radius: 0, x: 0, y: isPressed ? 1 : 2
                )
                .shadow(
                    color: drawsCap ? KeyView.ambientShadow(for: capKind) : .clear,
                    radius: isPressed ? 3 : 7, x: 0, y: isPressed ? 2 : 4
                )
            label()
                .foregroundStyle(isPressed ? Theme.Keys.label : glyphColor)
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .offset(y: isPressed ? 1 : 0)
        .animation(Theme.Motion.quick, value: isPressed)
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
    }

    /// Fires on finger-down rather than on lift, which is what makes a key feel
    /// immediate — `KeyView.pressGesture` for the same reason.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { _ in
                guard !isPressed else { return }
                isPressed = true
                feedback?()
                action()
                if repeats { repeater.start(action) }
            }
            .onEnded { _ in endPress() }
    }

    private func endPress() {
        isPressed = false
        repeater.stop()
    }

    private var fill: Color {
        // A capless button has nothing to lighten, so the press is a card
        // *appearing* rather than a cap going pale — `functionPressed` is
        // 0xFFFEFA against a 0xF4F3EF panel, a difference small enough on a phone
        // in daylight to read as no answer at all.
        if isPressed { return drawsCap ? Theme.Keys.functionPressed : Theme.Keys.card }
        if isSelected { return Theme.Brand.solid.opacity(0.14) }
        return drawsCap ? restingCap : .clear
    }
}
