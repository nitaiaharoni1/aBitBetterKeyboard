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
    @State private var showsPlayground = false

    // Nothing here can be verified from inside the app, so these stand in for the
    // checks the real product would run against the App Group.
    @State private var keyboardAdded = true
    @State private var fullAccessGranted = false
    @State private var microphoneGranted = true

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(intensity: 0.7)

                ScrollView {
                    VStack(spacing: Theme.Space.md) {
                        screenContextCard
                        setupCard
                        playgroundCard
                        statsRow
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
    }

    // MARK: Screen context

    /// Sits above everything else because it is the only thing on this screen
    /// that is a session rather than a setting: it needs starting, it can be
    /// running right now, and the user should always be able to see which.
    private var screenContextCard: some View {
        NavigationLink {
            ScreenContextView()
        } label: {
            Card {
                HStack(spacing: Theme.Space.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(session.isLive
                                  ? AnyShapeStyle(Theme.Semantic.record.opacity(0.14))
                                  : AnyShapeStyle(Theme.Brand.softGradient))
                            .frame(width: 38, height: 38)

                        Image(systemName: session.isLive ? "eye.fill" : "eye")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(session.isLive
                                             ? AnyShapeStyle(Theme.Semantic.record)
                                             : AnyShapeStyle(Theme.Brand.gradient))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text("Screen Context")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.Text.primary)

                            if session.isLive {
                                Text("LIVE")
                                    .font(.system(size: 9, weight: .bold))
                                    .tracking(0.5)
                                    .foregroundStyle(Theme.Text.onBrand)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.Semantic.record))
                            }
                        }

                        Text(session.isLive
                             ? "The keyboard can reply to what's on screen"
                             : "Let the keyboard answer the message you're looking at")
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

    // MARK: Setup

    private var setupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.xs) {
                    Text(isReady ? "Ready to type" : "Almost there")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)

                    Spacer()

                    Text("\(completedSteps)/3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isReady ? Theme.Semantic.success : Theme.Text.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(
                                (isReady ? Theme.Semantic.success : Theme.Text.secondary).opacity(0.14)
                            )
                        )
                }

                Divider().overlay(Theme.Surface.separator)

                StatusRow(
                    title: "Keyboard added",
                    detail: keyboardAdded ? "Available in every app" : "Add it in Settings",
                    isDone: keyboardAdded,
                    action: openSettings
                )
                StatusRow(
                    title: "Full Access",
                    detail: fullAccessGranted ? "Cloud rewrites enabled" : "Typing and local AI still work without it",
                    isDone: fullAccessGranted,
                    action: openSettings
                )
                StatusRow(
                    title: "Microphone",
                    detail: microphoneGranted ? "Dictation ready" : "Needed for dictation",
                    isDone: microphoneGranted,
                    action: openSettings
                )
            }
        }
    }

    private var completedSteps: Int {
        [keyboardAdded, fullAccessGranted, microphoneGranted].filter { $0 }.count
    }

    private var isReady: Bool { completedSteps == 3 }

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

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: Theme.Space.xs) {
            StatTile(value: "1,284", label: "Words fixed", icon: "checkmark.circle")
            StatTile(value: "37m", label: "Time saved", icon: "clock")
            StatTile(value: "\(store.enabledLanguages.count)", label: "Languages", icon: "globe")
        }
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
                        Text("Unlimited rewrites, cloud dictation and every tone.")
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

struct StatTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Brand.solid)

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.Text.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Surface.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Surface.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
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
                KeyboardPreview(
                    seedText: "i dont think we should do it because its not make sense",
                    placeholder: "Type in Hebrew or English, then tap ✨"
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
}
