import SwiftUI
import AIKeyboardCore

@main
struct AIKeyboardApp: App {
    @StateObject private var store = SharedStore.shared
    @State private var selectedMainTab: MainTab = .home

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
            DictationChannel.clear()
        } else {
            SharedStore.shared.load()
        }

        // The app is the process that tidies the shared container: it has no
        // memory cap, no keyboard's latency budget, and it is the only one of the
        // three that is not holding a page open when it runs. Both halves are
        // debris a previous build or a killed producer left behind — orphaned
        // channel directories, and the text of a message whose session is over.
        CaptureChannel.sweep()

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

        // Stands in for the microphone and the transcriber, and for nothing
        // else: the channel underneath it is the shipping one. See
        // `DictationChannelProbe`, and `Scripts/prove-dictation.sh` for what it
        // does and does not prove.
        if arguments.contains("-uiTestDictationChannel") {
            DictationChannelProbe.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(selectedMainTab: $selectedMainTab)
                .environmentObject(store)
                .tint(Theme.Brand.solid)
        }
        // **iOS wakes the app for this, and the user never learns it happened.**
        // A session token lasts ninety days and only this process can renew one,
        // so an install whose owner onboarded and never came back would have gone
        // dark on every AI action until they happened to open the app again. That
        // is the whole reason the keyboard used to have to say "open AI Keyboard"
        // to somebody who had no idea it had a cloud model. `.backgroundTask` both
        // registers the identifier at launch and handles the wake-up; an
        // identifier that is permitted in `Info.plist` and never registered is a
        // launch crash, which is why the two names come from one constant.
        .backgroundTask(.appRefresh(AppAttestation.refreshTaskIdentifier)) {
            await AppAttestation.refreshIfNeeded(store: .shared)
            // Rescheduled from inside the wake-up, because iOS grants exactly one
            // run per submitted request. Without this the app reconnects itself
            // precisely once and then never again.
            await AppAttestation.scheduleRefresh()
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: SharedStore
    @Binding var selectedMainTab: MainTab
    @StateObject private var search = AppSearch()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                MainTabView(selection: $selectedMainTab)
                    .environmentObject(search)
                    // **`Theme.Brand` is a global, so somebody has to tell
                    // SwiftUI it moved.** Most of the views that draw an accent
                    // observe nothing and take no parameter that changes with
                    // the palette, so without this they keep the colour they
                    // were built with until something unrelated invalidates
                    // them. Rebuilding the tab tree is the cheap, total answer.
                    //
                    // The state it costs is navigation depth inside a tab, and
                    // that is affordable *because of where the picker is*: it
                    // sits on the Keys root, which is the only screen a
                    // palette can be changed from, so there is nothing pushed
                    // above it to lose. Moving the picker behind a
                    // `NavigationRow` would break that and this would start
                    // dismissing the screen the user tapped on.
                    //
                    // Search state lives on this view, above the `.id`, so a
                    // palette change does not wipe the query.
                    .id(store.brandPalette)
            } else {
                OnboardingFlow()
            }
        }
        .animation(Theme.Motion.quick, value: store.hasCompletedOnboarding)
        .onOpenURL { url in
            if url == SharedStore.settingsURL {
                selectedMainTab = .settings
            } else if url == SharedStore.dictationStartURL {
                beginDictationHandoffIfFresh()
            } else if url == SharedStore.screenContextURL {
                selectedMainTab = .home
                search.openScreenContext()
            }
        }
        // The app watches the same capture channel the keyboard does, as an
        // observer: it reads the status page so Home shows what the capture
        // session is actually doing, and it never writes
        // `intent.keyboardVisible`, because the keyboard is the only thing
        // that can honestly claim to be on screen.
        .onAppear {
            ScreenContextSession.shared.startConsuming(.shared, as: .observer)
            // Cold-launch fallback: the keyboard wrote a handoff before the app
            // was running. Consume it here so the hot-path `onOpenURL` and this
            // path cannot both trigger auto-start.
            beginDictationHandoffIfFresh()
            // **Unstructured, where this used to be a `.task`.** A `.task` is
            // cancelled when its view goes away, and this view is a `Group`
            // whose branch swaps the moment onboarding finishes — so the one
            // attestation an install got could be killed part-way by the user
            // tapping Done, and nothing retried it. Attestation guards itself
            // against overlapping runs, so it does not need the view to own its
            // lifetime.
            Task { await AppAttestation.refreshIfNeeded(store: store) }
        }
        // **Launch is not enough, and believing it was is half of why the cloud
        // was dead.** Attestation can fail for reasons that are gone a minute
        // later — Apple's own service answering `serverUnavailable`, no network
        // at the instant of a cold start, the run suspended when the user left
        // for the app they were typing in. A single unretried attempt per launch
        // turned any of those into an install that 401s on every AI action until
        // somebody force-quits and reopens. `refreshIfNeeded` is cheap when there
        // is nothing to do and holds its own cooldown, so this cannot loop.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                // Submitted on the way out, because a request survives the app
                // being suspended and terminated but not being uninstalled, and
                // this is the last moment the app is guaranteed to run. Resubmitting
                // an identifier that already has a pending request replaces it.
                AppAttestation.scheduleRefresh()
                return
            }
            Task { await AppAttestation.refreshIfNeeded(store: store) }
        }
    }

    /// The keyboard recorded a handoff before opening us. Consume it so the
    /// cold-launch path and the warm-launch `onOpenURL` path do not both
    /// auto-start (only one process writes, only one read counts). Guard on
    /// the return value: an arbitrary external open of this URL with no fresh
    /// shared request must not auto-start the mic.
    ///
    /// Lands on Home and starts the session. The microphone still opens here,
    /// in the foreground, because that is the OS boundary: the keyboard cannot
    /// open it, and an app cannot *begin* recording from the background.
    private func beginDictationHandoffIfFresh() {
        guard SharedStore.shared.consumeDictationHandoff() else { return }
        selectedMainTab = .home
        search.openDictation()
        Task {
            _ = await DictationService.shared.start(minutes: 0)
        }
    }
}
