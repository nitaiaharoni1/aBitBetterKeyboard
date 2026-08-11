import AIKeyboardCore
import SwiftUI

struct FullAccessStep: View {
    let setup: SetupState

    var body: some View {
        StepLayout(
            icon: "lock.shield",
            eyebrow: "Setup",
            title: setup.fullAccess == .confirmed ? "Full Access is on" : "Allow Full Access",
            subtitle: "It sounds alarming, so here is exactly what it does and does not do."
        ) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    StatusRow(
                        title: "Full Access",
                        detail: setup.fullAccessDetail,
                        check: setup.fullAccess
                    )
                    if let explanation = setup.unresolvedExplanation, setup.fullAccess != .confirmed {
                        Text(explanation)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Text.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: 0) {
                // Reads the measurement rather than asserting the happy case. The
                // fixed sentence here promised "cloud rewrites for languages the
                // on-device model cannot handle" to a user with no cloud model —
                // which is every stock install, and is exactly the language this
                // keyboard is for. See `SetupState.fullAccessTurnsOn`.
                InfoRow(
                    icon: "checkmark.shield",
                    title: "What it turns on",
                    detail: setup.fullAccessTurnsOn
                )
                .padding(.vertical, Theme.Space.sm)

                Divider.themed

                InfoRow(
                    icon: "xmark.shield",
                    title: "What we never send",
                    detail:
                        "Passwords, payment fields and anything you type in a secure field. Those never reach us, by design."
                )
                .padding(.vertical, Theme.Space.sm)

                Divider.themed

                // Also read out of `SetupState` rather than written here, and for a
                // sharper reason than the row above: the sentence this replaced
                // said Full Access was "only for the cloud fallback", which is
                // what silently loses a French-only user the language list they
                // chose on step 2. See `SetupState.worksWithoutFullAccess`.
                InfoRow(
                    icon: "iphone",
                    title: "Works without it",
                    detail: SetupState.worksWithoutFullAccess
                )
                .padding(.vertical, Theme.Space.sm)
            }
        }
    }
}
