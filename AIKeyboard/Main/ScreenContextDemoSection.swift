import AIKeyboardCore
import SwiftUI

/// "Not sure yet?" section: lets the user play a scripted sample conversation
/// without starting a real broadcast. Labels the sample clearly, stops it, and
/// refuses to start it while a real session is running.
struct ScreenContextDemoSection: View {
    @EnvironmentObject private var store: SharedStore
    @ObservedObject var session: ScreenContextSession

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Not sure yet?")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(
                        "See it with a sample conversation. Nothing is captured, nothing is sent, and the message is one we wrote."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if session.source == .scripted {
                        SecondaryButton(title: "Stop the sample") {
                            session.stop()
                        }
                    } else if session.canPlaySample {
                        PrimaryButton(title: "Play a sample conversation", icon: "play.fill") {
                            store.screenContextAllowed = true
                            session.start()
                        }
                    } else {
                        // Words rather than a button that does nothing. The sample
                        // would have to paint a message nobody sent over a session
                        // that is watching the real screen, so it is refused — and
                        // the one thing the user can do about it is named.
                        Text(
                            "Not while screen context is running: the strip is showing your real screen, and a made-up message on top of it would be the one thing this feature must never do. Stop the broadcast from the red indicator in the status bar first."
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
