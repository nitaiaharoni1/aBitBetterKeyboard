import AIKeyboardCore
import SwiftUI

struct FullAccessStep: View {
    let setup: SetupState

    var body: some View {
        StepLayout(
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
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: Theme.Space.xs) {
                // Reads the measurement rather than asserting the happy case. The
                // fixed sentence here promised "cloud rewrites for languages the
                // on-device model cannot handle" to a user with no cloud model —
                // which is every stock install, and is exactly the language this
                // keyboard is for. See `SetupState.fullAccessTurnsOn`.
                AccessRow(
                    icon: "checkmark.shield",
                    tint: Theme.Semantic.success,
                    title: "What it turns on",
                    detail: setup.fullAccessTurnsOn
                )
                AccessRow(
                    icon: "xmark.shield",
                    tint: Theme.Semantic.warning,
                    title: "What we never send",
                    detail:
                        "Passwords, payment fields and anything you type in a secure field. Those never reach us, by design."
                )
                // Also read out of `SetupState` rather than written here, and for a
                // sharper reason than the row above: the sentence this replaced
                // said Full Access was "only for the cloud fallback", which is
                // what silently loses a French-only user the language list they
                // chose on step 2. See `SetupState.worksWithoutFullAccess`.
                AccessRow(
                    icon: "iphone",
                    tint: Theme.Brand.solid,
                    title: "Works without it",
                    detail: SetupState.worksWithoutFullAccess
                )
            }
        }
    }
}

struct AccessRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        Card {
            InfoRow(icon: icon, tint: tint, title: title, detail: detail)
        }
    }
}
