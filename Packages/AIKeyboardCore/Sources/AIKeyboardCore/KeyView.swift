import SwiftUI

/// One key. Owns its own press state so a touch registers on finger-down rather
/// than on lift, which is what makes typing feel immediate.
public struct KeyView: View {

    private let spec: KeySpec
    private let width: CGFloat
    private let height: CGFloat
    private let language: KeyboardLanguage
    private let shift: ShiftState
    /// What the space bar should say about the language instead of "space", and
    /// whether the finger choosing it is still down. Nil on every other key.
    private let indication: LanguageSwitchIndication?
    /// The languages the space bar can slide between, in the order a slide moves
    /// through them. Read only by the space bar, which prints their codes, and
    /// passed to every key the way `language` and `shift` already are.
    private let enabledLanguages: [KeyboardLanguage]
    /// The registers a long press on the one-tap rewrite key offers, default
    /// first. Empty on every other key, and passed in for the same reason
    /// `enabledLanguages` is: the list comes from a stored setting in another
    /// process and a `KeySpec` is a value that cannot read one.
    private let toneAlternates: [String]
    private let onPress: (KeyCap) -> Void
    private let onRepeat: (() -> Void)?
    private let onAlternate: ((String) -> Void)?
    /// Set only on the space bar, and its presence is what makes that key defer:
    /// a touch here may still turn into a language slide, so it reports the touch
    /// and lets the controller decide whether it was a space.
    private let onSpaceTouch: ((SpaceTouchPhase) -> Void)?

    @State private var isPressed = false
    @State private var repeater = KeyRepeater()
    @State private var alternatesTask: Task<Void, Never>?
    @State private var showsAlternates = false
    @State private var selectedAlternate = 0

    /// True for as long as a touch is on this key.
    ///
    /// **The only signal that survives a cancelled gesture**, which is the whole
    /// reason it is here rather than a second `@State` flag. SwiftUI does not call
    /// `DragGesture.onEnded` when a touch sequence is cancelled — a banner, a
    /// Control Centre pull, the host resigning first responder — and `onEnded` was
    /// the only place the repeat loop was ever stopped.
    @GestureState private var isTouching = false

    public init(
        spec: KeySpec,
        width: CGFloat,
        height: CGFloat,
        language: KeyboardLanguage,
        shift: ShiftState,
        indication: LanguageSwitchIndication? = nil,
        enabledLanguages: [KeyboardLanguage] = [],
        toneAlternates: [String] = [],
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

    private var accessibilityValue: String {
        guard spec.cap == .space else { return "" }
        guard let indication else {
            return enabledLanguages.count > 1 ? language.displayName : ""
        }
        return indication.isPending
            ? "Release for \(indication.language.displayName)"
            : indication.language.displayName
    }

    // MARK: Press handling

    /// The space bar, and only when someone is listening for a slide. Everything
    /// keyed off this defers rather than committing on finger-down.
    private var slidesForLanguage: Bool { spec.cap == .space && onSpaceTouch != nil }

    /// The one-tap rewrite key, when it has registers to offer.
    ///
    /// **It commits on lift rather than on finger-down, and it is the only key
    /// besides the space bar that does.** Every other key acts immediately because
    /// that is what makes typing feel instant, and for a letter a long press that
    /// picks an alternate simply replaces the character already inserted. This key
    /// runs a *model call*: firing on finger-down would spend one on the default
    /// tone every time the user held the key to choose a different one, and
    /// `beginWork` cancels its predecessor, so the answer being paid for would be
    /// thrown away by the register that was actually wanted. A tap still runs the
    /// default — it just runs it 100ms later, on the lift, which no thumb can feel.
    private var runsOnLift: Bool { spec.cap == .quickTone && toneAlternates.count > 1 }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { value in
                guard isPressed else {
                    isPressed = true
                    // Every key but this one commits on finger-down, which is
                    // what makes typing feel immediate. The space bar defers,
                    // because the same touch may still turn out to be a language
                    // slide. `SpaceTouchPhase` carries why deferring beat
                    // inserting and repairing, and `KeyboardController.press`
                    // carries what deferring costs and how it is paid.
                    if slidesForLanguage {
                        onSpaceTouch?(.began)
                    } else if !runsOnLift {
                        onPress(spec.cap)
                    }
                    startRepeatIfNeeded()
                    startAlternatesIfNeeded()
                    return
                }
                if slidesForLanguage {
                    onSpaceTouch?(.moved(value.translation.width))
                    return
                }
                // Every later change is either a finger sliding across an open
                // alternates popup or a finger wobbling on an ordinary key. Only
                // the first is worth reacting to.
                guard showsAlternates else { return }
                selectedAlternate = alternateIndex(at: value.location)
            }
            .onEnded { value in
                if slidesForLanguage {
                    // Not `endPress()`: that is the cancellation path and reports
                    // the touch as abandoned, which would throw away the slide
                    // this lift is committing. The space bar has no repeat and no
                    // alternates, so releasing the press is all there is to undo.
                    isPressed = false
                    onSpaceTouch?(.ended(value.translation.width))
                    return
                }
                let picked = showsAlternates ? alternateIndex(at: value.location) : 0
                endPress()
                // Index 0 is what the key would have done on its own — the
                // character it already inserted, or the default tone it has not run
                // yet — so lifting on it means the long press changed nothing.
                guard picked > 0, picked < alternateItems.count else {
                    // The tap this key deferred. See `runsOnLift`.
                    if runsOnLift { onPress(spec.cap) }
                    return
                }
                onAlternate?(alternateItems[picked])
            }
    }

