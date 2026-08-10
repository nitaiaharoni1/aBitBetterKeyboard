import SwiftUI

/// Where each key ended up, keyed by `KeySpec.id`, in `KeyboardView.frameSpace`.
///
/// Published only so the layout editor can put a selection ring and a drop target
/// over the *real* keyboard rather than over a drawing of one. Nothing in the
/// keyboard itself reads this, and it costs one `GeometryReader` per key in a
/// background that draws nothing.
public struct KeyFramesKey: PreferenceKey {
    public static var defaultValue: [String: CGRect] { [:] }
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// The whole keyboard: suggestion strip, key grid, and whatever panel is covering
/// the grid right now.
public struct KeyboardView: View {

    /// The coordinate space `KeyFramesKey` reports in. It is this view's own
    /// bounds, so an `.overlay` on a `KeyboardView` shares it exactly.
    public static let frameSpace = "aikeyboard-frames"

    @ObservedObject private var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            // **One strip, always there, replacing two things that were not.**
            // `ScreenContextStrip` occupied a 30pt row only while a capture session
            // was live, and every AI answer arrived in a panel over the keys. The
            // banner is both: it carries the live reading when there is one, and
            // the running action and its answer when there is one of those.
            ActionBanner(controller: controller)

            SuggestionBar(controller: controller)

