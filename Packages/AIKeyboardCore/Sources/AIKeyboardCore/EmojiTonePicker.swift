import SwiftUI

/// The skin-tone strip a held emoji opens, and where on the panel it sits.
///
/// **A value rather than a pile of `@State`.** The panel owns one optional of
/// these; the cell that opened it owns the touch. `owner` is what keeps those two
/// honest: the same emoji is in the People tab *and* in Recents, so a picker
/// identified by its emoji would be open on two cells at once and both would
/// insert on the lift. The id the grid already mints for a cell is unique, so it
/// is what names the one cell this belongs to.
struct EmojiTonePicker: Equatable {

    /// The cell that opened it, which is `EmojiPanel.Cell.id`.
    let owner: String
    /// The plain emoji first, then its five tones light to dark. Exactly what
    /// `EmojiCatalog.variants(for:)` returned, so index and `EmojiSkinTone`
    /// raw value are the same number.
    let variants: [String]
    /// The item a finger that has not moved is resting on: the tone the grid is
    /// already drawn in. **Lifting here must change nothing** — the same rule
    /// `KeyView.alternateRestIndex` is written under.
    let restIndex: Int
    /// The item the finger is over now.
    var selected: Int
    /// The held cell, in the surface's own coordinate space.
    let anchor: CGRect
    /// One item's box. Held rather than recomputed so the hit test and the
    /// drawing cannot disagree about it, which is how a lift on `.` used to pick
    /// `,` — see `KeyView.alternatesStripOffset`.
    let item: CGSize

    /// The strip's own box.
    var size: CGSize {
        CGSize(width: item.width * CGFloat(variants.count), height: item.height)
    }

    /// Air between the strip and the cell it belongs to, and the least it may
    /// come to the edge of the panel. The same 6 points a letter's accent strip
    /// stands off its key by.
    static let gap: CGFloat = 6

    /// What one item wants to be, given the cell that opened it and the panel it
    /// has to fit inside.
    ///
    /// **A cell is not big enough on its own.** The grid's cell is about 38 × 29
    /// in portrait and 38 × 30 in landscape, and 29 points of height is under
    /// `Theme.Metrics.minTouchTarget` in the one axis a finger is not sliding
    /// along. So the item is at least 34 square, which is what a category tab
    /// already is.
    ///
    /// **And then it is shrunk to fit, rather than drawn off the panel.** Six
    /// items at 38 is 228 points, comfortable on a 402 pt phone and comfortable
    /// on a 320 pt one. It is not comfortable on the narrowest keyboard the
    /// layout editor can build, and a strip wider than the panel would have its
    /// last tone unreachable — a picker with a tone in it that no finger can
    /// land on. Dividing the room that is actually there keeps all six
    /// reachable at whatever size that costs.
    static func item(cellWidth: CGFloat, cellHeight: CGFloat, count: Int, surface: CGSize) -> CGSize {
        let room = max(0, surface.width - gap * 2)
        var width = max(cellWidth, 34)
        if count > 0, width * CGFloat(count) > room {
            width = room / CGFloat(count)
        }
        return CGSize(width: width, height: max(cellHeight * 1.15, 34))
    }

    /// Where the strip's top-left corner goes.
    ///
    /// **Above the held cell where there is room, below it where there is not,
    /// and never outside the panel.** A letter's accent strip can hang over the
    /// suggestion bar because the keyboard is what draws both. This one is inside
    /// the emoji panel, and the row a thumb reaches for first is the top row —
    /// where "above" is off the panel entirely. Flipping under the cell keeps
    /// every tone on screen and the finger off the thing it is choosing from.
    ///
    /// **The third branch is the one that had to be written twice, and the
    /// landscape bottom row is why.** Flipping below and then clamping into the
    /// panel looks like it covers every case and does not: the last row has
    /// nothing below it, so the clamp drags the strip straight back up *onto the
    /// cell the finger is holding*. A 60 pt landscape grid two rows tall has 30
    /// points above that row and 26 below, and a 34 pt strip fits in neither, so
    /// there is no placement that misses the cell — only a choice about which
    /// edge of it to cross. Crossing the top puts the strip above the fingertip,
    /// where it can be read; crossing the bottom puts it under the finger, which
    /// is the one outcome worth ruling out. So the fallback takes the roomier
    /// side rather than always the lower one.
    ///
    /// Measured over every geometry `LayoutGeometry` can describe: in portrait
    /// the strip clears the cell completely at every row of every row count, and
    /// landscape's bottom row is the only case that overlaps at all — by 4.5
    /// points of the cell's top edge, well clear of its centre.
    ///
    /// The fit test against 0 rather than `gap`: a strip flush with the top of
    /// the panel is fine, and insisting on six points of air there is six points
    /// of the room this is short of.
    static func origin(anchor: CGRect, size: CGSize, surface: CGSize) -> CGPoint {
        let above = anchor.minY - gap - size.height
        let below = anchor.maxY + gap
        var y: CGFloat
        if above >= 0 {
            y = above
        } else if below + size.height <= surface.height {
            y = below
        } else {
            y = anchor.minY >= surface.height - anchor.maxY ? 0 : surface.height - size.height
        }
        y = min(max(0, y), max(0, surface.height - size.height))
        var x = anchor.midX - size.width / 2
        x = min(max(gap, x), max(gap, surface.width - gap - size.width))
        return CGPoint(x: x, y: y)
    }

