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
                                replyCard
                                // The card said, in as many words, "A mock
                                // paywall. Nothing in this build is gated, for
                                // anyone." `AppFeatureFlags.subscriptionPaywall`
                                // is why it is not on the home screen of a
                                // shipping build; NIT-20 is what brings it back.
                                if AppFeatureFlags.subscriptionPaywall, !store.isSubscribed {
                                    upgradeCard
                                }
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

    /// The AI features share one card with a hairline between the rows: two
    /// separate cards read as clutter above the setup checklist. In the v1
    /// build that is Dictation alone — see the gate below.
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
            // **Screen Context is out of the v1 build, so the row and the
            // hairline under it both go.** `FeatureFlags.screenCaptureReply`
            // holds the reason: no part of the ReplayKit path has ever run,
            // because the Simulator ships no `replayd`, and NIT-6 needs a
            // physical phone to close. Offering the row anyway would ask for a
            // screen recording — the most expensive permission this product has
            // — to reach the one feature nobody has ever seen work. Gated, not
            // deleted: the flag flips when NIT-6 passes and the card is the
            // screen it comes back on.
            if FeatureFlags.screenCaptureReply {
                HomeScreenContextCard()
                Divider().overlay(Theme.Keys.labelOnFunction.opacity(0.14))
            }
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
                    // **Named after what it buys, not where it lives.** Onboarding no
                    // longer spends a whole step asking for this, so this card is the
                    // one place left that raises it — and the row that used to repeat
                    // the Settings path now says what is actually gated behind it:
                    // Hebrew Fix, Rewrite and Reply need the network, and the language
                    // list and custom layout need the shared container, neither of
                    // which the keyboard can reach without this.
                    StatusRow(
                        title: "Allow Full Access",
                        detail: "Needed for Hebrew AI, Reply, and your saved languages and layout",
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

    // MARK: Reply

    /// How to give Reply something to answer, which in this build is three steps
    /// across two apps.
    ///
    /// **This is the card that replaced Screen Context, and it is teaching
    /// rather than a control.** Reply's v1 source is the clipboard, not a screen
    /// reading (NIT-162), and no part of that gesture can be started from here:
    /// the copy happens in somebody else's app and both taps happen on the
    /// keyboard. So it is a flat explainer card and deliberately not a row in
    /// the graphite feature card above, whose every row is a session with a
    /// control and a LIVE badge. A row there with a dead trailing control would
    /// be exactly the kind of button that does nothing this release is removing.
    ///
    /// **Why the app teaches it at all, when the keyboard already refuses
    /// well.** `ScreenContextPrompt` prints two good sentences at the moment of
    /// the tap and one of them carries a button. But both are refusals: they are
    /// only read by somebody who already found Reply and already failed with it,
    /// and neither can be found by a person wondering what this keyboard does.
    /// The middle step is also the unguessable one: reading the clipboard
    /// outright raises Apple's "Allow Paste?" alert, so `CopyClipPasteControl`
    /// uses `UIPasteControl` instead and the user's tap is the consent. That
    /// puts a tap in the middle of this gesture for a reason nobody can infer
    /// from the outcome.
    ///
    /// **Nothing here describes screen reading.** No broadcast, no "reads your
    /// conversation": the words are checked against `ReplySource` and against
    /// `ScreenContextPrompt`'s own refusal copy, which is what the user meets if
    /// they arrive at Reply from the other end. When
    /// `FeatureFlags.screenCaptureReply` flips, the screen becomes the preferred
    /// source and these steps become the fallback rather than the whole story —
    /// this card is where that has to be said.
    private var replyCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.sm) {
                    // The key's own glyph and the key's own word, read off
                    // `AIAction` rather than spelled again here, so the card and
                    // the thing it points at cannot drift apart.
                    IconBadge(systemName: AIAction.reply.icon, tint: Theme.Brand.solid)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(AIAction.reply.title) answers what you copied")
                            .font(Theme.Fonts.headline)
                            .foregroundStyle(Theme.Text.primary)
                        Text("Three steps, and the middle one is the surprising one.")
                            .font(Theme.Fonts.callout)
                            .foregroundStyle(Theme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Self.replySteps.enumerated()), id: \.offset) { index, step in
                        if index > 0 { Divider.themed }
                        ExplainerStepRow(number: index + 1, title: step.title, detail: step.detail)
                            .padding(.vertical, Theme.Space.sm)
                    }
                }

                Text(
                    "Reading what you copied outright would raise Apple's \"Allow Paste?\" alert, "
                        + "so this keyboard does not: the Paste button is Apple's own, and your tap "
                        + "on it is the permission. Nothing is photographed and no screen is read."
                )
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .searchTarget(.reply)
        .accessibilityIdentifier("home-reply-explainer")
    }

    /// **Written to survive being read next to the refusal.** Step 2 names
    /// CopyClip and Paste in the same words `ScreenContextPrompt` uses, because
    /// a user who met the refusal first must not have to work out that the two
    /// sentences describe one action. Neither step names where a key sits: the
    /// CopyClip key can be moved or removed in the layout editor, and Reply's
    /// end of the suggestion bar is the *leading* end, which is the right-hand
    /// one in Hebrew.
    private static let replySteps: [(title: String, detail: String)] = [
        (
            "Copy the message",
            "In the app you are reading it in, copy the message you want to answer."
        ),
        (
            "Let it in with CopyClip's Paste",
            "Open CopyClip on the keyboard and tap Paste. That tap is what lets this keyboard "
                + "see the text you copied."
        ),
        (
            "Tap \(AIAction.reply.title)",
            "It sits on the suggestion bar above the letters, and answers in the language the "
                + "message was written in."
        )
    ]

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
        // Named so a UI test can assert this is *absent* while
        // `AppFeatureFlags.subscriptionPaywall` is false. An unnamed view can
        // only be looked for by its copy, which is the one thing about a gated
        // surface nobody should have to depend on.
        .accessibilityIdentifier("home-upgrade")
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
