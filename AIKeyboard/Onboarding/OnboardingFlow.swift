import AIKeyboardCore
import SwiftUI

struct OnboardingFlow: View {
    @EnvironmentObject private var store: SharedStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var step = 0

    /// The same measurement Home makes, for the same reason: three of these six
    /// steps ask the user to change something outside the app, and two of the
    /// three now leave evidence the app can read. Re-read on every return to the
    /// foreground, because that is when the user comes back from Settings.
    @State private var setup = SetupState()

    private let stepCount = 6

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
                    MicrophoneStep(setup: setup).tag(4)
                    TryItStep(setup: setup).tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.28), value: step)

                footer
            }
        }
        .onAppear { setup = .current() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current() }
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(
                        index <= step
                            ? AnyShapeStyle(Theme.Brand.gradient) : AnyShapeStyle(Theme.Surface.separator)
                    )
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.top, Theme.Space.sm)
        .animation(.easeInOut(duration: 0.28), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(stepCount)")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            PrimaryButton(title: step == stepCount - 1 ? "Start typing" : "Continue") {
                if step == stepCount - 1 {
                    store.hasCompletedOnboarding = true
                } else {
                    withAnimation { step += 1 }
                }
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
        .padding(.bottom, Theme.Space.xs)
    }
}
