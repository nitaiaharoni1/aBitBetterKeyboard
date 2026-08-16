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

    /// Written by the keyboard extension, in another process, whenever it comes
    /// up or goes away. Re-read on every return to the foreground for the same
    /// reason `setup` is: the interesting change happens while this screen is not
    /// on top.
    @State private var memory: KeyboardMemoryPeak?

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
                                diagnosticsSection
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
        .onAppear {
            setup = .current(store: store)
            memory = KeyboardMemoryPeak.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            setup = .current(store: store)
            memory = KeyboardMemoryPeak.load()
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

    // MARK: Diagnostics

    /// What the keyboard reported about its own memory, which is the only place
    /// that reading can be seen without attaching a Mac to the phone.
    ///
    /// iOS kills a keyboard extension that runs out of memory silently — the
    /// user is put back on the stock keyboard and nothing is logged — so this is
    /// evidence written ahead of time rather than a crash report read
    /// afterwards. See `KeyboardMemoryPeak`, which also says what it cannot
    /// prove.
    private var diagnosticsSection: some View {
        section("Diagnostics") {
            if let memory, memory.bootIdentity == KeyboardPresence.bootIdentity {
                InfoRow(
                    icon: "memorychip",
                    tint: memory.warnings > 0 ? Theme.Semantic.warning : nil,
                    title: "Keyboard memory",
                    detail: memoryDetail(memory))
            } else {
                // Nil and stale are one case on purpose: both mean there is no
                // reading for this boot, and inventing a distinction between
                // "never wrote one" and "wrote one before the last restart"
                // would put two sentences on screen that lead to the same act.
                InfoRow(
                    icon: "memorychip",
                    title: "Keyboard memory",
                    detail: """
                        No reading since the last restart. Type something with \
                        aBitBetterKeyboard and come back. If it stays empty, the \
                        keyboard does not have Full Access.
                        """)
            }
        }
    }

    /// Peak first, because it is the number that answers the question, and the
    /// warning count last, because zero of them is the good news and a reader
    /// should not have to hunt for it.
    private func memoryDetail(_ memory: KeyboardMemoryPeak) -> String {
        var parts = [String(format: "Peak %.0f MB", memory.peakMB)]
        // Nil is expected until this is read on a device. Saying nothing about
        // headroom is better than printing a zero the kernel never claimed.
        if let headroom = memory.headroomMB {
            parts.append(String(format: "%.0f MB to spare", headroom))
        }
        parts.append(
            memory.warnings == 0
                ? "no memory warnings"
                : "\(memory.warnings) memory warning\(memory.warnings == 1 ? "" : "s")")
        return parts.joined(separator: ", ")
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
