import SwiftUI
import AIKeyboardCore

struct LanguagesView: View {
    @EnvironmentObject private var store: SharedStore
    @EnvironmentObject private var search: AppSearch
    @Environment(\.scenePhase) private var scenePhase

    /// Measured for one sentence: without Full Access the keyboard cannot read
    /// this screen's list at all, and this is where a user picks it. Re-read on
    /// every return to the foreground, like Home's copy, because the switch is
    /// thrown in Settings and nothing notifies the app.
    @State private var setup = SetupState()

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Space.lg) {
                            if search.isSearching {
                                AppSearchResults(
                                    includeLanguages: false,
                                    showsEmpty: LanguageCatalogueSection.matches(for: search.query)
                                        .isEmpty)
                                LanguageCatalogueSection(
                                    filter: search.query, hideIfEmpty: true)
                            } else {
                                activeSummary
                                LanguageCatalogueSection()
                                LanguageMixingSection()
                                    .searchTarget(.mixing)
                            }
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.bottom, Theme.Space.xl)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: search.highlightedLanguage) { _, _ in
                        scrollToSearchHit(proxy)
                    }
                    .onChange(of: search.highlightedRow) { _, _ in
                        scrollToSearchHit(proxy)
                    }
                    .onAppear { scrollToSearchHit(proxy) }
                }
            }
            .safeAreaInset(edge: .top, spacing: Theme.Space.xs) {
                AppSearchHeader(searchAccessibilityID: "language-search") {
                    Text("Languages")
                        .font(Theme.Fonts.display)
                        .tracking(-0.5)
                        .foregroundStyle(Theme.Text.primary)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { setup = .current(store: store) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current(store: store) }
        }
    }

    // MARK: Active summary

    /// What the globe key will cycle through, as a row of chips.
    ///
    /// Deliberately not a second list of toggles. There is exactly one switch per
    /// language on this screen and it is in the catalogue below, which is what
    /// keeps a language in the same place when it is turned off — a row that
    /// jumps to another section under the finger that just tapped it is the kind
    /// of list nobody can use, and `AppGroupCrossProcessTests` reads the first
    /// switch on this screen and expects it to still be English's afterwards.
    private var activeSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "On this keyboard")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    if store.enabledLanguages.isEmpty {
                        Text("None yet. Turn one on below.")
                            .font(Theme.Fonts.callout)
                            .foregroundStyle(Theme.Text.secondary)
                    } else {
                        FlowRow(spacing: Theme.Space.xs) {
                            ForEach(store.enabledLanguages) { language in
                                chip(for: language)
                            }
                        }
                    }

                }
            }

            // Without Full Access, none of these choices reaches the keyboard.
            // Keep the warning quiet, outside the primary content card, and only
            // show it while it is actionable.
            if setup.fullAccess != .confirmed {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xxs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11, weight: .regular))

                    Text("Full Access is off. Changes here won’t reach the keyboard.")
                        .font(Theme.Fonts.micro.weight(.regular))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.Text.tertiary)
                .padding(.horizontal, Theme.Space.xxs)
            }
        }
    }

    private func chip(for language: KeyboardLanguage) -> some View {
        HStack(spacing: 5) {
            Text(language.flag)
                .font(.system(size: 13))
            Text(language.nativeName)
                .font(Theme.Fonts.caption.weight(.medium))
                .foregroundStyle(Theme.Text.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.Surface.elevated))
        .overlay(Capsule().strokeBorder(Theme.Surface.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(language.displayName), on")
    }

    private func scrollToSearchHit(_ proxy: ScrollViewProxy) {
        let language = search.highlightedLanguage
        let mixing = search.highlightedRow == .mixing
        guard language != nil || mixing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(Theme.Motion.quick) {
                if let language {
                    proxy.scrollTo(language.id, anchor: .center)
                } else {
                    proxy.scrollTo(AppSearchRow.mixing, anchor: .center)
                }
            }
        }
    }
}