    /// Everything a finger leaving this key has to undo, on every path it can
    /// leave by. Idempotent, because a normal lift arrives here twice: once from
    /// `onEnded` and once from the gesture state resetting behind it.
    private func endPress() {
        // Read before the reset, because a normal lift has already cleared it in
        // `onEnded` and must not be reported as a cancellation on the way past.
        let wasPressed = isPressed
        isPressed = false
        showsAlternates = false
        repeater.stop()
        alternatesTask?.cancel()
        alternatesTask = nil
        if wasPressed, slidesForLanguage { onSpaceTouch?(.cancelled) }
    }

    /// Delete accelerates while held, the way every other keyboard behaves.
    private func startRepeatIfNeeded() {
        guard let onRepeat, spec.cap == .backspace else { return }
        repeater.start(onRepeat)
    }

    /// Holding a key with alternates opens them, the way it does on the system
    /// keyboard. Nothing happens for a key that has none, which is most of them.
    private func startAlternatesIfNeeded() {
        // `alternateItems` rather than `spec.alternates`, because the one-tap
        // rewrite key's registers do not live on the spec — they come from a
        // setting in the containing app. For a letter the two say the same thing:
        // the list is the character plus its alternates, so "more than one" is
        // exactly "has alternates".
        guard onAlternate != nil, alternateItems.count > 1 else { return }
        alternatesTask?.cancel()
        alternatesTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            selectedAlternate = 0
            Feedback.modifierPress()
            withAnimation(Theme.Motion.quick) { showsAlternates = true }
        }
    }

    // MARK: Alternates

    /// What the popup offers: the key's own character first, then its alternates.
    ///
    /// The character itself leads so that lifting a finger that has not moved
    /// commits nothing new — a long press that the user did not follow through on
    /// must not silently swap the letter they already typed.
    /// What the popup offers, for the two kinds of key that have one.
    ///
    /// A letter offers its own character and then its accents. The one-tap rewrite
    /// key offers the registers, which arrive already ordered with the default
    /// first — see `KeyboardController.toneAlternates` for why that order is not
    /// cosmetic.
    private var alternateItems: [String] {
        if spec.cap == .quickTone { return toneAlternates }
        guard case .character(let value) = spec.cap else { return [] }
        let base = shift.isUppercase ? language.uppercased(value) : value
        return [base]
            + spec.alternates.map { shift.isUppercase ? language.uppercased($0) : $0 }
    }

    /// **Words stack, glyphs run along a row.** Seven registers at a readable size
    /// is about 1,000 points of width on a 393-point screen, so the strip that
    /// works for five accented `e`s cannot hold them. Stacking also puts the list
    /// where the thumb already is: this key is in the action row at the bottom of
    /// the keyboard, so the popup opens upward over the keys, which is empty space
    /// for as long as the finger is down.
    private var alternatesAreStacked: Bool { spec.cap == .quickTone }

    private var alternateItemWidth: CGFloat { alternatesAreStacked ? 156 : max(width, 34) }
    private var alternateItemHeight: CGFloat {
        alternatesAreStacked ? 34 : height * 1.15
    }

    private var alternatesWidth: CGFloat {
        alternatesAreStacked
            ? alternateItemWidth
            : alternateItemWidth * CGFloat(max(1, alternateItems.count))
    }

    private var alternatesHeight: CGFloat {
        alternatesAreStacked
            ? alternateItemHeight * CGFloat(max(1, alternateItems.count))
            : alternateItemHeight
    }

    /// Which item the finger is over, in the key's own coordinate space.
    ///
    /// A row is centred on the key, so its leading edge sits half its overhang to
    /// the left of x = 0. A stack sits directly above the key: its bottom edge is
    /// 6 points above the key's top, so it spans `-(6 + height)` to `-6` and the
    /// index runs downward from there.
    private func alternateIndex(at point: CGPoint) -> Int {
        let index: Int
        if alternatesAreStacked {
            index = Int(((point.y + 6 + alternatesHeight) / alternateItemHeight).rounded(.down))
        } else {
            let overhang = (alternatesWidth - width) / 2
            index = Int(((point.x + overhang) / alternateItemWidth).rounded(.down))
        }
        return min(max(index, 0), max(0, alternateItems.count - 1))
    }

    @ViewBuilder
    private var alternatesPopup: some View {
        if showsAlternates, alternateItems.count > 1 {
            Group {
                if alternatesAreStacked {
                    VStack(spacing: 0) {
                        ForEach(Array(alternateItems.enumerated()), id: \.offset) { index, item in
                            alternateItem(item, index: index)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(alternateItems.enumerated()), id: \.offset) { index, item in
                            alternateItem(item, index: index)
                        }
                    }
                }
            }
            // Laid out left to right whatever the keyboard's direction, because
            // `alternateIndex(at:)` reads a raw coordinate and a mirrored stack
            // would put item 0 under the far end of it.
            .environment(\.layoutDirection, .leftToRight)
            .frame(width: alternatesWidth, height: alternatesHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Keys.letter)
                    .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 5, y: 2)
            )
            .offset(y: -height - 6)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func alternateItem(_ item: String, index: Int) -> some View {
        Text(item)
            .font(
                alternatesAreStacked
                    ? .system(size: 15, weight: .regular) : .system(size: 24, weight: .light)
            )
            .foregroundStyle(index == selectedAlternate ? Theme.Text.onBrand : Theme.Keys.label)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: alternateItemWidth, height: alternateItemHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                    .fill(index == selectedAlternate ? Theme.Brand.solid : Color.clear)
            )
    }

    // MARK: Appearance

    /// Whether this key carries a cap of its own at rest.
    ///
    /// **Only the keys that insert something do.** Letters and the space bar are
    /// what a finger aims at a hundred times a message, and a drawn cap is what it
    /// aims at. Shift, delete, the plane switch, globe, return and dictation are
    /// controls rather than targets, so they are drawn as bare glyphs on the
    /// keyboard's own surface. Their touch targets are unchanged — `KeyboardLayout`
    /// still gives them the same widths — but the boundary is no longer painted,
    /// which is why the press cap below is not decoration: with the resting cap
    /// gone it is the whole of the feedback that a control was hit.
    private var hasRestingCap: Bool {
        switch spec.cap {
        case .character, .space: return true
        default: return false
        }
    }

    private var showsCap: Bool { hasRestingCap || isPressed }

    private var background: Color {
        guard hasRestingCap else {
            // Under a finger a control takes the *letter* cap, not the old
            // function grey. Grey on grey was legible as a press only because a
            // resting cap sat beside it to compare against; with nothing drawn at
            // rest the pressed state has to be the light one.
            return isPressed ? Theme.Keys.functionPressed : .clear
        }
        return isPressed ? Theme.Keys.letterPressed : Theme.Keys.letter
    }

    @ViewBuilder
    private var label: some View {
        switch spec.cap {
        case .character(let value):
            // The bottom row's punctuation key wears its long presses in
            // miniature above the mark it types. Everywhere else the popup is a
            // shortcut to something the user already knows is there — an accent
            // on the letter it belongs to — but this key's whole purpose is the
            // four marks that are not drawn on it, and a lone full stop is the
            // faintest cap on the keyboard. The hint is what says to hold it.
            // `addressableID`, not `id`: compiled from a custom layout this key is
            // `punctuation#a1b2c3d4`, and against the raw id the miniature marks
            // silently stopped being drawn.
            if spec.addressableID == KeyboardLayout.punctuationKeyID, !spec.alternates.isEmpty {
                VStack(spacing: 0) {
                    Text(spec.alternates.prefix(3).joined())
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Theme.Keys.label.opacity(0.5))
                    Text(value)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.Keys.label)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            } else {
                Text(shift.isUppercase ? language.uppercased(value) : value)
                    .font(.system(size: characterFontSize, weight: .light))
                    .foregroundStyle(Theme.Keys.label)
            }

        case .shift:
            // **The fill is the entire shift state now.** The key used to say it
            // twice, with a white cap under a filled arrow; the cap is gone with
            // every other control's, so this glyph carries it alone.
            Image(systemName: shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift"))
                .font(Theme.Glyph.font(19))
                .foregroundStyle(Theme.Keys.label)

        case .backspace:
            Image(systemName: "delete.left")
                .font(Theme.Glyph.font(19))
                .foregroundStyle(Theme.Keys.label)

        case .plane(_, let text):
            Text(text)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Theme.Keys.label)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

        case .globe:
            Image(systemName: "globe")
                .font(Theme.Glyph.font(18))
                .foregroundStyle(Theme.Keys.label)

        case .space:
            spaceLabel

        case .ret:
            // The glyph in every language, never a word. Apple ships no localised
            // return-key cap — the only per-language string on the machine is
            // VoiceOver's phrasing ("Volver", "Клавиша «Ввод»"), not a key cap —
            // so a word here is either English on a Greek keyboard or a
            // translation nobody has checked. The arrow needs neither.
            Image(systemName: "return")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Keys.label)

        case .dictation:
            // Outline, not `mic.fill`. A solid microphone reads as *recording* —
            // it is the shape the banner uses for exactly that — and this key is
            // the one that has not started yet.
            actionLabel(icon: "mic", title: "Dictate", tint: Theme.Brand.solid)

        case .emoji:
            // Neutral rather than brand: `Theme.Brand` is reserved for the AI
            // moments, and this one opens a grid of pictures.
            actionLabel(icon: "face.smiling", title: "Emoji", tint: Theme.Keys.label)

        case .aiMenu:
            // The same mark the suggestion bar's sparkle wears, because it opens
            // the same panel.
            SparkleMark(size: 18)

        case .quickTone:
            // `AIAction.rewrite`'s own icon, and never a sparkle in any count —
            // see `SuggestionBar.toneButtonSymbol` and `ToneIconTests` for the
            // pairing that has already shipped once.
            //
            // **The word matters more here than on any other key in the row.**
            // `arrow.triangle.2.circlepath` alone is a refresh glyph: it says
            // nothing about rewriting, nothing about AI, and it is the same
            // "a glyph is not a name" defect that has now been fixed twice on this
            // one control — first when it wore the tone's own symbol in the bar,
            // then when the tone name was moved under it. It does not name the
            // *tone* here, unlike the bar button it replaced, because the register
            // is a long press away and the label has to say what a tap does.
            actionLabel(
                icon: SuggestionBar.toneButtonSymbol,
                title: AIAction.rewrite.title,
                tint: Theme.Brand.solid)

        case .cursorLeft:
            Image(systemName: "arrow.left")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Keys.label)

        case .cursorRight:
            Image(systemName: "arrow.right")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Keys.label)

        case .hideKeyboard:
            Image(systemName: "keyboard.chevron.compact.down")
                .font(Theme.Glyph.font(17))
                .foregroundStyle(Theme.Keys.label)

        case .aiReply:
            actionLabel(
                icon: AIAction.reply.icon, title: AIAction.reply.title, tint: Theme.Brand.solid)

        case .aiFix:
            actionLabel(
                icon: AIAction.fix.icon, title: AIAction.fix.title, tint: Theme.Brand.solid)
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

    /// An action drawn as a key: its glyph, and its name under it when there is
    /// room.
    ///
    /// **All five keys of the action row go through this, and the first version
    /// only sent two.** Reply and Fix were captioned and emoji, Rewrite and
    /// dictation were left as bare glyphs, so the row read as two labelled buttons
    /// beside three unexplained symbols — and the worst of the three was Rewrite,
    /// whose `arrow.triangle.2.circlepath` is a refresh glyph to anyone who has not
    /// been told otherwise. No test could see it: the accessibility label comes
    /// from `KeyCap.accessibilityLabel` and was correct throughout, so every
    /// assertion passed against a row nobody could read. It took a screenshot.
    ///
    /// The tint is per key rather than fixed, because `Theme.Brand` is reserved for
    /// the AI moments and the emoji key opens a grid of pictures.
    @ViewBuilder
    private func actionLabel(icon: String, title: String, tint: Color) -> some View {
        if width >= Self.captionMinimumWidth {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(Theme.Glyph.medium(15))
                Text(title)
                    .font(Font(SuggestionBar.toneLabelFont))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Space.xxs)
        } else {
            Image(systemName: icon)
                .font(Theme.Glyph.medium(16))
                .foregroundStyle(tint)
        }
    }

    /// The space bar: a strip of language codes over the word for space, with a
    /// chevron at each end of the key. `SpaceSwipe.codeStrip` carries why it is
    /// that rather than the single language name it used to be.
    ///
    /// **The chevrons are the only thing on this keyboard that says the gesture
    /// exists.** Naming the language after a switch and during a slide is
    /// feedback for somebody who already knows; a caption reading "space" is what
    /// somebody who does not sees, and they never find it. They are SF Symbols
    /// rather than the guillemets ‹ ›, which Unicode marks as mirrored characters
    /// and which therefore swap shape around a right-to-left name.
    ///
    /// They sit in a layer of their own, pushed to the key's two edges, rather than
    /// either side of the codes: the strip changes width as the codes under it
    /// change, and chevrons that hugged it would wander about the key on every
    /// switch. Everything is inside the key's own fixed frame, so nothing around it
    /// moves either, and pinned left to right because it is a control — the
    /// chevrons point at the two directions a finger can travel, and those do not
    /// swap when the language does. `SpaceSwipe.language` carries why.
    private var spaceLabel: some View {
        // The lit code follows the finger, so a slide walks the highlight along the
        // strip and — past three languages, where the strip is a window — scrolls
        // it. Nil until a finger is down, which is the resting state.
        let lit = indication?.language ?? language
        let codes = SpaceSwipe.codeStrip(active: lit, in: enabledLanguages)
        return ZStack {
            if !codes.isEmpty {
                HStack(spacing: 0) {
                    slideChevron("chevron.compact.left")
                    Spacer(minLength: 0)
                    slideChevron("chevron.compact.right")
                }
            }
            VStack(spacing: 0) {
                if !codes.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(codes, id: \.self) { code in
                            Text(code.shortName)
                                .font(.system(size: 12, weight: code == lit ? .semibold : .regular))
                                .foregroundStyle(
                                    code == lit
                                        ? Theme.Keys.label
                                        : Theme.Keys.secondaryLabel.opacity(0.6))
                        }
                    }
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                }
                Text(indication?.language.nativeName ?? language.spaceLabel)
                    .font(
                        .system(
                            size: codes.isEmpty ? 15 : 11,
                            weight: indication == nil ? .light : .medium)
                    )
                    .foregroundStyle(
                        indication == nil ? Theme.Keys.secondaryLabel : Theme.Keys.label
                    )
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func slideChevron(_ name: String) -> some View {
        Image(systemName: name)
            // One step above the house weight, and deliberately. These sit at 0.55
            // opacity on a grey key: a light hairline at this size disappears
            // altogether, and they are the only thing that says the slide exists.
            // Bigger than they were now that they live at the key's edges rather
            // than tucked against the caption, which is where the room is.
            .font(Theme.Glyph.medium(15))
            .foregroundStyle(Theme.Keys.secondaryLabel.opacity(0.55))
    }

    /// Scripts carry different amounts of ink, and a twelve-column layout has
    /// narrower keys than a ten-column one, so the size follows both.
    private var characterFontSize: CGFloat {
        let base: CGFloat
        switch language.script {
        case .hebrew, .arabic, .thaana: base = 23
        // The scripts whose letters carry the most ink per glyph, so they need
        // the most room inside a key that is no wider.
        case .devanagari, .tamil, .georgian: base = 22
        case .latin, .cyrillic, .greek, .other: base = 25
        }
        return min(base, width * 0.78)
    }

    /// The balloon that pops above a letter while the finger is down, so the
    /// glyph stays readable under the thumb.
    @ViewBuilder
    private var callout: some View {
        if isPressed, !showsAlternates, case .character(let value) = spec.cap {
            Text(shift.isUppercase ? language.uppercased(value) : value)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Theme.Keys.label)
                .frame(width: width * 1.35, height: height * 1.05)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Theme.Keys.letter)
                        .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 4, y: 2)
                )
                .offset(y: -height - 4)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// The same balloon, for the language a slide along the space bar is pointing
    /// at. Only while the finger is down: once it lifts the thumb is out of the
    /// way and the space bar's own caption is the confirmation.
    @ViewBuilder
    private var languageCallout: some View {
        if let indication, indication.isPending {
            LanguageCallout(indication: indication)
                .offset(y: -height - 6)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

// MARK: - Key repeat

/// The accelerating repeat behind a held delete key.
///
/// **Lifted out of `KeyView` because it is the most dangerous loop in the
/// product and a `@State` task inside a view body cannot be tested.** It was a
/// bare `Task` that ran `while !Task.isCancelled` with no bound and exactly one
/// cancellation site, `DragGesture.onEnded` — which SwiftUI does not call for a
/// *cancelled* touch. Until the typing fix that was inert, because
/// `KeyboardController.target` was `weak` and always nil on a device, so the loop
/// deleted from nothing. With a strong target and a proxy re-resolved per call,
/// the same loop deletes from whichever document is focused at that moment, 22
/// times a second, with a haptic each time, until iOS kills the extension.
///
/// Three things stop it, and none of them is enough alone. `KeyView` resets a
/// `@GestureState`, which fires on cancellation as well as on lift. `deinit`
/// cancels, so a discarded key cannot leave a task running — which is why `start`
/// copies its timings into locals rather than letting the task capture `self`; a
/// task holding the repeater alive would never let `deinit` run. And the loop
/// counts its own repeats: roughly nine seconds of continuous deletion, about two
/// hundred characters, which is longer than any message this keyboard is for.
/// A user who genuinely wants to delete more lifts and presses again, the way
/// every hardware key repeat that has ever shipped behaves after a timeout.
@MainActor
final class KeyRepeater {

    private var task: Task<Void, Never>?

    private let initialDelay: Duration
    private let firstInterval: Duration
    private let shortestInterval: Duration
    private let acceleration: Duration
    private let limit: Int

    /// Defaults are the shipping feel; the parameters exist so a test can run the
    /// whole loop, including its end, in a few milliseconds.
    init(
        initialDelay: Duration = .milliseconds(420),
        firstInterval: Duration = .milliseconds(110),
        shortestInterval: Duration = .milliseconds(45),
        acceleration: Duration = .milliseconds(8),
        limit: Int = 200
    ) {
        self.initialDelay = initialDelay
        self.firstInterval = firstInterval
        self.shortestInterval = shortestInterval
        self.acceleration = acceleration
        self.limit = limit
    }

    func start(_ tick: @escaping @MainActor () -> Void) {
        stop()
        // Copied out deliberately. A closure that reads `self.limit` captures the
        // repeater, the repeater then outlives the view that owned it, and the
        // `deinit` below never runs — which is the bug this type exists to close.
        let initialDelay = initialDelay
        let firstInterval = firstInterval
        let shortestInterval = shortestInterval
        let acceleration = acceleration
        let limit = limit

        task = Task { @MainActor in
            try? await Task.sleep(for: initialDelay)
            var interval = firstInterval
            var repeats = 0
            while !Task.isCancelled, repeats < limit {
                tick()
                repeats += 1
                try? await Task.sleep(for: interval)
                interval = max(shortestInterval, interval - acceleration)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
