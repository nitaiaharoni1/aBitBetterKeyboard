import AIKeyboardCore
import SwiftUI

struct AddKeyboardStep: View {
    let setup: SetupState

    var body: some View {
        StepLayout(
            title: setup.keyboardAdded == .confirmed ? "The keyboard is added" : "Add the keyboard",
            subtitle: setup.keyboardAdded == .confirmed
                ? "We can see it, so there is nothing to do here."
                : "iOS keeps custom keyboards behind Settings. It takes about twenty seconds."
        ) {
            Card {
                StatusRow(
                    title: "Keyboard added",
                    detail: setup.keyboardAddedDetail,
                    check: setup.keyboardAdded
                )
            }

            if setup.keyboardAdded != .confirmed {
                VStack(spacing: Theme.Space.xs) {
                    InstructionRow(number: 1, text: "Open Settings, then General")
                    InstructionRow(number: 2, text: "Tap Keyboard, then Keyboards")
                    InstructionRow(number: 3, text: "Tap Add New Keyboard…")
                    InstructionRow(number: 4, text: "Choose AI Keyboard")
                }

                SettingsLinkButton()
            }
        }
    }
}

/// Opens Settings. The numbered steps beside this button carry the path from
/// the top of Settings; the button promises nothing more than getting there.
struct SettingsLinkButton: View {
    var body: some View {
        Button(action: openSettings) {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "arrow.up.forward.app")
                Text("Open Settings")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.Brand.solid)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Brand.solid.opacity(0.12))
            )
            .contentShape(Rectangle())
        }
        .pressable()
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Text.onBrand)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.Brand.gradient))

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Text.primary)

            Spacer()
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.horizontal, Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.raised)
        )
        .accessibilityElement(children: .combine)
    }
}
