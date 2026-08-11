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
                AmbientBackground(intensity: 0.7)

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
            .safeAreaInset(edge: .top, spacing: Theme.Space.xs) {
                Text("Languages")
                    .font(Theme.Fonts.display)
                    .foregroundStyle(Theme.Text.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.vertical, Theme.Space.xxs)
                    .background(Theme.Surface.background.opacity(0.96))
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

                    // Without Full Access, none of these choices reaches the
                    // keyboard. Keep the warning short and only show it while it
                    // is actionable.
                    if setup.fullAccess != .confirmed {
                        Text("Full Access is off. Changes here won’t reach the keyboard.")
                            .font(Theme.Fonts.caption)
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
}
