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

    /// Handed down from `KeyboardView` rather than read again here.
    ///
    /// `KeyboardView.orientation` is the one place that decides what landscape
    /// is, from `verticalSizeClass`, and everything that sheds a row in landscape
    /// already reads it: the banner, the key grid, and the panel that has to be
    /// closed on the way in. A second read in this file would be a second thing
    /// that can disagree with the height published to the host, which is exactly
    /// the drift `Theme.Metrics.landscapeLayout(basedOn:)` exists to prevent
    /// between the published height and the rows drawn.
    let orientation: KeyboardGeometry.Orientation

    public init(
        controller: KeyboardController,
        orientation: KeyboardGeometry.Orientation = .portrait
    ) {
        self.controller = controller
        self.orientation = orientation
    }

    /// The row this bar draws in, for one orientation.
    ///
    /// **The two orientations budget different numbers and the view used to know
    /// only one of them.** `Theme.Metrics.totalHeight(for:showsBanner:orientation:)`
    /// pays 30 pt for the bar in landscape and 36 in portrait, and this file
    /// drew the portrait figure in both — so the landscape keyboard drew 6 pt
    /// more than the height it asked the host for, on a form whose whole margin
    /// against the fingerprint cap is about 3 pt. Everything the bar hosts in
    /// landscape is free only because this number is the one that was already
    /// paid for; read it from here rather than spelling 36 again.
    public static func barHeight(for orientation: KeyboardGeometry.Orientation) -> CGFloat {
        orientation == .landscape
            ? Theme.Metrics.Landscape.suggestionBarHeight : Theme.Metrics.suggestionBarHeight
    }

    var barHeight: CGFloat { Self.barHeight(for: orientation) }

    public var body: some View {
        // **Landscape keeps the action strip while a panel is up, and gives up
        // the search box to do it.** Both panels hide every letter key, and in
        // landscape the row carrying the key that closes them is shed — so a bar
        // that turned itself into a search box would be a grid with no way out,
        // which is the trap `KeyboardController.closeOverlayForLandscape` exists
        // for, arriving through the new door this strip opens. Search needs the
        // query, an alphabet and the results on screen at once and landscape has
        // room for two of the three; the way out is the half that cannot be
        // dropped, so the lit Emoji or CopyClip chip is what stands here instead.
        // The candidates go with the box for the reason they always do: nobody is
        // typing a word while a grid is open.
        if orientation == .landscape, controller.overlay.isEmoji || controller.overlay.isCopyClip {
            landscapePanelBar
        } else if controller.overlay.isCopyClip {
            // The bar becomes the CopyClip search box for as long as the list
            // is open. Same height trade as emoji: see `CopyClipBar`.
            CopyClipBar(controller: controller)
                .frame(height: barHeight)
                .padding(.horizontal, Theme.Space.xxs)
                .environment(\.layoutDirection, .leftToRight)
        } else if controller.overlay.isEmoji {
            // The bar becomes the emoji search box for as long as the grid is
            // open. Not an extra row: see `EmojiSearchField` for the height that
            // is not available to spend.
            EmojiSearchField(controller: controller)
                .frame(height: barHeight)
                .padding(.horizontal, Theme.Space.xxs)
                .environment(\.layoutDirection, .leftToRight)
        } else {
            candidates
        }
    }

    /// The landscape bar with a panel open: every control the bar can draw, and
    /// no words beside them.
    ///
    /// **All three groups, not just the strip, because any of them can be the way
    /// out.** A user is free to clear their action row and keep Emoji on a bar
    /// edge instead — `landscapeActions(for:)` then deduplicates it out of the
    /// strip, and a version of this that drew the strip alone would open a panel
    /// from a chip and then stop drawing that chip. The rule between the groups
    /// is dropped: with no candidates between them there is nothing to separate.
    private var landscapePanelBar: some View {
        HStack(spacing: 0) {
            ForEach(Self.landscapePanelControls(for: controller.customization)) { slot in
                slotButton(slot.action)
            }
            Spacer(minLength: 0)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: barHeight)
        .padding(.horizontal, Theme.Space.xxs)
    }

    /// The action row's keys, drawn as chips, for as long as landscape is
    /// shedding the row that held them.
    ///
    /// **Inline rather than folded behind one affordance, and the width is the
    /// argument.** Landscape is short and wide: an iPhone 17 Pro rotated is 402
    /// pt tall and 874 wide, and every point of the height is already spoken for
    /// while the width is the axis nothing competes over. Five 44 pt chips and a
    /// rule cost 229 of those 874 points, which still leaves each of the three
    /// candidates about **194 pt against the 113** the same candidate gets in
    /// portrait — so the actions arrive and the words read wider than they do on
    /// the keyboard this is being compared against. On the narrowest phone this
    /// ships to (a 667 pt landscape) it is about 125 pt a candidate against that
    /// same phone's portrait 104. A drawer would have cost a tap, and worse, it
    /// would have hidden *which* actions exist from the one person who does not
    /// know yet: somebody who has just rotated and found the row gone.
    ///
    /// The chips are 44 pt wide, the full portrait target: width is what
    /// landscape has. Only their height comes down, and `chipSize(for:)` is
    /// where.
    @ViewBuilder
    var landscapeActionStrip: some View {
        // Same order the action row had them in, drawn through the same
        // `slotButton` every other configured control goes through, so a control
        // cannot behave differently for having been rotated into.
        ForEach(Self.landscapeActions(for: controller.customization)) { slot in
            slotButton(slot.action)
        }
    }

    private var candidates: some View {
        let landscapeActions = Self.landscapeActions(for: controller.customization)
        return HStack(spacing: 0) {
            // **In landscape the action row's keys are here, before the user's
            // own leading end.** That row is shed at 402 pt of screen height (see
            // `Theme.Metrics.landscapeLayout(basedOn:)`) and every control on it
            // went with it, so five things a user reached for in portrait simply
            // stopped existing when they turned the phone. The bar's row is
            // already paid for, which is why this costs the keyboard's total
            // height nothing at all — the one currency landscape has none of.
            if orientation == .landscape, !landscapeActions.isEmpty {
                landscapeActionStrip
                separator
            }

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
            // directly above the keys.
            //
            // **It used to last exactly one keystroke and now outlives ordinary
            // typing**, because a wrong word is noticed in the sentence it landed
            // in rather than before the next one is typed (NIT-154). It costs the
            // three candidates about 52pt of the bar for as long as it is up, which
            // is what `RevertibleEdit.charactersOfTypingAllowed` is a bound on:
            // that number is about this row, and the exactness of the undo itself
            // is `rebased(onto:)` and `spanUndo(behind:)`.
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
        .frame(height: barHeight)
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
    /// find the keystrokes. Only the drawing order changes here.
    private var suggestions: some View {
        // `wordUnderConsideration`, not `currentWordPrefix`: the echo the bar
        // drops is whatever the engine was scored on, and for a selected word
        // that is the selection. Drawing it would spend a slot on a tap that
        // replaces a word with itself.
        let slots = Self.centeredSlots(
            controller.suggestions, typed: controller.wordUnderConsideration)
        // Asked once for the whole row rather than per slot: it is a call into
        // the host, and the three candidates are three evaluations of `candidate`.
        let overSelectedWord = controller.selectedWord != nil
        return HStack(spacing: 0) {
            ForEach(0..<SuggestionEngine.barSlots, id: \.self) { slot in
                if slot > 0 { candidateSeparator }
                if let suggestion = slots[slot] {
                    candidate(suggestion, replacesSelection: overSelectedWord)
                        .accessibilityIdentifier("suggestion-\(slot)")
                } else {
                    // `barHeight`, not a repeated 36: a floor taller than the row
                    // it sits in is a bar that draws past the height the keyboard
                    // published, which in landscape is the whole margin against
                    // the fingerprint cap.
                    Color.clear.frame(maxWidth: .infinity, minHeight: barHeight)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Visual order for the three candidate slots: default in the middle, the
    /// others on either side, a lone word centered rather than hugging the left.
    ///
    /// **The word already in the field is drawn when the bar is completing it
    /// and dropped when the bar is correcting it.** Mid-word the engine pins
    /// those keystrokes at index 0 and marks them default whenever nothing is
    /// going to replace them, so the echo is the answer to the question this row
    /// exists to answer — and leaving it out meant that typing `hello` correctly
    /// produced **no bold slot at all**: the default was on the word that had
    /// just been filtered out, `firstIndex(where: \.isDefault) ?? 0` fell through
    /// to a candidate carrying `isDefault == false`, and `candidate(_:)` draws
    /// that `.light` with no `accessibilityHint`. The row that says what space
    /// will do said nothing, about the one word it could have said it about.
    ///
    /// **Being the default is not enough on its own, and a Hebrew typo is why.**
    /// `תדוה` and `טןב` are misspellings Apple's Hebrew checker calls real words,
    /// so `commitReason` deliberately declines to commit `תודה` and `טוב`
    /// and leaves the default on the keystrokes — at which point boldening the
    /// echo is a keyboard endorsing a typo it is holding the fix for, and
    /// pushing that fix out of the middle to do it. The second question is
    /// therefore whether anything on offer *continues* the keystrokes: a
    /// completion agrees with every key that was pressed, so its presence is the
    /// bar saying the word is still being typed, while a bar holding corrections
    /// alone is saying the opposite. Measured over 44 inputs through the real
    /// engine, that line lands on every one of them — `cat`, `dog`, `בית`, `אני`
    /// and `מכונ` all carry a continuation, while `תדוה`, `טןב` and `qwt` carry
    /// nothing but a correction. A word with no offers at all keeps its slot:
    /// `כן`, `תודה` and `עכשיו` have no completions in any dictionary here, and
    /// an empty bar is not an answer.
    ///
    /// **The continuation is looked for in every candidate, including the one
    /// that will not fit.** `מכונ` on the way to `מכונית` arrives as `[מכונ*,
    /// נכון, מוכן, מכונה]`, so the completion holding its slot open is the fourth
    /// candidate and is pushed off the bar by the echo it justifies. That is the
    /// right way round: whether the word is still being typed is something the
    /// engine knows, and deciding it from the drawn slots instead would be
    /// circular, since whether the echo is drawn is what changes them.
    ///
    /// An empty prefix is next-word, so nothing is filtered.
    static func centeredSlots(_ items: [Suggestion], typed: String = "") -> [Suggestion?] {
        SuggestionSlotOrder.centeredSlots(items, typed: typed)
    }

    /// The three candidates are the bar's primary content, so they get real
    /// room to grow — capped at 70% of the row they are drawn in, which is
    /// fixed at 36pt in portrait (see `.claude/rules/suggestion-bar.md`) and
    /// 30 in landscape, and stays that way regardless of Dynamic Type, so the
    /// growth has to go somewhere within it rather than push the row taller.
    /// `.minimumScaleFactor(0.75)` below already absorbs a long word at the
    /// larger size; it existed before this for the same reason, on a long
    /// completion at the shipped size.
    ///
    /// **The cap takes the row rather than naming it**, because landscape's row
    /// is 6 pt shorter and a cap read off the portrait constant would let
    /// accessibility text grow past the height the keyboard published. It
    /// defaults to portrait so every existing caller keeps today's answer.
    static func candidateFontSize(
        for dynamicTypeSize: DynamicTypeSize,
        barHeight: CGFloat = Theme.Metrics.suggestionBarHeight
    ) -> CGFloat {
        min(17 * Theme.DynamicType.scale(for: dynamicTypeSize), barHeight * 0.7)
    }

    private func candidate(_ suggestion: Suggestion, replacesSelection: Bool = false) -> some View {
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
                        size: Self.candidateFontSize(
                            for: dynamicTypeSize, barHeight: barHeight),
                        weight: suggestion.isDefault ? .bold : .light)
                )
                .foregroundStyle(Theme.Keys.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, Theme.Space.xxs)
                .frame(maxWidth: .infinity, minHeight: barHeight)
                .contentShape(Rectangle())
        }
        .pressable(scale: 0.94)
        .accessibilityLabel(suggestion.text)
        // **Three states, three sentences.** Over a selected word nothing is the
        // default — space types a space over a range — so a bar that only ever
        // explained the bold slot read out three bare words with no hint that any
        // of them would land on the word the user had just selected. Same rule the
        // microphone key is under: a control that gains a state gains a sentence.
        .accessibilityHint(Self.candidateHint(suggestion, replacesSelection: replacesSelection))
    }

    static func candidateHint(_ suggestion: Suggestion, replacesSelection: Bool) -> String {
        if case .replaceSuffix = suggestion.commit { return "Repairs a misplaced space" }
        if replacesSelection { return "Replaces the selected word" }
        return suggestion.isDefault ? "Inserted when you press space" : ""
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
