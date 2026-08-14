import SwiftUI
import AIKeyboardCore

/// Names the user added by hand, and words this keyboard inferred from typing.
/// Two stores, one screen. Adding a name never-corrects it. A typed word only
/// changes ranking after two sightings. Forget wipes the inferred list only.
struct DictionaryView: View {
    @EnvironmentObject private var store: SharedStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var newWord = ""
    @State private var learned: [LearnedWord] = []
    @State private var query = ""
    @State private var confirmForget = false
    @FocusState private var isAdding: Bool

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
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
        .onAppear(perform: refreshLearned)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshLearned() }
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
                    Card(padding: Theme.Space.xs) {
                        VStack(spacing: 0) {
                            ForEach(Array(group.words.enumerated()), id: \.element.id) {
                                index, word in
                                if index > 0 {
                                    Divider.themed.padding(.leading, Theme.Space.xs)
                                }
                                wordRow(word.word, count: word.count) { forgetLearned(word) }
                            }
                        }
                    }
                }
            }
        }
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
