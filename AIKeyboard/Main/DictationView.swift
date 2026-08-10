import AIKeyboardCore
import SwiftUI

/// Where a dictation session is started, and the only place it can be.
///
/// **The screen exists because of an OS boundary, and it says so rather than
/// hiding it.** A keyboard extension cannot open the microphone — that is
/// Apple's own documentation and the 561145187 every developer who tries it
/// hits — and an app cannot *begin* recording from the background. So the
/// microphone is opened here, in the foreground, and the keyboard borrows it.
/// Every honest version of this feature on iOS looks like this; Wispr Flow's
/// does too, down to the swipe back.
///
/// The one thing this screen must never do is imply the keyboard will start a
/// session on its own. It cannot: nothing in an app extension can launch its
/// containing app, `UIApplication` is unavailable there, and the responder-chain
/// workaround is explicitly disallowed. So the instructions say "come back here"
/// in as many words.
struct DictationView: View {

    @EnvironmentObject private var store: SharedStore
    @StateObject private var service = DictationService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var setup = SetupState()
    @State private var starting = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AmbientBackground(intensity: 0.5)

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    sessionCard
                    if service.isRunning { liveCard } else { howCard }
                    lengthCard
                    if !setup.cloudConfigured { cloudCard }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setup = .current() }
        .onReceive(tick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current() }
        }
    }

    // MARK: The session

    private var sessionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.xs) {
                    IconBadge(
                        systemName: service.isRunning ? "mic.fill" : "mic.slash",
                        tint: service.isRunning ? Theme.Semantic.record : Theme.Text.tertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.isRunning ? "Session running" : "Session off")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Text.primary)
                        Text(statusDetail)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                if service.isRunning {
                    SecondaryButton(title: "Stop dictation") { service.stop() }
                        .accessibilityIdentifier("dictation-stop")
                } else {
                    PrimaryButton(
                        title: starting ? "Starting…" : "Start dictation",
                        icon: "mic.fill",
                        isEnabled: !starting
                    ) {
                        starting = true
                        Task {
                            await service.start(minutes: store.dictationSessionMinutes)
                            setup = .current()
                            starting = false
                        }
                    }
                    .accessibilityIdentifier("dictation-start")
                }

                if !service.lastError.isEmpty {
                    Text(service.lastError)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Semantic.record)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusDetail: String {
        if service.isRunning {
            guard let expiresAt = service.expiresAt else { return "The keyboard can dictate now" }
            let left = max(0, Int(expiresAt.timeIntervalSince(now)))
            return "The keyboard can dictate now — \(left / 60)m \(left % 60)s left"
        }
        switch service.endReason {
        case .notEnded: return "Start one here, then switch to the app you're writing in"
        case .stoppedByUser: return "Start one here, then switch to the app you're writing in"
        default: return service.endReason.explanation
        }
    }

    // MARK: While it runs

    private var liveCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeader(title: "Live")

                WaveformView(
                    phase: service.level * 24, barCount: 30,
                    color: Theme.Semantic.record.opacity(0.85),
                    isActive: service.phase == .listening
                )
                .frame(height: 30)

                Text(phaseLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)

                if !service.lastTranscript.isEmpty {
                    Text(service.lastTranscript)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dictation-last-transcript")
                }

                // The refusal count is not a debug number. It is how often the
                // thing that would otherwise have typed an invented sentence was
                // stopped, and it belongs where the person who owns the phone can
                // see it.
                Text(
                    "\(service.utterances) recorded"
                        + (service.refusedNoSpeech > 0
                            ? " · \(service.refusedNoSpeech) had nothing in them" : "")
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.tertiary)
            }
        }
    }

    private var phaseLine: String {
        switch service.phase {
        case .idle: return "Waiting for the keyboard's microphone button"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        }
    }

    // MARK: How it works

    private var howCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeader(title: "How dictation works")

                step(
                    1, "Start the session here",
                    "iOS won't let a keyboard open the microphone, and won't let an app start recording from the background. So it starts here, with AI Keyboard in front of you."
                )
                step(
                    2, "Switch to the app you're writing in",
                    "The session keeps running while AI Keyboard is in the background. iOS shows the orange microphone dot the whole time it does."
                )
                step(
                    3, "Tap the microphone on the keyboard",
                    "Speak, then tap Insert. The recording is transcribed and the words go straight into the field."
                )
                step(
                    4, "It closes itself",
                    "After \(store.dictationSessionMinutes) minutes, or when you stop it here, or if a call takes the microphone."
                )

                Divider().overlay(Theme.Surface.separator)

                Text(
                    "Nothing is recorded between taps, and no recording is ever written to disk. What is kept is the text, until the session ends."
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Text.onBrand)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.Brand.gradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Length

    private var lengthCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader(title: "Session length")

                Picker("Session length", selection: $store.dictationSessionMinutes) {
                    ForEach(SharedStore.dictationSessionChoices, id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(service.isRunning)

                Text(
                    service.isRunning
                        ? "Stop the session to change this."
                        : "How long the microphone stays available before it closes itself. There is deliberately no \"never\"."
                )
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The cloud

    /// **Dictation without a backend is a microphone that records into nothing**,
    /// and the failure would otherwise land after the user has already spoken.
    /// Said here, before they start, in the same words every other cloud
    /// dead-end in this app uses.
    private var cloudCard: some View {
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
