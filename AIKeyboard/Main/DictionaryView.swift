import SwiftUI
import AIKeyboardCore

/// Names the user added by hand, and words this keyboard inferred from typing.
/// Two stores, one screen. Adding a name never-corrects it. A typed word only
/// changes ranking after two sightings. Forget wipes the inferred list only.
struct DictionaryView: View {
    @EnvironmentObject private var store: SharedStore
    @Environment(\.scenePhase) private var scenePhase

    /// Measured for `FullAccessNeededBanner`: the keyboard reads
    /// `storedPersonalDictionary` through `UserDefaults` at the moment of the
    /// keystroke, so without Full Access it falls back to its own process-local
    /// copy — `SharedStore.shippedPersonalDictionary` — and every name added
    /// here is autocorrected away while this editor counts it and reports
    /// success. Re-read on every return to the foreground, like `KeysView`'s
    /// copy, because the switch is thrown in Settings and nothing notifies the
    /// app.
    @State private var setup = SetupState()
    @State private var newWord = ""
    @State private var learned: [LearnedWord] = []
    @State private var query = ""
    @State private var confirmForget = false
    @State private var expandedLanguages: Set<String> = []
    @FocusState private var isAdding: Bool

    /// Rows of one language's inferred list drawn before the "Show all" row.
    ///
    /// **Every language after the first was unreachable without this.** The
    /// sections are ordered by `KeyboardLanguage.allCases`, so a bilingual user
    /// with 267 English words had to scroll past all 267 of them to find out
    /// whether the keyboard had learned a single Hebrew one — and the answer to
    /// "does it remember Hebrew" is the whole reason this list is on screen. The
    /// cap is per language, so the head of every section is visible at once and
    /// the count in the header is still the true total.
    private static let collapsedRowCount = 12

    /// Mirrors `SetupState.languagesNeedFullAccess`'s hedge: `setup.fullAccess`
    /// can only ever *confirm* a yes, so this says "once Full Access is on"
    /// rather than asserting it is off right now. It names what the keyboard
    /// falls back to rather than claiming the save failed, because the save is
    /// real either way and only the reading of it is blocked.
    private static let fullAccessMessage =
        "The keyboard can only read this list once Full Access is on. Words are still saved; until "
        + "then it protects the names it shipped with and autocorrects the rest."

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    if setup.fullAccess != .confirmed {
                        FullAccessNeededBanner(
                            message: Self.fullAccessMessage, context: "dictionary")
                    }
                    addField

                    if isEmpty {
                        emptyState
                    } else {
                        searchField
                        if filteredDictionary.isEmpty, filteredLearned.isEmpty {
                            Text("No words match")
                                .font(Theme.Fonts.callout)
                                .foregroundStyle(Theme.Text.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, Theme.Space.lg)
                        }
                        if !filteredDictionary.isEmpty {
                            addedList
                        }
                        if !filteredLearned.isEmpty {
                            learnedLists
                            caption
                        }
                        if !learned.isEmpty {
                            forgetButton
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle("Personal dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear {
            setup = .current(store: store)
            refreshLearned()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                setup = .current(store: store)
                refreshLearned()
            }
        }
    }

    // MARK: Added words

