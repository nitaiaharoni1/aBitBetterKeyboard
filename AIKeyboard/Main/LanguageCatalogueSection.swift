import AIKeyboardCore
import SwiftUI

/// The "All languages" list, grouped by script.
///
/// Filtering is the header search on `LanguagesView` (the Languages tab), not a
/// second field: `RenderedRowOrderTests.enableArabic` types into
/// `language-search` there and needs the matching toggle to stay on this list.
struct LanguageCatalogueSection: View {
    @EnvironmentObject private var store: SharedStore
    @EnvironmentObject private var search: AppSearch
    /// When set, this is the header search rather than a second field. The
    /// Languages UI test types into `language-search` on that header and
    /// expects the matching toggle to stay on this list.
    var filter = ""
    var hideIfEmpty = false

    var body: some View {
        let rows = Self.matches(for: filter)
        Group {
            if rows.isEmpty {
                if !hideIfEmpty {
                    emptyCard
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionHeader(title: "All languages")
                    ForEach(scriptGroups(in: rows), id: \.script) { group in
                        scriptGroup(group)
                    }
                }
            }
        }
    }

    private var emptyCard: some View {
        Card(padding: Theme.Space.xs) {
            Text("No language matches \u{201C}\(filter)\u{201D}.")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Text.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Space.sm)
        }
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
    private func scriptGroups(in languages: [KeyboardLanguage]) -> [ScriptGroup] {
        var order: [TextScript] = []
        var byScript: [TextScript: [KeyboardLanguage]] = [:]
        for language in languages {
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
    static func matches(for query: String) -> [KeyboardLanguage] {
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
        .id(language.id)
        .background {
            if search.highlightedLanguage == language {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Brand.solid.opacity(0.12))
            }
        }
        .animation(Theme.Motion.quick, value: search.highlightedLanguage)
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
