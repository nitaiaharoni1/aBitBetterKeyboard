import SwiftUI
import AIKeyboardCore

struct KeysView: View {
    @EnvironmentObject private var store: SharedStore
    @EnvironmentObject private var search: AppSearch
    @Environment(\.scenePhase) private var scenePhase

    /// **Nothing on this screen survives without Full Access.** Layout,
    /// Grouped keys and the number-row toggle all go through
    /// `SharedStore.keyboardLayout` / `storedGroupedLevel`; the palette in
    /// `lookSection` is `storedBrandPalette`; both feedback switches in
    /// `feelSection` are `storedHaptics` / `storedKeySounds`. Every one of
    /// them is read across the App Group, so there is no row here to carve
    /// out as a survivor the way `accountSection` is on Settings. Re-read on
    /// every return to the foreground, the same as `LayoutView`.
    @State private var setup = SetupState()

    /// Mirrors `LayoutView.fullAccessMessage`'s hedge: `setup.fullAccess` can
    /// only ever *confirm* a yes, so this says "once Full Access is on"
    /// rather than asserting it is off right now.
    private static let fullAccessMessage =
        "The keyboard can only read the layout, palette and sound choices on this screen once "
        + "Full Access is on. Until then it draws and sounds the way it shipped, whatever is set "
        + "here."

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
                                if setup.fullAccess != .confirmed {
                                    FullAccessNeededBanner(
                                        message: Self.fullAccessMessage, context: "keys")
                                }
                                layoutSection
                                lookSection
                                feelSection
                            }
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.bottom, Theme.Space.xl)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: search.highlightedRow) { _, row in
                        guard let row, row.tab == .keys else { return }
                        scrollToHighlight(proxy)
                    }
                    .onAppear { scrollToHighlight(proxy) }
                }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Space.xs) {
                AppSearchHeader(title: "Keys", searchAccessibilityID: "app-search-keys")
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $search.keysPush) { push in
                switch push {
                case .layout: LayoutView()
                }
            }
        }
        .id(search.stackEpoch)
        .onAppear { setup = .current(store: store) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current(store: store) }
        }
    }

    // MARK: Layout

    private var layoutSection: some View {
        section("Layout") {
            NavigationRow(
                title: "Layout",
                subtitle: "Arrange the keys. Spare ones sit underneath.",
                icon: "square.grid.3x2",
                badge: layoutSummary
            ) {
                LayoutView()
            }
            Divider.themed
            groupedKeysRow
                .searchTarget(.groupedKeys)
            Divider.themed
            ToggleRow(
                title: "Number row",
                subtitle: "Digits above the letters. Makes the keyboard taller.",
                icon: "textformat.123",
                isOn: numberRowBinding
            )
            .searchTarget(.numberRow)
        }
    }

    /// The preset's name, or that it has been edited away from one.
    private var layoutSummary: String {
        guard let id = store.keyboardLayout.preset, let preset = LayoutPreset.named(id) else {
            return "Custom"
        }
        return preset.name
    }

    /// Wider keys, several letters each, and the keyboard works out the word.
    ///
    /// **The accuracy is on the row, next to the choice, because it is the whole
    /// trade.** Every step up this dial makes the keys bigger and the guessing
    /// worse, and a picker that only says "Three letters" hides the half that
    /// costs something. The numbers are the top-1 rates measured in
    /// `Bar/grouped/results.json` — what the space bar would insert — and they are
    /// labelled as measured rather than promised.
    @ViewBuilder private var groupedKeysRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Space.sm) {
                IconBadge(systemName: "rectangle.grid.1x2")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Grouped keys")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Text.primary)
                    Text("Bigger keys holding several letters. The keyboard picks the word.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                }
                Spacer(minLength: 0)
                Picker("Grouped keys", selection: $store.groupedLevel) {
                    ForEach(GroupedKeys.Level.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            if store.groupedLevel != .off {
                let measured = store.groupedLevel.measuredAccuracy
                let hebrewCapped = store.groupedLevel.rawValue > GroupedKeys.Level.hebrewCeiling.rawValue
                Text(
                    hebrewCapped
                        ? "Measured: English \(measured.english)%. Hebrew stays at three letters "
                            + "(\(GroupedKeys.Level.hebrewCeiling.measuredAccuracy.hebrew)%), because four "
                            + "commits the wrong word about three times in ten. Tap a corner to pick "
                            + "that letter. Hold a key to pick one letter exactly."
                        : "Measured: the right word is chosen \(measured.english)% of the time in English, "
                            + "\(measured.hebrew)% in Hebrew. Tap a corner to pick that letter. "
                            + "Hold a key to pick one letter exactly."
                )
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Text.secondary)
                if !GroupedKeys.hasBundledLexicon(for: .english)
                    || !GroupedKeys.hasBundledLexicon(for: .hebrew)
                {
                    Text(
                        "This build has no full word list, so grouping only knows a few hundred common words."
                    )
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Text.secondary)
                }
            }
        }
    }

    /// Writes `showsNumberRow` and, if that moves the layout away from its
    /// preset, clears the preset too — the same thing `LayoutEditorModel.draft`'s
    /// `didSet` does for every edit made inside the layout editor itself.
    private var numberRowBinding: Binding<Bool> {
        Binding(
            get: { store.keyboardLayout.showsNumberRow },
            set: { newValue in
                store.keyboardLayout.showsNumberRow = newValue
                if let preset = store.keyboardLayout.preset,
                    LayoutPreset.named(preset)?.customization != store.keyboardLayout
                {
                    store.keyboardLayout.preset = nil
                }
            }
        )
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
        .searchTarget(.palette)
    }

    // MARK: Feel

    private var feelSection: some View {
        section("Feel") {
            hapticsRows
                .searchTarget(.haptics)
            Divider.themed
            ToggleRow(
                title: "Key sounds",
                subtitle: "Needs Full Access",
                icon: "speaker.wave.2",
                isOn: $store.keySounds
            )
            .searchTarget(.keySounds)
        }
    }

    /// The switch and the strength dial, as one row.
    ///
    /// **Both are exactly as affected as Key sounds below.**
    /// `Feedback.hapticsEnabled` reads `storedHaptics` and `Feedback.strength`
    /// reads `storedHapticStrength`, both at the press, the same cross-process
    /// read as `storedKeySounds` — so they get the same static subtitle Key
    /// sounds already carries, not a new dialect.
    ///
    /// The dial is drawn only when the switch is on: greyed out it would still
    /// be a row asking to be read, and a strength for a haptic nobody is
    /// playing is a question with no answer.
    @ViewBuilder private var hapticsRows: some View {
        VStack(spacing: Theme.Space.sm) {
            ToggleRow(
                title: "Haptics",
                subtitle: "Needs Full Access",
                icon: "hand.tap",
                isOn: $store.haptics
            )
            if store.haptics {
                HStack(spacing: Theme.Space.sm) {
                    IconBadge(systemName: "slider.horizontal.3")
                    // 16 / 13 rather than a named role, because this row sits
                    // directly under a `ToggleRow` in the same card and has to
                    // line up with it. `Theme.Fonts.body` is 15 and would read
                    // as a smaller row. Same reason `idleDelayRow` spells them.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Strength")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.Text.primary)
                        Text("How hard a key hits back")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                    }
                    Spacer(minLength: 0)
                    Picker("Strength", selection: $store.hapticStrength) {
                        ForEach(HapticStrength.allCases, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                // Plays the stop the user just picked, here in the app, because
                // a strength you cannot feel until you next open the keyboard in
                // another app is a choice made blind. `Feedback` reads the suite
                // at the press, so this is the same impact the keyboard will
                // play — the generator is only unbound from a view, which costs
                // this one tap a little latency and nothing else.
                .onChange(of: store.hapticStrength) { _, _ in
                    Feedback.keyPress()
                }
            }
        }
    }

    // MARK: Scaffolding

    private func scrollToHighlight(_ proxy: ScrollViewProxy) {
        guard let row = search.highlightedRow, row.tab == .keys else { return }
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