    private var addField: some View {
        HStack(spacing: Theme.Space.xs) {
            TextField("Add a word or name", text: $newWord)
                .font(Theme.Fonts.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isAdding)
                .onSubmit(add)
                .padding(.horizontal, Theme.Space.sm)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Surface.raised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .strokeBorder(Theme.Surface.separator, lineWidth: 1)
                )

            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Text.onBrand)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .fill(Theme.Brand.action)
                    )
            }
            .pressable()
            .disabled(trimmedWord.isEmpty)
            .opacity(trimmedWord.isEmpty ? 0.45 : 1)
            .accessibilityLabel("Add word")
        }
    }

    private var addedList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            listHeader("Your words", count: filteredDictionary.count)

            Card(padding: Theme.Space.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(filteredDictionary.enumerated()), id: \.element) { index, word in
                        if index > 0 {
                            Divider.themed.padding(.leading, Theme.Space.xs)
                        }
                        wordRow(word, count: nil) { removeAdded(word) }
                    }
                }
            }
        }
    }

    // MARK: Learned words

    private var learnedLists: some View {
        let groups = groupedLearned
        return VStack(alignment: .leading, spacing: Theme.Space.md) {
            ForEach(groups, id: \.language.id) { group in
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    listHeader(
                        groups.count > 1
                            ? "From typing · \(group.language.displayName)"
                            : "From typing",
                        count: group.words.count)
                    let shown = visibleWords(of: group)
                    Card(padding: Theme.Space.xs) {
                        VStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) {
                                index, word in
                                if index > 0 {
                                    Divider.themed.padding(.leading, Theme.Space.xs)
                                }
                                wordRow(word.word, count: word.count) { forgetLearned(word) }
                            }
                            if shown.count < group.words.count || isExpanded(group.language) {
                                Divider.themed.padding(.leading, Theme.Space.xs)
                                expandRow(for: group)
                            }
                        }
                    }
                }
            }
        }
    }

    private func isExpanded(_ language: KeyboardLanguage) -> Bool {
        expandedLanguages.contains(language.languageTag)
    }

    /// A search has already narrowed the list to something a person asked for, so
    /// it is never capped; an unsearched section is.
    private func visibleWords(
        of group: (language: KeyboardLanguage, words: [LearnedWord])
    ) -> [LearnedWord] {
        guard needle.isEmpty, !isExpanded(group.language) else { return group.words }
        return Array(group.words.prefix(Self.collapsedRowCount))
    }

    private func expandRow(
        for group: (language: KeyboardLanguage, words: [LearnedWord])
    ) -> some View {
        let expanded = isExpanded(group.language)
        return Button {
            Feedback.modifierPress()
            withAnimation(Theme.Motion.quick) {
                if expanded {
                    expandedLanguages.remove(group.language.languageTag)
                } else {
                    expandedLanguages.insert(group.language.languageTag)
                }
            }
        } label: {
            HStack(spacing: Theme.Space.xxs) {
                Text(expanded ? "Show fewer" : "Show all \(group.words.count)")
                    .font(Theme.Fonts.body)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.Brand.action)
            .padding(.vertical, Theme.Space.sm)
            .padding(.horizontal, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func listHeader(_ title: String, count: Int) -> some View {
        Text("\(title) (\(count))")
            .font(Theme.Fonts.callout)
            .foregroundStyle(Theme.Text.secondary)
            .padding(.horizontal, Theme.Space.xxs)
    }

    private func wordRow(_ word: String, count: Int?, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(word)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Text.primary)
            Spacer(minLength: Theme.Space.sm)
            if let count {
                Text("\(count)")
                    .font(Theme.Fonts.body.monospacedDigit())
                    .foregroundStyle(Theme.Text.secondary)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Text.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(count == nil ? "Remove \(word)" : "Forget \(word)")
        }
        .padding(.vertical, Theme.Space.sm)
        .padding(.horizontal, Theme.Space.xs)
    }

    private var caption: some View {
        Text("Suggestions use a typed word after 2 times. Names you add are never corrected.")
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Space.xxs)
    }

    private var forgetButton: some View {
        Button(role: .destructive) {
            confirmForget = true
        } label: {
            HStack(spacing: Theme.Space.sm) {
                IconBadge(systemName: "trash", tint: Theme.Semantic.record)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Forget what it learned")
                        .font(Theme.Fonts.body)
                    Text("Keeps the names you added")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Text.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Semantic.record)
        .padding(.top, Theme.Space.sm)
        .confirmationDialog(
            "Forget what it learned?",
            isPresented: $confirmForget,
            titleVisibility: .visible
        ) {
            Button("Forget \(learned.count) words", role: .destructive) {
                PersonalLanguageModel.shared.clear()
                learned = []
                query = ""
            }
        } message: {
            Text("Removes words remembered from typing. Names you added stay.")
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.Text.tertiary)
                .accessibilityHidden(true)

            TextField("Search words", text: $query)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Text.primary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("dictionary-search")
                .accessibilityLabel("Search words")

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

    private var emptyState: some View {
        VStack(spacing: Theme.Space.xs) {
            DoodleArrow()
                .frame(width: 40, height: 36)
                .rotationEffect(.degrees(-90))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, Theme.Space.xxl)

            Image(systemName: "character.book.closed")
                .font(.system(size: 34))
                .foregroundStyle(Theme.Text.tertiary)
            Text("Nothing here yet")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Text.primary)
            Text("Add a name autocorrect keeps getting wrong. Words you type also show up here.")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxl)
    }

    // MARK: Data

    private var isEmpty: Bool {
        store.personalDictionary.isEmpty && visibleLearned.isEmpty
    }

    private var needle: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A name already in Your words is not listed again under From typing.
    private var visibleLearned: [LearnedWord] {
        learned.filter { word in
            !store.personalDictionary.contains {
                $0.compare(word.word, options: [.caseInsensitive, .diacriticInsensitive])
                    == .orderedSame
            }
        }
    }

    private var filteredDictionary: [String] {
        guard !needle.isEmpty else { return store.personalDictionary }
        return store.personalDictionary.filter {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var filteredLearned: [LearnedWord] {
        guard !needle.isEmpty else { return visibleLearned }
        return visibleLearned.filter {
            $0.word.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var groupedLearned: [(language: KeyboardLanguage, words: [LearnedWord])] {
        let byLanguage = Dictionary(grouping: filteredLearned, by: \.language)
        return KeyboardLanguage.allCases.compactMap { language in
            guard var list = byLanguage[language], !list.isEmpty else { return nil }
            list.sort {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.word < $1.word
            }
            return (language, list)
        }
    }

    private var trimmedWord: String {
        newWord.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let word = trimmedWord
        guard !word.isEmpty, !store.personalDictionary.contains(word) else { return }
        Feedback.success()
        withAnimation(Theme.Motion.quick) {
            store.personalDictionary.insert(word, at: 0)
        }
        newWord = ""
    }

    private func removeAdded(_ word: String) {
        guard let index = store.personalDictionary.firstIndex(of: word) else { return }
        Feedback.modifierPress()
        withAnimation(Theme.Motion.quick) {
            _ = store.personalDictionary.remove(at: index)
        }
    }

    private func forgetLearned(_ word: LearnedWord) {
        Feedback.modifierPress()
        PersonalLanguageModel.shared.forget(word.word, in: word.language)
        withAnimation(Theme.Motion.quick) {
            learned.removeAll { $0.id == word.id }
        }
    }

    private func refreshLearned() {
        PersonalLanguageModel.shared.reload()
        learned = PersonalLanguageModel.shared.learnedWords()
    }
}
