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

    var pressGesture: some Gesture {
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
            // Letters keep the longer hold: their callout is already up, so the
            // wait is filled. The punctuation key has no callout (the strip *is*
            // the feedback), so a shorter threshold is what stops the hold from
            // feeling dead before the marks appear. Still not zero — opening on
            // finger-down would flash the strip on every deliberate tap.
            let delay: Duration =
                showsCharacterCallout ? .milliseconds(450) : .milliseconds(250)
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            selectedAlternate = 0
            Feedback.modifierPress()
            withAnimation(Theme.Motion.quick) { showsAlternates = true }
        }
    }
}
