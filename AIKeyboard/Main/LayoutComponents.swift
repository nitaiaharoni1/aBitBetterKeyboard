import AIKeyboardCore
import SwiftUI

// MARK: - LayoutSlider

/// A labelled slider with a monospaced value readout, shared by
/// `LayoutGeometrySection` and `LayoutKeyInspectorSection`.
struct LayoutSlider: View {
    let title: String
    let value: CGFloat
    let range: ClosedRange<CGFloat>
    let unit: String
    let identifier: String
    let onChange: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(Theme.Fonts.body)
                Spacer()
                Text("\(Int(value))\(unit)")
                    .font(Theme.Fonts.caption.monospaced())
                    .foregroundStyle(Theme.Text.secondary)
            }
            Slider(
                value: Binding(get: { Double(value) }, set: { onChange(CGFloat($0)) }),
                in: Double(range.lowerBound)...Double(range.upperBound), step: 1
            )
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(value)) \(unit)")
        }
    }
}
