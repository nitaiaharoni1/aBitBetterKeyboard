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
                    if service.isRunning {
                        liveCard
                    } else {
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

}
