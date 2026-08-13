import SwiftUI

extension KeyView {

    // MARK: Press handling

    /// The space bar, and only when someone is listening for a slide. Everything
    /// keyed off this defers rather than committing on finger-down.
    var slidesForLanguage: Bool { spec.cap == .space && onSpaceTouch != nil }

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
    var runsOnLift: Bool { spec.cap == .quickTone && toneAlternates.count > 1 }

    /// **The disabled check the key makes for itself, rather than trusting
    /// `.disabled()` to make it.**
    ///
    /// `.disabled()` sets `\.isEnabled` in the environment and the built-in
    /// controls consult it before they fire. This key is not a control: it is a raw
    /// `DragGesture` on a `ZStack`, and nothing in `KeyView` reads that environment
    /// value. Whether SwiftUI stops the gesture anyway is a framework detail that
    /// has changed across releases, and the cost of being wrong about it is exactly
    /// the defect the disabled state exists to remove — a key drawn dim that
    /// answers the tap anyway, which is worse than one that is plainly lit.
    ///
    /// So both halves of the gesture ask this directly. `.disabled()` stays on the
    /// view because it is also what tells VoiceOver, and the two agreeing costs one
    /// line.
    var acceptsTouches: Bool { !isDisabled }

    var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isTouching) { _, touching, _ in touching = true }
            .onChanged { value in
                guard acceptsTouches else { return }
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
                        onPress(spec.cap, unitPoint(value.startLocation))
                    }
                    startRepeatIfNeeded()
                    startAlternatesIfNeeded()
                    return
                }
                if slidesForLanguage {
                    onSpaceTouch?(.moved(value.translation.width))
                    return
                }
                // Every later change is either a finger sliding across a popup this
                // key has or a finger wobbling on an ordinary key. Only the first
                // is worth reacting to.
                //
                // `hasAlternates` rather than `showsAlternates`, so a slide that
                // happens during the hold is not dropped: the popup would
                // otherwise arm on item 0 while the finger was already pointing at
                // another, and a finger that has stopped moving sends nothing more
                // to correct it with. Nothing is drawn from this until the popup
                // arms — see `alternateItem`.
                guard hasAlternates else { return }
                selectedAlternate = hasSlid(value.translation) ? alternateIndex(at: value.location) : 0
            }
            .onEnded { value in
                // Not just a mirror of the `onChanged` guard: `runsOnLift` means
                // this is the *only* place the one-tap rewrite key ever fires, so a
                // disabled Rewrite key with a guard on one half and not the other
                // would still run on every tap.
                guard acceptsTouches else {
                    endPress()
                    return
                }
                if slidesForLanguage {
                    // Not `endPress()`: that is the cancellation path and reports
                    // the touch as abandoned, which would throw away the slide
                    // this lift is committing. The space bar has no repeat and no
                    // alternates, so releasing the press is all there is to undo.
                    isPressed = false
                    onSpaceTouch?(.ended(value.translation.width))
                    return
                }
                let picked = alternateIndexOnLift(
                    popupIsVisible: showsAlternates,
                    translation: value.translation,
                    location: value.location)
                endPress()
                // Index 0 is what the key would have done on its own — the
                // character it already inserted, or the default tone it has not run
                // yet — so lifting on it means the long press changed nothing.
                guard picked > 0, picked < alternateItems.count else {
                    // The tap this key deferred. See `runsOnLift`.
                    if runsOnLift { onPress(spec.cap, unitPoint(value.startLocation)) }
                    return
                }
                onAlternate?(alternateItems[picked])
            }
    }

    /// Whether this touch has travelled far enough to be choosing rather than
    /// resting.
    ///
    /// **Without it the popup reads the raw location and index 0 is unreachable
    /// from a standing finger**, which contradicts the rule `alternateItems` is
    /// built on: lifting a finger that has not moved must commit nothing new. The
    /// popup is centred on the *key*, not on its first item, so the point under a
    /// finger that never moved is `(alternatesWidth - width) / 2` into the strip —
    /// dead on the boundary for a two-item popup and the middle of item 4 for
    /// English's nine-item `a`. Holding a letter a beat too long and lifting
    /// straight up therefore swapped it for an accent nobody aimed at, and the
    /// highlight said otherwise the whole time, because it is seeded to 0.
    ///
    /// Six points is well above the wobble of a thumb resting on glass and well
    /// below the 34 an item is wide, so the first item stays reachable and the
    /// second still takes an ordinary flick to reach.
    func hasSlid(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) > Self.slideThreshold
    }

    /// What a lift commits from the popup. Kept as one pure decision so the
    /// standing-finger rule is testable without trying to synthesize a SwiftUI
    /// gesture in a host-less unit test.
    func alternateIndexOnLift(
        popupIsVisible: Bool,
        translation: CGSize,
        location: CGPoint
    ) -> Int {
        guard popupIsVisible, hasSlid(translation) else { return 0 }
        return alternateIndex(at: location)
    }

    static let slideThreshold: CGFloat = 6

    /// Finger-down in this key, 0...1, origin top-left. Grouped keys read it as
    /// a soft pin; every other key ignores it.
    func unitPoint(_ location: CGPoint) -> CGPoint {
        CGPoint(
            x: width > 0 ? min(1, max(0, location.x / width)) : 0.5,
            y: height > 0 ? min(1, max(0, location.y / height)) : 0.5)
    }

    /// Everything a finger leaving this key has to undo, on every path it can
    /// leave by. Idempotent, because a normal lift arrives here twice: once from
    /// `onEnded` and once from the gesture state resetting behind it.
    func endPress() {
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
        guard acceptsTouches, let onRepeat, spec.cap == .backspace else { return }
        repeater.start(onRepeat)
    }

    /// Holding a key with alternates opens them, the way it does on the system
    /// keyboard. Nothing happens for a key that has none, which is most of them.
    private func startAlternatesIfNeeded() {
        // `hasAlternates` reads `alternateItems` rather than `spec.alternates`,
        // because the one-tap rewrite key's registers do not live on the spec —
        // they come from a setting in the containing app. For a letter the two say
        // the same thing: the list is the character plus its alternates, so "more
        // than one" is exactly "has alternates".
        //
        // `acceptsTouches` first: the one-tap rewrite key is both the key that has
        // registers on a long press and one of the two that go disabled on an empty
        // field, so without this a disabled key would still open its popup — and a
        // popup pick reaches `onAlternate` on a path of its own.
        guard acceptsTouches, hasAlternates else { return }
        // Here rather than at the end of the wait below, so a finger that slides
        // before the popup arms keeps what it slid to. `@State` outlives the
        // press, so without a reset somewhere the next press on this key would
        // arm on whatever the last one chose.
        selectedAlternate = 0
        alternatesTask?.cancel()
        alternatesTask = Task { @MainActor in
            // Never zero: opening on finger-down flashes the popup on every
            // deliberate tap. `alternatesDelay` carries why the wait is not one
            // number.
            try? await Task.sleep(for: Self.alternatesDelay)
            guard !Task.isCancelled else { return }
            Feedback.modifierPress()
            withAnimation(Theme.Motion.quick) { showsAlternates = true }
        }
    }
}
