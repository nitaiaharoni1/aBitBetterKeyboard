import SwiftUI
import AIKeyboardCore

struct SettingsView: View {
    @EnvironmentObject private var store: SharedStore
    @StateObject private var session = ScreenContextSession.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        SettingsTypingSection()
                        SettingsAISection()
                        lookSection
                        feedbackSection
                        moreSection
                        footer
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Space.xs) {
                Text("Settings")
                    .font(Theme.Fonts.display)
                    .tracking(-0.5)
                    .foregroundStyle(Theme.Text.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.xxs)
                    .background(Theme.Surface.background.opacity(0.96))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Look

    /// The same picker onboarding shows, in the same order, because it is the
    /// same view. Inline rather than behind a `NavigationRow`: there are four
    /// options and the answer is a colour, so a screen that has to be opened to
    /// see them costs more than it saves.
    private var lookSection: some View {
        section("Look") {
            PalettePicker()
        }
    }

    // MARK: Feedback

    private var feedbackSection: some View {
        section("Feel") {
            ToggleRow(title: "Haptics", icon: "hand.tap", isOn: $store.haptics)
            Divider.themed
            ToggleRow(
                title: "Key sounds",
                subtitle: "Needs Full Access",
                icon: "speaker.wave.2",
                isOn: $store.keySounds
            )
        }
    }

    // MARK: More

    /// Reports the session rather than the stored opt-in. The setting only means
    /// the user has seen the sample; whether Reply can read anything depends on a
    /// broadcast that iOS starts and ends.
    private var screenContextSubtitle: String {
        switch session.source {
        case .capture: return session.isLive ? "Watching your screen" : "Stopped"
        case .scripted: return "Playing a sample"
        case .none: return "Off"
        }
    }

    private var moreSection: some View {
        section("More") {
            NavigationRow(
                title: "Screen context",
                subtitle: screenContextSubtitle,
                icon: "eye"
            ) {
                ScreenContextView()
            }
            Divider.themed
            NavigationRow(
                title: "Personal dictionary",
                subtitle: "Names and words we should never correct",
                icon: "character.book.closed",
                badge: "\(store.personalDictionary.count)"
            ) {
                DictionaryView()
            }
            Divider.themed
            NavigationRow(
                title: store.isSubscribed ? "Subscription" : "Upgrade to Pro",
                subtitle: store.isSubscribed ? "Active" : "Mock paywall, nothing is gated yet",
                icon: "sparkles"
            ) {
                SubscriptionView()
            }
            Divider.themed
            Button {
                store.hasCompletedOnboarding = false
            } label: {
                HStack(spacing: Theme.Space.sm) {
                    IconBadge(systemName: "arrow.counterclockwise", tint: Theme.Text.secondary)
                    Text("Replay onboarding")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Text.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Space.xxs) {
            Text("AI Keyboard 0.1")
                .font(Theme.Fonts.caption.weight(.medium))
                .foregroundStyle(Theme.Text.secondary)
            // Was "Mock build · no network, no model, no microphone". Two of
            // those three stopped being true when `MockAI` was replaced by
            // `RoutedIntelligence` over Apple's on-device model and a backend
            // transport. The third is still true and is the only one left here,
            // because it is the one the user can feel: dictation streams a
            // script, and a keyboard extension has no microphone with or without
            // Full Access.
            Text("Dictation is a scripted demo. iOS gives a keyboard no microphone.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.xs)
    }

    // MARK: Scaffolding

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: title)
            Card {
                VStack(spacing: Theme.Space.sm) {
                    content()
                }
            }
        }
    }
}
