import SwiftUI
import AIKeyboardCore

struct LanguagesView: View {
    @EnvironmentObject private var store: SharedStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var query = ""

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
                        catalogueSection
                        codeSwitchingCard
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

    // MARK: Active

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

    // MARK: The catalogue

    private var catalogueSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "All languages")

            searchField

            if matches.isEmpty {
                Card(padding: Theme.Space.xs) {
                    Text("No language matches “\(query)”.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Text.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.sm)
                }
            } else {
                ForEach(scriptGroups, id: \.script) { group in
                    scriptGroup(group)
                }
            }
        }
    }

    /// One run of the catalogue, all written in the same script.
    private struct ScriptGroup {
        let script: TextScript
        let languages: [KeyboardLanguage]
    }

    /// **A flat list of sixty-four rows is what iOS Settings shows, and it is not
    /// what this screen needs.** iOS can be flat because its rows are the only
    /// thing on the screen and it has a search field of its own; here the list
    /// sits under two other cards inside a scroll view. Grouping by script is the
    /// cut that answers the question a long list raises — Serbian appears twice
    /// and the headings are the only thing that says why — and it costs no
    /// reordering, because the groups come out in catalogue order and English
    /// still leads the first of them.
    private var scriptGroups: [ScriptGroup] {
        var order: [TextScript] = []
        var byScript: [TextScript: [KeyboardLanguage]] = [:]
        for language in matches {
            if byScript[language.script] == nil { order.append(language.script) }
            byScript[language.script, default: []].append(language)
        }
        return order.map { ScriptGroup(script: $0, languages: byScript[$0] ?? []) }
    }

    private func scriptGroup(_ group: ScriptGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(group.script.displayName) · \(group.languages.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Text.tertiary)
                .padding(.leading, Theme.Space.xs)
                .accessibilityLabel("\(group.script.displayName), \(group.languages.count) languages")

            Card(padding: Theme.Space.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(group.languages.enumerated()), id: \.element.id) {
                        index, language in
                        if index > 0 {
                            Divider()
                                .overlay(Theme.Surface.separator)
                                .padding(.leading, 46)
                        }
                        row(for: language)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Text.tertiary)

            TextField("Search \(KeyboardLanguage.allCases.count) languages", text: $query)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Text.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("language-search")

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.Text.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Surface.raised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.Surface.separator, lineWidth: 1)
        )
    }

    /// Matches on the English name, the native name, the language tag and the
    /// script, so "greek", "Ελληνικά", "el" and "cyrillic" all find rows — the
    /// last of those because with six Cyrillic keyboards and thirty-eight Latin
    /// ones, "which of these is my script" is a question the list has to answer.
    private var matches: [KeyboardLanguage] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return KeyboardLanguage.allCases }
        return KeyboardLanguage.allCases.filter { language in
            [
                language.displayName, language.nativeName, language.languageTag,
                language.shortName, language.script.displayName
            ]
            .contains {
                $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
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
                Text(subtitle(for: language))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Text.secondary)
            }

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { isOn },
                    set: { _ in toggle(language) }
                )
            )
            .labelsHidden()
            .disabled(isOn && store.enabledLanguages.count == 1)
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.horizontal, Theme.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(language.displayName)
    }

    /// The English name plus the two facts that change how the keyboard behaves:
    /// which way it runs, and whether Apple has a dictionary for it.
    private func subtitle(for language: KeyboardLanguage) -> String {
        var parts = [language.displayName]
        if language.isRightToLeft { parts.append("right to left") }
        if language.spellCheckerLocale == nil { parts.append("no spellcheck") }
        return parts.joined(separator: " · ")
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

                    Text(
                        "Predictions look at the whole sentence, not the current layout. Type a Latin word inside a Hebrew sentence and the suggestions follow you."
                    )
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
}
