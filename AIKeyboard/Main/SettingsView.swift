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

    /// Written by the same process at the two ends of a launch, and read here
    /// for the same reason `memory` is. See `KeyboardLaunchRecord`, which says
    /// what the two counters mean together and why neither means anything alone.
    @State private var launch: KeyboardLaunchRecord?

    /// What the hosts this keyboard has served said about their own text fields,
    /// read here for the same reason `memory` and `launch` are. See
    /// `SecureDecisionRecord`, which says which of its numbers is the one the
    /// record exists for and why a nil must not be drawn as a zero.
    @State private var secure: SecureDecisionRecord?

    /// Whether the Reset row has been tapped on this visit, which is the only
    /// thing it has to say afterwards: the identifier is gone the instant it is
    /// pressed and the next one is not made until something is sent, so there is
    /// no new value to show and nothing to read back.
    @State private var didResetAnalyticsID = false

    /// Mirrors `Analytics.isOptedOut`, which lives in `UserDefaults.standard`
    /// rather than in `SharedStore`: analytics is app-only by design, and the
    /// keyboard must not be able to reach any of it. Seeded on appear rather than
    /// bound through `@AppStorage` so the whole screen keeps one way of reading
    /// state that another process cannot change under it.
    @State private var analyticsOptedOut = Analytics.isOptedOut

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
                                privacySection
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
            launch = KeyboardLaunchRecord.load()
            secure = SecureDecisionRecord.load()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            setup = .current(store: store)
            memory = KeyboardMemoryPeak.load()
            launch = KeyboardLaunchRecord.load()
            secure = SecureDecisionRecord.load()
        }
    }

    // MARK: Account

    /// **The header follows the contents.** With the paywall gated there is no
    /// account in this build at all — nothing signs in, nothing is bought, and
    /// `SharedStore.isSubscribed` is false for everyone — so "Account" would be
    /// a heading over one button that replays onboarding. It comes back with the
    /// row, under `AppFeatureFlags.subscriptionPaywall`.
    private var accountSection: some View {
        section(AppFeatureFlags.subscriptionPaywall ? "Account" : "Setup") {
            // **The row that said "Mock paywall, nothing is gated yet".** It is
            // the last way into `SubscriptionView` from the shipping app, so
            // `AppFeatureFlags.subscriptionPaywall` takes it and its hairline
            // together; the destination below stays wired for the search jump
            // the same flag currently withholds. NIT-20 is the condition.
            if AppFeatureFlags.subscriptionPaywall {
                NavigationRow(
                    title: store.isSubscribed ? "Subscription" : "Upgrade to Pro",
                    subtitle: store.isSubscribed ? "Active" : "Mock paywall, nothing is gated yet",
                    icon: "sparkles"
                ) {
                    SubscriptionView()
                }
                Divider.themed
            }
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

    // MARK: Privacy

    /// The sentence `.claude/docs/analytics-policy.md` section 6 requires in the
    /// app, and the row that makes its "resettable" claim true from here.
    ///
    /// **The policy names two homes for this and one of them no longer exists.**
    /// It asked for the landing page's privacy page, which has it, and for
    /// `OnboardingFullAccessStep`, which the onboarding cut deleted. Settings is
    /// the surface that survived and it is the better of the two anyway: this is
    /// what somebody comes looking for, on purpose, days after they installed —
    /// not something to be handed on the way past a permission dialog.
    private var privacySection: some View {
        section("Privacy") {
            InfoRow(icon: "hand.raised", title: "What we count", detail: Self.whatWeCount)
                .searchTarget(.privacy)
            Divider.themed
            countMeToggle
            Divider.themed
            resetAnalyticsRow
        }
    }

    /// **The screen-sharing clause is withheld while the feature is, and it is
    /// tied to the flag rather than deleted.** The policy's wording counts
    /// "whether you open a screen-sharing session", which is
    /// `screen_context_session_started` — an event that cannot fire while
    /// `FeatureFlags.screenCaptureReply` is false, because nothing in the build
    /// can start a broadcast. Claiming to count something uncountable is the
    /// smaller of the two errors it would make. The larger one is that this
    /// paragraph would introduce *screen sharing* to somebody who has seen no
    /// trace of it anywhere in this app, in the one place where the app is
    /// making a promise about trust — which is the same rule the rest of this
    /// release follows: nothing here describes a capability the build does not
    /// ship. Written as a branch on the flag so the clause returns with the
    /// feature instead of waiting for somebody to remember it.
    ///
    /// **The `false` branch is word for word the landing page's "What we count"
    /// section** (`Landing/app/privacy/page.tsx`), which dropped the same clause
    /// independently. The policy asks for this statement in two places, and two
    /// places that say it differently is worse than one that says it at all, so
    /// an edit to either of them belongs in both.
    private static var whatWeCount: String {
        let counted =
            FeatureFlags.screenCaptureReply
            ? "how far setup gets, whether Full Access and the keyboard were confirmed, whether "
                + "you open a screen-sharing session, and whether you come back to the app"
            : "how far setup gets, whether Full Access and the keyboard were confirmed, and "
                + "whether you come back to the app"
        // **The last sentence answers "who is counting", which the rest of the
        // paragraph never did.** `.claude/docs/analytics-policy.md` section 5
        // rejects a third-party SDK, and its reason is the same fear the Full
        // Access permission itself raises: a stranger's closed binary running
        // inside the process that holds the shared container, whose "no content
        // collected" claim cannot be checked the way this file can. That is the
        // strongest thing this app can say here and it was going unsaid. The
        // landing page's "Never sold" section covers advertising rather than
        // SDKs, so neither surface carried it.
        return "The app counts \(counted). It never counts a keystroke, a correction, a dictated "
            + "word, an AI answer, or anything read off your screen. The keyboard itself sends "
            + "nothing, with or without Full Access. Nothing is sold, and no other company's "
            + "code is doing the counting."
    }

    /// The switch the policy does not require, phrased as the thing being done
    /// rather than as the thing being refused.
    ///
    /// **"Count this install" rather than "Opt out of analytics".** A negative
    /// toggle makes the on position mean "off", which is the shape people get
    /// wrong when they are skimming, and this is a screen where getting it wrong
    /// means believing you turned something off that is still on. The stored
    /// value is `Analytics.isOptedOut`, so the binding inverts once, here, rather
    /// than making every reader remember the polarity.
    ///
    /// Turning it off does not clear the identifier. That is the row below, and
    /// keeping them separate is deliberate: "stop counting me" and "forget who I
    /// was" are different asks, and doing the second silently as a side effect of
    /// the first would be a surprise in the direction nobody wants surprises.
    private var countMeToggle: some View {
        ToggleRow(
            title: "Count this install",
            subtitle: "Switch it off and the app sends none of the six counts above",
            icon: "chart.bar",
            isOn: Binding(
                get: { !analyticsOptedOut },
                set: { newValue in
                    analyticsOptedOut = !newValue
                    Analytics.isOptedOut = !newValue
                })
        )
        .searchTarget(.privacy)
    }

    /// **What makes the identifier resettable, which until now was a promise
    /// kept only in a comment.** `Analytics.installID` is a locally generated
    /// UUID rather than `identifierForVendor` precisely so it *can* be thrown
    /// away, and `Analytics.reset()` has existed unused since the day it was
    /// written, waiting for a row to call it. This is that row.
    ///
    /// **Deliberately not a confirmation dialog**, unlike the dictionary's
    /// Forget button beside it in spirit: nothing of the user's is destroyed
    /// here. The only consequence is that this install stops being joinable to
    /// the counts it sent before, which is the thing the user is asking for. The
    /// caption confirms afterwards instead, because a button that reports
    /// nothing is a button people press twice.
    ///
    /// The reset also clears the two once-per-install latches, so the next time
    /// `SetupState.current` runs it reports Full Access and the keyboard once
    /// more under the new identifier. That is correct rather than a leak: a new
    /// identity with no state reported is a row nothing can be read from.
    private var resetAnalyticsRow: some View {
        Button {
            Analytics.reset()
            didResetAnalyticsID = true
        } label: {
            HStack(spacing: Theme.Space.sm) {
                IconBadge(systemName: "arrow.counterclockwise.circle", tint: Theme.Text.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reset the anonymous ID")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Text.primary)
                    Text(
                        didResetAnalyticsID
                            ? "Done. The next count starts a fresh one."
                            : "Starts a count that cannot be joined to the old one"
                    )
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings-reset-analytics-id")
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
            // Shown only when there is a reading for this boot, and with no
            // empty-state twin. The memory row above already carries the one
            // "use the keyboard and come back" sentence this screen needs, and
            // a second copy of it under a different icon would read as a second
            // thing being wrong.
            if let launch, launch.bootIdentity == KeyboardPresence.bootIdentity {
                Divider.themed
                InfoRow(
                    icon: "bolt.horizontal",
                    tint: Self.launchGapIsEvidence(launch) ? Theme.Semantic.warning : nil,
                    title: "Keyboard launches",
                    detail: launchDetail(launch))
            }
            // Same rule as the row above: shown only when there is a reading for
            // this boot, and with no empty-state twin. A zero here would be
            // actively misleading rather than merely unhelpful — the whole hazard
            // `SecureDecisionRecord` was written for is a zero that means the
            // question was never asked being read as the question answered no.
            if let secure, secure.bootIdentity == KeyboardPresence.bootIdentity {
                Divider.themed
                InfoRow(
                    icon: "lock.shield",
                    tint: secure.refusedSecure > 0 ? Theme.Semantic.warning : nil,
                    title: "Reply and secure fields",
                    detail: secureDetail(secure))
            }
        }
    }

    /// **The tint is on `refusedSecure` alone, and the other two numbers moving
    /// is not news.**
    ///
    /// `answered` reading zero is the *expected* answer, and it is what "silence
    /// permits" was chosen for, so colouring it would put a warning on the
    /// ordinary case and teach the reader to ignore the colour — the same
    /// argument `launchGapIsEvidence` is written under. `refusedContentType`
    /// moving is the guard working, which is also not a fault. A host saying a
    /// field *is* secure is the one reading that contradicts something Apple
    /// documents — that the system replaces a custom keyboard for a secure field,
    /// so this keyboard should never be on screen to be asked — and it is worth
    /// a second look on its own.
    private func secureDetail(_ record: SecureDecisionRecord) -> String {
        var parts = ["\(record.decisions) Reply \(record.decisions == 1 ? "tap" : "taps")"]
        parts.append(
            record.answered == 0
                ? "no host answered isSecureTextEntry"
                : "\(record.answered) answered isSecureTextEntry")
        if record.refusedSecure > 0 {
            parts.append("\(record.refusedSecure) said the field was secure")
        }
        if record.refusedContentType > 0 {
            parts.append("\(record.refusedContentType) refused by content type")
        }
        if record.refusedSecure == 0, record.refusedContentType == 0 {
            parts.append("none refused")
        }
        return parts.joined(separator: ", ")
    }

    /// Whether the gap between the two counters has earned a warning tint.
    ///
    /// **Two, not one, and the record's own doc is why.** `KeyboardLaunchRecord`
    /// concedes that iOS may build a controller it never presents for reasons of
    /// its own, so it says in as many words that one point of gap is noise and
    /// only a persistent ratio is evidence. Tinting at a gap of one would put a
    /// warning colour on the case the instrument already calls noise, which
    /// teaches the reader to ignore the colour. The detail line always prints the
    /// real numbers either way, so nothing is hidden by waiting for the second.
    private static func launchGapIsEvidence(_ launch: KeyboardLaunchRecord) -> Bool {
        launch.loads - launch.presentations >= 2
    }

    /// **The count leads and the gap follows it**, because a gap of two means
    /// one thing over five launches and another over two hundred, and the reader
    /// cannot weigh it without the denominator. The timing goes last: it only
    /// matters once the counters have said there is something to explain.
    private func launchDetail(_ launch: KeyboardLaunchRecord) -> String {
        let missing = launch.loads - launch.presentations
        var parts = ["\(launch.loads) launch\(launch.loads == 1 ? "" : "es")"]
        parts.append(
            missing > 0
                ? "\(missing) never reached the screen"
                : "all reached the screen")
        if launch.presentations > 0 {
            parts.append(String(format: "slowest %.0f ms", launch.slowestPresentMS))
        }
        return parts.joined(separator: ", ")
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
