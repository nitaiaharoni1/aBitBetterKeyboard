import SwiftUI

/// One key. Owns its own press state so a touch registers on finger-down rather
/// than on lift, which is what makes typing feel immediate.
public struct KeyView: View, Equatable {

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
    /// The Fix passes a long press offers, proofread first. Empty on every
    /// other key. Same shape as `toneAlternates`: the list lives on the
    /// controller, and a `KeySpec` is a value that cannot read one.
    let fixAlternates: [String]
    /// Recent clips a long press on CopyClip offers, rest title first. Empty
    /// on every other key. Same shape as `toneAlternates` and `fixAlternates`.
    let copyclipAlternates: [String]
    /// Whether the emoji grid is open, which is the only thing that changes what
    /// the Emoji key says. Passed in for the same reason `toneAlternates` is: it
    /// is controller state, and a `KeySpec` is a value that cannot read any.
    /// False on every other key, where it is not read at all.
    let isEmojiOpen: Bool
    /// Whether the CopyClip panel is open. Passed separately from `isEmojiOpen`
    /// so the two keys cannot steal each other's letters-plane label.
    let isCopyClipOpen: Bool
    /// Whether this key draws its name under its glyph.
    ///
    /// **Already resolved, floor included.** The caller answers it with
    /// `KeySpec.showsActionCaption(inRow:width:)`, which folds the user's own
    /// switch, the row the key stands in and the width below which a name will
    /// not fit into one boolean. The view does not second-guess it: a key told
    /// yes at one unit draws a squeezed word, because somebody asked for it.
    let showsActionCaption: Bool
    /// Whether action glyphs and captions should match the standard key label color.
    let usesNeutralActionTint: Bool
    /// Whether this key is the action currently running (or the open emoji grid).
    /// The key wears a filled brand cap so the row says which action is live
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
    /// Live work on this key, if it is the one that started it. `.idle` on
    /// every other key so one key's call does not rebuild the grid.
    let activity: KeyActivity

    /// The accent this key was drawn with.
    ///
    /// **The one thing this view reads that is neither passed in nor SwiftUI
    /// state, and `==` below is what makes capturing it necessary.** Every brand
    /// colour on a key comes from `Theme.Brand`, which reads the mutable global
    /// `Theme.palette`; the picker lives in the companion app, so the extension
    /// repaints by writing that global and firing `controller.objectWillChange`
    /// (see `KeyboardViewController.applyBrandPalette`). That nudge rebuilds
    /// `KeyboardView` and constructs fresh keys, and without the palette among
    /// the compared values every one of them would compare equal to the key it
    /// replaced and keep the old accent — an equality check quietly undoing the
    /// only repaint route the keyboard has.
    ///
    /// A property initialiser rather than an `init` parameter, so it is captured
    /// at construction with no call site having to know: `Theme.palette` is read
    /// once per key, where the key is built, which is exactly the moment its
    /// colours are decided.
    let palette: BrandPalette = Theme.palette
    let onPress: (KeyCap, CGPoint) -> Void
    let onRepeat: (() -> Void)?
    let onAlternate: ((String) -> Void)?
    /// Set only on the space bar, and its presence is what makes that key defer:
    /// a touch here may still turn into a language slide, so it reports the touch
    /// and lets the controller decide whether it was a space.
    let onSpaceTouch: ((SpaceTouchPhase) -> Void)?
    /// Set on every character key, and its presence is what makes that key defer.
    ///
    /// Same shape as `onSpaceTouch` and for a related reason: the touch's meaning
    /// is not settled on finger-down, because a long press may pick an alternate
    /// instead. `onPress` stays wired as well and stays immediate — a VoiceOver
    /// rotor pick has no lift behind it and goes through `commitAlternate`, which
    /// must type now rather than park.
    let onCharacterTouch: ((CharacterTouchPhase) -> Void)?
    /// Set on Fix, Rewrite and CopyClip so the action row can climb over the
    /// letters for the length of the hold. A preference from every key was a
    /// frame late and a letter press could raise the wrong block.
    let onPopupLayerChange: ((Bool) -> Void)?

    @State var isPressed = false
    @State var repeater = KeyRepeater()
    @State var wordRepeater = KeyRepeater.wordDelete()
    @State var alternatesTask: Task<Void, Never>?
    @State var showsAlternates = false
    @State var selectedAlternate = 0
    @State var keyMinXInCanvas: CGFloat = 0

