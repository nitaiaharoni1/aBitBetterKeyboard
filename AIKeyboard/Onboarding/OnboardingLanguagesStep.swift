import AIKeyboardCore
import SwiftUI

struct LanguagesStep: View {
    @EnvironmentObject private var store: SharedStore
    let setup: SetupState

    var body: some View {
        StepLayout(
            title: "Which languages do you type in?",
            subtitle: "Keeping the list short is what makes prediction fast. You can change this later."
        ) {
            // A card saying "Arabic, Russian and French are on the way." used to
            // sit here, under fourteen live switches three of which are Arabic,
            // Russian and French. Deleted rather than rewritten to name a
            // different set: there is no fifteenth language queued, so any
            // sentence in this slot would be another promise nothing is keeping.
            VStack(spacing: Theme.Space.xs) {
                ForEach(KeyboardLanguage.allCases) { language in
                    LanguageToggleRow(language: language)
                }
            }

            // Said here as well as on step 4, because this is the screen where the
            // choice is made and the keyboard cannot honour it yet. Withheld once
            // Full Access is confirmed, when it is no longer true of this phone.
            if setup.fullAccess != .confirmed {
                Text(SetupState.languagesNeedFullAccess)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LanguageToggleRow: View {
    @EnvironmentObject private var store: SharedStore
    let language: KeyboardLanguage

    private var isOn: Bool { store.enabledLanguages.contains(language) }

    var body: some View {
        Button {
            toggle()
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Text(language.flag)
                    .font(.system(size: 26))

                VStack(alignment: .leading, spacing: 1) {
                    Text(language.nativeName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)
                    Text(language.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.secondary)
                }

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? Theme.Brand.solid : Theme.Text.tertiary)
            }
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isOn ? Theme.Brand.solid.opacity(0.5) : Theme.Surface.separator,
                        lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityLabel(language.displayName)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggle() {
        Feedback.modifierPress()
        withAnimation(Theme.Motion.quick) {
            store.toggleEnabledLanguage(language)
        }
    }
}
