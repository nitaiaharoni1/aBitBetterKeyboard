import AIKeyboardCore
import SwiftUI

/// The session-length segmented picker group.
struct DictationLengthSection: View {
    @Binding var sessionMinutes: Int
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Session length")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Picker("Session length", selection: $sessionMinutes) {
                        ForEach(SharedStore.dictationSessionChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRunning)

                    Text(
                        isRunning
                            ? "Stop the session to change this."
                            : "How long the microphone stays available before it closes itself. There is deliberately no \"never\"."
                    )
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
