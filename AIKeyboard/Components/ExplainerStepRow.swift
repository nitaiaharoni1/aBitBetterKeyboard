import AIKeyboardCore
import SwiftUI

/// A numbered step row used across explanation and starter sections.
///
/// The ring is graphite, not brand: the numbers are wayfinding chrome, and
/// orange stays with AI moments, primary actions and selection.
struct ExplainerStepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text("\(number)")
                .font(Theme.Fonts.micro)
                .foregroundStyle(Theme.Text.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().strokeBorder(Theme.Text.tertiary, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Fonts.body.weight(.semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
