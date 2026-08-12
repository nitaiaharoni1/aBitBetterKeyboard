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
/// **The keyboard can now hand off here directly.** When the user taps the mic
/// key with no session running, the banner shows an "Open AI Keyboard" button.
/// `KeyboardViewController` wires `onOpenContainingApp` to try
/// `extensionContext?.open(_:)` first, with a responder-chain fallback.
/// `DictationHandoffView` is what appears when that deep link lands.
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
            AmbientBackground()

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    sessionCard
                    if !service.isRunning {
                        DictationHowItWorksSection(sessionMinutes: store.dictationSessionMinutes)
                    }
                    DictationLengthSection(
                        sessionMinutes: $store.dictationSessionMinutes,
                        isRunning: service.isRunning
                    )
                    if !setup.cloudConfigured { DictationCloudSection() }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
                .animation(Theme.Motion.quick, value: service.isRunning)
            }
        }
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { setup = .current(store: store) }
        .onReceive(tick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current(store: store) }
        }
    }

    // MARK: The session

    /// One card is the whole recorder: the state and its status on top, the
    /// live waveform and transcript in the middle while it runs, and the one
    /// action the state allows at the bottom.
    private var sessionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.xs) {
                    IconBadge(
                        systemName: service.isRunning ? "mic.fill" : "mic.slash",
                        tint: service.isRunning ? Theme.Semantic.record : Theme.Text.tertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.isRunning ? "Session running" : "Session off")
                            .font(Theme.Fonts.headline)
                            .foregroundStyle(Theme.Text.primary)
                        Text(statusDetail)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if service.isRunning {
                        StatusCapsule(text: "LIVE", colour: Theme.Semantic.record)
                    }
                }

                if service.isRunning {
                    Divider.themed

                    WaveformView(
                        phase: service.level * 24, barCount: 30,
                        color: Theme.Semantic.record.opacity(0.85),
                        isActive: service.phase == .listening
                    )
                    .frame(height: 30)

                    Text(phaseLine)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)

                    if !service.lastTranscript.isEmpty {
                        Text(service.lastTranscript)
                            .font(Theme.Fonts.body)
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
                    .font(Theme.Fonts.micro)
                    .foregroundStyle(Theme.Text.tertiary)

                    Divider.themed

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
                            setup = .current(store: store)
                            starting = false
                        }
                    }
                    .accessibilityIdentifier("dictation-start")
                }

                if !service.lastError.isEmpty {
                    Text(service.lastError)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Semantic.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusDetail: String {
        if service.isRunning {
            guard let expiresAt = service.expiresAt else { return "The keyboard can dictate now" }
            let left = max(0, Int(expiresAt.timeIntervalSince(now)))
            return "The keyboard can dictate now: \(left / 60)m \(left % 60)s left"
        }
        switch service.endReason {
        case .notEnded: return "Start one here, then switch to the app you're writing in"
        case .stoppedByUser: return "Start one here, then switch to the app you're writing in"
        default: return service.endReason.explanation
        }
    }

    private var phaseLine: String {
        switch service.phase {
        case .idle: return "Waiting for the keyboard's microphone button"
        case .listening: return "Listening"
        case .paused: return "Paused from the keyboard"
        case .transcribing: return "Transcribing"
        }
    }

}
