import SwiftUI

extension SuggestionBar {

    // MARK: Bar edge catalogue

    /// What the bar's two ends may hold.
    ///
    /// A subset of `SlotAction.catalogue`, and the exclusions are the point. A
    /// space bar or a shift key 46 points tall above the letters is not a layout
    /// anybody meant to build. Delete and forward delete are out for a subtler
    /// reason: they are the keys with an accelerating repeat, and the repeat is
    /// wired in `KeyView`, which does not draw this bar — an edge button would
    /// delete once per tap and look broken beside the real one.
    public static let barCatalogue: [SlotAction] = [
        .emoji, .copyclip, .reply, .quickTone, .dictation, .cursorLeft, .cursorRight,
        .hideKeyboard, .globe
    ]

    /// What the bar will host on the user's behalf when landscape sheds the
    /// action row, which is `barCatalogue` plus the two the editor's own drawer
    /// has no reason to offer.
    ///
    /// **It is a superset rather than a second opinion, and each addition is a
    /// route that would otherwise close.** `barCatalogue` answers "what may a
    /// user *choose* to put on the bar", and Fix and Settings are absent from it
    /// because they are keys with a home elsewhere — Fix ships in the action row
    /// and the gear on the bottom row. Landscape is the one orientation where
    /// that home is not drawn: Fix is one of the three AI actions and would
    /// otherwise be unreachable outright, and the gear is the only route from
    /// this keyboard into the containing app, so a user who moved it up into
    /// their action row would have no way into Settings at all while the phone is
    /// sideways. Everything `barCatalogue` excludes stays excluded for the
    /// reasons written there: a space bar or a shift key in this row is not a
    /// keyboard, and delete's accelerating repeat is wired in `KeyView`, which
    /// does not draw this bar. `.text` and the plane keys go too, because they
    /// have no glyph (`SlotAction.glyph` answers nil) and a chip drawing a
    /// literal question mark for the comma somebody put in their action row is
    /// worse than not drawing it.
    static let landscapeBarActions: Set<SlotAction> =
        Set(barCatalogue).union([.fix, .settings])

    /// The action row's controls, for a bar that has to carry them.
    ///
    /// Reads the *unmodified* customization, not `landscapeLayout(basedOn:)`,
    /// because the whole point is the row that layout emptied. Order is kept, so
    /// the chips read left to right in the arrangement the user built.
    ///
    /// **Deduplicated against both ends of the bar**, since a user is free to put
    /// Rewrite in their action row and on the trailing edge as well: in portrait
    /// those are two rows and two controls, and in landscape they would collapse
    /// into the same strip and draw one action twice.
    public static func landscapeActions(for layout: KeyboardCustomization) -> [SlotSpec] {
        let alreadyOnTheBar = Set((layout.barLeading + layout.barTrailing).map(\.action))
        var seen = Set<SlotAction>()
        return layout.cursorRow.filter { slot in
            guard landscapeBarActions.contains(slot.action) else { return false }
            guard !alreadyOnTheBar.contains(slot.action) else { return false }
            return seen.insert(slot.action).inserted
        }
    }

    /// Everything the landscape bar draws while a panel is covering the letters.
    ///
    /// **The way out of that panel is in here or it does not exist.** Both panels
    /// hide every letter key, landscape sheds the row whose key closes them, and
    /// landscape draws no search box, so this list is the whole surface left. It
    /// is all three groups rather than the strip alone because
    /// `landscapeActions(for:)` deduplicates: a user who clears their action row
    /// and keeps Emoji on a bar edge has it in `barTrailing` and nowhere else,
    /// and a strip-only version would let that chip open a grid and then stop
    /// drawing itself.
    public static func landscapePanelControls(
        for layout: KeyboardCustomization
    ) -> [SlotSpec] {
        layout.barLeading + landscapeActions(for: layout) + layout.barTrailing
    }

