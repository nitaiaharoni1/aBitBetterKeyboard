import SwiftUI
import AIKeyboardCore

@main
struct AIKeyboardApp: App {
    @StateObject private var store = SharedStore.shared

    init() {
        let arguments = ProcessInfo.processInfo.arguments

        // The UI tests walk the app from a known starting point, so they ask for
        // a clean slate rather than inheriting whatever the last run left. That
        // includes the capture channel: a status page left behind by an earlier
        // run has a heartbeat that stopped, which is a real session that ended
        // unexpectedly and would correctly take the screen away from the sample
        // conversation the walkthrough drives.
        if arguments.contains("-uiTestReset") {
            SharedStore.shared.resetToDefaults()
            CaptureChannel.clear()
        } else {
            SharedStore.shared.load()
        }

        // Tests that are not about onboarding start past it. Doing this here
        // rather than by tapping through six screens keeps those tests short and
        // stops an onboarding change from breaking every unrelated test.
        if arguments.contains("-uiTestSkipOnboarding") {
            SharedStore.shared.hasCompletedOnboarding = true
        }

        // Stands in for the broadcast extension, which cannot run on this
        // destination at all. Only `Scripts/prove-capture-channel.sh` passes
        // this; see `CaptureChannelProbe` for what it does and does not show.
        if arguments.contains("-uiTestCaptureChannel") {
            CaptureChannelProbe.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(Theme.Brand.solid)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: store.hasCompletedOnboarding)
        // The app watches the same capture channel the keyboard does, as an
        // observer: it reads the status page so Home and the Screen Context
        // screen show what the capture session is actually doing, and it never
        // writes `intent.keyboardVisible`, because the keyboard is the only
        // thing that can honestly claim to be on screen.
        .onAppear { ScreenContextSession.shared.startConsuming(.shared, as: .observer) }
    }
}
