import AIKeyboardCore
import SwiftUI

/// The "What needs it" card on `CloudModelView`: explains which features rely
/// on the cloud model so neither is invisible to the user.
///
/// **Both jobs are named here because the whole defect `CloudModelView` exists
/// to fix was one of them being invisible.** Text actions and screen context
/// both consult `BackendTransport.configured`, and a setting that only
/// described screen context left users whose AI actions failed with no path to
/// the fix.
struct CloudModelUsesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "What needs it")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    use(
                        icon: "textformat",
                        title: "Fix, Rewrite, Tone and Reply in Hebrew",
                        detail:
                            "Apple's on-device model does not list Hebrew, so those actions have nowhere to run without this. English, French, German and the rest of the languages Apple does list keep working on the device either way."
                    )
                    use(
                        icon: "eye",
                        title: "Reading the screen",
                        detail:
                            "Screen context sends one screenshot per Reply tap and gets back the sender, the message and its language. Without this a broadcast is refused the moment it starts, rather than recording your screen for nothing."
                    )
                }
            }
        }
    }

    private func use(icon: String, title: String, detail: String) -> some View {
        InfoRow(icon: icon, title: title, detail: detail)
    }
}