    /// One chip in the bar, for one orientation.
    ///
    /// **Width is untouched and only the height comes down.** Landscape is short
    /// and wide, so 44 pt across stays exactly the portrait target a thumb
    /// already knows while the height drops to fit inside a 30 pt row — the same
    /// trade the 26 pt landscape key makes one band down, and for the same
    /// reason: the fingerprint cap is a fraction of the screen's *short* axis.
    /// A chip taller than the row would draw over the keys and past the height
    /// the keyboard published to the host.
    public static func chipSize(
        for orientation: KeyboardGeometry.Orientation
    ) -> CGSize {
        orientation == .landscape ? CGSize(width: 44, height: 26) : CGSize(width: 44, height: 40)
    }

    var chipSize: CGSize { Self.chipSize(for: orientation) }

    /// Where to send a reader looking for the AI actions, named once.
    ///
    /// For the reason `ToneSetting.settingsNote` gives: a glyph is not a name. The
    /// playground and onboarding both said "tap ✨" while two brand-tinted buttons
    /// sat side by side in this bar — and the default tone's own icon was SF
    /// `sparkle` next to this one's `sparkles`, so the instruction pointed at
    /// whichever of the two the reader looked at first.
    ///
    /// **It now names a row rather than a button, because the buttons moved and
    /// there is more than one of them.** Fix, Rewrite and dictation are keys
    /// in the action row. Reply ships at the trailing end of the bar so that row
    /// can stay two-and-two around settings.
    public static let aiButtonName = "the action row above the keys"

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
        case .quickTone where orientation == .landscape:
            // **The named tone button needs a second line and landscape has no
            // room for one.** `toneButton` is 68 × 40 and prints the tone under
            // the glyph, because the tone is a setting and the button is the one
            // place it is visible while typing; 40 pt does not fit in a 30 pt
            // row, and squeezing the word into 9 pt of what is left would be a
            // label nobody can read next to a glyph they can. So landscape draws
            // the same fixed `toneButtonSymbol` — `AIAction.rewrite`'s own icon,
            // never the tone's, for the reason `.claude/rules/suggestion-bar.md`
            // records — and the tone survives in the spoken label, which is where
            // the key in the action row keeps it too.
            edgeButton(
                systemImage: Self.toneButtonSymbol,
                label: AIAction.rewrite.title,
                identifier: "bar-tone",
                spokenLabel: "Rewrite as \(controller.defaultTone.title)",
                isActive: controller.isActionKeyActive(.quickTone),
                activity: KeyActivity.resolve(for: .quickTone, controller: controller),
                isDisabled: controller.isActionKeyDisabled(.quickTone),
                disabledHint: controller.actionKeyDisabledReason(.quickTone)
            ) {
                controller.runDefaultTone()
            }
        case .quickTone:
            toneButton
        case .dictation:
            // The bar's copy of the microphone key wears the same appearances the
            // key does — filled orange at rest, red while recording — because two
            // surfaces disagreeing about what is happening is D8, and it is worse
            // here than it was for an empty field: the disagreement would be about
            // whether a microphone is on. `isActive: true` unconditionally is what
            // makes it filled at rest, the same thing `KeyView.capKind` does for
            // the key.
            edgeButton(
                systemImage: controller.dictationKeyState.icon,
                label: SlotAction.dictation.title,
                // Said out loud, because the appearances of this control are a
                // glyph and a cap colour and nothing else. The same words the key
                // in the action row uses — two copies of one control that described
                // themselves differently would be D8 with a live microphone as the
                // stake.
                spokenLabel: controller.dictationKeyState.accessibilityLabel,
                value: controller.dictationKeyState.accessibilityValue,
                isActive: true,
                activeFill: controller.dictationKeyState.isRecording
                    ? Theme.Semantic.record : Theme.Brand.action,
                activity: KeyActivity.resolve(for: .dictation, controller: controller)
            ) {
                controller.press(.dictation)
            }
        default:
            // Guarded rather than defaulted. `keyCap` answers non-nil for every
            // case today, and a `?? .space` here would mean a future gap types a
            // space into the user's message rather than drawing nothing.
            if let cap = action.keyCap(language: controller.language) {
                edgeButton(
                    systemImage: action.glyph(
                        isRightToLeft: controller.language.isRightToLeft) ?? "questionmark",
                    label: action.title,
                    spokenLabel: (cap == .cursorLeft || cap == .cursorRight)
                        ? cap.accessibilityLabel(
                            isRightToLeft: controller.language.isRightToLeft)
                        : nil,
                    isActive: controller.isActionKeyActive(cap),
                    activity: KeyActivity.resolve(for: cap, controller: controller),
                    // Asked of the controller, never of the field, for the reason
                    // `.claude/rules/suggestion-bar.md` gives: two copies of one
                    // control keeping their own opinion about whether it can run
                    // is D8, and there are three reasons now — an empty field, a
                    // live recording, and another call already in flight.
                    isDisabled: controller.isActionKeyDisabled(cap),
                    disabledHint: controller.actionKeyDisabledReason(cap)
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
    /// identifier must not. `identifier` overrides the derived one for the
    /// control that has two drawings across the two orientations.
    ///
    /// **The chip's own size comes from `chipSize`, not from a pair of numbers
    /// written here.** Landscape's row is 30 pt and a 40 pt chip drawn in it is a
    /// bar taller than the height the keyboard published — which is the whole
    /// margin that orientation has against the fingerprint cap.
    ///
    /// `isDisabled` fades the glyph and stops the tap, and the cap under it keeps
    /// its colour: fading a filled chip punches a hole in the strip, and the same
    /// split is what `KeyView.disabledLabelOpacity` does one row down.
    fileprivate func edgeButton(
        systemImage: String,
        label: String,
        identifier: String? = nil,
        spokenLabel: String? = nil,
        value: String = "",
        isActive: Bool,
        activeFill: Color = Theme.Brand.action,
        activity: KeyActivity = .idle,
        isDisabled: Bool = false,
        disabledHint: String = "",
        action: @escaping () -> Void
    ) -> some View {
        let workingLabel: String? = {
            if case .working = activity { return "\(label), working" }
            return nil
        }()
        return Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(isActive ? activeFill : .clear)
                ControlActivityChrome(activity: activity, cornerRadius: Theme.Radius.chip)
                edgeGlyph(
                    systemImage: systemImage, activity: activity, isActive: isActive,
                    isDisabled: isDisabled)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            )
            .frame(width: chipSize.width, height: chipSize.height)
            .contentShape(Rectangle())
        }
        .pressable()
        .disabled(isDisabled)
        // Derived from the name by default, and overridable for the one control
        // that has two drawings. Landscape swaps the named tone button for a
        // glyph chip, and a test or a screen reader that addressed `bar-tone` in
        // portrait must find the same control after a rotation: the same reason
        // the microphone's identifier is fixed while its spoken name changes.
        .accessibilityIdentifier(identifier ?? "bar-\(label.lowercased())")
        .accessibilityLabel(workingLabel ?? spokenLabel ?? label)
        .accessibilityValue(value)
        // The words behind a faded glyph, which is the only form the reason
        // reaches somebody who cannot see it in.
        .accessibilityHint(disabledHint)
    }

    @ViewBuilder
    private func edgeGlyph(
        systemImage: String, activity: KeyActivity, isActive: Bool, isDisabled: Bool
    ) -> some View {
        let tint = isActive ? Theme.Text.onBrand : Theme.Keys.secondaryLabel
        let opacity = isDisabled ? KeyView.disabledLabelOpacity : 1
        if case .recording(let levels) = activity {
            ControlWaveform(levels: levels, color: tint)
                .padding(.horizontal, 6)
                .opacity(opacity)
        } else {
            Image(systemName: systemImage)
                .font(Theme.Glyph.font(19))
                .foregroundStyle(tint)
                .opacity(opacity)
        }
    }

    // MARK: Undo

    /// Puts back what the last Fix, Rewrite or pasted clip put in the field.
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
        // The origin names itself, so a clip pasted from CopyClip is "Undo paste"
        // here without this file learning what a clip is. See
        // `RevertibleEdit.Origin.undoLabel`.
        let label = controller.revertibleEdit?.origin.undoLabel ?? "Undo"
        return Button {
            controller.revertEdit()
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
        .accessibilityLabel(label)
        .accessibilityHint("Puts back what you had written")
    }
}
