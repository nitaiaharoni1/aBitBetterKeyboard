import SwiftUI

/// The emoji search box, drawn where the three word candidates normally are.
///
/// **It takes the suggestion bar's row rather than adding one, and the keyboard's
/// height is why.** The whole keyboard is capped at 364 pt by the screen-context
/// fingerprint (`.claude/rules/keyboard-layout.md`), so a search row of its own
/// would have come out of the grid — three rows of emoji instead of five. While
/// the grid is open the candidates have nothing to say anyway: nobody is typing a
/// word.
struct EmojiSearchField: View {

    @ObservedObject var controller: KeyboardController

    /// True once the box has been tapped and the letters are back.
    var isEditing: Bool { controller.overlay == .emojiSearch }

    @State private var caretVisible = true

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Glyph.font(15))
                .foregroundStyle(Theme.Keys.secondaryLabel)

            content

            Spacer(minLength: 0)

            if isEditing {
                Button {
                    controller.show(.emoji)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Theme.Glyph.font(16))
                        .foregroundStyle(Theme.Keys.secondaryLabel)
                        .contentShape(Rectangle())
                }
                .pressable()
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Keys.letter)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { controller.show(.emojiSearch) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emoji-search-field")
    }

    @ViewBuilder
    private var content: some View {
        if controller.emojiQuery.isEmpty {
            Text("Search emoji")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.Keys.secondaryLabel)
            caret
        } else {
            // Renders in its own direction — a Hebrew query reads right to left
            // inside the box while the box itself stays put, the same rule the
            // candidates next to it follow.
            Text(controller.emojiQuery)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.Keys.label)
                .lineLimit(1)
            caret
        }
    }

    @ViewBuilder
    private var caret: some View {
        if isEditing {
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.Brand.solid)
                .frame(width: 2, height: 20)
                .opacity(caretVisible ? 1 : 0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                        caretVisible = false
                    }
                }
        }
    }
}

/// The matches for a search, in the band the action row normally occupies.
///
/// **Below the keys, not beside the box, and there was nowhere else.** Search
/// needs three things on screen at once — what was typed, the letters to type it
/// with, and the results — and at 364 pt the keyboard has room for exactly the
/// bands it already has. The letters take 204 of them.
struct EmojiResultsStrip: View {

    @ObservedObject var controller: KeyboardController
    let height: CGFloat

    var body: some View {
        Group {
            if controller.emojiQuery.isEmpty {
                // Nothing typed yet: the recents are a better opening than an
                // empty band, and they are what the user reaches for most.
                strip(controller.recentEmoji)
            } else if controller.emojiResults.isEmpty {
                Text("No emoji for \u{201C}\(controller.emojiQuery)\u{201D}")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.Keys.secondaryLabel)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            } else {
                strip(controller.emojiResults)
            }
        }
        .frame(height: height)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func strip(_ emoji: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(emoji, id: \.self) { character in
                    Button {
                        controller.insertEmoji(character)
                    } label: {
                        Text(character)
                            .font(.system(size: height * 0.62))
                            .frame(width: height, height: height)
                            .contentShape(Rectangle())
                    }
                    .pressable(scale: 0.85)
                    .accessibilityLabel(EmojiCatalog.names(for: character).first ?? character)
                }
            }
        }
        .accessibilityIdentifier("emoji-search-results")
    }
}
