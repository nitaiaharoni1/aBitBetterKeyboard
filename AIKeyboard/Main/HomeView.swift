import SwiftUI
import AIKeyboardCore

struct HomeView: View {
    @EnvironmentObject private var store: SharedStore
    @EnvironmentObject private var search: AppSearch
    @Environment(\.scenePhase) private var scenePhase

    /// Measured, never assumed. Two of the three answers come from a file only a
    /// keyboard with Full Access could have written and the third from
    /// AVFoundation; all three used to be hardcoded `@State` booleans, which is
    /// how this screen came to show an unticked Full Access box with a Fix button
    /// to somebody who had granted Full Access.
    @State private var setup = SetupState()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: Theme.Space.md) {
                            if search.isSearching {
                                AppSearchResults()
                            } else {
                                if !setup.isReady { setupCard }
                                featureCard
                                playgroundCard
                                if !store.isSubscribed { upgradeCard }
                            }
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.bottom, Theme.Space.xl)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: search.highlightedRow) { _, row in
                        guard let row, row.tab == .home else { return }
                        scrollToHighlight(proxy)
                    }
                    .onAppear { scrollToHighlight(proxy) }
                }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Space.xs) {
                AppSearchHeader(title: "aBitBetterKeyboard", searchAccessibilityID: "app-search")
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $search.showsPlayground) {
                PlaygroundView()
            }
        }
        .id(search.stackEpoch)
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
    ///
    /// **The card is this screen's one graphite moment.** The design direction
    /// gives a feature card a graphite fill with orange icon chips once per
    /// screen, and this is Home's: the rows' white labels ride on
    /// `Theme.Keys.functionStrong` (the graphite/white pairing the keyboard
    /// uses for its strong function keys), and the divider between them is a
    /// light hairline because `Divider.themed` is mixed for warm white. As the
    /// screen's hero it also carries the editor's-desk lift — the top-edge
    /// highlight and ambient shadow — which every other card here stays flat
    /// to protect.
    private var featureCard: some View {
        VStack(spacing: 0) {
            HomeScreenContextCard()
            Divider().overlay(Theme.Keys.labelOnFunction.opacity(0.14))
            HomeDictationCard()
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Keys.functionStrong)
        )
        .graphiteTopHighlight()
        .ambientDepth()
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
                        title: "Add aBitBetterKeyboard",
                        detail: setup.keyboardAddedDetail,
                        check: setup.keyboardAdded,
                        singleLineDetail: true
                    )
                }

                if setup.fullAccess != .confirmed {
                    StatusRow(
                        title: "Allow Full Access",
                        detail: "Settings › General › Keyboard › Keyboards › aBitBetterKeyboard",
                        check: setup.fullAccess,
                        singleLineDetail: true
                    )
                }

                PrimaryButton(title: "Open iOS Settings", icon: "gearshape") {
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
            search.showsPlayground = true
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

                // The screen's primary action wears the flat orange chip;
                // the wash-and-tint version belonged to the old direction.
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Text.onBrand)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Theme.Brand.action))
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
                    IconBadge(systemName: "sparkles", tint: Theme.Brand.solid)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("aBitBetterKeyboard Pro")
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

    private func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard let row = search.highlightedRow, row.tab == .home else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(Theme.Motion.quick) {
                proxy.scrollTo(row, anchor: .center)
            }
        }
    }
}
