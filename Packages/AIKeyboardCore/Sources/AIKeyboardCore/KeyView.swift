import SwiftUI

/// One key. Owns its own press state so a touch registers on finger-down rather
/// than on lift, which is what makes typing feel immediate.
public struct KeyView: View {

    let spec: KeySpec
    let width: CGFloat
    let height: CGFloat
    let language: KeyboardLanguage
    let shift: ShiftState
    /// What the space bar should say about the language instead of "space", and
    /// whether the finger choosing it is still down. Nil on every other key.
    let indication: LanguageSwitchIndication?
    /// The languages the space bar can slide between, in the order a slide moves
    /// through them. Read only by the space bar, which prints their codes, and
    /// passed to every key the way `language` and `shift` already are.
    let enabledLanguages: [KeyboardLanguage]
    /// The registers a long press on the one-tap rewrite key offers, default
    /// first. Empty on every other key, and passed in for the same reason
    /// `enabledLanguages` is: the list comes from a stored setting in another
    /// process and a `KeySpec` is a value that cannot read one.
    let toneAlternates: [String]
    /// Whether the emoji grid is open, which is the only thing that changes what
    /// the Emoji key says. Passed in for the same reason `toneAlternates` is: it
    /// is controller state, and a `KeySpec` is a value that cannot read any.
    /// False on every other key, where it is not read at all.
    let isEmojiOpen: Bool
    /// Whether a wide action key should include its text caption.
    let showsActionCaption: Bool
    /// Whether action glyphs and captions should match the standard key label color.
    let usesNeutralActionTint: Bool
    /// Whether this key is the action currently running (or the open emoji grid).
    /// The key wears a filled brand cap so the row says which of the five is live
    /// without the user having to read the strip.
    let isActionActive: Bool
    /// Whether this key has nothing it could do — Fix and Rewrite over an empty
    /// field. Drawn dim and takes no touch. See
    /// `KeyboardController.isActionKeyDisabled` for why this is a disabled control
    /// rather than one that refuses out loud.
    let isDisabled: Bool
    /// Why this key is off, in words, for the accessibility hint. Empty on a key
    /// that is not. Passed in rather than written here because there is more than
    /// one reason a key can be off and only the controller knows which applies —
    /// see `KeyboardController.actionKeyDisabledReason`.
    let disabledHint: String
    /// What the microphone key is showing. `.idle` on every other key, where it is
    /// not read. Passed in for the same reason `toneAlternates` and `isEmojiOpen`
    /// are: it is resolved from a recording running in another process, and a
    /// `KeySpec` is a value that can read none of that. See `DictationKeyState`.
    let dictationState: DictationKeyState
    let onPress: (KeyCap, CGPoint) -> Void
    let onRepeat: (() -> Void)?
    let onAlternate: ((String) -> Void)?
    /// Set only on the space bar, and its presence is what makes that key defer:
    /// a touch here may still turn into a language slide, so it reports the touch
    /// and lets the controller decide whether it was a space.
    let onSpaceTouch: ((SpaceTouchPhase) -> Void)?

    @State var isPressed = false
    @State var repeater = KeyRepeater()
    @State var alternatesTask: Task<Void, Never>?
    @State var showsAlternates = false
    @State var selectedAlternate = 0