    /// True for as long as a touch is on this key.
    ///
    /// **The only signal that survives a cancelled gesture**, which is the whole
    /// reason it is here rather than a second `@State` flag. SwiftUI does not call
    /// `DragGesture.onEnded` when a touch sequence is cancelled — a banner, a
    /// Control Centre pull, the host resigning first responder — and `onEnded` was
    /// the only place the repeat loop was ever stopped.
    @GestureState var isTouching = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.keyboardCanvasWidth) var keyboardCanvasWidth
    @Environment(\.keyboardCanvasOriginX) var keyboardCanvasOriginX
    /// Read here and forwarded into the `static` sizing functions in
    /// `KeyView+SpaceLabel`, rather than read again inside them: those take
    /// the size as an explicit parameter so a test can compare two sizes
    /// against one key box without standing up a second SwiftUI environment.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    public init(
        spec: KeySpec,
        width: CGFloat,
        height: CGFloat,
        language: KeyboardLanguage,
        shift: ShiftState,
        indication: LanguageSwitchIndication? = nil,
        enabledLanguages: [KeyboardLanguage] = [],
        toneAlternates: [String] = [],
        fixAlternates: [String] = [],
        copyclipAlternates: [String] = [],
        isEmojiOpen: Bool = false,
        isCopyClipOpen: Bool = false,
        showsActionCaption: Bool = true,
        usesNeutralActionTint: Bool = false,
        isActionActive: Bool = false,
        isDisabled: Bool = false,
        disabledHint: String = "",
        dictationState: DictationKeyState = .idle,
        activity: KeyActivity = .idle,
        onPress: @escaping (KeyCap, CGPoint) -> Void,
        onRepeat: (() -> Void)? = nil,
        onAlternate: ((String) -> Void)? = nil,
        onSpaceTouch: ((SpaceTouchPhase) -> Void)? = nil,
        onCharacterTouch: ((CharacterTouchPhase) -> Void)? = nil,
        onPopupLayerChange: ((Bool) -> Void)? = nil
    ) {
        self.spec = spec
        self.width = width
        self.height = height
        self.language = language
        self.shift = shift
        self.indication = indication
        self.enabledLanguages = enabledLanguages
        self.toneAlternates = toneAlternates
        self.fixAlternates = fixAlternates
        self.copyclipAlternates = copyclipAlternates
        self.isEmojiOpen = isEmojiOpen
        self.isCopyClipOpen = isCopyClipOpen
        self.showsActionCaption = showsActionCaption
        self.usesNeutralActionTint = usesNeutralActionTint
        self.isActionActive = isActionActive
        self.isDisabled = isDisabled
        self.disabledHint = disabledHint
        self.dictationState = dictationState
        self.activity = activity
        self.onPress = onPress
        self.onRepeat = onRepeat
        self.onAlternate = onAlternate
        self.onSpaceTouch = onSpaceTouch
        self.onCharacterTouch = onCharacterTouch
        self.onPopupLayerChange = onPopupLayerChange
    }

    /// Every value this key draws from, and none of the six closures it is handed.
    ///
    /// **`KeyboardController` publishes on every keystroke and every key on the
    /// board redraws, because a `View` holding a closure can never compare equal
    /// to itself.** `KeyboardView` observes that one object, so `suggestions`,
    /// `shift`, `documentHasText` or a dictation level tick each rebuild the
    /// whole grid — and SwiftUI cannot skip a body it cannot prove is unchanged,
    /// which for a struct carrying function values it never can. Roughly forty
    /// keys, two shadows and a gradient each, several times per letter. The worst
    /// offender was the model call's 60 Hz `workingPhase` tick; the orbit keeps
    /// its own clock now (`ControlOrbit`), but every published value above still
    /// makes this conformance earn its place. `KeyView+Keys` already went to the
    /// trouble of handing letter keys `activity: .idle` so one key's call cannot
    /// rebuild the grid; that intent could not work until this existed.
    ///
    /// **Ignoring the closures is sound rather than convenient, and it rests on
    /// what they capture.** Every one of them captures `controller`, whose
    /// identity never changes, plus values that are compared here: `onRepeat`,
    /// `onSpaceTouch`, `onCharacterTouch` and `onPopupLayerChange` are chosen by
    /// `spec.cap`, `onAlternate` by `spec` and by the three alternates lists, and
    /// `onPress` is the same expression for every key. So a stale closure held
    /// past an update that compared equal cannot behave differently from a fresh
    /// one. Add a stored property to this view and it must be added here too, or
    /// the key stops following it.
    ///
    /// `@State`, `@GestureState` and `@Environment` are unaffected: SwiftUI tracks
    /// those separately, so a press, a cancelled touch, a rotation or a Dynamic
    /// Type change still redraws the key that owns it.
    public static func == (lhs: KeyView, rhs: KeyView) -> Bool {
        lhs.spec == rhs.spec
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.language == rhs.language
            && lhs.shift == rhs.shift
            && lhs.indication == rhs.indication
            && lhs.enabledLanguages == rhs.enabledLanguages
            && lhs.toneAlternates == rhs.toneAlternates
            && lhs.fixAlternates == rhs.fixAlternates
            && lhs.copyclipAlternates == rhs.copyclipAlternates
            && lhs.isEmojiOpen == rhs.isEmojiOpen
            && lhs.isCopyClipOpen == rhs.isCopyClipOpen
            && lhs.showsActionCaption == rhs.showsActionCaption
            && lhs.usesNeutralActionTint == rhs.usesNeutralActionTint
            && lhs.isActionActive == rhs.isActionActive
            && lhs.isDisabled == rhs.isDisabled
            && lhs.disabledHint == rhs.disabledHint
            && lhs.dictationState == rhs.dictationState
            && lhs.activity == rhs.activity
            && lhs.palette == rhs.palette
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

            activityChrome

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
        .overlay(alignment: alternatesPopupAlignment) { alternatesPopup }
        .overlay(alignment: .bottom) { languageCallout }
        // Instant on the way down: even an 80ms ease-out is longer than a tap,
        // so the pressed fill the tokens specify was a colour the thumb never
        // saw. The release still eases, so the flash is the full grey rather
        // than a smear back to white. After the overlays so a hold that opens
        // the strip is in the same transaction.
        .animation(isPressed ? nil : Theme.Motion.press, value: isPressed)
        // High enough that a balloon wider than the key sits above every
        // neighbour, not only the ones SwiftUI happened to draw first. An
        // active action key uses the same raise so Reply's orange cap is
        // not sliced by Fix.
        .zIndex((raisesPopupLayer || isActionActive) ? 10 : 0)
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
            reportPopupLayer(touching)
        }
        // And if the key is taken off screen mid-press — a plane switch, a
        // language switch, the keyboard being dismissed — the touch never ends at
        // all. `@State` releasing the repeater covers this too; this makes it
        // prompt rather than dependent on when the storage is torn down.
        .onDisappear {
            endPress()
            reportPopupLayer(false)
        }
        .background {
            GeometryReader { proxy in
                let minX = proxy.frame(in: .global).minX - keyboardCanvasOriginX
                Color.clear
                    .onAppear { keyMinXInCanvas = minX }
                    .onChange(of: minX) { _, x in keyMinXInCanvas = x }
            }
        }
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
                ForEach(alternatePickerItems, id: \.self) { item in
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
        if case .working = activity {
            return "\(workingTitle(for: cap)), working"
        }
        if let spoken = spec.spokenLabel { return spoken }
        switch cap {
        case .dictation:
            return dictationState.accessibilityLabel
        default:
            return cap.accessibilityLabel(isRightToLeft: language.isRightToLeft)
        }
    }

    /// The action's own title, so VoiceOver names the thing that is running
    /// rather than the key's idle name ("One-tap rewrite, working").
    func workingTitle(for cap: KeyCap) -> String {
        switch cap {
        case .aiFix: return AIAction.fix.title
        case .aiReply: return AIAction.reply.title
        case .quickTone: return AIAction.rewrite.title
        default:
            return spec.spokenLabel
                ?? cap.accessibilityLabel(isRightToLeft: language.isRightToLeft)
        }
    }

    /// Orbit under the label, drawn to the cap's own shape. Recording draws
    /// in the icon slot instead — see `actionLabel`.
    @ViewBuilder
    var activityChrome: some View {
        ControlActivityChrome(activity: activity, cornerRadius: Theme.Radius.key)
    }

    /// Finger down, or the hold strip already open. Same signal the key uses
    /// to sit above its neighbours.
    var raisesPopupLayer: Bool { isTouching || isPressed || showsAlternates }

    /// The action row climbs over the letters only for a stacked hold menu.
    /// A letter press must not raise that row, or the balloon is under Reply
    /// again. Finger-down, not popup-open, so the menu is already in front
    /// when the 200ms wait ends.
    func reportPopupLayer(_ touching: Bool) {
        onPopupLayerChange?(touching && alternatesAreStacked)
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

    /// Below this a key does not name itself unless it was told to.
    ///
    /// **A key wide enough to name itself should, and one that is not should not
    /// try.** The action row splits the width six ways, which is about 62pt on a
    /// 375pt screen — room for a word. The same action dragged into the bottom row
    /// beside the space bar is one unit, about 32pt, where a caption either
    /// truncates to two letters or scales into a hairline. The width is what
    /// decides rather than the row, because `KeyboardLayout.widths` is what
    /// actually resolves `.fill`.
    ///
    /// **It is a default rather than a rail**, and it is applied in
    /// `KeySpec.showsActionCaption(inRow:width:)` rather than at the moment of
    /// drawing, so a user who turns a narrow key's label on in the editor gets
    /// the squeezed word they asked for instead of a switch that does nothing.
    ///
    /// 56 is the narrowest width at which `Rewrite` — the longest of the four
    /// captions — fits at 9pt with the 4pt insets, measured the way
    /// `SuggestionBar.toneButtonWidth` was.
    static let captionMinimumWidth: CGFloat = 56
}
