import AIKeyboardCore
import SwiftUI

/// The "All languages" search field and grouped language list.
///
/// Owns `query` state so the search field is local to this section.
/// Toggle behaviour is driven through `SharedStore` from the environment.
struct LanguageCatalogueSection: View {
    @EnvironmentObject private var store: SharedStore
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "All languages")

            searchField

            if matches.isEmpty {
                Card(padding: Theme.Space.xs) {
                    Text("No language matches \u{201C}\(query)\u{201D}.")
                        .font(Theme.Fonts.callout)
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

    // MARK: Search field

    private var searchField: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Text.tertiary)

            TextField("Search \(KeyboardLanguage.allCases.count) languages", text: $query)
                .font(Theme.Fonts.body)
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

    // MARK: Script groups

    /// One run of the catalogue, all written in the same script.
    private struct ScriptGroup {
        let script: TextScript
        let languages: [KeyboardLanguage]
    }

    /// **A flat list of sixty-four rows is what iOS Settings shows, and it is not
    /// what this screen needs.** Grouping by script answers the question a long
    /// list raises — Serbian appears twice and the headings are the only thing
    /// that says why — and it costs no reordering, because the groups come out in
    /// catalogue order and English still leads the first of them.
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
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text("\(group.script.displayName) · \(group.languages.count)")
                .font(Theme.Fonts.micro.weight(.semibold))
                .foregroundStyle(Theme.Text.tertiary)
                .padding(.leading, Theme.Space.xs)
                .accessibilityLabel("\(group.script.displayName), \(group.languages.count) languages")

            Card(padding: Theme.Space.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(group.languages.enumerated()), id: \.element.id) {
                        index, language in
                        if index > 0 {
                            Divider.themed
                                .padding(.leading, 46)
                        }
                        languageRow(for: language)
                    }
                }
            }
        }
    }

    // MARK: Language row

    /// Matches on the English name, the native name, the language tag and the
    /// script, so "greek", "Ελληνικά", "el" and "cyrillic" all find rows.
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

    private func languageRow(for language: KeyboardLanguage) -> some View {
        let isOn = store.enabledLanguages.contains(language)

        return HStack(spacing: Theme.Space.sm) {
            Text(language.flag)
                .font(.system(size: 24))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(language.nativeName)
                    .font(Theme.Fonts.body.weight(.medium))
                    .foregroundStyle(Theme.Text.primary)
                Text(subtitle(for: language))
                    .font(Theme.Fonts.caption)
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
            store.toggleEnabledLanguage(language)
        }
    }
}
