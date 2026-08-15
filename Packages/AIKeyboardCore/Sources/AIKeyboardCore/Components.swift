import SwiftUI

// MARK: - Brand mark

/// The sparkle, drawn in the brand gradient. Used wherever an AI action starts.
public struct SparkleMark: View {
    private let size: CGFloat

    /// Named rather than inlined so `ToneIconTests` can assert that no
    /// `ToneStyle` wears the same drawing. `ToneStyle.clearer` did — SF `sparkle`
    /// is this symbol at one point instead of three — and the two buttons sat
    /// side by side in `SuggestionBar`.
    public static let symbolName = "sparkles"

    public init(size: CGFloat = 20) {
        self.size = size
    }

    public var body: some View {
        Image(systemName: Self.symbolName)
            .font(Theme.Glyph.medium(size))
            .foregroundStyle(Theme.Brand.gradient)
            .accessibilityHidden(true)
    }
}

// MARK: - Waveform

/// Live input level, faked from a phase value. Bars ease rather than jump so the
/// motion reads as audio rather than as a progress bar.
public struct WaveformView: View {
    private let phase: Double
    private let barCount: Int
    private let color: Color
    private let isActive: Bool

    public init(
        phase: Double, barCount: Int = 28, color: Color = Theme.Semantic.record, isActive: Bool = true
    ) {
        self.phase = phase
        self.barCount = barCount
        self.color = color
        self.isActive = isActive
    }

    public var body: some View {
        GeometryReader { geo in
            let barWidth = max(2, (geo.size.width - CGFloat(barCount - 1) * 3) / CGFloat(barCount))
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: height(at: index, in: geo.size.height))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .animation(.easeOut(duration: 0.12), value: phase)
        .accessibilityHidden(true)
    }

    private func height(at index: Int, in maxHeight: CGFloat) -> CGFloat {
        guard isActive else { return 3 }
        // Two out-of-step sine waves keep neighbouring bars from marching in lockstep.
        let position = Double(index)
        let a = sin(phase * 2.4 + position * 0.55)
        let b = sin(phase * 1.3 + position * 0.21)
        let normalised = (a * 0.6 + b * 0.4 + 1) / 2
        // Taper the ends so the shape reads as a burst rather than a block.
        let taper = sin(Double(index + 1) / Double(barCount + 1) * .pi)
        return max(3, maxHeight * CGFloat(0.18 + normalised * 0.82) * CGFloat(taper))
    }
}

// MARK: - Language tag

/// The small marker that identifies a suggestion coming from the other language.
public struct LanguageTag: View {
    private let language: KeyboardLanguage
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ language: KeyboardLanguage) {
        self.language = language
    }

    public var body: some View {
        Text(language.shortName)
            .font(
                .system(
                    size: min(9 * Theme.DynamicType.scale(for: dynamicTypeSize), Theme.Glyph.lightFloor),
                    weight: .semibold)
            )
            .foregroundStyle(Theme.Brand.solid)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Theme.Brand.solid.opacity(0.14))
            )
            .accessibilityLabel(language.displayName)
    }
}

// MARK: - Press feedback

/// Scale-down on touch. Applied to every tappable surface outside the key grid,
/// which has its own pressed colour instead.
public struct PressableStyle: ButtonStyle {
    private let scale: CGFloat

    public init(scale: CGFloat = 0.97) {
        self.scale = scale
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

public extension View {
    func pressable(scale: CGFloat = 0.97) -> some View {
        buttonStyle(PressableStyle(scale: scale))
    }
}
