import SwiftUI
import AIKeyboardCore

struct SettingsView: View {
    @EnvironmentObject private var store: SharedStore
    @EnvironmentObject private var search: AppSearch
    @Environment(\.scenePhase) private var scenePhase

    /// Measured once here rather than inside each section: every row on
    /// Typing and AI is a setting the keyboard reads across the App Group,
    /// so both sections need it, and measuring it twice would be the same
    /// state read twice a beat apart. Re-read on every return to the
    /// foreground, the same as `LayoutView` and `LanguagesView`.
    @State private var setup = SetupState()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.md) {
                            if search.isSearching {
                                AppSearchResults()
                            } else {
                                SettingsTypingSection(setup: setup)
                                SettingsAISection(setup: setup)
                                accountSection
                                footer
                            }
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.bottom, Theme.Space.xl)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: search.highlightedRow) { _, row in
                        guard let row, row.tab == .settings else { return }
                        scrollToHighlight(proxy)
                    }
                    .onAppear { scrollToHighlight(proxy) }
                }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Space.xs) {
                AppSearchHeader(title: "Settings", searchAccessibilityID: "app-search-settings")
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $search.settingsPush) { push in
                switch push {
                case .subscription: SubscriptionView()
                }
            }
        }
        .id(search.stackEpoch)
        .onAppear { setup = .current(store: store) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current(store: store) }
        }
    }

    // MARK: Account

    private var accountSection: some View {
        section("Account") {
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
            .searchTarget(.replayOnboarding)
        }
    }

    private var footer: some View {
        VStack(spacing: Theme.Space.xxs) {
            Text("aBitBetterKeyboard 0.1")
                .font(Theme.Fonts.caption.weight(.medium))
                .foregroundStyle(Theme.Text.secondary)
            // The keyboard still has no microphone. Dictation is real, and it
            // starts from Home because that is the only process that can
            // open the mic.
            Text("iOS gives a keyboard no microphone. Start dictation from Home.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Theme.Space.xs)
    }

    // MARK: Scaffolding

    private func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard let row = search.highlightedRow, row.tab == .settings else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(Theme.Motion.quick) {
                proxy.scrollTo(row, anchor: .center)
            }
        }
    }

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
