import AIKeyboardCore
import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var store: SharedStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var step = 0

    /// The same measurement Home makes, for the same reason: three of these
    /// steps ask the user to change something outside the app, and two of the
    /// three now leave evidence the app can read. Re-read on every return to the
    /// foreground, because that is when the user comes back from Settings.
    @State private var setup = SetupState()

    private let setupStepCount = 6
    private let stepCount = 6 + OnboardingPracticeStage.allCases.count

    /// The step whose footer's primary action is the globe-key confirmation.
    /// Named once here so the footer and the step itself cannot drift apart.
    private let switchStep = 4

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                header

                TabView(selection: $step) {
                    WelcomeStep().tag(0)
                    LanguagesStep(setup: setup).tag(1)
                    AddKeyboardStep(setup: setup).tag(2)
                    FullAccessStep(setup: setup).tag(3)
                    SwitchStep(setup: setup).tag(4)
                    MicrophoneStep(setup: setup).tag(5)
                    ForEach(OnboardingPracticeStage.allCases, id: \.rawValue) { practice in
                        TryItStep(setup: setup, stage: practice)
                            .tag(setupStepCount + practice.rawValue)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Theme.Motion.quick, value: step)

                footer
            }
        }
        .onAppear { setup = .current(store: store) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current(store: store) }
        }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: Theme.Space.sm) {
            HStack {
                Button {
                    withAnimation { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Text.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.Surface.raised))
                        .overlay(Circle().strokeBorder(Theme.Surface.separator, lineWidth: 1))
                        .contentShape(Circle())
                }
                .pressable()
                .opacity(step == 0 ? 0 : 1)
                .disabled(step == 0)
                .accessibilityHidden(step == 0)
                .accessibilityLabel("Back")

                Spacer()

                Text("Step \(step + 1) of \(stepCount)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.tertiary)

                Spacer()

                // Keeps the counter centred whether or not the back button is
                // visible.
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, Theme.Space.lg)

            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.Brand.solid : Theme.Surface.separator)
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .animation(Theme.Motion.quick, value: step)
            // The visible text above already announces the step. These capsules
            // are the same information drawn graphically, not a second control.
            .accessibilityHidden(true)
        }
        .padding(.top, Theme.Space.sm)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider.themed

            VStack(spacing: 0) {
                PrimaryButton(title: primaryTitle) {
                    primaryAction()
                }

                // Skipping stays available even now that two of these steps can be
                // verified, because the third cannot and because a user who has done
                // the work in Settings but not yet switched to the keyboard has
                // nothing the app can see. A step that cannot be proven done must not
                // become a step that cannot be passed.
                if step > 0 && step < stepCount - 1 {
                    SecondaryButton(title: "Skip for now") {
                        withAnimation { step += 1 }
                    }
                } else {
                    Color.clear.frame(height: 48)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xs)
        }
    }

    /// On the switch step the primary action *is* the confirmation the step
    /// exists to collect; everywhere else it just advances.
    private var primaryTitle: String {
        if step == switchStep && !setup.switchAcknowledged {
            return "I've switched to it"
        }
        return step == stepCount - 1 ? "Start typing" : "Continue"
    }

    private func primaryAction() {
        if step == switchStep && !setup.switchAcknowledged {
            Feedback.actionPress()
            store.hasAcknowledgedKeyboardSwitch = true
            setup = .current(store: store)
        }
        if step == stepCount - 1 {
            store.hasCompletedOnboarding = true
        } else {
            withAnimation { step += 1 }
        }
    }
}
