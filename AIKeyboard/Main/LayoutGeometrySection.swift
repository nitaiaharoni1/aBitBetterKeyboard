import AIKeyboardCore
import SwiftUI

/// "Size and rows" configuration card: a key height per row band, row spacing,
/// number row, and the one-handed reach picker.
///
/// **Three height sliders, and the letters are the one that covers several
/// rows.** The action row and the space row do different jobs from the letters
/// and from each other, so each answers to its own; the three letter rows and
/// the optional number row share one, because a stagger inside the letter grid
/// reads as a rendering fault rather than a preference. `LayoutGeometry.RowBand`
/// is the list, so a fourth band can never appear here without the arithmetic in
/// `Theme.Metrics.keyAreaHeight(for:)` being asked about it.
///
/// **There is deliberately no "Extra row" switch, and there was one.** That row
/// is the *action* row — CopyClip, Fix, settings, Rewrite, dictation — so a
/// single tap on a control named after its position rather than its contents
/// emptied the whole AI surface, and nothing on the switch said so. The keys
/// come off it one at a time by dragging them up to the spare keys, which is the
/// same outcome arrived at deliberately, and any preset puts a full row back.
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
                    // Without this, three sliders reading "44pt", "39pt" and
                    // "44pt" sit directly above one reading "12pt" and nothing
                    // says the first three are heights and the fourth is the gap
                    // between them.
                    Text("Row height")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(LayoutGeometry.RowBand.allCases, id: \.self) { band in
                        LayoutSlider(
                            title: band.title, value: model.draft.geometry.height(band),
                            range: LayoutGeometry.keyHeightRange, unit: "pt",
                            identifier: identifier(for: band)
                        ) { model.setKeyHeight($0, for: band) }
                    }
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

    /// **The letters band keeps the original `layout-key-height`.** It is the
    /// band that existed when there was one height, so it keeps the name; the
    /// other two are suffixed. Nothing addresses it yet — the justification here
    /// used to claim the UI tests and the in-app search did, and a grep across
    /// `AIKeyboard`, `AIKeyboardUITests` and `Packages` returns only the
    /// definition below. Keep the name anyway, because the first test to reach
    /// for this slider should not have to know it was ever called anything else.
    private func identifier(for band: LayoutGeometry.RowBand) -> String {
        band == .letters ? "layout-key-height" : "layout-key-height-\(band.rawValue)"
    }
}
