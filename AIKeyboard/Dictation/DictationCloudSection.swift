import AIKeyboardCore
import SwiftUI

/// Shown when no cloud model is configured.
///
/// Dictation without a backend is a microphone that records into nothing: the
/// failure would land after the user has already spoken. This card says so
/// before they start, in the same words every other cloud dead-end in the app
/// uses, and links directly to the fix.
struct DictationCloudSection: View {
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader(title: "Needs a cloud model")
                Text(
                    "Speech is transcribed in the cloud. Apple's on-device speech has no Hebrew at all, so there is no on-device path for the languages this keyboard is for. \(BackendTransport.setUpRecovery)"
                )
                .font(.system(size: 13))
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)

                NavigationLink("Set up the cloud model") { CloudModelView() }
                    .font(.system(size: 14, weight: .semibold))
            }
        }
    }
}
