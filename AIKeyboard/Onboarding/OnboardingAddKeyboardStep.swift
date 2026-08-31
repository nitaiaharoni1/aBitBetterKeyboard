import AIKeyboardCore
import SwiftUI

/// **The one required setup step, and it covers both halves of getting the
/// keyboard onto the screen.**
///
/// Adding it in Settings and switching to it with the globe key used to be two
/// steps, and they are one task: `KeyboardPresence` is written by the extension's
/// own process, so the app cannot see the keyboard *at all* until it has run,
/// which does not happen until the user has switched to it. The two rows tick
/// together or not at all, and a step that could never tick on its own was a step
/// that only ever cost a tap.
///
/// The globe half carries the one setup fact iOS will never hand the app: which
/// keyboard is on screen in another process. Presence proves the keyboard ran;
/// this step's primary button collects the user's own confirmation that they
/// reached it with the globe key, and persists that answer on the store. That row
/// is `unknown`, never `blocked`, because the app cannot distinguish "hasn't yet"
/// from "did and hasn't said".
struct AddKeyboardStep: View {
    @EnvironmentObject private var store: SharedStore
    let setup: SetupState

    var body: some View {
        StepLayout(
            icon: "keyboard",
            eyebrow: "Setup",
            title: setup.keyboardAdded == .confirmed ? "The keyboard is added" : "Add the keyboard",
            subtitle: subtitle
        ) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    StatusRow(
                        title: "Keyboard added",
                        detail: setup.keyboardAddedDetail,
                        check: setup.keyboardAdded
                    )

                    Divider.themed

                    StatusRow(
                        title: "Switched with the globe key",
                        detail: setup.keyboardSwitchedDetail,
                        check: setup.keyboardSwitched
                    )

                    Divider.themed

                    StatusRow(
                        title: "Allow Full Access",
                        detail: setup.fullAccessDetail,
                        check: setup.fullAccess
                    )
                }
            }

            if setup.fullAccess != .confirmed {
                Text(fullAccessConsequence)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card {
                CloudAIConsentRow(
                    isAllowed: Binding(
                        get: { store.allowsCloudAIProcessing },
                        set: { store.allowsCloudAIProcessing = $0 }
                    ))
            }

            if !instructions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(instructions.enumerated()), id: \.offset) { index, row in
                        if index > 0 {
                            Divider.themed
                        }
                        ExplainerStepRow(number: index + 1, title: row.title, detail: row.detail)
                            .padding(.vertical, Theme.Space.sm)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if setup.keyboardAdded != .confirmed {
                // The numbered rows above carry the path from the top of
                // Settings; this button promises nothing more than getting there.
                SecondaryButton(title: "Open Settings", action: openSettings)
            }

            // Withheld once all three rows have ticked: an explanation of why a
            // box is empty is noise under a box that is full.
            if !setup.isReady || !setup.switchAcknowledged {
                Text(
                    "The first and last rows tick themselves once you have switched to the keyboard "
                        + "in any app; until then the app genuinely cannot tell. The middle one is "
                        + "yours to confirm, because iOS never says which keyboard is on screen."
                )
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var subtitle: String {
        if setup.keyboardAdded != .confirmed {
            return "iOS keeps custom keyboards behind Settings, and then you switch to it with the "
                + "globe key. It takes about twenty seconds."
        }
        return setup.switchAcknowledged
            ? "We can see it, so there is nothing to do here."
            : "We can see it. Confirm below that you reached it with the globe key."
    }

    /// One numbered list rather than two, renumbered as halves of it are
    /// finished: the walk through Settings and the globe key are one journey,
    /// and a second list restarting at 1 underneath the first reads as a second
    /// task on a step whose whole point is that it is a single one.
    private var instructions: [(title: String, detail: String)] {
        var rows: [(title: String, detail: String)] = []
        if setup.keyboardAdded != .confirmed {
            rows += [
                ("Open Settings", "Then tap General."),
                ("Tap Keyboard", "Then tap Keyboards."),
                (
                    "Tap Add New Keyboard…",
                    "aBitBetterKeyboard is listed under Third-Party Keyboards."
                ),
                ("Choose aBitBetterKeyboard", "Then open any app with a text field.")
            ]
        }
        if !setup.switchAcknowledged {
            rows += [
                ("Tap the globe key", "Keep tapping until aBitBetterKeyboard appears."),
                ("Come back here", "Confirm with the button below.")
            ]
        }
        return rows
    }

    /// **The one Full Access sentence on the required path, and it is a
    /// statement rather than an ask.**
    ///
    /// NIT-15 moved the ask to Home's setup card, where the row is named after
    /// what the permission buys. What could not move is the truth, because the
    /// row above this says `SetupState.fullAccessDetail` — "Typing and on-device
    /// AI work without it" — which is true of English and misleading in Hebrew:
    /// Apple's on-device model has no Hebrew (README, "Full Access is optional in
    /// English and effectively required in Hebrew"), so every Hebrew Fix, Rewrite
    /// or Reply goes over the network, and a keyboard extension only has a
    /// network with Full Access on. Read off `enabledLanguages` rather than said
    /// unconditionally, so an English-only user is not told their AI needs a
    /// permission it does not, and shown only while the permission is
    /// unconfirmed, which is the only state in which any of it is news.
    private var fullAccessConsequence: String {
        if store.enabledLanguages.contains(.hebrew) {
            return "Hebrew cloud AI needs Full Access and the separate Allow cloud AI switch. "
                + "Apple's on-device model does not speak Hebrew, so a Hebrew Fix, Rewrite or "
                + "Reply uses the network only after you allow it. Typing, autocorrect and emoji "
                + "work without either permission."
        }
        return "Full Access lets the keyboard reach the network for languages Apple's on-device "
            + "model does not cover. Cloud AI also stays off until you separately allow it. "
            + "Typing, autocorrect and emoji work without either permission."
    }
}
