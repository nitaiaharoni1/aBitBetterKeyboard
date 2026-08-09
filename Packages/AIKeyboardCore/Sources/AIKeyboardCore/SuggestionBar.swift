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

    /// Rewrite in the default tone, without opening anything.
    ///
    /// It wears the tone's own icon rather than a generic wand, because the one
    /// thing a user cannot otherwise learn without opening a panel is *which* tone
    /// a tap will run. `KeyboardController.runDefaultTone` carries why this is
    /// Rewrite and not Fix.
    ///
    /// Three states, and they are not the same refusal. Nothing to work with is
    /// drawn flat and disabled — *unlike* the sparkle beside it, which stays live
    /// on an empty field because the menu behind it still has Reply to offer. This
    /// button rewrites what you typed, so with nothing typed there is nothing it
    /// could do. A call in flight replaces the icon with a spinner and disables the
    /// button, because `beginWork` cancels its predecessor and a second tap would
    /// throw away the answer being waited on. A call that *failed* needs nothing
    /// here: `beginWork` puts the reason in `aiError` and `AIResultPanel` is
    /// already on screen showing it, so the bar goes back to offering the action
    /// again rather than holding onto an error the user has already read.
    private var toneButton: some View {
        let tone = controller.defaultTone
        let isBusy = controller.isWorking
        let canRun = controller.hasTextToWorkWith && !isBusy

        return Button {
            controller.runDefaultTone()
        } label: {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Brand.solid)
                } else {
                    Image(systemName: tone.icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Brand.solid)
                }
            }
            .frame(width: 44, height: 40)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Brand.softGradient)
                    .opacity(canRun ? 1 : 0.45)
            )
            .contentShape(Rectangle())
        }
        .pressable()
        .disabled(!canRun)
        .accessibilityIdentifier("bar-tone")
        .accessibilityLabel("Rewrite as \(tone.title)")
        .accessibilityHint(toneHint(canRun: canRun, isBusy: isBusy))
    }

    private func toneHint(canRun: Bool, isBusy: Bool) -> String {
        if isBusy { return "Working" }
        if !canRun { return "Type something first" }
        // The same words `ToneSetting.settingsNote` points at this button with, so
        // "the one-tap rewrite button" names one control everywhere it is written.
        return "The one-tap rewrite button. Rewrites what you typed in your default tone"
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
