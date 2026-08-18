import AIKeyboardCore
import SwiftUI

/// One screen in the flow, and the whole ordering in one place.
///
/// A list of cases rather than a `switch` on an `Int`, because the required path
/// and the optional half are two different lengths and the count now changes
/// while the user is standing in it. The old shape kept `switchStep = 4` and
/// `paletteStep = 1` as literals beside a `TabView` whose tags were written out
/// by hand; inserting or removing a screen is exactly the edit that makes two
/// spellings of one position disagree, and this flow has just had six screens
/// taken off it.
enum OnboardingStep: Hashable {
    case welcome
    /// Settings *and* the globe key. See `AddKeyboardStep` for why those are one
    /// step and not two.
    case addKeyboard
    case practice(OnboardingPracticeStage)
    case palette
    case languages
    case microphone

    /// Everything between a fresh install and a first useful keystroke. Three
    /// screens, and nothing may be added here without a reason that survives
    /// "this is where people leave".
    static let required: [OnboardingStep] = [.welcome, .addKeyboard, .practice(.writing)]

    /// Reached only by asking for them, from the end of the required path.
    static let extras: [OnboardingStep] = [
        .palette, .languages, .microphone, .practice(.everyday), .practice(.smartTools)
    ]

    /// The closed vocabulary `.claude/docs/analytics-policy.md` fixed for the
    /// funnel. Mapped here rather than at the call site so a screen and its
    /// event name cannot be paired differently in two places.
    var event: AnalyticsEvent.Step {
        switch self {
        case .welcome: return .welcome
        case .addKeyboard: return .addKeyboard
        case .palette: return .palette
        case .languages: return .languages
        case .microphone: return .microphone
        case .practice(let stage):
            switch stage {
            case .writing: return .practiceWriting
            case .everyday: return .practiceEveryday
            case .smartTools: return .practiceSmartTools
            }
        }
    }
}

/// **Three screens before the first keystroke, not nine.**
///
/// Every step in front of a user's first useful keystroke is a place they leave,
/// and this flow had six setup steps plus a three-stage practice tour standing
/// in front of a keyboard nobody had yet seen do anything. The required path is
/// now welcome → add the keyboard → type a sentence. Everything else is offered
/// at the *end* of that path instead of blocking it: one "Show me more" on the
/// last required step opens `OnboardingStep.extras`.
///
/// Nothing was deleted, and each of the five demoted screens was kept as an
/// optional step rather than dropped outright, for its own reason:
///
/// - **Palette.** The Keys tab holds the same `PalettePicker`, and `orange` is a
///   shipped default that is never wrong, so this gates nothing. It stays
///   offered because it is the one screen here that costs a tap and gives
///   something back immediately, and because `AIKeyboardApp`'s brand-`id`
///   comment depends on the picker living in exactly two places. Its old reason
///   for being *second* — "put at the end it would have recoloured three screens
///   instead of eight" — died with the six screens that used to follow it.
/// - **Languages.** The Languages tab covers the list, and the shipped default
///   is English and Hebrew, so no user of this keyboard is stranded by never
///   seeing it. It stays because it is the only one of the five that changes
///   what the keyboard *types*, and because it is where
///   `SetupState.languagesNeedFullAccess` is said at the moment the choice is
///   made rather than two screens later.
/// - **Microphone.** Home's dictation card holds the button, and the permission
///   is asked when a session starts rather than here, so there was never
///   anything to gate. What is said nowhere else is *why* the microphone lives
///   in the app and not in the keyboard — the one piece of architecture a user
///   walks head-first into — so the explanation is kept and offered.
/// - **Practice: everyday, and practice: smart tools.** The closest thing here
///   to duplicated content: the Playground runs the same nine
///   `PlaygroundTourStep` tasks with the same guidance, which the step's own
///   subtitle says out loud. They stay because the Playground is a sheet behind
///   a Home card that somebody who has just finished onboarding has no
///   particular reason to open, and a stage costs one tap from where they are
///   already standing.
///
/// **Full Access is never asked for on this path** (NIT-15). The dedicated step
/// that asked for it before the user had seen the keyboard do anything is gone,
/// and the ask lives on Home's setup card, named after what it buys. What could
/// not move is the *truth*, and it is said in both places a decision depends on
/// it: the Allow Full Access row on the add-keyboard step, with the Hebrew
/// consequence spelled out beside it, and `SetupState.languagesNeedFullAccess`
/// beside the language list. For a Hebrew user the permission is not optional in
/// any practical sense — Apple's on-device model has no Hebrew, so every Hebrew
/// Fix, Rewrite or Reply needs the network — and `SetupState.fullAccessDetail`'s
/// "Typing and on-device AI work without it" is true of English and misleading
/// in Hebrew, which is why that sentence cannot be the only one.
struct OnboardingFlow: View {
    @EnvironmentObject private var store: SharedStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var step = 0

    /// Whether the user asked for the optional half. One-way: nothing sets it
    /// back to false, so `step` can never point past the end of `steps`.
    @State private var showsExtras = false

    /// What `onboardingCompleted` reports. Counted as it happens rather than
    /// derived at the end, because a skipped step leaves no other trace.
    @State private var skippedSteps = 0

