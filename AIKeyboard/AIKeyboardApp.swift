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
                .onOpenURL { url in
                    if url == SharedStore.settingsURL {
                        selectedMainTab = .settings
                    } else if url == SharedStore.dictationStartURL {
                        // The keyboard recorded a handoff before opening us. Consume it
                        // so the cold-launch path and this warm-launch path do not both
                        // auto-start (only one process writes, only one read counts).
                        // Guard on the return value: an arbitrary external open of this
                        // URL with no fresh shared request must not auto-start the mic.
                        if SharedStore.shared.consumeDictationHandoff() {
                            DictationHandoffTrigger.shared.activate()
                        }
                    }
                }
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
    @ObservedObject private var handoffTrigger = DictationHandoffTrigger.shared
    @Binding var selectedMainTab: MainTab
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if store.hasCompletedOnboarding {
                MainTabView(selection: $selectedMainTab)
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
        .onAppear {
            ScreenContextSession.shared.startConsuming(.shared, as: .observer)
            // Cold-launch fallback: the keyboard wrote a handoff before the app
            // was running. Consume it here so the hot-path `onOpenURL` and this
            // path cannot both trigger auto-start.
            if SharedStore.shared.consumeDictationHandoff() {
                DictationHandoffTrigger.shared.activate()
            }
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
        // Full-screen so the swipe-back gesture is the main affordance, which
        // matches the instruction this screen gives. A `.sheet` presents with
        // a drag handle that pulls focus away from the "swipe back" message.
        .fullScreenCover(isPresented: $handoffTrigger.isPresented) {
            DictationHandoffView()
                .environmentObject(store)
        }
    }
}

// MARK: - Handoff trigger

/// A singleton that signals when a keyboard-initiated dictation handoff should
/// be presented. Observable so `RootView` can react without coupling to the URL
/// handling code. `ObservableObject` rather than `@Observable` to match the
/// rest of the app's Combine pattern.
@MainActor
final class DictationHandoffTrigger: ObservableObject {
    static let shared = DictationHandoffTrigger()
    @Published var isPresented = false

    func activate() {
        isPresented = true
    }
}

// MARK: - Handoff screen

/// A focused modal that appears when the app is opened by a keyboard handoff
/// request. It starts a dictation session automatically and tells the user to
/// swipe back.
///
/// **Does not stop the session when dismissed.** The whole point of the handoff
/// is to start a recording the keyboard borrows, and closing this sheet is
/// returning to the app — not ending dictation. The session self-terminates
/// after the duration the user chose.
private struct DictationHandoffView: View {
    @EnvironmentObject private var store: SharedStore
    @StateObject private var service = DictationService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var phase: HandoffPhase = .starting

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()

                VStack(spacing: Theme.Space.lg) {
                    Spacer()

                    phaseContent

                    Spacer()

                    if phase == .ready {
                        Text("Swipe back to the app you were writing in.")
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Text.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Theme.Space.lg)
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
            .navigationTitle("Starting Dictation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await autoStart() }
        // Do not stop the session on disappear. The user is switching back to
        // their app, which is exactly when dictation should be live.
    }

    private var phaseContent: some View {
        VStack(spacing: Theme.Space.md) {
            switch phase {
            case .starting:
                ProgressView()
                    .scaleEffect(1.5)
                Text("Starting dictation session…")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Text.primary)

            case .ready:
                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Semantic.record)
                Text("Session running")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Text.primary)
                Text("The keyboard can dictate now. Tap the mic key to start each recording.")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Text.secondary)
                    .multilineTextAlignment(.center)

            case .failed(let message):
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Text.tertiary)
                Text("Couldn't start dictation")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.Text.primary)
                Text(message)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Semantic.record)
                    .multilineTextAlignment(.center)
                HStack(spacing: Theme.Space.sm) {
                    SecondaryButton(title: "Close") { dismiss() }
                    PrimaryButton(title: "Retry", icon: "arrow.clockwise") {
                        phase = .starting
                        Task { await autoStart() }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.md)
    }

    private func autoStart() async {
        // Idempotent: if the session is already running (e.g. the sheet was
        // dismissed and re-shown without the session ending), skip the start.
        if service.isRunning {
            phase = .ready
            return
        }
        let ok = await service.start(minutes: store.dictationSessionMinutes)
        phase = ok ? .ready : .failed(service.lastError)
    }

    private enum HandoffPhase: Equatable {
        case starting
        case ready
        case failed(String)
    }
}
