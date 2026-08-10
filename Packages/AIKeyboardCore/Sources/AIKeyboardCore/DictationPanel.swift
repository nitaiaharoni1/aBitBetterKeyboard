import SwiftUI

/// What the user sees while speaking.
///
/// **This panel used to play a scripted transcript and say so in eight-point
/// type.** It now shows a real recording made in the containing app: the
/// keyboard cannot open the microphone — an OS boundary, not a permission, see
/// `DictationChannel` — so the microphone lives there and this reads the result
/// across the App Group. The one thing that boundary costs the user is that the
/// keyboard cannot start a session, and the state below that matters most is
/// therefore `.noSession`, which has to explain rather than fail.
public struct DictationPanel: View {

    @ObservedObject var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                header

                switch controller.dictationAvailability {
                case .needsFullAccess, .noSession:
                    explanation
                default:
                    waveform
                    transcript
                    controls
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.xs) {
            Circle()
                .fill(Theme.Semantic.record)
                .frame(width: 8, height: 8)
                .opacity(controller.isDictating ? 1 : 0.3)
                .scaleEffect(controller.isDictating ? 1 + 0.25 * sin(controller.waveformPhase * 2) : 1)
                .animation(.easeInOut(duration: 0.2), value: controller.waveformPhase)

            Text(headline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Keys.label)

            Spacer(minLength: Theme.Space.xs)

            // The engine follows the speaker between languages instead of asking
            // them to pick one before they start.
            if !controller.dictationTranscript.isEmpty {
                detectedLanguageTag
            } else if let remaining = controller.dictationRemainingSeconds, remaining < 60 {
                // Only in the last minute. A countdown running for the whole
                // session is a clock the user is invited to watch; a countdown
                // that appears is news.
                Text("\(Int(remaining))s left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
            }

            Button {
                controller.stopDictation(insert: false)
                controller.dismissOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.Glyph.medium(13))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.Keys.function.opacity(0.6)))
                    .contentShape(Circle())
            }
            .pressable()
            .accessibilityLabel("Cancel dictation")
        }
        .padding(.horizontal, Theme.Space.sm)
        .frame(height: 38)
    }

    private var headline: String {
        switch controller.dictationAvailability {
        case .needsFullAccess: return "Dictation needs Full Access"
        case .noSession: return "No dictation session"
        case .ready: return controller.dictationFailure.isEmpty ? "Ready" : "Nothing inserted"
        case .listening: return "Listening"
        case .transcribing: return "Transcribing"
        }
    }

    /// The languages actually in the transcript, in the order they dominate it.
    ///
    /// **Both halves used to be written for a two-language keyboard.** The badge
    /// named the runner-up as `dominant.next()`, which is the *next row of the
    /// catalogue* rather than the other language on screen, so a Hebrew
    /// transcript carrying English loanwords was badged `עב ⟷ ع`. And "is this
    /// mixed" was a hand-rolled Hebrew-versus-Latin scan, which answers no for a
    /// Russian sentence carrying English words. Counting scripts answers both
    /// questions at once, for every language in the catalogue.
    private var detectedLanguageTag: some View {
        let detected = SuggestionEngine.languages(in: controller.dictationTranscript)
        let primary = detected.first ?? .english
        let secondary = detected.dropFirst().first

        return HStack(spacing: 3) {
            Text(primary.shortName)
                .font(.system(size: 10, weight: .semibold))
            if let secondary {
                Image(systemName: "arrow.left.arrow.right")
                    .font(Theme.Glyph.medium(8))
                Text(secondary.shortName)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.Brand.solid)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.Brand.solid.opacity(0.14)))
        .accessibilityLabel(
            secondary.map { "\(primary.displayName) and \($0.displayName)" } ?? primary.displayName)
    }

    // MARK: Nothing to record into

    /// **The most important state in this panel, and the one a spinner would
    /// lie about.** Nothing in a keyboard extension can start a recording
    /// session or launch its own app, so this is a dead end the user has to be
    /// walked out of by hand. It names the app, the screen and the button.
    private var explanation: some View {
        VStack(spacing: Theme.Space.xs) {
            Spacer(minLength: 0)

            Image(systemName: "mic.slash")
                .font(Theme.Glyph.medium(22))
                .foregroundStyle(Theme.Keys.secondaryLabel)

            Text(explanationText)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.md)
                .accessibilityIdentifier("dictation-explanation")

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Theme.Space.sm)
    }

    private var explanationText: String {
        switch controller.dictationAvailability {
        case .needsFullAccess:
            return
                "Dictation records in the AI Keyboard app and sends the words here, which needs Full Access. Turn it on in Settings › General › Keyboard › Keyboards."
        case .noSession(let reason):
            let why = reason == .notEnded || reason == .stoppedByUser ? "" : reason.explanation + " "
            return
                "\(why)Open AI Keyboard and tap Start dictation, then come back. iOS doesn't let a keyboard open the microphone, so the app holds it and the keyboard borrows it."
        default:
            return ""
        }
    }

    // MARK: Waveform

    private var waveform: some View {
        WaveformView(
            phase: controller.waveformPhase,
            barCount: 30,
            color: Theme.Semantic.record.opacity(0.85),
            isActive: controller.isDictating
        )
        .frame(height: 34)
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.xxs)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollView {
            Text(transcriptText)
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(
                    controller.dictationTranscript.isEmpty
                        ? Theme.Keys.secondaryLabel : Theme.Keys.label
                )
                .multilineTextAlignment(controller.dictationIsRightToLeft ? .trailing : .leading)
                .frame(
                    maxWidth: .infinity, alignment: controller.dictationIsRightToLeft ? .trailing : .leading
                )
                .padding(.horizontal, Theme.Space.sm)
                .padding(.vertical, Theme.Space.xs)
        }
        .frame(maxHeight: .infinity)
        .accessibilityLabel("Transcript")
        .accessibilityValue(controller.dictationTranscript)
    }

    /// **A failure is shown here rather than swallowed**, and it has to be: the
    /// user has already spoken. "I didn't catch that" costs them one more tap;
    /// an empty panel that clears itself costs them the whole sentence with no
    /// idea why.
    private var transcriptText: String {
        if !controller.dictationFailure.isEmpty { return controller.dictationFailure }
        if !controller.dictationTranscript.isEmpty { return controller.dictationTranscript }
        switch controller.dictationAvailability {
        case .transcribing: return "Working out what you said…"
        case .listening: return "Speak now…"
        default: return "Tap Insert when you've finished."
        }
    }

    // MARK: Controls

    /// **A refusal has to offer the next tap, or it is a dead end.** `SpeechGate`
    /// will sometimes refuse a real utterance — it is tuned to, because the other
    /// direction types a sentence nobody said — and without this the user's only
    /// route back is to close the panel and find the microphone key again. The
    /// same button becomes the way out, because it is the one their thumb is
    /// already on.
    private var canRetry: Bool {
        !controller.isDictating && !controller.dictationFailure.isEmpty
            && controller.dictationAvailability == .ready
    }

    private var controls: some View {
        VStack(spacing: 4) {
            HStack(spacing: Theme.Space.xs) {
                Button {
                    controller.stopDictation(insert: false)
                    controller.dismissOverlay()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Theme.Keys.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Metrics.minTouchTarget)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                .fill(Theme.Keys.card)
                        )
                        .contentShape(Rectangle())
                }
                .pressable()

                Button {
                    if canRetry {
                        controller.startDictation()
                    } else {
                        controller.stopDictation(insert: true)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: canRetry ? "arrow.clockwise" : "text.insert")
                            .font(Theme.Glyph.medium(13))
                        Text(canRetry ? "Try again" : "Insert")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(Theme.Text.onBrand)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Metrics.minTouchTarget)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(Theme.Brand.gradient)
                    )
                    .contentShape(Rectangle())
                }
                .pressable()
                // **Enabled while recording, disabled while the words are in
                // flight.** The old panel disabled this until a transcript
                // existed, which under a real recorder would mean the button
                // that *ends* the recording only becomes available after the
                // recording has ended.
                .disabled(!controller.isDictating && !canRetry)
                .opacity(controller.isDictating || canRetry ? 1 : 0.5)
                .accessibilityIdentifier("dictation-insert")
            }

            Text(footnote)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Keys.secondaryLabel.opacity(0.8))
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.bottom, Theme.Space.xs)
    }

    /// Says where the microphone is, because the orange dot in the status bar
    /// belongs to a different app than the one the user is looking at and that
    /// is worth explaining once, in place.
    private var footnote: String {
        controller.dictationAvailability == .transcribing
            ? "Transcribed in the cloud — Apple's on-device speech has no Hebrew"
            : "Recording in the AI Keyboard app"
    }
}