    /// Which item a point in the surface's space is over.
    static func index(at point: CGPoint, origin: CGPoint, itemWidth: CGFloat, count: Int) -> Int {
        guard itemWidth > 0, count > 0 else { return 0 }
        let index = Int(((point.x - origin.x) / itemWidth).rounded(.down))
        return min(max(index, 0), count - 1)
    }

    /// What a lift commits.
    ///
    /// **A finger that has not moved commits the rest item, whatever it is
    /// standing over.** The strip is centred on the cell, not on its first item,
    /// so a thumb that opened the picker and lifted straight up is sitting over
    /// the middle of it — which is a tone nobody aimed at, and would repaint the
    /// whole grid. `KeyView.hasSlid` carries the same reasoning and the same six
    /// points; this reuses the number rather than picking a second one.
    static func indexOnLift(
        translation: CGSize, location: CGPoint, origin: CGPoint, itemWidth: CGFloat,
        count: Int, restIndex: Int
    ) -> Int {
        guard hasSlid(translation) else { return restIndex }
        return index(at: location, origin: origin, itemWidth: itemWidth, count: count)
    }

    static func hasSlid(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) > KeyView.slideThreshold
    }
}

/// The strip itself. Drawn by the surface that owns the picker, outside whatever
/// `ScrollView` the held cell lives in — a scroll view clips its content, and a
/// popup clipped to the row it came from is a popup nobody can see.
struct EmojiTonePickerView: View {

    let picker: EmojiTonePicker
    /// The surface the strip is positioned inside, which is the same space
    /// `picker.anchor` was measured in.
    let surface: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let origin = EmojiTonePicker.origin(
            anchor: picker.anchor, size: picker.size, surface: surface)
        HStack(spacing: 0) {
            ForEach(Array(picker.variants.enumerated()), id: \.offset) { index, variant in
                Text(variant)
                    .font(.system(size: min(picker.item.width, picker.item.height) * 0.72))
                    .frame(width: picker.item.width, height: picker.item.height)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                            .fill(index == picker.selected ? Theme.Brand.solid : Color.clear)
                    )
            }
        }
        // Left to right whatever the keyboard's direction, for the reason
        // `KeyView.alternatesPopup` is: `EmojiTonePicker.index(at:)` reads a raw
        // x, and a mirrored strip would put the plain emoji under the far end
        // of it.
        .environment(\.layoutDirection, .leftToRight)
        .frame(width: picker.size.width, height: picker.size.height)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Keys.letter)
                .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 5, y: 2)
        )
        .offset(x: origin.x, y: origin.y)
        // The finger that opened it is still the thing steering it; the strip
        // itself must not take the touch. Same as the accents strip.
        .allowsHitTesting(false)
        // Growing out of the cell means growing from whichever edge the cell is
        // on, and this strip is on both — above the held cell where there was
        // room and below it where there was not (`origin`). A fixed anchor
        // would have the flipped case swelling away from the finger.
        .transition(
            Theme.Motion.pop(
                reduceMotion: reduceMotion,
                anchor: origin.y < picker.anchor.minY ? .bottom : .top))
    }
}

