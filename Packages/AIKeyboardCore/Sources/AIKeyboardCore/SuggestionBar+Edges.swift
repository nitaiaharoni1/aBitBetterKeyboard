import SwiftUI

extension SuggestionBar {

    // MARK: Bar edge catalogue

    /// What the bar's two ends may hold.
    ///
    /// A subset of `SlotAction.catalogue`, and the exclusions are the point. A
    /// space bar or a shift key 46 points tall above the letters is not a layout
    /// anybody meant to build. Delete is out for a subtler reason: it is the one
    /// key with an accelerating repeat, and the repeat is wired in `KeyView`,
    /// which does not draw this bar — an edge button would delete once per tap and
    /// look broken beside the real one.
    public static let barCatalogue: [SlotAction] = [
        .emoji, .quickTone, .dictation, .cursorLeft, .cursorRight,
        .hideKeyboard, .globe
    ]

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

    /// Whether any AI action could run right now.
    ///
    /// **Kept after the sparkle it was named for was deleted**, because the question
    /// was never about that button: the bar answering it differently from the
    /// actions themselves is D8, and `AIAction` is now the one place that answers.
    static func anyActionCouldRun(hasTextToWorkWith: Bool) -> Bool {
        AIAction.hasRunnableAction(hasTextToWorkWith: hasTextToWorkWith)
    }

    // MARK: Slot button

    /// One configured control.
    ///
    /// The two that keep their own views carry a measured decision each: the tone
    /// button's three-way tap, and the emoji key's active tint. Everything else is
    /// the same tap the grid key makes, so a control cannot behave differently
    /// depending on which of the two places the user put it.
    @ViewBuilder
    func slotButton(_ action: SlotAction) -> some View {
        switch action {
        case .emoji:
            // `isEmoji` rather than `== .emoji`, so the button stays lit and stays
            // a way out while the search box is open. Against the bare case it
            // went dark the moment the user tapped search, which reads as the grid
            // having been closed by something the user did not do.
            edgeButton(
                systemImage: "face.smiling", label: "Emoji",
                isActive: controller.overlay.isEmoji
            ) {
                controller.show(controller.overlay.isEmoji ? .none : .emoji)
            }
        case .quickTone:
            toneButton
        case .dictation:
            // The bar's copy of the microphone key wears the same four
            // appearances the key does, record red included — two surfaces
            // disagreeing about what is happening is D8, and it is worse here
            // than it was for an empty field, because the disagreement would be
            // about whether a microphone is on.
            edgeButton(
                systemImage: controller.dictationKeyState.icon,
                label: SlotAction.dictation.title,
                // Said out loud, because the four appearances of this control are
                // a glyph and a cap colour and nothing else. The same words the
                // key in the action row uses — two copies of one control that
                // described themselves differently would be D8 with a live
                // microphone as the stake.
                spokenLabel: controller.dictationKeyState.accessibilityLabel,
                value: controller.dictationKeyState.accessibilityValue,
                isActive: controller.isActionKeyActive(.dictation),
                activeFill: controller.dictationKeyState.isRecording
                    ? Theme.Semantic.record : Theme.Brand.action
            ) {
                controller.press(.dictation)
            }
        default:
            // Guarded rather than defaulted. `keyCap` answers non-nil for every
            // case today, and a `?? .space` here would mean a future gap types a
            // space into the user's message rather than drawing nothing.
            if let cap = action.keyCap(language: controller.language) {
                edgeButton(
                    systemImage: action.glyph ?? "questionmark",
                    label: action.title,
                    isActive: controller.isActionKeyActive(cap)
                ) {
                    controller.press(cap)
                }
            }
        }
    }

