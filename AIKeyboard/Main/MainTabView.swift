import SwiftUI
import AIKeyboardCore

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            LanguagesView()
                .tabItem { Label("Languages", systemImage: "globe") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var store: SharedStore
    @StateObject private var session = ScreenContextSession.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsPlayground = false

    /// Measured, never assumed. Two of the three answers come from a file only a
    /// keyboard with Full Access could have written and the third from
    /// AVFoundation; all three used to be hardcoded `@State` booleans, which is
    /// how this screen came to show an unticked Full Access box with a Fix button
    /// to somebody who had granted Full Access.
    @State private var setup = SetupState()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.7)

                ScrollView {
                    VStack(spacing: Theme.Space.md) {
                        screenContextCard
                        setupCard
                        playgroundCard
                        if !store.isSubscribed { upgradeCard }
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .navigationTitle("AI Keyboard")
            .toolbarBackground(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsPlayground) {
                PlaygroundView()
            }
        }
        // Both halves of this can change while the app is in the background — the
        // user leaves for Settings, or types on the keyboard in another app —
        // and neither sends a notification, so the answer is re-read every time
        // this screen comes back rather than cached at launch.
        .onAppear { setup = .current() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current() }
        }
    }

    // MARK: Screen context

    /// Sits above everything else because it is the only thing on this screen
    /// that is a session rather than a setting: it needs starting, it can be
    /// running right now, and the user should always be able to see which.
    /// LIVE means a capture session is running, and only that. The sample
    /// conversation gets its own badge: a red LIVE over a scripted demo says the
    /// screen is being watched when nothing is.
    private var isCapturing: Bool { session.source == .capture && session.isLive }

    private var screenContextCard: some View {
        NavigationLink {
            ScreenContextView()
        } label: {
            Card {
                HStack(spacing: Theme.Space.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(
                                isCapturing
                                    ? AnyShapeStyle(Theme.Semantic.record.opacity(0.14))
                                    : AnyShapeStyle(Theme.Brand.softGradient)
                            )
                            .frame(width: 38, height: 38)

                        Image(systemName: isCapturing ? "eye.fill" : "eye")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                isCapturing
                                    ? AnyShapeStyle(Theme.Semantic.record)
                                    : AnyShapeStyle(Theme.Brand.gradient))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("Screen Context")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.Text.primary)

                            if isCapturing {
                                badge("LIVE", colour: Theme.Semantic.record)
                            } else if session.source == .scripted {
                                badge("SAMPLE", colour: Theme.Text.tertiary)
                            }
                        }

                        Text(screenContextDetail)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Text.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-screen-context")
    }

    private func badge(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Theme.Text.onBrand)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(colour))
    }

    private var screenContextDetail: String {
        switch session.source {
        case .capture: return "The keyboard can reply to what's on screen"
        case .scripted: return "Playing a sample conversation"
        case .none: return "Let the keyboard answer the message you're looking at"
        }
    }

    // MARK: Setup

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.xs) {
                    Text(setup.isReady ? "Ready to type" : "Almost there")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)

                    Spacer()

                    Text("\(setup.confirmedRequirements)/\(setup.requirementCount)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(setup.isReady ? Theme.Semantic.success : Theme.Text.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                (setup.isReady ? Theme.Semantic.success : Theme.Text.secondary)
                                    .opacity(0.14)
                            )
                        )
                }

                Divider().overlay(Theme.Surface.separator)

                StatusRow(
                    title: "Keyboard added",
                    detail: setup.keyboardAddedDetail,
                    check: setup.keyboardAdded,
                    action: openSettings
                )
                StatusRow(
                    title: "Full Access",
                    detail: setup.fullAccessDetail,
                    check: setup.fullAccess,
                    action: openSettings
                )

                if let explanation = setup.unresolvedExplanation {
                    Text(explanation)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(Theme.Surface.separator)

                // Under its own heading because it is not one of the two the
                // badge counts, and a row that looks like a step but is not
                // counted would make the badge look wrong.
                SectionHeader(title: "For dictation")

                StatusRow(
                    title: "Microphone",
                    detail: setup.microphoneDetail,
                    check: setup.microphoneAccess,
                    // Nothing has asked iOS for the microphone yet, and Settings
                    // shows no switch for a permission that was never requested,
                    // so an untouched microphone gets no button to press.
                    action: setup.microphoneAccess == .blocked ? openSettings : nil
                )
            }
        }
    }

    /// Opens Settings, and nothing more precise than that is promised anywhere
    /// the user can read.
    ///
    /// `UIApplication.openSettingsURLString` is the only Settings destination iOS
    /// offers — checked against the iOS 26.2 SDK, where it is still undeprecated
    /// and where the only other constants are
    /// `openNotificationSettingsURLString` and
    /// `openDefaultApplicationsSettingsURLString`. There is no constant for
    /// General › Keyboard and no way to deep-link the Full Access switch, so the
    /// row's own copy spells out the path from the top of Settings rather than
    /// implying the button lands on it.
    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: Playground

    private var playgroundCard: some View {
        Button {
            showsPlayground = true
        } label: {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Try the keyboard")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Text.onBrand)
                    Text("Type here without leaving the app")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Text.onBrand.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Space.xs)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Text.onBrand)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Brand.gradient)
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier("home-playground")
    }

    // A row of three tiles used to sit here reading "1,284 Words fixed" and
    // "37m Time saved". Both were invented constants on the home screen of a
    // shipping build, and neither is measurable today: counting fixes needs a
    // counter in the keyboard's own typing path, and "time saved" has no honest
    // definition at all — it is a words-per-minute guess dressed as a
    // measurement. Removed rather than replaced. The third tile, the language
    // count, was real, and it is one tap away in the Languages tab; a stat row
    // with one stat left in it is worse than none.

    // MARK: Upgrade

    private var upgradeCard: some View {
        NavigationLink {
            SubscriptionView()
        } label: {
            Card {
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    SparkleMark(size: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI Keyboard Pro")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.Text.primary)
                        // "cloud dictation" was in this list. There is no
                        // dictation at all in this build, in either process, so a
                        // paid tier cannot have a better one. See `MockDictation`.
                        //
                        // "Unlimited rewrites and every tone" went the same way and
                        // for the same reason: nothing meters a rewrite and nothing
                        // gates a tone, so "unlimited" is a claim about a cap that
                        // was never built. See `SubscriptionView.features`.
                        Text("A mock paywall. Nothing in this build is gated, for anyone.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Text.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playground

struct PlaygroundView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Seeded with something worth fixing. An empty playground gives
                // the AI actions nothing to act on, so the first tap does nothing
                // and the feature looks broken.
                //
                // Which is exactly why the instruction cannot be "type a
                // sentence": the sentence is already typed, so the one thing the
                // screen told the user to do was the one thing already done. The
                // hint names what to do *with* it, and `KeyboardPreview` drops it
                // the moment the text stops being the seed. The placeholder is a
                // different sentence for a different state — it is only ever seen
                // once the user has cleared the field, and then typing really is
                // the next thing.
                KeyboardPreview(
                    seedText: PlaygroundView.seedSentence,
                    placeholder: PlaygroundView.seedPlaceholder,
                    hint: PlaygroundView.seedHint
                )
            }
            .background(Theme.Surface.background)
            .navigationTitle("Playground")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Shared with onboarding's last step so the two places that hand the user a
    /// keyboard hand them the same sentence and the same next move.
    ///
    /// **Both name the button rather than drawing it.** These said "tap ✨" above a
    /// bar carrying two brand-tinted buttons side by side, the left one wearing the
    /// default tone's own icon — which was SF `sparkle`, the same drawing as the
    /// menu's `sparkles`. `ToneSetting.settingsNote` fixed exactly this in Settings
    /// and these two were left behind; the name now comes from
    /// `SuggestionBar.aiButtonName`, so there is one spelling of it.
    static let seedSentence = "i dont think we should do it because its not make sense"
    static let seedPlaceholder = "Type in Hebrew or English, then tap \(SuggestionBar.aiButtonName)"
    static let seedHint =
        "This sentence has mistakes in it on purpose. Tap \(SuggestionBar.aiButtonName), then Fix to "
        + "correct it, or Tone to say it another way."
}
