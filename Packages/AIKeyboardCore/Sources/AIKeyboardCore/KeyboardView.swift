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
            let unit = KeyboardLayout.unitWidth(
                totalWidth: geo.size.width,
                spacing: Theme.Metrics.keySpacing,
                sideInset: Theme.Metrics.sideInset
            )
            let rows = KeyboardLayout.rows(for: controller.language, plane: controller.plane)
                + [KeyboardLayout.bottomRow(
                    for: controller.language,
                    plane: controller.plane,
                    showsGlobe: controller.showsGlobeKey
                )]

            VStack(spacing: Theme.Metrics.rowSpacing) {
                ForEach(rows) { row in
                    rowView(row, availableWidth: geo.size.width - Theme.Metrics.sideInset * 2, unit: unit)
                }
            }
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
                    onPress: { controller.press($0) },
                    onRepeat: key.cap == .backspace ? { controller.deleteBackward() } : nil
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
