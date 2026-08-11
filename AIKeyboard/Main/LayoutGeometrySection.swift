import AIKeyboardCore
import SwiftUI

/// "Size and rows" configuration card: key height, row spacing, number row,
/// extra row, and one-handed reach picker.
///
/// Only reads `model` so it can live outside the large `LayoutView` file without
/// needing the canvas-layer `@State` vars.
struct LayoutGeometrySection: View {
    @ObservedObject var model: LayoutEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Size and rows")
            Card {
                VStack(spacing: Theme.Space.sm) {
                    LayoutSlider(
                        title: "Key height", value: model.draft.geometry.keyHeight,
                        range: LayoutGeometry.keyHeightRange, unit: "pt",
                        identifier: "layout-key-height"
                    ) { model.setKeyHeight($0) }
                    Divider.themed
                    LayoutSlider(
                        title: "Row spacing", value: model.draft.geometry.rowSpacing,
                        range: LayoutGeometry.rowSpacingRange, unit: "pt",
                        identifier: "layout-row-spacing"
                    ) { model.setRowSpacing($0) }
                    Divider.themed
                    Toggle(
                        "Number row",
                        isOn: Binding(
                            get: { model.draft.showsNumberRow },
                            set: { model.setNumberRow(enabled: $0) })
                    )
                    .font(Theme.Fonts.body)
                    .accessibilityIdentifier("layout-number-row")
                    Divider.themed
                    Toggle(
                        "Extra row",
                        isOn: Binding(
                            get: { !model.draft.cursorRow.isEmpty },
                            set: { model.setExtraRow(enabled: $0) })
                    )
                    .font(Theme.Fonts.body)
                    .accessibilityIdentifier("layout-extra-row")
                    Divider.themed
                    VStack(alignment: .leading, spacing: 4) {
                        Text("One-handed")
                            .font(Theme.Fonts.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Picker(
                            "One-handed",
                            selection: Binding(
                                get: { model.draft.geometry.reach },
                                set: { model.setReach($0) })
                        ) {
                            Text("Off").tag(Reach.full)
                            Text("Left").tag(Reach.left)
                            Text("Right").tag(Reach.right)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .accessibilityIdentifier("layout-reach")
                    }
                }
            }
        }
    }
}
