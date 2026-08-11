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
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
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

                        Text(title)
                            .font(Theme.Fonts.display)
                            .foregroundStyle(Theme.Text.primary)
                            .fixedSize(horizontal: false, vertical: true)

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

    /// Flat on purpose: the brand gradient stays with the welcome hero and the
    /// keyboard's own AI moments, so a step icon never competes with either.
    private func iconWell(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .light))
            .foregroundStyle(Theme.Brand.solid)
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
