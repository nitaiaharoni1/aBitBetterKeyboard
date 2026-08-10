import AIKeyboardCore
import SwiftUI

/// "What actually happens" section: three numbered steps followed by an
/// honest caveat about what has not been measured on a real device.
///
/// No session or store dependency — entirely static content, so it owns no
/// state and can be diffed as a documentation change.
struct ScreenContextExplanationSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "What actually happens")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ExplainerStepRow(
                        number: 1,
                        title: "iOS captures the screen",
                        detail:
                            "The broadcast keeps running when you switch to WhatsApp or Slack. Nothing is sent anywhere while it just runs."
                    )
                    // "Half the size" is the measurement, not a hedge: the
                    // capture process uploads 602x1310 rather than the full
                    // 1206x2622, and `Bar/screen-context/` §"Size and format"
                    // scores both. It costs no accuracy and saves 74% of the
                    // bytes. Saying the size here is what stops this screen
                    // quoting a full-resolution bar for a half-resolution
                    // pipeline.
                    ExplainerStepRow(
                        number: 2,
                        title: "Tapping Reply sends one screenshot",
                        detail:
                            "The screen is read in the cloud, because on-device text recognition has no Hebrew and reads the rest less accurately. One picture goes out per tap, shrunk to half the screen's width and height, and nothing else does."
                    )
                    ExplainerStepRow(
                        number: 3,
                        title: "Only text reaches the keyboard",
                        detail:
                            "What comes back is the sender, the message and its language. The picture is never saved — not on disk, not in the shared container, not in a backup. That text is handed over in a file the keyboard deletes as soon as the broadcast it came from has stopped."
                    )

                    Divider().overlay(Theme.Surface.separator)

                    // All three steps are built now. What is still missing is a
                    // measurement, not code, and the honest thing is to say which
                    // it is rather than let a Reply tap fail with a reason it
                    // invented.
                    Text(
                        "All three steps are built, and none of them has run on a phone yet: a broadcast cannot start in the simulator, so no frame has ever reached the capture process here. Reply may not work on your device, and if it does not, the reason it gives you is the real one."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
