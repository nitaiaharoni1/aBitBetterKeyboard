import SwiftUI

/// The strip above the keys: emoji on one edge, the AI sparkle on the other, and
/// three candidates between them.
///
/// Emoji and sparkle live here rather than in the bottom row on purpose. Both are
/// about text you are looking at, not keys you are pressing, and it leaves the
/// bottom row close to the system layout where muscle memory expects it.
public struct SuggestionBar: View {

    @ObservedObject var controller: KeyboardController
    /// Observed so the one-tap button re-tints the moment the tone is changed in
    /// Settings. Only within one process: the keyboard is a second process and
    /// nothing notifies it, which is why `KeyboardController.defaultTone` reads the
    /// store at the moment of the tap rather than trusting what is drawn here.
    @ObservedObject private var store: SharedStore = .shared
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        if controller.overlay.isCopyClip {
            // The bar becomes the CopyClip search box for as long as the list
            // is open. Same height trade as emoji: see `CopyClipBar`.
            CopyClipBar(controller: controller)
                .frame(height: Theme.Metrics.suggestionBarHeight)
                .padding(.horizontal, Theme.Space.xxs)
                .environment(\.layoutDirection, .leftToRight)
        } else if controller.overlay.isEmoji {
            // The bar becomes the emoji search box for as long as the grid is
            // open. Not an extra row: see `EmojiSearchField` for the height that
            // is not available to spend.
            EmojiSearchField(controller: controller)
                .frame(height: Theme.Metrics.suggestionBarHeight)
                .padding(.horizontal, Theme.Space.xxs)
                .environment(\.layoutDirection, .leftToRight)
        } else {
            candidates
        }
    }

    private var candidates: some View {
        HStack(spacing: 0) {
            // Both ends are configured in the layout editor. The three controls
            // that shipped are still the default, and each keeps its own view
            // below: what moved is which ones are drawn and where, never how they
            // behave. Controls in the same group sit together with no rule between
            // them, because one of them runs the default tone outright and the
            // other opens the menu holding everything that still needs a choice.
            ForEach(controller.customization.barLeading) { slot in
                slotButton(slot.action)
            }

            if !controller.customization.barLeading.isEmpty { separator }

            suggestions

            // **The way back from a Fix, a Rewrite or a Reply.** All three write
            // their answer straight into the field (see
            // `KeyboardController.applyDirectly`), so the undo has to live where the
            // user is already looking when the text changes under them — the row
            // directly above the keys. It lasts until the next keystroke and costs
            // the three candidates about 52pt of the bar for that long, which is
            // the right trade while the last thing that happened to the field is an
            // edit the keyboard made rather than a word the user is typing.
            if controller.revertibleEdit != nil {
                separator
                revertButton
            }

            if !controller.customization.barTrailing.isEmpty { separator }

            ForEach(controller.customization.barTrailing) { slot in
                slotButton(slot.action)
            }
        }
        // **Nothing in this bar swaps sides when the language does — not the
        // buttons and not the words.** It sits inside `KeyboardView`, which runs
        // in the language's own direction, so on Hebrew the emoji key jumped to
        // the right and the two AI buttons to the left; a swipe along the space
        // bar moves between languages, so they jumped mid-use. The candidates
        // then kept their own right-to-left arrangement for a while longer, on
        // the argument that words should read the way the language does — but the
        // three slots are targets a thumb learns, and the same slide that moves
        // the language would have moved the word under it. Every other row is
        // pinned for that reason already: the key rows and bottom row in
        // `KeyboardView`, the alternates popup and the space bar's own strip in
        // `KeyView`, the dots in `LanguageCallout`, and the swipe direction itself
        // in `SpaceSwipe.language`. A Hebrew word still renders right to left
        // inside its own slot; that is the text engine's business and is
        // untouched by this.
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: Theme.Metrics.suggestionBarHeight)
        .padding(.horizontal, Theme.Space.xxs)
        // The revert control arrives with an answer already in the field, so it
        // fades in rather than appearing between two frames beside three candidate
        // slots that emptied in the same moment. The words themselves do not
        // animate: a fresh `UUID` on every refresh used to make this bar fade
        // for 180ms on every letter, a beat behind the fingers. See `Suggestion`.
        .animation(Theme.Motion.content, value: controller.revertibleEdit)
    }

    // MARK: Candidates

    /// Always three slots of equal width, in the same three places in every
    /// language. A single candidate stretched across the whole bar reads as a
    /// banner rather than as a word you can tap.
    ///
    /// **The default sits in the middle, even when the engine left it at index
    /// 0.** Mid-word the array is still `[typed, best, next]` so the refiner can
    /// find the keystrokes. The typed echo is not drawn: it is already in the
    /// field. Only the drawing order changes here.
    private var suggestions: some View {
        let slots = Self.centeredSlots(
            controller.suggestions, typed: controller.currentWordPrefix)
        return HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { slot in
                if slot > 0 { candidateSeparator }
                if let suggestion = slots[slot] {
                    candidate(suggestion)
                        .accessibilityIdentifier("suggestion-\(slot)")
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 36)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Visual order for the three candidate slots: default in the middle, the
    /// others on either side, a lone word centered rather than hugging the left.
    ///
    /// **The word already in the field is not an offer.** Mid-word the engine
    /// still pins those keystrokes at index 0. Drawing them spent a slot on a
    /// tap that types nothing new. Completions and corrections stay. An empty
    /// prefix is next-word, so nothing is filtered.
    static func centeredSlots(_ items: [Suggestion], typed: String = "") -> [Suggestion?] {
        var slots: [Suggestion?] = [nil, nil, nil]
        let offers: [Suggestion]
        if typed.isEmpty {
            offers = items
        } else {
            let key = SuggestionEngine.comparable(typed)
            // "" is a prefix of every word. Equality against it would drop
            // nothing useful and is the same trap `comparable`'s other
            // callers already guard. A punctuation-only echo still matches
            // by the raw keystrokes.
            offers =
                key.isEmpty
                ? items.filter { $0.text != typed }
                : items.filter { SuggestionEngine.comparable($0.text) != key }
        }
        guard !offers.isEmpty else { return slots }
        let defaultIndex = offers.firstIndex(where: \.isDefault) ?? 0
        slots[1] = offers[defaultIndex]
        let others = offers.indices.filter { $0 != defaultIndex }.map { offers[$0] }
        if others.count > 0 { slots[0] = others[0] }
        if others.count > 1 { slots[2] = others[1] }
        return slots
    }

    /// The three candidates are the bar's primary content, so they get real
    /// room to grow — capped at 70% of `suggestionBarHeight`, which is fixed
    /// at 36pt (see `.claude/rules/suggestion-bar.md`) and stays that way
    /// regardless of Dynamic Type, so the growth has to go somewhere within
    /// it rather than push the row taller. `.minimumScaleFactor(0.75)` below
    /// already absorbs a long word at the larger size; it existed before this
    /// for the same reason, on a long completion at the shipped size.
    static func candidateFontSize(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        min(17 * Theme.DynamicType.scale(for: dynamicTypeSize), Theme.Metrics.suggestionBarHeight * 0.7)
    }

    private func candidate(_ suggestion: Suggestion) -> some View {
        Button {
            controller.apply(suggestion)
        } label: {
            // The word alone. A candidate coming from the other language used to
            // carry a small `LanguageTag` beside it, which is a badge on the one
            // control in the bar that has to be read at a glance mid-word: the
            // word is already written in its own script, so the tag repeats what
            // the letters say and costs the room they are read in.
            Text(suggestion.text)
                .font(
                    .system(
                        size: Self.candidateFontSize(for: dynamicTypeSize),
                        weight: suggestion.isDefault ? .bold : .light)
                )
                .foregroundStyle(Theme.Keys.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, Theme.Space.xxs)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .pressable(scale: 0.94)
        .accessibilityLabel(suggestion.text)
        .accessibilityHint(suggestion.isDefault ? "Inserted when you press space" : "")
    }

    // MARK: Rules

    private var separator: some View {
        Rectangle()
            .fill(Theme.Keys.secondaryLabel.opacity(0.22))
            .frame(width: 1, height: 22)
            .padding(.horizontal, Theme.Space.xxs)
    }

    private var candidateSeparator: some View {
        Rectangle()
            .fill(Theme.Keys.secondaryLabel.opacity(0.18))
            .frame(width: 1, height: 18)
    }
}

// MARK: - Previews

#if DEBUG

/// Candidates are set directly rather than through `refreshSuggestions()` so
/// the canvas shows the same three words every time. The engine still pins
/// the typed echo at index 0; the bar does not draw it. The middle slot is
/// the one a space press commits, when that offer is the default.
private struct SuggestionBarPreviewHost: View {
    @StateObject private var controller: KeyboardController

    init(language: KeyboardLanguage, text: String, suggestions: [Suggestion]) {
        let preview = KeyboardController.preview(language: language, text: text)
        preview.suggestions = suggestions
        _controller = StateObject(wrappedValue: preview)
    }

    var body: some View {
        SuggestionBar(controller: controller)
            .background(Theme.Keys.background)
    }
}

#Preview("English") {
    SuggestionBarPreviewHost(
        language: .english,
        text: "the quick brown fo",
        suggestions: [
            Suggestion(text: "fo", language: .english),
            Suggestion(text: "for", language: .english, isDefault: true),
            Suggestion(text: "fox", language: .english)
        ])
}

/// The candidate slots do **not** mirror in Hebrew: they are targets a thumb
/// learns, and language changes on a space-bar swipe. The typed echo `שלו`
/// is not drawn. `שלום` sits in the middle. See
/// `.claude/rules/keyboard-layout.md`.
#Preview("Hebrew") {
    SuggestionBarPreviewHost(
        language: .hebrew,
        text: "שלו",
        suggestions: [
            Suggestion(text: "שלו", language: .hebrew),
            Suggestion(text: "שלום", language: .hebrew, isDefault: true),
            Suggestion(text: "שלוש", language: .hebrew)
        ])
}

#endif
