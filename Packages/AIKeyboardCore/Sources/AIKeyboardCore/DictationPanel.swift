import SwiftUI

/// What the user sees while speaking.
///
/// A keyboard extension has no path to the microphone at all — confirmed against
/// Apple's current documentation, not assumed; see `MockDictation`'s doc comment
/// for the citation and for why there is also no way to hand the recording off
/// to the containing app from in here. `MockDictation` plays the onboarding
/// script and the in-app playground; nothing behind this panel ever will record.
public struct DictationPanel: View {

    @ObservedObject var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                header

                waveform

                transcript

                controls
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

            Text(controller.isDictating ? "Listening" : "Paused")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Keys.label)

            Spacer(minLength: Theme.Space.xs)

            // The engine follows the speaker between languages instead of asking
            // them to pick one before they start.
            if !controller.dictationTranscript.isEmpty {
                detectedLanguageTag
            }

            Button {
                controller.stopDictation(insert: false)
                controller.dismissOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
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

    /// The languages actually in the transcript, in the order they dominate it.
    ///
    /// **Both halves used to be written for a two-language keyboard.** The badge
    /// named the runner-up as `dominant.next()`, which is the *next row of the
    /// catalogue* rather than the other language on screen, so the shipped first
    /// dictation script — Hebrew with English loanwords — was badged `עב ⟷ ع`.
    /// And "is this mixed" was a hand-rolled Hebrew-versus-Latin scan, which
    /// answers no for a Russian sentence carrying English words. Counting scripts
    /// answers both questions at once, for every language in the catalogue.
    private var detectedLanguageTag: some View {
        let detected = SuggestionEngine.languages(in: controller.dictationTranscript)
        let primary = detected.first ?? .english
        let secondary = detected.dropFirst().first

        return HStack(spacing: 3) {
            Text(primary.shortName)
                .font(.system(size: 10, weight: .semibold))
            if let secondary {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 8, weight: .bold))
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
            Text(controller.dictationTranscript.isEmpty ? "Start speaking…" : controller.dictationTranscript)
                .font(.system(size: 17))
                .foregroundStyle(
                    controller.dictationTranscript.isEmpty ? Theme.Keys.secondaryLabel : Theme.Keys.label
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

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 4) {
            HStack(spacing: Theme.Space.xs) {
                Button {
                    controller.stopDictation(insert: false)
                    controller.dismissOverlay()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
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
                    controller.stopDictation(insert: true)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.insert")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Insert")
                            .font(.system(size: 15, weight: .semibold))
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
                .disabled(controller.dictationTranscript.isEmpty)
                .opacity(controller.dictationTranscript.isEmpty ? 0.5 : 1)
            }

            // Said, not implied. This line used to read "Recording runs in the AI
            // Keyboard app", which is the architecture dictation *would* need and
            // is not something this build does: nothing records anywhere, in
            // either process. See `MockDictation`.
            Text("A scripted demo — iOS gives a keyboard no microphone")
                .font(.system(size: 10))
                .foregroundStyle(Theme.Keys.secondaryLabel.opacity(0.8))
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.bottom, Theme.Space.xs)
    }
}
