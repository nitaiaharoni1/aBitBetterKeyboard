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
    /// How many languages the space bar can slide between. Read only by the space
    /// bar, and passed to every key the way `language` and `shift` already are.
    private let enabledLanguageCount: Int
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
        enabledLanguageCount: Int = 1,
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
        self.enabledLanguageCount = enabledLanguageCount
        self.onPress = onPress
        self.onRepeat = onRepeat
        self.onAlternate = onAlternate
        self.onSpaceTouch = onSpaceTouch
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(background)
                .shadow(color: Theme.Keys.shadow.opacity(0.45), radius: 0, x: 0, y: 1)

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
        .accessibilityIdentifier("key-\(spec.id)")
        .accessibilityLabel(spec.cap.accessibilityLabel)
        // The whole indication is visual, so without this a VoiceOver user
        // sliding along the space bar is told nothing at all about where they
        // are in the list.
        .accessibilityValue(accessibilityValue)
        // The chevrons are the whole of the gesture's affordance and a VoiceOver
        // user cannot see them, so they are said instead.
        .accessibilityHint(
            spec.cap == .space
                ? SpaceSwipe.slideHint(languageCount: enabledLanguageCount) : ""
        )
        .accessibilityAddTraits(.isKeyboardKey)
    }

    private var accessibilityValue: String {
        guard spec.cap == .space else { return "" }
        guard let indication else {
            return enabledLanguageCount > 1 ? language.displayName : ""
        }
        return indication.isPending
            ? "Release for \(indication.language.displayName)"
            : indication.language.displayName
    }

    // MARK: Press handling

    /// The space bar, and only when someone is listening for a slide. Everything
    /// keyed off this defers rather than committing on finger-down.
    private var slidesForLanguage: Bool { spec.cap == .space && onSpaceTouch != nil }

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
                    } else {
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
                selectedAlternate = alternateIndex(at: value.location.x)
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
                let picked = showsAlternates ? alternateIndex(at: value.location.x) : 0
                endPress()
                // Index 0 is the character the key already inserted on finger-
                // down, so lifting on it means the long press changed nothing.
                guard picked > 0, picked < alternateItems.count else { return }
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
        guard onAlternate != nil, !spec.alternates.isEmpty else { return }
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
    private var alternateItems: [String] {
        guard case .character(let value) = spec.cap else { return [] }
        let base = shift.isUppercase ? language.uppercased(value) : value
        return [base]
            + spec.alternates.map { shift.isUppercase ? language.uppercased($0) : $0 }
    }

    private var alternateItemWidth: CGFloat { max(width, 34) }

    private var alternatesWidth: CGFloat {
        alternateItemWidth * CGFloat(max(1, alternateItems.count))
    }

    /// Which item the finger is over, in the key's own coordinate space. The
    /// popup is centred on the key, so its leading edge sits half its overhang to
    /// the left of x = 0 and the index runs from there.
    private func alternateIndex(at x: CGFloat) -> Int {
        let overhang = (alternatesWidth - width) / 2
        let index = Int(((x + overhang) / alternateItemWidth).rounded(.down))
        return min(max(index, 0), max(0, alternateItems.count - 1))
    }

    @ViewBuilder
    private var alternatesPopup: some View {
        if showsAlternates, alternateItems.count > 1 {
            HStack(spacing: 0) {
                ForEach(Array(alternateItems.enumerated()), id: \.offset) { index, item in
                    Text(item)
                        .font(.system(size: 24))
                        .foregroundStyle(
                            index == selectedAlternate ? Theme.Text.onBrand : Theme.Keys.label
                        )
                        .frame(width: alternateItemWidth, height: height * 1.15)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                                .fill(index == selectedAlternate ? Theme.Brand.solid : Color.clear)
                        )
                }
            }
            // Laid out left to right whatever the keyboard's direction, because
            // `alternateIndex(at:)` reads a raw x coordinate and a mirrored HStack
            // would put item 0 under the highest x.
            .environment(\.layoutDirection, .leftToRight)
            .frame(width: alternatesWidth, height: height * 1.15)
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

    // MARK: Appearance

    private var background: Color {
        if case .character = spec.cap {
            return isPressed ? Theme.Keys.letterPressed : Theme.Keys.letter
        }
        if spec.cap == .space {
            return isPressed ? Theme.Keys.letterPressed : Theme.Keys.letter
        }
        if spec.cap == .ret {
            return isPressed ? Theme.Keys.functionPressed : Theme.Keys.function
        }
        if spec.cap == .shift && shift != .off {
            return Theme.Keys.letter
        }
        return isPressed ? Theme.Keys.functionPressed : Theme.Keys.function
    }

    @ViewBuilder
    private var label: some View {
        switch spec.cap {
        case .character(let value):
            Text(shift.isUppercase ? language.uppercased(value) : value)
                .font(.system(size: characterFontSize, weight: .regular))
                .foregroundStyle(Theme.Keys.label)

        case .shift:
            Image(systemName: shift == .locked ? "capslock.fill" : (shift == .on ? "shift.fill" : "shift"))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(shift == .off ? Theme.Keys.label : Theme.Keys.label)

        case .backspace:
            Image(systemName: "delete.left")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.Keys.label)

        case .plane(_, let text):
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Theme.Keys.label)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

        case .globe:
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.Keys.label)

        case .space:
            spaceLabel

        case .ret:
            // A word only where a verified one exists. Apple ships no localised
            // return-key cap — see `KeyboardLanguage.returnLabel` — so rather
            // than translate one for fifty languages this draws the glyph the
            // key has always had.
            if let caption = language.returnLabel {
                Text(caption)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.Keys.label)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } else {
                Image(systemName: "return")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.Keys.label)
            }

        case .dictation:
            Image(systemName: "mic.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.Brand.gradient)
        }
    }

    /// The space bar's caption, and the two chevrons that say it slides.
    ///
    /// **The chevrons are the only thing on this keyboard that says the gesture
    /// exists.** Naming the language after a switch and during a slide is
    /// feedback for somebody who already knows; a caption reading "space" is what
    /// somebody who does not sees, and they never find it. See
    /// `SpaceSwipe.restingCaption`. They are SF Symbols rather than the guillemets
    /// ‹ ›, which Unicode marks as mirrored characters and which therefore swap
    /// shape around a right-to-left name.
    ///
    /// One row inside the key's own fixed frame, so nothing around it moves when
    /// the caption changes, and pinned left to right because it is a control:
    /// the chevrons point at the two directions a finger can travel, and those do
    /// not swap when the language does — `SpaceSwipe.language` carries why.
    private var spaceLabel: some View {
        HStack(spacing: 5) {
            if SpaceSwipe.showsSlideAffordance(languageCount: enabledLanguageCount) {
                slideChevron("chevron.compact.left")
            }
            Text(
                indication?.language.nativeName
                    ?? SpaceSwipe.restingCaption(
                        for: language, languageCount: enabledLanguageCount)
            )
            .font(.system(size: 15, weight: indication == nil ? .regular : .semibold))
            .foregroundStyle(indication == nil ? Theme.Keys.secondaryLabel : Theme.Keys.label)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            if SpaceSwipe.showsSlideAffordance(languageCount: enabledLanguageCount) {
                slideChevron("chevron.compact.right")
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func slideChevron(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 32, weight: .regular))
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
