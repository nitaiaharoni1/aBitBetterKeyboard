import SwiftUI

/// One key. Owns its own press state so a touch registers on finger-down rather
/// than on lift, which is what makes typing feel immediate.
public struct KeyView: View {

    private let spec: KeySpec
    private let width: CGFloat
    private let height: CGFloat
    private let language: KeyboardLanguage
    private let shift: ShiftState
    private let onPress: (KeyCap) -> Void
    private let onRepeat: (() -> Void)?

    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    public init(
        spec: KeySpec,
        width: CGFloat,
        height: CGFloat,
        language: KeyboardLanguage,
        shift: ShiftState,
        onPress: @escaping (KeyCap) -> Void,
        onRepeat: (() -> Void)? = nil
    ) {
        self.spec = spec
        self.width = width
        self.height = height
        self.language = language
        self.shift = shift
        self.onPress = onPress
        self.onRepeat = onRepeat
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(background)
                .shadow(color: Theme.Keys.shadow.opacity(0.45), radius: 0, x: 0, y: 1)

            label
        }
        .frame(width: width, height: height)
        .overlay(alignment: .bottom) { callout }
        .zIndex(isPressed ? 1 : 0)
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .accessibilityElement()
        .accessibilityIdentifier("key-\(spec.id)")
        .accessibilityLabel(spec.cap.accessibilityLabel)
        .accessibilityAddTraits(.isKeyboardKey)
    }

    // MARK: Press handling

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isPressed else { return }
                isPressed = true
                onPress(spec.cap)
                startRepeatIfNeeded()
            }
            .onEnded { _ in
                isPressed = false
                repeatTask?.cancel()
                repeatTask = nil
            }
    }

    /// Delete accelerates while held, the way every other keyboard behaves.
    private func startRepeatIfNeeded() {
        guard let onRepeat, spec.cap == .backspace else { return }
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            var interval = 110
            while !Task.isCancelled {
                onRepeat()
                try? await Task.sleep(for: .milliseconds(interval))
                interval = max(45, interval - 8)
            }
        }
    }

    // MARK: Appearance

    private var background: Color {
        if case .character = spec.cap {
            return isPressed ? Theme.Keys.letterPressed : Theme.Keys.letter
        }
        if spec.cap == .space {
            return isPressed ? Theme.Keys.letterPressed : Theme.Keys.letter
        }
        if spec.cap == .ret {
            return isPressed ? Theme.Keys.functionPressed : Theme.Keys.function
        }
        if spec.cap == .shift && shift != .off {
            return Theme.Keys.letter
        }
        return isPressed ? Theme.Keys.functionPressed : Theme.Keys.function
    }

    @ViewBuilder
    private var label: some View {
        switch spec.cap {
        case .character(let value):
            Text(shift.isUppercase ? value.uppercased() : value)
                .font(.system(size: characterFontSize, weight: .regular))
                .foregroundStyle(Theme.Keys.label)

        case .shift:
            Image(systemName: shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift"))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(shift == .off ? Theme.Keys.label : Theme.Keys.label)

        case .backspace:
            Image(systemName: "delete.left")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.Keys.label)

        case .plane(_, let text):
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.Keys.label)

        case .globe:
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.Keys.label)

        case .space:
            Text(language.spaceLabel)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.Keys.secondaryLabel)

        case .ret:
            Text(language.returnLabel)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.Keys.label)

        case .dictation:
            Image(systemName: "mic.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Brand.gradient)
        }
    }

    /// Hebrew glyphs carry more ink than Latin ones and need a touch less size.
    private var characterFontSize: CGFloat {
        language == .hebrew ? 23 : 25
    }

    /// The balloon that pops above a letter while the finger is down, so the
    /// glyph stays readable under the thumb.
    @ViewBuilder
    private var callout: some View {
        if isPressed, case .character(let value) = spec.cap {
            Text(shift.isUppercase ? value.uppercased() : value)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(Theme.Keys.label)
                .frame(width: width * 1.35, height: height * 1.05)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Keys.letter)
                        .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 4, y: 2)
                )
                .offset(y: -height - 4)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
