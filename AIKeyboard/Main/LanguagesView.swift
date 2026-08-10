import SwiftUI
import AIKeyboardCore

struct LanguagesView: View {
    @EnvironmentObject private var store: SharedStore
    @Environment(\.scenePhase) private var scenePhase

    /// Measured for one sentence: without Full Access the keyboard cannot read
    /// this screen's list at all, and this is where a user picks it. Re-read on
    /// every return to the foreground, like Home's copy, because the switch is
    /// thrown in Settings and nothing notifies the app.
    @State private var setup = SetupState()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Surface.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        activeSummary
                        LanguageCatalogueSection()
                        LanguageMixingSection()
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.xl)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .navigationTitle("Languages")
        }
        .onAppear { setup = .current() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { setup = .current() }
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
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Text.secondary)
                    } else {
                        FlowRow(spacing: Theme.Space.xs) {
                            ForEach(store.enabledLanguages) { language in
                                chip(for: language)
                            }
                        }
                    }

                    Text(
                        store.enabledLanguages.count > 1
                            ? "The globe key cycles these, in this order. A swipe along the space bar does the same."
                            : "Turn on a second language and the globe key starts cycling between them."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    // The sentence above describes a keyboard that can see this
                    // list, and without Full Access none of it reaches the
                    // keyboard at all. Said here as well as in onboarding, because
                    // this is the screen a user comes back to when the keyboard is
                    // in the wrong language.
                    if setup.fullAccess != .confirmed {
                        Text(SetupState.languagesNeedFullAccess)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func chip(for language: KeyboardLanguage) -> some View {
        HStack(spacing: 5) {
            Text(language.flag)
                .font(.system(size: 13))
            Text(language.nativeName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Text.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.Surface.elevated))
        .overlay(Capsule().strokeBorder(Theme.Surface.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(language.displayName), on")
    }
}
