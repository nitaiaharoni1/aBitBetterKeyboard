import AIKeyboardCore
import SwiftUI

/// Centred when the step is short, scrollable when it is not, so no step
/// ends up with a band of dead space between the copy and the button.
struct StepLayout<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Fills the scroll view's own height so `alignment: .center` has something
    /// to centre against.
    private var minimumContentHeight: CGFloat? {
        verticalSizeClass == .compact ? nil : 520
    }
}
