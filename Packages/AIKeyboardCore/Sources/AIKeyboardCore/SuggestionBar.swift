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
            edgeButton(
                systemImage: "face.smiling",
                label: "Emoji",
                isActive: controller.overlay == .emoji
            ) {
                controller.show(controller.overlay == .emoji ? .none : .emoji)
            }

            separator

            suggestions

            separator

            // The two AI controls sit together with no rule between them: one runs
            // the default tone outright, the other opens the menu holding
            // everything that still needs a choice.
            toneButton

            sparkleButton
        }
        // **The buttons do not swap sides when the language does; the candidates
        // do.** This bar sits inside `KeyboardView`, which runs in the language's
        // own direction, so on Hebrew the emoji key jumped to the right and the
        // two AI buttons to the left — and a swipe along the space bar moves
        // between languages, so they jumped mid-use. Every other control row here
        // is already pinned: the bottom row in `KeyboardView`, the alternates
        // popup in `KeyView`, the dots in `LanguageCallout`, and the swipe
        // direction itself in `SpaceSwipe.language`. Controls stay put; text
        // follows the language, which is why `suggestions` sets its own direction.
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: Theme.Metrics.suggestionBarHeight)
        .padding(.horizontal, Theme.Space.xxs)
    }

    // MARK: Candidates

    /// Always three slots of equal width. A single candidate stretched across the
    /// whole bar reads as a banner rather than as a word you can tap.
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
        // The candidates are words, so they read in the language's direction:
        // candidate 0 is the literal echo of what was typed and belongs at the
        // edge the reader starts from. The default stays in the middle either way.
        .environment(\.layoutDirection, controller.language.layoutDirection)
        .animation(Theme.Motion.quick, value: controller.suggestions)
    }

    private func candidate(_ suggestion: Suggestion) -> some View {
        Button {
            controller.apply(suggestion)
        } label: {
            HStack(spacing: 3) {
                Text(suggestion.text)
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.Keys.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                // Only tag a candidate when it comes from the other language, so
                // the marker means something instead of decorating every word.
                if suggestion.language != controller.language {
                    LanguageTag(suggestion.language)
                }
            }
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

    private func edgeButton(
        systemImage: String,
        label: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
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

    /// What to call the sparkle in prose, named once and next to the button it
    /// names.
    ///
    /// For the reason `ToneSetting.settingsNote` gives: a glyph is not a name.
    /// The playground and onboarding both said "tap ✨" while two brand-tinted
    /// buttons sat side by side in this bar — and the default tone's own icon was
    /// SF `sparkle` next to this one's `sparkles`, so the instruction pointed at
    /// whichever of the two the reader looked at first.
    public static let aiButtonName = "the AI button above the keys"

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

    /// Rewrite in the default tone, without opening anything.
    ///
    /// It wears the tone's own icon rather than a generic wand, because the one
    /// thing a user cannot otherwise learn without opening a panel is *which* tone
    /// a tap will run. `KeyboardController.runDefaultTone` carries why this is
    /// Rewrite and not Fix.
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

        return Button {
            switch tap {
            case .rewrite: controller.runDefaultTone()
            case .openMenu: controller.show(.aiMenu)
            case .ignore: break
            }
        } label: {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Brand.solid)
                } else {
                    Image(systemName: tone.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(
                            tap == .rewrite ? Theme.Brand.solid : Theme.Keys.secondaryLabel)
                }
            }
            .frame(width: 44, height: 40)
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
