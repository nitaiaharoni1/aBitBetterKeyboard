import SwiftUI
import AIKeyboardCore

struct SettingsView: View {
    @EnvironmentObject private var store: SharedStore
    @EnvironmentObject private var search: AppSearch
    @Environment(\.selectedMainTab) private var selectedTab
    @Environment(\.scenePhase) private var scenePhase

    /// Walks the whole store. Refreshed when this tab is shown, not every redraw.
    @State private var learnedWordCount = 0
    @State private var confirmForget = false

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
                                SettingsTypingSection()
                                SettingsAISection()
                                accountSection
                                if learnedWordCount > 0 || search.highlightedRow == .forgetLearned {
                                    dangerSection
                                }
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
                    .onAppear {
                        refreshLearnedWordCount()
                        scrollToHighlight(proxy)
                    }
                    .onChange(of: selectedTab) { _, tab in
                        if tab == .settings { refreshLearnedWordCount() }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { refreshLearnedWordCount() }
                    }
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

    // MARK: Danger zone

    /// Only shown once there is something to clear. A row that always reads
    /// "0 words" invites the user to press it to find out what it does, and
    /// this is the one press here that cannot be undone.
    private var dangerSection: some View {
        section("Danger zone") {
            Button(role: .destructive) {
                confirmForget = true
            } label: {
                HStack(spacing: Theme.Space.sm) {
                    IconBadge(systemName: "trash", tint: Theme.Semantic.record)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Forget what it learned")
                        Text("\(learnedWordCount) words remembered on this device")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Text.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Semantic.record)
            .searchTarget(.forgetLearned)
            .confirmationDialog(
                "Forget what it learned?",
                isPresented: $confirmForget,
                titleVisibility: .visible
            ) {
                Button("Forget \(learnedWordCount) words", role: .destructive) {
                    PersonalLanguageModel.shared.clear()
                    learnedWordCount = 0
                }
            } message: {
                Text("Removes the words remembered on this device. This cannot be undone.")
            }
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

    private func refreshLearnedWordCount() {
        learnedWordCount = PersonalLanguageModel.shared.learnedWordCount
    }

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
