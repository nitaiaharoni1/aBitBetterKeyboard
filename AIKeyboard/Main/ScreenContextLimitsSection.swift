import AIKeyboardCore
import SwiftUI

/// "What it will not do" section: four factual limits on what screen context
/// can and cannot do. Static content with no session dependency.
struct ScreenContextLimitsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "What it will not do")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    limitRow(
                        "Run forever. Apple reserves permanent capture for remote-desktop apps, so every session is one you started, and iOS can end it for a phone call, the lock button or its own memory limit. This screen tells you it stopped. It cannot tell you which of those did it: iOS says only that the broadcast finished, and never why."
                    )
                    limitRow(
                        "Read anything by itself. A screenshot leaves the device only when you tap Reply, and never on a timer, a screen change or because the keyboard is open."
                    )
                    limitRow(
                        "Promise that protected content is hidden. Apps can exclude themselves from a recording and banking and video apps usually do, but we have not verified that on a device, so do not rely on it."
                    )
                    limitRow(
                        "Work in the background silently. iOS shows a recording indicator the entire time, and the keyboard shows a strip whenever it is up."
                    )
                }
            }
        }
    }

    private func limitRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Text.tertiary)
                .frame(width: 14, height: 18)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
