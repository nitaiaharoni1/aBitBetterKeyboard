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
    let onPress: (KeyCap) -> Void
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
        onPress: @escaping (KeyCap) -> Void,
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
        self.onPress = onPress
        self.onRepeat = onRepeat
        self.onAlternate = onAlternate
        self.onSpaceTouch = onSpaceTouch
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(background)
                .shadow(color: Theme.Keys.shadow.opacity(showsCap ? 0.45 : 0), radius: 0, x: 0, y: 1)

            label
        }
        .frame(width: width, height: height)
        .overlay(alignment: .bottom) { callout }
        .overlay(alignment: .bottom) { alternatesPopup }
        .overlay(alignment: .bottom) { languageCallout }
        .zIndex(isPressed ? 1 : 0)
        .contentShape(Rectangle())
        .gesture(pressGesture)
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
        .accessibilityLabel(spec.cap.accessibilityLabel)
        // The whole indication is visual, so without this a VoiceOver user
        // sliding along the space bar is told nothing at all about where they
        // are in the list.
        .accessibilityValue(accessibilityValue)
        // The chevrons are the whole of the gesture's affordance and a VoiceOver
        // user cannot see them, so they are said instead.
        .accessibilityHint(
            spec.cap == .space
                ? SpaceSwipe.slideHint(languageCount: enabledLanguages.count) : ""
        )
        .accessibilityAddTraits(.isKeyboardKey)
        // **A long press and a slide is unusable under VoiceOver, so the registers
        // get a non-gesture route.** The same rule the layout editor is built on:
        // every edit there has a button as well as a drag. Without this the only
        // way to change tone with VoiceOver on would be to add the AI-actions key
        // in the editor first, which is a setting nobody should need to find in
        // order to reach a feature the keyboard already has.
        .accessibilityActions {
            if spec.cap == .quickTone {
                ForEach(alternateItems.dropFirst(), id: \.self) { tone in
                    Button("Rewrite as \(tone)") { onAlternate?(tone) }
                }
            }
        }
    }

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