    /// True for as long as a touch is on this key.
    ///
    /// **The only signal that survives a cancelled gesture**, which is the whole
    /// reason it is here rather than a second `@State` flag. SwiftUI does not call
    /// `DragGesture.onEnded` when a touch sequence is cancelled — a banner, a
    /// Control Centre pull, the host resigning first responder — and `onEnded` was
    /// the only place the repeat loop was ever stopped.
    @GestureState var isTouching = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public init(
        spec: KeySpec,
        width: CGFloat,
        height: CGFloat,
        language: KeyboardLanguage,
        shift: ShiftState,
        indication: LanguageSwitchIndication? = nil,
        enabledLanguages: [KeyboardLanguage] = [],
        toneAlternates: [String] = [],
        isEmojiOpen: Bool = false,
        showsActionCaption: Bool = true,
        usesNeutralActionTint: Bool = false,
        isActionActive: Bool = false,
        isDisabled: Bool = false,
        disabledHint: String = "",
        dictationState: DictationKeyState = .idle,
        onPress: @escaping (KeyCap, CGPoint) -> Void,
        onRepeat: (() -> Void)? = nil,
        onAlternate: ((String) -> Void)? = nil,
        onSpaceTouch: ((SpaceTouchPhase) -> Void)? = nil
    ) {
        self.spec = spec
        self.width = width
        self.height = height
        self.language = language
        self.shift = shift
        self.indication = indication
        self.enabledLanguages = enabledLanguages
        self.toneAlternates = toneAlternates
        self.isEmojiOpen = isEmojiOpen
        self.showsActionCaption = showsActionCaption
        self.usesNeutralActionTint = usesNeutralActionTint
        self.isActionActive = isActionActive
        self.isDisabled = isDisabled
        self.disabledHint = disabledHint
        self.dictationState = dictationState
        self.onPress = onPress
        self.onRepeat = onRepeat
        self.onAlternate = onAlternate
        self.onSpaceTouch = onSpaceTouch
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(background)
                .shadow(
                    color: Self.contactShadow(for: capKind),
                    radius: 0, x: 0, y: isPressed ? Self.pressContactY : Self.restContactY
                )
                .shadow(
                    color: Self.ambientShadow(for: capKind),
                    radius: isPressed ? Self.pressAmbientRadius : Self.restAmbientRadius,
                    x: 0, y: isPressed ? Self.pressAmbientY : Self.restAmbientY
                )

            label
        }
        .frame(width: width, height: height)
        // The press, felt: the cap — label with it — seats onto the keyboard
        // and the lift goes out from under it. An offset, not layout, so no
        // neighbour moves; applied before the overlays, so the callouts stay
        // anchored where the key sits at rest.
        .offset(y: isPressed ? Self.pressTravel : 0)
        .overlay(alignment: .bottom) { callout }
        // The balloon follows `isTouching`, which changes a beat before
        // `isPressed`. Without this, that insertion is SwiftUI's default
        // animation, and a tap is over before the letter is readable.
        .animation(nil, value: isTouching)
        .overlay(alignment: .bottom) { alternatesPopup }
        .overlay(alignment: .bottom) { languageCallout }
        // Instant on the way down: `Motion.press` is 100ms, and a tap is over
        // before that ease-out finishes, so the pressed fill the tokens specify
        // was a colour the thumb never saw. The release still eases, so the
        // flash is the full grey rather than a smear back to white. After the
        // overlays so a hold that opens the strip is in the same transaction.
        .animation(isPressed ? nil : Theme.Motion.press, value: isPressed)
        // High enough that a balloon wider than the key sits above every
        // neighbour, not only the ones SwiftUI happened to draw first.
        .zIndex((isTouching || isPressed) ? 10 : 0)
        .contentShape(Rectangle())
        .gesture(pressGesture)
        // **The whole key, not the gesture alone.** `.disabled` takes the touch out
        // of the subtree, so there is no path — gesture, accessibility action or
        // rotor — that reaches `onPress` on a key that has nothing to do. A guard
        // inside the handler would leave the key looking pressable and answering
        // nothing, which is the defect this repo already shipped once on the
        // one-tap rewrite button.
        .disabled(isDisabled)
        // Cancellation lands here and nowhere else: SwiftUI resets a
        // `@GestureState` when the gesture ends *or* is cancelled, and only the
        // first of those calls `onEnded`.
        .onChange(of: isTouching) { _, touching in
            if !touching { endPress() }
        }
        // And if the key is taken off screen mid-press — a plane switch, a
        // language switch, the keyboard being dismissed — the touch never ends at
        // all. `@State` releasing the repeater covers this too; this makes it
        // prompt rather than dependent on when the storage is torn down.
        .onDisappear { endPress() }
        .accessibilityElement()
        // **The part before the `#`, not the whole id.** A key compiled from a
        // custom layout carries `char-,#a1b2c3d4`: the prefix is what a test or a
        // screen reader addresses, and the suffix is only there to keep two
        // commas on one row from being one `ForEach` identity. See
        // `KeyboardLayout.identifier(for:slot:)`.
        .accessibilityIdentifier("key-\(spec.addressableID)")
        .accessibilityLabel(label(for: spec.cap))
        // The whole indication is visual, so without this a VoiceOver user
        // sliding along the space bar is told nothing at all about where they
        // are in the list.
        .accessibilityValue(accessibilityValue)
        // The chevrons are the whole of the gesture's affordance and a VoiceOver
        // user cannot see them, so they are said instead.
        .accessibilityHint(hint)
        .accessibilityAddTraits(traits)
        // **A long press and a slide is unusable under VoiceOver, so everything
        // behind one gets a non-gesture route.** The same rule the layout editor
        // is built on: every edit there has a button as well as a drag.
        //
        // This was the registers alone until the letters had anything to offer
        // that could not be typed another way. It is now every key with a popup,
        // because a Hebrew letter's geresh and gershayim and Catalan's interpunt
        // live *only* here — there is no plane carrying them — so a VoiceOver
        // user could not write צ׳יפס, צה״ל or col·legi at all.
        .accessibilityActions {
            if hasAlternates {
                ForEach(alternateItems.dropFirst(), id: \.self) { item in
                    Button(alternateActionLabel(item)) { commitAlternate(item) }
                }
            }
        }
    }

    /// What a VoiceOver user is told about this key beyond its name.
    ///
    /// **A dimmed cap says "not now" to somebody who can see it and nothing at all
    /// to somebody who cannot**, so a key with nothing to do spells out why — the
    /// same sentence `refuseForEmptyField` prints, minus the strip. Otherwise it is
    /// the space bar's slide hint, because the chevrons are the whole of that
    /// gesture's affordance and a VoiceOver user cannot see them.
    ///
    /// Computed here rather than written inline in `body`: nested ternaries inside a
    /// `ViewBuilder` chain are what tipped this view past the type-checker's
    /// budget, and the build failure it gives ("unable to type-check this
    /// expression in reasonable time") names the `ZStack` rather than the line that
    /// caused it.
    /// What this key is called.
    ///
    /// **`KeyCap` answers for every key but one.** A `KeyCap` is a value and knows
    /// nothing about a recording running in another process, so the microphone key
    /// said "Record" in both of its states — including while it was the button
    /// that stops a live microphone. Its two appearances are visual (a red cap, a
    /// pause glyph) and were, until this, entirely silent.
    func label(for cap: KeyCap) -> String {
        // A grouped letter key is the other one: it is `.character("qw\nas")`, and
        // only the layout that built it knows that is four letters rather than a
        // snippet. See `KeySpec.spokenLabel`.
        if let spoken = spec.spokenLabel { return spoken }
        guard cap == .dictation else { return cap.accessibilityLabel }
        return dictationState.accessibilityLabel
    }

    var hint: String {
        if isDisabled { return disabledHint }
        guard spec.cap == .space else { return "" }
        return SpaceSwipe.slideHint(languageCount: enabledLanguages.count)
    }

    /// **`.disabled(isDisabled)` below is what marks the key unavailable to
    /// VoiceOver**, and there is no trait to add here for it: SwiftUI has no
    /// `isNotEnabled` trait — that is a UIKit `UIAccessibilityTraits` spelling —
    /// and the modifier already sets the underlying flag. The hint above is what
    /// says *why*, which the flag alone never does.
    var traits: AccessibilityTraits { .isKeyboardKey }

    /// Below this the caption comes off and the glyph stands alone.
    ///
    /// **A key wide enough to name itself should, and one that is not must not
    /// try.** The action row splits the width five ways, which is about 74pt on a
    /// 375pt screen — room for a word. The same action dragged into the bottom row
    /// beside the space bar is one unit, about 32pt, where a caption either
    /// truncates to two letters or scales into a hairline. The key decides from
    /// its own width rather than from which row it is in, because a `KeySpec` does
    /// not know its row and `KeyboardLayout.widths` is what actually resolves
    /// `.fill`.
    ///
    /// 56 is the narrowest width at which `Rewrite` — the longest of the four
    /// captions — fits at 9pt with the 4pt insets, measured the way
    /// `SuggestionBar.toneButtonWidth` was.
    static let captionMinimumWidth: CGFloat = 56
}