            ZStack {
                keyGrid
                    .opacity(controller.overlay == .none ? 1 : 0)
                    // Keys keep their layout while hidden so the grid does not
                    // reflow every time a panel opens.
                    .allowsHitTesting(controller.overlay == .none)

                panel
            }
            .frame(height: Theme.Metrics.keyAreaHeight(for: controller.customization))
        }
        .background(Theme.Keys.background)
        .environment(\.layoutDirection, controller.language.layoutDirection)
        .coordinateSpace(name: Self.frameSpace)
        .onAppear { Feedback.prepare() }
    }

    // MARK: Keys

    private var keyGrid: some View {
        GeometryReader { geo in
            let layout = controller.customization
            let columns = KeyboardLayout.columns(for: controller.language, plane: controller.plane)
            // One-handed narrows the grid and pins it to a side. The keys inside
            // are solved against the narrowed width, so nothing has to know: the
            // whole keyboard is simply drawn in a smaller box.
            let gridWidth = geo.size.width * layout.geometry.reach.widthFraction
            let unit = KeyboardLayout.unitWidth(
                totalWidth: gridWidth,
                spacing: Theme.Metrics.keySpacing,
                sideInset: Theme.Metrics.sideInset,
                columns: columns
            )
            let available = gridWidth - Theme.Metrics.sideInset * 2
            let rows = KeyboardLayout.rows(
                for: controller.language,
                plane: controller.plane,
                showsGlobe: controller.showsGlobeKey,
                customization: layout
            )

            VStack(spacing: layout.geometry.rowSpacing) {
                ForEach(rows) { row in
                    rowView(
                        row, availableWidth: available, unit: unit,
                        height: layout.geometry.keyHeight)
                }
            }
            // **Every row is drawn in the order its keys are listed, in every
            // language, and the letters plane is not an exception.** It was, and
            // that shipped all six right-to-left keyboards mirrored: the rows come
            // out of Apple's own layout data in physical key order, which is
            // already the order Apple draws them on screen — ק at the left of the
            // Hebrew top row, ض at the left of the Arabic one — and an RTL `HStack`
            // draws its first element last, so it reversed rows that were right.
            // `Bar/layouts/stock-rendered-rows.json` is the measurement and
            // `RenderedRowOrderTests` is what holds this to it.
            .padding(.horizontal, Theme.Metrics.sideInset)
            .padding(.top, Theme.Metrics.topInset)
            .padding(.bottom, Theme.Metrics.bottomInset)
            .frame(width: gridWidth)
            // Which edge a narrowed grid hugs.
            .frame(maxWidth: .infinity, alignment: reachAlignment(layout.geometry.reach))
            // **Applied last, so it covers the frame above as well as the rows.**
            // `.leading` and `.trailing` resolve against the layout direction in
            // force *where the modifier sits*, so with this pinned only around the
            // `VStack` a one-handed Hebrew keyboard hugged the wrong side — the
            // rows were right and the box holding them was mirrored. One-handed is
            // about which thumb is holding the phone, and that does not swap with
            // the script.
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    /// Where the grid sits when it has been narrowed for one hand. Physical
    /// sides, guaranteed by the `.leftToRight` pin this is resolved inside.
    private func reachAlignment(_ reach: Reach) -> Alignment {
        switch reach {
        case .full: return .center
        case .left: return .leading
        case .right: return .trailing
        }
    }

    private func rowView(
        _ row: KeyRow, availableWidth: CGFloat, unit: CGFloat, height: CGFloat
    ) -> some View {
        let widths = KeyboardLayout.widths(
            for: row,
            totalWidth: availableWidth,
            unitWidth: unit,
            spacing: Theme.Metrics.keySpacing
        )

        return HStack(spacing: Theme.Metrics.keySpacing) {
            ForEach(Array(row.keys.enumerated()), id: \.element.id) { index, key in
                KeyView(
                    spec: key,
                    width: widths.indices.contains(index) ? widths[index] : unit,
                    height: height,
                    language: controller.language,
                    shift: controller.shift,
                    // Only the space bar carries the language name, and only it
                    // reports a touch instead of a press. Both because a slide
                    // along it switches language — see `SpaceSwipe`. The list is
                    // what it prints codes from and what decides whether it wears
                    // the chevrons that say so.
                    indication: key.cap == .space ? controller.languageSwitchIndication : nil,
                    enabledLanguages: controller.enabledLanguages,
                    // Only the one-tap rewrite key, and only because the list comes
                    // from a setting the app writes: a `KeySpec` is a value and
                    // cannot read the store. Same shape as `enabledLanguages`.
                    toneAlternates: key.cap == .quickTone ? controller.toneAlternates : [],
                    onPress: { controller.press($0) },
                    onRepeat: key.cap == .backspace ? { controller.deleteBackward() } : nil,
                    onAlternate: alternateHandler(for: key),
                    onSpaceTouch: key.cap == .space ? { controller.spaceBarTouch($0) } : nil
                )
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: KeyFramesKey.self,
                            value: [key.id: proxy.frame(in: .named(Self.frameSpace))])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// What lifting a finger on the second or later item of a key's popup does.
    ///
    /// Two kinds of key have one and they mean opposite things. A letter has
    /// *already inserted* its character on finger-down, so picking an accent is a
    /// replacement — delete, then type the alternate. The one-tap rewrite key has
    /// deliberately run nothing yet (see `KeyView.runsOnLift`), so picking a
    /// register is the whole action and there is nothing to undo first.
    private func alternateHandler(for key: KeySpec) -> ((String) -> Void)? {
        if key.cap == .quickTone {
            return controller.toneAlternates.count > 1
                ? { controller.selectTone(named: $0) } : nil
        }
        guard !key.alternates.isEmpty else { return nil }
        return { alternate in
            controller.deleteBackward()
            controller.press(.character(alternate))
        }
    }

    // MARK: Panels

    @ViewBuilder
    private var panel: some View {
        switch controller.overlay {
        case .none:
            EmptyView()
        case .emoji:
            EmojiPanel(controller: controller)
                .transition(panelTransition)
        case .aiMenu:
            AIMenuPanel(controller: controller)
                .transition(panelTransition)
        case .aiResult(let kind):
            AIResultPanel(controller: controller, kind: kind)
                .transition(panelTransition)
        case .dictation:
            DictationPanel(controller: controller)
                .transition(panelTransition)
        }
    }

    private var panelTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
    }
}
