import SwiftUI

/// The strip above the keys: emoji on one edge, the AI sparkle on the other, and
/// three candidates between them.
///
/// Emoji and sparkle live here rather than in the bottom row on purpose. Both are
/// about text you are looking at, not keys you are pressing, and it leaves the
/// bottom row close to the system layout where muscle memory expects it.
public struct SuggestionBar: View {

    @ObservedObject private var controller: KeyboardController
    /// Observed so the one-tap button re-tints the moment the tone is changed in
    /// Settings. Only within one process: the keyboard is a second process and
    /// nothing notifies it, which is why `KeyboardController.defaultTone` reads the
    /// store at the moment of the tap rather than trusting what is drawn here.
    @ObservedObject private var store: SharedStore = .shared

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
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
    }

    // MARK: Candidates

    /// Always three slots of equal width, in the same three places in every
    /// language. A single candidate stretched across the whole bar reads as a
    /// banner rather than as a word you can tap.
    private var suggestions: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { slot in
                if slot > 0 { candidateSeparator }
                if slot < controller.suggestions.count {
                    candidate(controller.suggestions[slot])
                        .accessibilityIdentifier("suggestion-\(slot)")
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 36)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.Motion.quick, value: controller.suggestions)
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
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.Keys.label)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, Theme.Space.xxs)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(suggestion.isDefault ? Theme.Keys.letter.opacity(0.9) : .clear)
                )
                .contentShape(Rectangle())
        }
        .pressable(scale: 0.94)
        .accessibilityLabel(suggestion.text)
        .accessibilityHint(suggestion.isDefault ? "Inserted when you press space" : "")
    }

    // MARK: Edges

    /// What the bar's two ends may hold.
    ///
    /// A subset of `SlotAction.catalogue`, and the exclusions are the point. A
    /// space bar or a shift key 46 points tall above the letters is not a layout
    /// anybody meant to build. Delete is out for a subtler reason: it is the one
    /// key with an accelerating repeat, and the repeat is wired in `KeyView`,
    /// which does not draw this bar — an edge button would delete once per tap and
    /// look broken beside the real one.
    public static let barCatalogue: [SlotAction] = [
        .emoji, .aiMenu, .quickTone, .dictation, .cursorLeft, .cursorRight,
        .hideKeyboard, .globe
    ]

    /// One configured control.
    ///
    /// The three that shipped keep their own views, unchanged: each carries a
    /// measured decision — the tone button's three-way tap, the sparkle agreeing
    /// with `AIMenuPanel.hasRunnableAction`, the emoji key's active tint.
    /// Everything else is the same tap the grid key makes, so a control cannot
    /// behave differently depending on which of the two places the user put it.
    @ViewBuilder
    func slotButton(_ action: SlotAction) -> some View {
        switch action {
        case .emoji:
            edgeButton(
                systemImage: "face.smiling", label: "Emoji",
                isActive: controller.overlay == .emoji
            ) {
                controller.show(controller.overlay == .emoji ? .none : .emoji)
            }
        case .aiMenu:
            sparkleButton
        case .quickTone:
            toneButton
        default:
            // Guarded rather than defaulted. `keyCap` answers non-nil for every
            // case today, and a `?? .space` here would mean a future gap types a
            // space into the user's message rather than drawing nothing.
            if let cap = action.keyCap(language: controller.language) {
                edgeButton(
                    systemImage: action.glyph ?? "questionmark",
                    label: action.title,
                    isActive: false
                ) {
                    controller.press(cap)
                }
            }
        }
    }

    private func edgeButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Glyph.font(19))
                .foregroundStyle(isActive ? Theme.Brand.solid : Theme.Keys.secondaryLabel)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(isActive ? Theme.Brand.solid.opacity(0.14) : .clear)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier("bar-\(label.lowercased())")
        .accessibilityLabel(label)
    }

    /// Where to send a reader looking for the AI actions, named once.
    ///
    /// For the reason `ToneSetting.settingsNote` gives: a glyph is not a name. The
    /// playground and onboarding both said "tap ✨" while two brand-tinted buttons
    /// sat side by side in this bar — and the default tone's own icon was SF
    /// `sparkle` next to this one's `sparkles`, so the instruction pointed at
    /// whichever of the two the reader looked at first.
    ///
    /// **It now names a row rather than a button, because the buttons moved and
    /// there is more than one of them.** Reply, Fix, Rewrite and dictation are keys
    /// in the action row under the keyboard, and the bar's own ends ship empty. It
    /// deliberately does not say "the sparkle": on a stock install there is no
    /// sparkle, and a user who has put one back in the bar through the layout
    /// editor is not who this copy is written for.
    public static let aiButtonName = "the action row under the keys"

    /// Whether the sparkle opens the AI menu.
    ///
    /// The menu answers this, not the bar. See `AIMenuPanel.hasRunnableAction` for
    /// what the bar used to answer instead and what it cost.
    static func sparkleOpensTheMenu(hasTextToWorkWith: Bool) -> Bool {
        AIMenuPanel.hasRunnableAction(hasTextToWorkWith: hasTextToWorkWith)
    }

    // MARK: One-tap rewrite

    /// What a tap on the one-tap rewrite button does, in every state it has.
    ///
    /// **The point of the enum is that there is no fourth case for "nothing".**
    /// The button shipped `.disabled(!canRun)` with a brand gradient behind a
    /// fully-saturated brand-coloured icon: only the *background* faded, so beside
    /// the fully-lit sparkle it read as live, and on an empty field — which is
    /// most of the time, because a keyboard comes up on an empty field — a tap on
    /// it did nothing at all and said nothing about why.
    enum ToneTap: Equatable {
        case rewrite
        /// Nothing to rewrite. The tap opens the AI menu instead, because that is
        /// the panel this button is a shortcut through: it names the three text
        /// actions and greys them, and it carries Reply, which is the one thing
        /// that *is* available with an empty field. See `AIMenuPanel.isAvailable`.
        case openMenu
        /// A call is already in flight. `beginWork` cancels its predecessor, so a
        /// second tap would throw away the answer being waited on — and this is
        /// the one state where ignoring a tap is honest, because the button is
        /// showing a spinner rather than an icon.
        case ignore
    }

    static func toneTap(hasTextToWorkWith: Bool, isWorking: Bool) -> ToneTap {
        if isWorking { return .ignore }
        return hasTextToWorkWith ? .rewrite : .openMenu
    }

    /// The glyph the one-tap button always wears, whatever the tone is.
    ///
    /// **It is `AIAction.rewrite`'s own icon on purpose.** The button is a
    /// shortcut through the Rewrite row in `AIMenuPanel`, so drawing what that row
    /// draws is the only thing in the bar that says which panel it is short for.
    /// It must not be a sparkle in any count: `SparkleMark` sits against it with no
    /// rule between them, and that pairing has already shipped once — see
    /// `ToneIconTests`.
    static let toneButtonSymbol = AIAction.rewrite.icon

    /// The one-tap button's width, the same for every tone.
    ///
    /// **Fixed rather than grown to fit, because the label under the glyph is a
    /// setting and a button that resizes when a setting changes moves its
    /// neighbours with it.** Letting it size to its text put `Professional` at 67pt
    /// against `Casual`'s 44, so changing the default tone in Settings silently
    /// re-laid-out the suggestion bar — three candidates the user reads mid-word,
    /// shifted sideways by a choice made on another screen.
    ///
    /// 68 is the widest label plus the padding, so nothing ever scales down:
    /// `Professional` measures 56.6pt at this font and the inset is 5 a side.
    /// `ToneIconTests` holds every tone name to fitting, which is the assertion
    /// that fails if a seventh register arrives with a longer name.
    static let toneButtonWidth: CGFloat = 68

    /// The inset either side of the label inside `toneButtonWidth`.
    static let toneButtonInset: CGFloat = 5

    /// The label's type, as a `UIFont` so the width rule can be measured against
    /// the font the button actually draws rather than against a second spelling of
    /// it. The view wraps it back into a `Font`.
    ///
    /// Semibold at 9pt, against the `Theme.Glyph` light house weight the icons use:
    /// a hairline holds up at 15pt and disappears at 9.
    static let toneLabelFont = UIFont.systemFont(ofSize: 9, weight: .semibold)

    /// Rewrite in the default tone, without opening anything.
    ///
    /// **The icon is fixed and the tone is written out under it, because the icon
    /// alone answered the wrong question.** It used to be the tone's own symbol and
    /// nothing else, so a user with Casual selected got a small waving stick figure
    /// (`figure.wave`) in a keyboard, which says nothing about rewriting, nothing
    /// about AI, and reads as a profile or contacts button. The fact it *was*
    /// carrying — which of six tones a tap runs, otherwise unknowable without
    /// opening a panel — is real and is kept, just moved into the label under the
    /// glyph where it can be read rather than guessed. `ToneStyle.icon` is still the
    /// per-tone symbol and still used, in the tone picker and on a result variant,
    /// where the surrounding panel already says what the screen is about.
    ///
    /// `KeyboardController.runDefaultTone` carries why this is Rewrite and not Fix.
    ///
    /// Three states, and they look like three things. With something to rewrite it
    /// is brand-tinted and lit. With nothing to rewrite the gradient goes and the
    /// icon drops to `secondaryLabel`, so it is drawn exactly like the inactive
    /// emoji button at the other end of this bar and cannot be mistaken for its
    /// lit neighbour — and it stays tappable, because a control that looks
    /// unavailable and swallows the tap teaches the user nothing. A call in flight
    /// replaces the icon with a spinner and is the only state that disables it. A
    /// call that *failed* needs nothing here: `beginWork` puts the reason in
    /// `aiError` and `AIResultPanel` is already on screen showing it.
    private var toneButton: some View {
        let tone = controller.defaultTone
        let isBusy = controller.isWorking
        let tap = Self.toneTap(
            hasTextToWorkWith: controller.hasTextToWorkWith, isWorking: isBusy)

        let tint = tap == .rewrite ? Theme.Brand.solid : Theme.Keys.secondaryLabel

        return Button {
            switch tap {
            case .rewrite: controller.runDefaultTone()
            case .openMenu: controller.show(.aiMenu)
            case .ignore: break
            }
        } label: {
            // The spinner replaces the glyph and not the label: a bare spinner in
            // a 68pt slot is an unlabelled box, and the button is being waited on
            // precisely when the user most wants to know what they tapped.
            VStack(spacing: 1) {
                Group {
                    if isBusy {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Theme.Brand.solid)
                    } else {
                        Image(systemName: Self.toneButtonSymbol)
                            .font(Theme.Glyph.medium(15))
                            .foregroundStyle(tint)
                    }
                }
                .frame(height: 18)

                Text(tone.title)
                    .font(Font(Self.toneLabelFont))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            .padding(.horizontal, Self.toneButtonInset)
            .frame(width: Self.toneButtonWidth, height: 40)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Brand.softGradient)
                    .opacity(tap == .rewrite ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .disabled(tap == .ignore)
        .accessibilityIdentifier("bar-tone")
        .accessibilityLabel("Rewrite as \(tone.title)")
        .accessibilityHint(toneHint(tap))
    }

    private func toneHint(_ tap: ToneTap) -> String {
        switch tap {
        case .ignore: return "Working"
        case .openMenu: return "Nothing to rewrite yet. Opens the AI actions"
        // The same words `ToneSetting.settingsNote` points at this button with, so
        // "the one-tap rewrite button" names one control everywhere it is written.
        case .rewrite:
            return "The one-tap rewrite button. Rewrites what you typed in your default tone"
        }
    }

    /// Opens the AI menu, whatever state the field is in.
    ///
    /// Unlike `toneButton` it does not go flat on an empty field: the panel behind
    /// it still has something to say, because Reply on an empty field with nothing
    /// running is the case D8 is about, and the menu greys the three text actions
    /// itself. The `disabled` wiring stays rather than becoming a hardcoded `true`
    /// so the button cannot drift away from the panel again — that drift is what
    /// this fixed.
    private var sparkleButton: some View {
        Button {
            controller.show(controller.overlay == .aiMenu ? .none : .aiMenu)
        } label: {
            SparkleMark(size: 19)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Brand.softGradient)
                        .opacity(isEnabled ? 1 : 0.45)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .disabled(!isEnabled)
        .accessibilityIdentifier("bar-sparkle")
        .accessibilityLabel("AI actions")
        .accessibilityHint(
            controller.hasTextToWorkWith
                ? "Fix, rewrite or reply" : "Reply to what's on screen, or type something to fix")
    }

    private var isEnabled: Bool {
        Self.sparkleOpensTheMenu(hasTextToWorkWith: controller.hasTextToWorkWith)
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
