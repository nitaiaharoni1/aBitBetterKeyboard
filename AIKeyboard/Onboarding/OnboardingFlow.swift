import SwiftUI
import AIKeyboardCore

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

// MARK: - Step scaffold

private struct StepLayout<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        // Centred when the step is short, scrollable when it is not, so no step
        // ends up with a band of dead space between the copy and the button.
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text(title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: minimumContentHeight, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// Fills the scroll view's own height so `alignment: .center` has something
    /// to centre against.
    private var minimumContentHeight: CGFloat? {
        verticalSizeClass == .compact ? nil : 520
    }
}

// MARK: - 1. Welcome

private struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        StepLayout(
            title: "One keyboard for how you actually write",
            subtitle:
                "Hebrew and English in the same sentence, fixed and rewritten without leaving the app you are in."
        ) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                ValuePoint(
                    icon: "character.cursor.ibeam",
                    title: "Types in both languages at once",
                    detail: "Predictions understand ‏אני אשלח לך את ה-document‏ without switching layouts."
                )
                ValuePoint(
                    icon: "sparkles",
                    title: "Fix and rewrite in one tap",
                    detail: "Small edits on the text in front of you, not a chatbot to talk to."
                )
                ValuePoint(
                    icon: "eye",
                    title: "Replies that read the room",
                    detail: "Turn on screen context and the keyboard answers the message you're looking at."
                )
                // This was a dictation promise — "Dictation that keeps up when you
                // switch language mid-sentence" — on the first screen a new user
                // ever sees, for a feature that streams a fixed script and records
                // nothing (see `MockDictation`). Replaced rather than softened,
                // with something the build actually does.
                ValuePoint(
                    icon: "globe",
                    title: "Fourteen keyboards, one swipe apart",
                    detail: "Slide along the space bar to change language, and it names the one you land on."
                )
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45).delay(0.1)) { appeared = true }
            }
        }
    }
}

private struct ValuePoint: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.Brand.gradient)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Brand.softGradient)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 2. Languages

private struct LanguagesStep: View {
    @EnvironmentObject private var store: SharedStore
    let setup: SetupState

    var body: some View {
        StepLayout(
            title: "Which languages do you type in?",
            subtitle: "Keeping the list short is what makes prediction fast. You can change this later."
        ) {
            // A card saying "Arabic, Russian and French are on the way." used to
            // sit here, under fourteen live switches three of which are Arabic,
            // Russian and French. Deleted rather than rewritten to name a
            // different set: there is no fifteenth language queued, so any
            // sentence in this slot would be another promise nothing is keeping.
            VStack(spacing: Theme.Space.xs) {
                ForEach(KeyboardLanguage.allCases) { language in
                    LanguageToggleRow(language: language)
                }
            }

            // Said here as well as on step 4, because this is the screen where the
            // choice is made and the keyboard cannot honour it yet. Withheld once
            // Full Access is confirmed, when it is no longer true of this phone.
            if setup.fullAccess != .confirmed {
                Text(SetupState.languagesNeedFullAccess)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LanguageToggleRow: View {
    @EnvironmentObject private var store: SharedStore
    let language: KeyboardLanguage

    private var isOn: Bool { store.enabledLanguages.contains(language) }

    var body: some View {
        Button {
            toggle()
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Text(language.flag)
                    .font(.system(size: 26))

                VStack(alignment: .leading, spacing: 1) {
                    Text(language.nativeName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)
                    Text(language.displayName)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.secondary)
                }

                Spacer()

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isOn ? Theme.Brand.solid : Theme.Text.tertiary)
            }
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        isOn ? Theme.Brand.solid.opacity(0.5) : Theme.Surface.separator, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityLabel(language.displayName)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    /// The last language cannot be turned off; a keyboard with no layout has
    /// nothing to draw.
    private func toggle() {
        Feedback.modifierPress()
        withAnimation(Theme.Motion.quick) {
            if isOn {
                guard store.enabledLanguages.count > 1 else { return }
                store.enabledLanguages.removeAll { $0 == language }
            } else {
                store.enabledLanguages.append(language)
            }
        }
    }
}

// MARK: - 3. Add the keyboard

private struct AddKeyboardStep: View {
    let setup: SetupState

    var body: some View {
        StepLayout(
            title: setup.keyboardAdded == .confirmed ? "The keyboard is added" : "Add the keyboard",
            subtitle: setup.keyboardAdded == .confirmed
                ? "We can see it, so there is nothing to do here."
                : "iOS keeps custom keyboards behind Settings. It takes about twenty seconds."
        ) {
            Card {
                StatusRow(
                    title: "Keyboard added",
                    detail: setup.keyboardAddedDetail,
                    check: setup.keyboardAdded
                )
            }

            if setup.keyboardAdded != .confirmed {
                VStack(spacing: Theme.Space.xs) {
                    InstructionRow(number: 1, text: "Open Settings, then General")
                    InstructionRow(number: 2, text: "Tap Keyboard, then Keyboards")
                    InstructionRow(number: 3, text: "Tap Add New Keyboard…")
                    InstructionRow(number: 4, text: "Choose AI Keyboard")
                }

                SettingsLinkButton()
            }
        }
    }
}

/// Opens Settings. `UIApplication.openSettingsURLString` is the only Settings
/// destination iOS offers — there is no constant for General › Keyboard — so the
/// numbered steps beside this button carry the path from the top of Settings and
/// the button promises nothing more than getting the user there.
private struct SettingsLinkButton: View {
    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "arrow.up.forward.app")
                Text("Open Settings")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.Brand.solid)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Brand.solid.opacity(0.12))
            )
            .contentShape(Rectangle())
        }
        .pressable()
    }
}

private struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.Text.onBrand)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.Brand.gradient))

            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Text.primary)

            Spacer()
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.horizontal, Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.raised)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 4. Full Access

private struct FullAccessStep: View {
    let setup: SetupState

    var body: some View {
        StepLayout(
            title: setup.fullAccess == .confirmed ? "Full Access is on" : "Allow Full Access",
            subtitle: "It sounds alarming, so here is exactly what it does and does not do."
        ) {
            Card {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    StatusRow(
                        title: "Full Access",
                        detail: setup.fullAccessDetail,
                        check: setup.fullAccess
                    )
                    if let explanation = setup.unresolvedExplanation, setup.fullAccess != .confirmed {
                        Text(explanation)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(spacing: Theme.Space.xs) {
                // Reads the measurement rather than asserting the happy case. The
                // fixed sentence here promised "cloud rewrites for languages the
                // on-device model cannot handle" to a user with no cloud model —
                // which is every stock install, and is exactly the language this
                // keyboard is for. See `SetupState.fullAccessTurnsOn`.
                AccessRow(
                    icon: "checkmark.shield",
                    tint: Theme.Semantic.success,
                    title: "What it turns on",
                    detail: setup.fullAccessTurnsOn
                )
                AccessRow(
                    icon: "xmark.shield",
                    tint: Theme.Semantic.warning,
                    title: "What we never send",
                    detail:
                        "Passwords, payment fields and anything you type in a secure field. Those never reach us, by design."
                )
                // Also read out of `SetupState` rather than written here, and for a
                // sharper reason than the row above: the sentence this replaced
                // said Full Access was "only for the cloud fallback", which is
                // what silently loses a French-only user the language list they
                // chose on step 2. See `SetupState.worksWithoutFullAccess`.
                AccessRow(
                    icon: "iphone",
                    tint: Theme.Brand.solid,
                    title: "Works without it",
                    detail: SetupState.worksWithoutFullAccess
                )
            }
        }
    }
}

private struct AccessRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                IconBadge(systemName: icon, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 5. Microphone

private struct MicrophoneStep: View {
    let setup: SetupState

    @State private var pulse = false

    /// **Nothing on this step turns anything on, so it no longer says it does.**
    /// It was titled "Turn on dictation" and described recording happening in the
    /// app — an architecture that is achievable and is not built: no code in either
    /// process opens a microphone, and the mic key streams a fixed script. There is
    /// no button here because there is nothing to grant, and the words now say
    /// that instead of implying a missing one. `MockDictation` carries the evidence
    /// for what is and is not possible; the blocker is a supported hand-off from
    /// the keyboard to the app, not the microphone.
    var body: some View {
        StepLayout(
            title: "About dictation",
            subtitle:
                "The mic key plays a scripted demo today, and nothing here switches that. iOS does not let a keyboard open the microphone, so recording would have to happen in this app and be handed over — that half is not built."
        ) {
            Card {
                StatusRow(
                    title: "Microphone",
                    detail: setup.microphoneDetail,
                    check: setup.microphoneAccess
                )
            }

            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Theme.Brand.softGradient)
                        .frame(width: 132, height: 132)
                        .scaleEffect(pulse ? 1.08 : 0.94)

                    Circle()
                        .fill(Theme.Brand.gradient)
                        .frame(width: 88, height: 88)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Theme.Text.onBrand)
                }
                Spacer()
            }
            .padding(.vertical, Theme.Space.sm)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { pulse = true }
            }
            .accessibilityHidden(true)

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Why it is split in two")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)
                    Text(
                        "Apple isolates keyboard extensions from the microphone. Every voice keyboard on iOS works this way, and it is the part of the product most likely to change with an iOS update."
                    )
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - 6. Try it

private struct TryItStep: View {
    let setup: SetupState

    /// "The same keyboard you just installed" is true only for the user who did
    /// the two Settings steps; "Skip for now" is on both of them, so the other
    /// path reaches this screen having installed nothing. The app can tell which,
    /// so it says which — and the skipped version has to make clear that this
    /// preview is not the keyboard appearing in other apps yet, or the next
    /// disappointment is discovering it is not there.
    private var subtitle: String {
        setup.keyboardAdded == .confirmed
            ? "The same keyboard you just installed, running inside the app."
            : "The keyboard itself, running inside the app. It will not appear in other apps until "
                + "it is added in Settings, but you can try it here now."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Try it here first")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.Text.primary)

                // Describes the screen; it does not instruct. The instruction is
                // the hint inside `KeyboardPreview`, which names what to do with
                // the sentence already sitting there and disappears once the user
                // has done something with it. Telling somebody to "type a
                // sentence" above a sentence is the defect this replaced.
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.top, Theme.Space.xl)

            KeyboardPreview(
                seedText: PlaygroundView.seedSentence,
                placeholder: PlaygroundView.seedPlaceholder,
                hint: PlaygroundView.seedHint
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .padding(.horizontal, Theme.Space.xs)
        }
    }
}