    /// A bar copy of an action key, lit the same way the key in the grid is.
    ///
    /// **Filled brand, not a 14% wash, and the key it mirrors made the same
    /// move.** See `KeyView.capKind`: a soft tint on a light strip is a control
    /// that looks very slightly different from its neighbours, which is not what
    /// "this is running right now" needs to say.
    /// `label` names the *identifier* and is what a test addresses; `spokenLabel`
    /// is what VoiceOver reads and defaults to the same thing. They are separate
    /// for the microphone, whose spoken name changes with the recording while its
    /// identifier must not.
    fileprivate func edgeButton(
        systemImage: String,
        label: String,
        spokenLabel: String? = nil,
        value: String = "",
        isActive: Bool,
        activeFill: Color = Theme.Brand.action,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.Glyph.font(19))
                .foregroundStyle(isActive ? Theme.Text.onBrand : Theme.Keys.secondaryLabel)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(isActive ? activeFill : .clear)
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier("bar-\(label.lowercased())")
        .accessibilityLabel(spokenLabel ?? label)
        .accessibilityValue(value)
    }

    // MARK: Pause and resume

    /// What the bar offers beside the candidates while a recording is open, as a
    /// decision rather than a chain of `if`s inside a `ViewBuilder`.
    ///
    /// **Separate and testable for the reason `SuggestionBar.ToneTap` is**: a
    /// `.disabled()` modifier and a button's action cannot be read back off a
    /// SwiftUI view, so a control that renders but answers nothing looks exactly
    /// like one that works — which shipped here once already, as a Pause button
    /// drawn over a transcription with nothing to pause.
    ///
    /// `nil` is that same state: between the stop tap and the words arriving there
    /// is no open utterance, `pauseDictation()` would return at its own
    /// `guard isDictating`, and the microphone key is captioned Cancel because it
    /// is the last moment the insert can be called off.
    enum DictationControl: Equatable {
        case pause
        case resume
    }

    static func dictationControl(for state: DictationKeyState) -> DictationControl? {
        switch state {
        case .recording: return .pause
        case .paused: return .resume
        case .idle, .finishing: return nil
        }
    }

    /// Whether the bar is drawing a pause or resume control right now. Its own
    /// property so `SuggestionBar` reads one thing rather than resolving the
    /// control twice — once to decide, once to draw.
    var dictationControl: DictationControl? {
        Self.dictationControl(for: controller.dictationKeyState)
    }

    /// Stops the recorder keeping samples without ending the recording.
    ///
    /// **It is here rather than on a strip of its own because there is no strip
    /// left and no height to build one.** Finishing a recording is the microphone
    /// key; pausing one is a second thing a user may want mid-sentence, and this
    /// row is the only surface in the keyboard that can hold it for nothing — the
    /// three candidates have little to say while somebody is speaking, and it
    /// takes the slot the undo uses, which cannot be live at the same time.
    ///
    /// **`record.circle` for resume, not `mic.fill`.** `mic.fill` is what the
    /// microphone key wears, so reusing it here would read as "open a second
    /// microphone" rather than "keep going with this one"; a filled red circle is
    /// what a paused recording resumes to elsewhere on iOS.
    @ViewBuilder
    func dictationControlButton(_ control: DictationControl) -> some View {
        let isPaused = control == .resume
        Button {
            isPaused ? controller.resumeDictation() : controller.pauseDictation()
        } label: {
            Image(systemName: isPaused ? "record.circle" : "pause.fill")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Semantic.record)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Semantic.record.opacity(0.14))
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier(isPaused ? "bar-resume" : "bar-pause")
        .accessibilityLabel(isPaused ? "Resume dictation" : "Pause dictation")
    }

    // MARK: Undo

    /// Puts back what the last Fix or Rewrite replaced.
    ///
    /// **Tinted rather than filled, because it is an offer and not a state.** The
    /// filled cap above means "this is happening"; this button means "you can take
    /// that back", it is on screen for one keystroke, and it sits beside three
    /// candidate slots that are empty at that exact moment — so it has to catch the
    /// eye without reading as the thing that just ran.
    ///
    /// It names the action it undoes rather than saying "Undo", because by the time
    /// it is read the field has already changed and the word is the only thing
    /// saying *what* changed it.
    var revertButton: some View {
        let action = controller.revertibleEdit?.action
        return Button {
            controller.revertAIEdit()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Brand.solid)
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Brand.solid.opacity(0.14))
                )
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityIdentifier("bar-revert")
        .accessibilityLabel("Undo \(action?.title ?? "")")
        .accessibilityHint("Puts back what you had written")
    }
}