/// One emoji: tap to insert it, hold to choose the tone the whole grid wears.
///
/// **Tapping is still a `Button`, and that is not laziness.** A `ScrollView` in
/// flight swallows the first tap to stop itself, and a raw `DragGesture` does
/// not know that — the tap that halts a scrolling strip would put an emoji in
/// somebody's message. So the tap keeps the control that already gets this
/// right, and the hold rides alongside it as a `simultaneousGesture` so the
/// strip still scrolls under a finger that is dragging rather than dwelling —
/// and only on the 304 cells that have a tone to offer, which is what `body`
/// branches on.
///
/// **Which leaves one touch that both of them want**: hold, then lift without
/// moving. The button fires on that lift and so does the strip, and both would
/// insert. `pickerTookTouch` is what settles it, and it is deliberately *not*
/// cleared when the strip commits — SwiftUI does not say whether the button's
/// action runs before or after the gesture's `onEnded`, so the flag is cleared
/// at the start of the *next* touch instead, where the order cannot matter.
struct EmojiPickCell: View {

    /// The cell's own id, unique on the surface. See `EmojiTonePicker.owner`.
    let identity: String
    /// The untoned spelling, as the catalogue and the recents store it.
    let emoji: String
    let tone: EmojiSkinTone
    let width: CGFloat
    let height: CGFloat
    /// The glyph, as a fraction of the shorter side of the cell.
    let glyphScale: CGFloat
    /// The named coordinate space the surface, this cell's gesture and the
    /// strip's anchor all agree in.
    let space: String
    /// The surface the strip has to stay inside.
    let surface: CGSize
    @Binding var picker: EmojiTonePicker?
    let onInsert: (String) -> Void
    let onTone: (EmojiSkinTone) -> Void

    /// How long a finger stays down before the strip opens. The same 200 ms a
    /// letter waits before its accents (`KeyView.alternatesDelay`) — under the
    /// quarter second a pause becomes visible at, well over the 60–120 ms a
    /// deliberate tap lasts.
    static let holdDelay: Duration = KeyView.alternatesDelay

    @State private var holdTask: Task<Void, Never>?
    /// True from the moment this strip opens until the next touch lands. The
    /// button reads it and stands down.
    @State private var pickerTookTouch = false
    /// Whether this gesture has had its first `onChanged` yet. `DragGesture` has
    /// no "began", and the first change is where a touch is set up.
    @State private var isTracking = false
    @State private var anchor: CGRect = .zero

    /// True for as long as a touch is on this cell, and the only signal that
    /// survives a cancelled gesture — the same reason `KeyStyleButton.isTouching`
    /// exists. Without it a strip opened by a touch that a banner took away
    /// would stay on screen with nothing steering it.
    @GestureState private var isTouching = false

    private var shown: String { EmojiCatalog.toned(emoji, tone) }
    private var hasTones: Bool { EmojiCatalog.hasTones(emoji) }
    private var isShowing: Bool { picker?.owner == identity }

    /// **The 1,566 that have no tone strip get none of this.** A `GeometryReader`
    /// per cell to anchor a strip, a `DragGesture` to wait on and a
    /// `@GestureState` to clean up after are all cost paid on every scroll frame,
    /// and five sixths of the grid could never open a picker with them. `hasTones`
    /// is two dictionary reads and never changes for a given cell, so the branch
    /// is stable: 😂 draws exactly the button it drew before this feature
    /// existed, and only 👋 pays.
    var body: some View {
        if hasTones {
            holdable
        } else {
            button
        }
    }