    /// The same measurement Home makes, for the same reason: the one required
    /// setup step asks the user to change something outside the app, and that
    /// change leaves evidence the app can read. Re-read on every return to the
    /// foreground, because that is when the user comes back from Settings.
    @State private var setup = SetupState()

    private var steps: [OnboardingStep] {
        showsExtras ? OnboardingStep.required + OnboardingStep.extras : OnboardingStep.required
    }

    /// Computed off the list rather than restated as a number, for the reason
    /// the old `setupStepCount + OnboardingPracticeStage.allCases.count` was:
    /// two spellings of one count are what an inserted step makes disagree. It
    /// now also *changes* while the user is standing in the flow — three until
    /// they ask for the optional half, eight after — so a stored copy would be
    /// wrong rather than merely fragile.
    private var stepCount: Int { steps.count }

    private var currentStep: OnboardingStep { steps[step] }

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(spacing: 0) {
                header

                TabView(selection: $step) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, item in
                        screen(for: item).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Theme.Motion.quick, value: step)
                // Same reason as `RootView`'s: `Theme.Brand` is a global and
                // the steps do not observe it. Here the id sits on the TabView
                // rather than on the flow, so `step` — which lives one level up
                // and is therefore not rebuilt — carries the user back to the
                // page they were standing on. Putting it on the flow instead
                // would send somebody who picked a colour back to the start.
                .id(store.brandPalette)

                footer
            }
        }
        .onAppear { setup = .current(store: store) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current(store: store) }
        }
    }

    @ViewBuilder
    private func screen(for item: OnboardingStep) -> some View {
        switch item {
        case .welcome: WelcomeStep()
        case .addKeyboard: AddKeyboardStep(setup: setup)
        case .palette: PaletteStep()
        case .languages: LanguagesStep(setup: setup)
        case .microphone: MicrophoneStep(setup: setup)
        case .practice(let stage): TryItStep(setup: setup, stage: stage)
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

    /// Skip exists so a step that cannot be proven done can still be passed.
    /// Withheld on the last step, where the primary action is "Start typing" and
    /// there is nothing left to step over. Welcome shows it, and that Skip
    /// leaves the tour rather than advancing.
    private var showsSkip: Bool { step < stepCount - 1 }

    /// The one door into the optional half, and it is only ever offered from the
    /// end of the required path. It takes the slot Skip vacates on the last
    /// step, so the footer never carries three buttons.
    private var showsMore: Bool { !showsExtras && step == stepCount - 1 }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider.themed

            HStack(spacing: Theme.Space.sm) {
                if showsSkip {
                    SecondaryButton(title: "Skip") {
                        skipAction()
                    }
                } else if showsMore {
                    SecondaryButton(title: "Show me more") {
                        moreAction()
                    }
                }
                PrimaryButton(title: primaryTitle) {
                    primaryAction()
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.md)
            .padding(.bottom, Theme.Space.xs)
        }
    }

    /// On the add-keyboard step the primary action *is* the confirmation that
    /// step exists to collect; everywhere else it just advances.
    private var primaryTitle: String {
        if currentStep == .addKeyboard && !setup.switchAcknowledged {
            return "I've switched to it"
        }
        return step == stepCount - 1 ? "Start typing" : "Continue"
    }

    // MARK: Advancing

    private func skipAction() {
        skippedSteps += 1
        record(via: .skip)
        // Welcome's Skip is the one that leaves the tour rather than stepping
        // over a screen: there is nothing behind it the user has asked for.
        if currentStep == .welcome {
            complete()
        } else {
            withAnimation { step += 1 }
        }
    }

    private func primaryAction() {
        var via = AnalyticsEvent.Advance.continue
        if currentStep == .addKeyboard && !setup.switchAcknowledged {
            Feedback.actionPress()
            store.hasAcknowledgedKeyboardSwitch = true
            setup = .current(store: store)
            via = .switchConfirmed
        }
        record(via: via)
        if step == stepCount - 1 {
            complete()
        } else {
            withAnimation { step += 1 }
        }
    }

    /// Opting into the optional half is a Continue, not a Skip: the user
    /// finished the step and asked for more, which is the opposite of the thing
    /// `skippedStepCount` counts.
    private func moreAction() {
        record(via: .continue)
        showsExtras = true
        withAnimation { step += 1 }
    }

    /// `step_index` is the position in the path the user actually walked, which
    /// is no longer a fixed 0–9: the required path is three long and the
    /// optional half extends it to eight. `step_name` is the stable key a query
    /// should join on; the index says how far in they were when they left.
    private func record(via: AnalyticsEvent.Advance) {
        Analytics.record(
            .onboardingStepAdvanced(index: step, step: currentStep.event, via: via))
    }

    /// The only place `hasCompletedOnboarding` is set, and the only caller of
    /// `onboardingCompleted`. Both exits — Skip on welcome, and the primary
    /// action on the last step — come through here, so the event and the flag
    /// cannot get out of step with each other.
    private func complete() {
        Analytics.record(.onboardingCompleted(skippedStepCount: skippedSteps))
        store.hasCompletedOnboarding = true
    }
}
