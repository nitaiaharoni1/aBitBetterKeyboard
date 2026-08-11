import AIKeyboardCore
import SwiftUI

/// The one place the cloud model is configured, and the only writer of
/// `cloudBackendURL` in the app.
///
/// **Why this is a screen of its own, and why it is reached from Settings › AI
/// rather than living on Screen Context.** `BackendTransport.configured()` is
/// consulted by three readers — the keyboard's Fix, Rewrite, Tone and Reply, the
/// capture process's screen reader, and `ScreenContextSession` — and for most of
/// this project its only writer was a card headed "Where the screen is read", on a
/// screen entirely about screen recording. Nothing said that the same field was
/// what switched on Hebrew. So on a stock install the keyboard's primary language
/// failed at every AI action with "no cloud model is set up", Home asserted that
/// cloud rewrites worked, and Settings › AI held a tone picker and a switch that
/// controlled nothing.
///
/// A row on Screen Context pointing here would have been the smaller diff. It was
/// rejected because it leaves the setting *living* inside the feature that needs it
/// least often: text actions are what a keyboard does every minute, screen context
/// is a session somebody starts occasionally, and a user who has never opened
/// Screen Context has no reason to go looking there for the thing that makes their
/// keyboard work. Settings › AI is where somebody stands when AI does not work, so
/// the setting lives there and Screen Context carries the pointer instead — still
/// above its start button, because a broadcast started without this ends inside a
/// second.
///
/// The name is single by construction: `BackendTransport.settingsPath` is this
/// row's path, and every failure that dead-ends here prints it.
struct CloudModelView: View {
    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    CloudModelFieldSection()
                    CloudModelUsesSection()
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle("Cloud model")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Pointing at it

/// The row both Settings › AI and Screen Context show, so one setting is reached
/// by one name from both features that need it.
struct CloudModelRow: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        NavigationRow(
            title: "Cloud model",
            subtitle: store.hasCloudModel ? "Set up" : "Not set up",
            icon: "cloud"
        ) {
            CloudModelView()
        }
    }
}
