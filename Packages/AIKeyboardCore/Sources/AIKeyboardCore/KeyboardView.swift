import SwiftUI

/// The whole keyboard: suggestion strip, key grid, and whatever panel is covering
/// the grid right now.
public struct KeyboardView: View {

    @ObservedObject private var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            if controller.showsScreenContextStrip {
                ScreenContextStrip(controller: controller)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            SuggestionBar(controller: controller)

            ZStack {
                keyGrid
                    .opacity(controller.overlay == .none ? 1 : 0)
                    // Keys keep their layout while hidden so the grid does not
                    // reflow every time a panel opens.
                    .allowsHitTesting(controller.overlay == .none)

                panel
            }
            .frame(height: Theme.Metrics.keyAreaHeight)
        }
        .background(Theme.Keys.background)
        .environment(\.layoutDirection, controller.language.layoutDirection)
        .onAppear { Feedback.prepare() }
    }

    // MARK: Keys

    private var keyGrid: some View {
        GeometryReader { geo in
            let columns = KeyboardLayout.columns(for: controller.language, plane: controller.plane)
            let unit = KeyboardLayout.unitWidth(
                totalWidth: geo.size.width,
                spacing: Theme.Metrics.keySpacing,
                sideInset: Theme.Metrics.sideInset,
                columns: columns
            )
            let available = geo.size.width - Theme.Metrics.sideInset * 2
            let characterRows = KeyboardLayout.rows(for: controller.language, plane: controller.plane)

            VStack(spacing: Theme.Metrics.rowSpacing) {
                ForEach(characterRows) { row in
                    rowView(row, availableWidth: available, unit: unit)
                }
                rowView(
                    KeyboardLayout.bottomRow(
                        for: controller.language,
                        plane: controller.plane,
                        showsGlobe: controller.showsGlobeKey
                    ),
                    availableWidth: available,
                    unit: unit
                )
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
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, Theme.Metrics.sideInset)
            .padding(.top, Theme.Metrics.topInset)
            .padding(.bottom, Theme.Metrics.bottomInset)
        }
    }

    private func rowView(_ row: KeyRow, availableWidth: CGFloat, unit: CGFloat) -> some View {
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
                    height: Theme.Metrics.keyHeight,
                    language: controller.language,
                    shift: controller.shift,
                    // Only the space bar carries the language name, and only it
                    // reports a touch instead of a press. Both because a slide
                    // along it switches language — see `SpaceSwipe`. The count is
                    // what decides whether it wears the chevrons that say so.
                    indication: key.cap == .space ? controller.languageSwitchIndication : nil,
                    enabledLanguageCount: controller.enabledLanguageCount,
                    onPress: { controller.press($0) },
                    onRepeat: key.cap == .backspace ? { controller.deleteBackward() } : nil,
                    // The key already inserted its own character on finger-down,
                    // so choosing an alternate is a replacement rather than an
                    // insertion.
                    onAlternate: key.alternates.isEmpty
                        ? nil
                        : { alternate in
                            controller.deleteBackward()
                            controller.press(.character(alternate))
                        },
                    onSpaceTouch: key.cap == .space ? { controller.spaceBarTouch($0) } : nil
                )
            }
        }
        .frame(maxWidth: .infinity)
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