    /// The tap, which is the whole of an emoji cell for most of the grid.
    ///
    /// **A `Button`, deliberately** — see the note on the type: a scroll view in
    /// flight swallows the first tap to stop itself, and this is the control that
    /// already knows that.
    private var button: some View {
        Button {
            guard !pickerTookTouch else { return }
            onInsert(shown)
        } label: {
            Text(shown)
                // Against the shorter side, so the glyph stays inside its cell
                // on a Compact layout where the rows are 28pt tall.
                .font(.system(size: min(width, height) * glyphScale))
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .pressable(scale: 0.85)
        // On the button rather than on any container around it: the button is
        // the accessibility element, and a label hung on a plain container
        // reaches nothing.
        .accessibilityLabel(EmojiCatalog.names(for: emoji).first ?? emoji)
    }

    private var holdable: some View {
        GeometryReader { geo in
            button
                .simultaneousGesture(hold(in: geo))
                // A hold is invisible to VoiceOver, so every tone is restated as
                // an action. Same rule the layout editor and the accents strip
                // are built on: every gesture has a non-gesture route.
                .accessibilityActions {
                    ForEach(EmojiSkinTone.allCases, id: \.rawValue) { choice in
                        Button(choice.accessibilityName) {
                            onTone(choice)
                            onInsert(EmojiCatalog.toned(emoji, choice))
                        }
                    }
                }
        }
        .frame(width: width, height: height)
        .onChange(of: isTouching) { _, touching in
            guard !touching else { return }
            // A lift has already been through `onEnded` and closed this itself;
            // what arrives here alone is a cancellation, which commits nothing.
            holdTask?.cancel()
            holdTask = nil
            isTracking = false
            if isShowing { withAnimation(Theme.Motion.quick) { picker = nil } }
        }
        // **The cleanup above cannot run if this view stops existing**, and
        // inside a `LazyHGrid` that is an ordinary thing to happen: `@GestureState`
        // resets and `onChange` fires only while something is still tracking the
        // gesture. A cell recycled while it owned the strip left `picker` set with
        // no other writer, and `EmojiPanel`'s `scrollDisabled` then froze the grid
        // until the panel was closed. Guarded on ownership like every other path
        // here, so a cell scrolling away while a *different* cell steers a strip
        // does not close it.
        .onDisappear {
            holdTask?.cancel()
            holdTask = nil
            if isShowing { picker = nil }
        }
    }

    private func hold(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .updating($isTouching) { _, state, _ in state = true }
            .onChanged { value in
                if !isTracking {
                    isTracking = true
                    pickerTookTouch = false
                    // Read now rather than when the wait ends: the proxy is from
                    // the layout pass this touch landed on, and the strip is
                    // stationary for the whole of a hold, so now and then are the
                    // same rectangle — with the difference that now is certain.
                    anchor = geo.frame(in: .named(space))
                    startHold()
                }
                guard isShowing else {
                    // Travel before the strip opens is a finger scrolling the
                    // grid, not a finger waiting on a picker.
                    if EmojiTonePicker.hasSlid(value.translation) { cancelHold() }
                    return
                }
                let next = pick(translation: value.translation, location: value.location)
                if next != picker?.selected { picker?.selected = next }
            }
            .onEnded { value in
                holdTask?.cancel()
                holdTask = nil
                isTracking = false
                guard let strip = picker, strip.owner == identity else { return }
                let index = pick(translation: value.translation, location: value.location)
                withAnimation(Theme.Motion.quick) { picker = nil }
                guard index >= 0, index < strip.variants.count else { return }
                // The tone first, so the emoji this lift inserts and the grid it
                // came from are already saying the same thing by the time the
                // insert lands in Recents.
                onTone(EmojiSkinTone.stored(index))
                onInsert(strip.variants[index])
            }
    }

    /// Which variant a touch at this point means, given how far it has travelled.
    private func pick(translation: CGSize, location: CGPoint) -> Int {
        guard let strip = picker else { return 0 }
        let origin = EmojiTonePicker.origin(
            anchor: strip.anchor, size: strip.size, surface: surface)
        return EmojiTonePicker.indexOnLift(
            translation: translation, location: location, origin: origin,
            itemWidth: strip.item.width, count: strip.variants.count,
            restIndex: strip.restIndex)
    }

    private func startHold() {
        guard hasTones else { return }
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled else { return }
            open()
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
    }

    /// **`@MainActor`, because `Feedback` is.** Reached only from inside the
    /// hold's own `Task { @MainActor in }`, the same shape `KeyView` opens its
    /// accents strip with. A nonisolated helper calling a main-actor haptic does
    /// not compile, which is why the annotation is here and not on `startHold`.
    @MainActor
    private func open() {
        let variants = EmojiCatalog.variants(for: emoji)
        guard variants.count > 1 else { return }
        let rest = min(max(tone.rawValue, 0), variants.count - 1)
        // Set before the animation, so a lift that races the transition still
        // finds the button stood down.
        pickerTookTouch = true
        Feedback.modifierPress()
        let strip = EmojiTonePicker(
            owner: identity,
            variants: variants,
            restIndex: rest,
            selected: rest,
            anchor: anchor,
            item: EmojiTonePicker.item(
                cellWidth: width, cellHeight: height, count: variants.count, surface: surface))
        withAnimation(Theme.Motion.quick) { picker = strip }
    }
}
