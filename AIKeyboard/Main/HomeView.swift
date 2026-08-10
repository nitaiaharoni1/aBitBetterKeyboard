import SwiftUI
import AIKeyboardCore

struct HomeView: View {
    @EnvironmentObject private var store: SharedStore
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
                        HomeScreenContextCard()
                        HomeDictationCard()
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
