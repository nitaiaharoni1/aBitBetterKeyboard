import AIKeyboardCore
import SwiftUI

/// Shown when the app has not connected yet.
///
/// Dictation without a backend is a microphone that records into nothing: the
/// failure would land after the user has already spoken. This card says so
/// before they start, in the same words every other cloud dead-end in the app
/// uses.
///
/// **It no longer offers a fix, because there is not one to offer.** The heading
/// said "Needs a cloud model" and the card ended in a row leading to a server
/// address. Nobody using this product has a server address, has been told they
/// need one, or can do anything with the screen behind that row — the connection
/// is made by `AppAttestation` without being asked. What is left is the part that
/// is worth saying: speech leaves the device, and here is why it has to.
struct DictationCloudSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Not connected yet")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(
                        "Speech is transcribed in the cloud. Apple's on-device speech has no Hebrew at all, so there is no on-device path for the languages this keyboard is for. \(BackendTransport.setUpRecovery)"
                    )
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    #if DEBUG
                    CloudModelRow()
                    #endif
                }
            }
        }
    }
}
