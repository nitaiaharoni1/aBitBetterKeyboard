import SwiftUI
import AIKeyboardCore

struct DictionaryView: View {
    @EnvironmentObject private var store: SharedStore
    @State private var newWord = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        ZStack {
            AmbientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    addField

                    if store.personalDictionary.isEmpty {
                        emptyState
                    } else {
                        wordList
                    }
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle("Personal dictionary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

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

    private var wordList: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            wordsHeader

            Card(padding: Theme.Space.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(store.personalDictionary.enumerated()), id: \.offset) { index, word in
                        if index > 0 {
                            Divider.themed.padding(.leading, Theme.Space.xs)
                        }
                        HStack {
                            Text(word)
                                .font(Theme.Fonts.body)
                                .foregroundStyle(Theme.Text.primary)
                            Spacer()
                            Button {
                                remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(Theme.Text.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(word)")
                        }
                        .padding(.vertical, Theme.Space.sm)
                        .padding(.horizontal, Theme.Space.xs)
                    }
                }
            }
        }
    }

    private var wordsHeader: some View {
        Text("Your words (\(store.personalDictionary.count))")
            .font(Theme.Fonts.callout)
            .foregroundStyle(Theme.Text.secondary)
            .padding(.horizontal, Theme.Space.xxs)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.xs) {
            // The pen pointing back up at the add field: the one doodle this
            // screen gets, and only while there is nothing to list.
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
            Text("Add names, companies and terms autocorrect keeps getting wrong.")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xxl)
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

    private func remove(at index: Int) {
        Feedback.modifierPress()
        withAnimation(Theme.Motion.quick) {
            _ = store.personalDictionary.remove(at: index)
        }
    }
}
