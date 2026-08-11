import AIKeyboardCore
import SwiftUI

/// The "Mixing languages" card explaining code-switching behaviour.
struct LanguageMixingSection: View {

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Mixing languages")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.sm) {
                        IconBadge(systemName: "arrow.left.arrow.right")
                        Text("Code switching is always on")
                            .font(Theme.Fonts.body.weight(.semibold))
                            .foregroundStyle(Theme.Text.primary)
                    }

                    Text(
                        "Predictions look at the whole sentence, not the current layout. Type a Latin word inside a Hebrew sentence and the suggestions follow you."
                    )
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    exampleBubble
                }
            }
        }
    }

    private var exampleBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("אני אשלח לך את ה-document מחר")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Text.primary)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(spacing: 6) {
                ForEach(["deadline", "document", "demo"], id: \.self) { word in
                    HStack(spacing: 3) {
                        Text(word)
                            .font(Theme.Fonts.micro)
                            .foregroundStyle(Theme.Text.primary)
                        LanguageTag(.english)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Surface.elevated))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.background)
        )
        .accessibilityHidden(true)
    }
}
