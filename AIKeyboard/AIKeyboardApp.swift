import SwiftUI
import AIKeyboardCore

@main
struct AIKeyboardApp: App {
    @StateObject private var store = SharedStore.shared

    init() {
        let arguments = ProcessInfo.processInfo.arguments

        // The UI tests walk the app from a known starting point, so they ask for
        // a clean slate rather than inheriting whatever the last run left.
        if arguments.contains("-uiTestReset") {
            SharedStore.shared.resetToDefaults()
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
    }
}
