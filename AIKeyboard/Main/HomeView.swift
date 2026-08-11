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
                    VStack(spacing: Theme.Space.lg) {
                        if !setup.isReady { setupCard }
                        featureCard
                        playgroundCard
                        if !store.isSubscribed { upgradeCard }
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Space.xs) {
                Text("AI Keyboard")
                    .font(Theme.Fonts.display)
                    .foregroundStyle(Theme.Text.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.xxs)
                    .background(Theme.Surface.background.opacity(0.96))
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsPlayground) {
                PlaygroundView()
            }
        }
        // Both halves of this can change while the app is in the background — the
        // user leaves for Settings, or types on the keyboard in another app —
        // and neither sends a notification, so the answer is re-read every time
        // this screen comes back rather than cached at launch.
        .onAppear { setup = .current(store: store) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current(store: store) }
        }
    }

    // MARK: Features

    /// The two AI features share one card with a hairline between the rows:
    /// two separate cards read as clutter above the setup checklist.
    private var featureCard: some View {
        Card {
            VStack(spacing: 0) {
                HomeScreenContextCard()
                Divider.themed
                HomeDictationCard()
            }
        }
    }

    // MARK: Setup

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.xs) {
                    Text("Finish setup")
                        .font(Theme.Fonts.title)
                        .foregroundStyle(Theme.Text.primary)

                    Spacer()

                    Text("\(setup.confirmedRequirements)/\(setup.requirementCount)")
                        .font(Theme.Fonts.caption.weight(.semibold))
                        .foregroundStyle(Theme.Text.secondary)
                        .padding(.horizontal, Theme.Space.xs)
                        .padding(.vertical, Theme.Space.xxs)
                        .background(
                            Capsule().fill(Theme.Text.secondary.opacity(0.14))
                        )
                }

                Divider.themed

                if setup.keyboardAdded != .confirmed {
                    StatusRow(
                        title: "Add AI Keyboard",
                        detail: setup.keyboardAddedDetail,
                        check: setup.keyboardAdded
                    )
                }

                if setup.fullAccess != .confirmed {
                    StatusRow(
                        title: "Allow Full Access",
                        detail: "Settings › General › Keyboard › Keyboards › AI Keyboard",
                        check: setup.fullAccess
                    )
                }

                PrimaryButton(title: "Open Settings", icon: "gearshape") {
                    openSettings()
                }
            }
        }
        .accessibilityIdentifier("setup-globe-switch")
        .accessibilityLabel("Switched via the globe key, \(setup.keyboardSwitchedDetail)")
    }

    // MARK: Playground

    private var playgroundCard: some View {
        Button {
            showsPlayground = true
        } label: {
            HStack(spacing: Theme.Space.md) {
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    Text("Try the keyboard")
                        .font(Theme.Fonts.title)
                        .foregroundStyle(Theme.Text.primary)
                    Text("Type here without leaving the app")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Space.xs)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Brand.solid)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.Brand.solid.opacity(0.12)))
            }
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Surface.raised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Surface.separator, lineWidth: 1)
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
                    IconBadge(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI Keyboard Pro")
                            .font(Theme.Fonts.headline)
                            .foregroundStyle(Theme.Text.primary)
                        Text("A mock paywall. Nothing in this build is gated, for anyone.")
                            .font(Theme.Fonts.callout)
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
