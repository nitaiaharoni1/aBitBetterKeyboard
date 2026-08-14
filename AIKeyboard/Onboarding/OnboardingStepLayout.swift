import AIKeyboardCore
import SwiftUI

/// Centred when the step is short, scrollable when it is not, so no step
/// ends up with a band of dead space between the copy and the button.
struct StepLayout<Content: View>: View {
    /// One SF Symbol for the step's single visual, drawn in a hairline well.
    /// Steps whose content is itself the visual (the welcome hero, the live
    /// keyboard) leave it nil.
    var icon: String?
    var eyebrow: String?
    let title: String
    let subtitle: String
    /// Set only on the welcome step: the title takes the hero voice (heavy,
    /// tight-tracked SF Pro, like the web hero's weight-800 / -.055em spec)
    /// and this word at the end of it gets the editor's-pen circle. Every
    /// other step keeps the plain display style.
    var circledWord: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    if let icon {
                        iconWell(icon)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        if let eyebrow {
                            Text(eyebrow.uppercased())
                                .font(Theme.Fonts.micro)
                                .tracking(0.8)
                                .foregroundStyle(Theme.Brand.solid)
                        }

                        if let circledWord, title.hasSuffix(circledWord) {
                            heroTitle(word: circledWord)
                        } else {
                            Text(title)
                                .font(Theme.Fonts.display)
                                .tracking(-0.5)
                                .foregroundStyle(Theme.Text.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(subtitle)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: minimumContentHeight, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The one marketing headline in onboarding. The circled word stays on
    /// the last line with the words before it so the pen mark wraps that
    /// word, not a stacked leftover, and the two parts combine back into
    /// one accessibility element so the sentence reads whole.
    private func heroTitle(word: String) -> some View {
        let parts = String(title.dropLast(word.count))
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
        let head = parts.dropLast(2).joined(separator: " ")
        let tail = parts.suffix(2).joined(separator: " ")

        return VStack(alignment: .leading, spacing: 2) {
            if !head.isEmpty {
                Text(head)
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-1.4)
                    .foregroundStyle(Theme.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(tail + " ")
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-1.4)
                    .foregroundStyle(Theme.Text.primary)
                Text(word)
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-1.4)
                    .foregroundStyle(Theme.Text.primary)
                    .overlay {
                        DoodleCircle()
                            .padding(.horizontal, -10)
                            .padding(.vertical, -12)
                    }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Graphite on warm white, on purpose: orange stays with the eyebrow, the
    /// primary button and AI moments, so a step icon never competes with any
    /// of them.
    private func iconWell(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(Theme.Text.primary)
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Surface.separator, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Fills the scroll view's own height so `alignment: .center` has something
    /// to centre against.
    private var minimumContentHeight: CGFloat? {
        verticalSizeClass == .compact ? nil : 520
    }
}
