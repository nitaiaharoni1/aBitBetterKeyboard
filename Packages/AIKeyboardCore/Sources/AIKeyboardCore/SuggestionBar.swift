import SwiftUI

/// The strip above the keys: emoji on one edge, the AI sparkle on the other, and
/// three candidates between them.
///
/// Emoji and sparkle live here rather than in the bottom row on purpose. Both are
/// about text you are looking at, not keys you are pressing, and it leaves the
/// bottom row close to the system layout where muscle memory expects it.
public struct SuggestionBar: View {

    @ObservedObject private var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: 0) {
            edgeButton(
                systemImage: "face.smiling",
                label: "Emoji",
                isActive: controller.overlay == .emoji
            ) {
                controller.show(controller.overlay == .emoji ? .none : .emoji)
            }

            separator

            suggestions

            separator

            sparkleButton
        }
        .frame(height: Theme.Metrics.suggestionBarHeight)
        .padding(.horizontal, Theme.Space.xxs)
    }

    // MARK: Candidates

    /// Always three slots of equal width. A single candidate stretched across the
    /// whole bar reads as a banner rather than as a word you can tap.
    private var suggestions: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { slot in
                if slot > 0 { candidateSeparator }
                if slot < controller.suggestions.count {
                    candidate(controller.suggestions[slot])
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 36)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.Motion.quick, value: controller.suggestions)
    }

    private func candidate(_ suggestion: Suggestion) -> some View {
        Button {
            controller.apply(suggestion)
        } label: {
            HStack(spacing: 3) {
                Text(suggestion.text)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                // Only tag a candidate when it comes from the other language, so
                // the marker means something instead of decorating every word.
                if suggestion.language != controller.language {
                    LanguageTag(suggestion.language)
                }
            }
            .padding(.horizontal, Theme.Space.xxs)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(suggestion.isDefault ? Theme.Keys.letter.opacity(0.9) : .clear)
            )
            .contentShape(Rectangle())
        }
        .pressable(scale: 0.94)
        .accessibilityLabel(suggestion.text)
        .accessibilityHint(suggestion.isDefault ? "Inserted when you press space" : "")
    }

    // MARK: Edges

    private func edgeButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(isActive ? Theme.Brand.solid : Theme.Keys.secondaryLabel)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(isActive ? Theme.Brand.solid.opacity(0.14) : .clear)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier("bar-\(label.lowercased())")
        .accessibilityLabel(label)
    }

    /// Open when there is text to work on, or a message on screen to answer.
    private var isEnabled: Bool {
        controller.hasTextToWorkWith || controller.canReply
    }

    private var sparkleButton: some View {
        Button {
            controller.show(controller.overlay == .aiMenu ? .none : .aiMenu)
        } label: {
            SparkleMark(size: 19)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Brand.softGradient)
                        .opacity(isEnabled ? 1 : 0.45)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .disabled(!isEnabled)
        .accessibilityIdentifier("bar-sparkle")
        .accessibilityLabel("AI actions")
        .accessibilityHint(isEnabled ? "Fix, rewrite or reply" : "Type something first")
    }

    // MARK: Rules

    private var separator: some View {
        Rectangle()
            .fill(Theme.Keys.secondaryLabel.opacity(0.22))
            .frame(width: 1, height: 22)
            .padding(.horizontal, Theme.Space.xxs)
    }

    private var candidateSeparator: some View {
        Rectangle()
            .fill(Theme.Keys.secondaryLabel.opacity(0.18))
            .frame(width: 1, height: 18)
    }
}
