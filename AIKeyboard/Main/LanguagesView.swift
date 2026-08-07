import SwiftUI
import AIKeyboardCore

struct LanguagesView: View {
    @EnvironmentObject private var store: SharedStore

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Surface.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.lg) {
                        activeSection
                        codeSwitchingCard
                        comingSoonSection
                    }
                    .padding(.horizontal, Theme.Space.md)
                    .padding(.bottom, Theme.Space.xl)
                }
            }
            .navigationTitle("Languages")
        }
    }

    // MARK: Active

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "On this keyboard")

            Card(padding: Theme.Space.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(KeyboardLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                        if index > 0 {
                            Divider()
                                .overlay(Theme.Surface.separator)
                                .padding(.leading, 46)
                        }
                        row(for: language)
                    }
                }
            }

            Text("The globe key cycles through the languages you turn on here.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Text.secondary)
                .padding(.horizontal, Theme.Space.xxs)
        }
    }

    private func row(for language: KeyboardLanguage) -> some View {
        let isOn = store.enabledLanguages.contains(language)

        return HStack(spacing: Theme.Space.sm) {
            Text(language.flag)
                .font(.system(size: 24))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(language.nativeName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Text.primary)
                Text(language.isRightToLeft ? "Right to left · no shift key" : "Left to right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Text.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in toggle(language) }
            ))
            .labelsHidden()
            .disabled(isOn && store.enabledLanguages.count == 1)
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.horizontal, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.displayName)
    }

    private func toggle(_ language: KeyboardLanguage) {
        Feedback.modifierPress()
        withAnimation(Theme.Motion.quick) {
            if store.enabledLanguages.contains(language) {
                guard store.enabledLanguages.count > 1 else { return }
                store.enabledLanguages.removeAll { $0 == language }
            } else {
                store.enabledLanguages.append(language)
            }
        }
    }

    // MARK: Code switching

    /// The one behaviour that is genuinely hard to get elsewhere, so it gets its
    /// own explanation rather than hiding in a settings row.
    private var codeSwitchingCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Mixing languages")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    HStack(spacing: Theme.Space.xs) {
                        SparkleMark(size: 15)
                        Text("Code switching is always on")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.Text.primary)
                    }

                    Text("Predictions look at the whole sentence, not the current layout. Type a Latin word inside a Hebrew sentence and the suggestions follow you.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    exampleBubble
                }
            }
        }
    }

    private var exampleBubble: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("אני אשלח לך את ה-document מחר")
                .font(.system(size: 15))
                .foregroundStyle(Theme.Text.primary)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)

            HStack(spacing: 6) {
                ForEach(["deadline", "document", "demo"], id: \.self) { word in
                    HStack(spacing: 3) {
                        Text(word)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Text.primary)
                        LanguageTag(.english)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.Surface.elevated))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(Theme.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.background)
        )
        .accessibilityHidden(true)
    }

    // MARK: Coming soon

    private var comingSoonSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Coming soon")

            Card(padding: Theme.Space.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(["🇸🇦 العربية", "🇷🇺 Русский", "🇫🇷 Français", "🇪🇸 Español"].enumerated()), id: \.offset) { index, name in
                        if index > 0 {
                            Divider().overlay(Theme.Surface.separator).padding(.leading, Theme.Space.xs)
                        }
                        HStack {
                            Text(name)
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.Text.secondary)
                            Spacer()
                            Text("Soon")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.Text.tertiary)
                        }
                        .padding(.vertical, Theme.Space.sm)
                        .padding(.horizontal, Theme.Space.xs)
                    }
                }
            }
        }
    }
}
