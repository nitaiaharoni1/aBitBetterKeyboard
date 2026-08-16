import SwiftUI

/// One touch on a character key, from the finger landing to whatever ends it.
///
/// **The sibling of `SpaceTouchPhase`, and it exists for the same reason.** A
/// character key used to settle its meaning on finger-down; it now settles it on
/// the lift, because a long press must not put a letter in the document that the
/// alternate the user is reaching for is about to replace. So the key reports a
/// touch instead of a press, and `KeyboardController.characterTouch(_:)` decides
/// when the character is actually typed — see `beginCharacterTouch` for the two
/// moments that can be, and for why rollover is settled on the *next* finger-down
/// rather than on this one's lift.
///
/// There is no `moved` and no `cancelled`. A character key has nothing to steer
/// with a slide except its own popup, which `KeyView` reads for itself, and a
/// touch taken away by a banner or a plane switch still owes the character —
/// finger-down is what the user meant by it, and the keyboard before this change
/// had already written it by then. The one case that does *not* owe it is the
/// keyboard coming back up over a new field, where no `KeyView` survives to
/// report anything at all; `KeyboardController.discardPendingCharacter` is that
/// path and it is a discard rather than a report.
public enum CharacterTouchPhase: Equatable, Sendable {
    /// A finger landed on this key, at this point inside it. Nothing is typed
    /// yet. The point is what a grouped cap reads as a soft pin; every other
    /// key ignores it.
    case began(KeyCap, CGPoint)
    /// The touch is over, by any route — a lift, a cancelled gesture, or the key
    /// leaving the screen underneath the finger. The character is typed now.
    case ended
}

extension KeyView {

    // MARK: Press handling

    /// The space bar, and only when someone is listening for a slide. Everything
    /// keyed off this defers rather than committing on finger-down.
    var slidesForLanguage: Bool { spec.cap == .space && onSpaceTouch != nil }

    /// The one-tap rewrite key, Fix and CopyClip, when they have items to offer.
    ///
    /// **They commit on lift rather than on finger-down, and their reason for it
    /// is not the letters' reason.** A character key defers too now (see
    /// `defersCharacterToLift`) so that a hold writes nothing until it is
    /// released; every remaining key acts immediately, because that is what makes
    /// shift, delete and the plane switch feel instant. These three run a *model
    /// call*, which is a different cost: firing on finger-down would
    /// spend one on the default pass every time the user held the key to
    /// choose a different one, and `beginWork` cancels its predecessor, so
    /// the answer being paid for would be thrown away by the style that was
    /// actually wanted. CopyClip is the same lift rule so a hold does not
    /// toggle the panel. A tap still runs the default — it just runs it 100ms
    /// later, on the lift, which no thumb can feel.
    var runsOnLift: Bool {
        switch spec.cap {
        case .quickTone: return toneAlternates.count > 1
        case .aiFix: return fixAlternates.count > 1
        case .copyclip: return copyclipAlternates.count > 1
        default: return false
        }
    }

    /// Every character key: the letter is typed on the lift, not on the
    /// finger-down.
    ///
    /// **This is the one behaviour on the keyboard that trades latency for
    /// correctness, so it is worth saying what it buys and what it costs.** A
    /// long press on a letter opens the accents strip, and until NIT-108 the
    /// letter was already in the document by then — picking `é` was a delete
    /// followed by a retype, and holding a key with no intention of picking
    /// anything wrote a character while the finger was still down. Deferring to
    /// the lift means a held key writes nothing until it is released, which is
    /// what the issue asks for. The cost is real and is paid on every keystroke:
    /// the character now lands one dwell time (roughly 60–120 ms) after the
    /// finger touches the glass, where Apple's own keyboard lands it on contact.
    ///
    /// **Three things deliberately do not move with it.** The press balloon and
    /// the pressed cap still track `isTouching`, so the key still answers the
    /// instant it is touched. The click and the thud still play on the
    /// finger-down — `KeyboardController.beginCharacterTouch` plays them, and
    /// tells the deferred press they are already spent — because a late haptic
    /// is felt where a late glyph is only seen. And key repeat is untouched:
    /// `startRepeatIfNeeded` only ever ran for delete, so holding a letter still
    /// types exactly one letter, once.
    ///
    /// Gated on the closure rather than on the cap alone so a `KeyView` built
    /// without one — a preview, a test asking only about geometry — keeps the
    /// old immediate path and does not silently swallow its keystrokes.
    var defersCharacterToLift: Bool {
        guard onCharacterTouch != nil, case .character = spec.cap else { return false }
        return true
    }

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
                    // Three keys defer and the rest commit here. The space bar
                    // defers because the same touch may still turn out to be a
                    // language slide (`SpaceTouchPhase`). A character key defers
                    // because a hold may still turn out to be reaching for an
                    // alternate (`defersCharacterToLift`). Fix, Rewrite and
                    // CopyClip defer because they spend a model call
                    // (`runsOnLift`). Everything else — shift, delete, the plane
                    // switch, return — acts now, which is what makes those keys
                    // feel immediate and is what keeps delete repeating.
                    if slidesForLanguage {
                        onSpaceTouch?(.began)
                    } else if defersCharacterToLift {
                        onCharacterTouch?(.began(spec.cap, unitPoint(value.startLocation)))
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
                selectedAlternate =
                    hasSlid(value.translation)
                    ? alternateIndex(
                        at: value.location,
                        keyMinX: keyMinXInCanvas,
                        canvasWidth: keyboardCanvasWidth) : alternateRestIndex
            }
            .onEnded { value in
                // Not just a mirror of the `onChanged` guard: `runsOnLift` means
                // this is the *only* place the rewrite and Fix keys ever fire, so a
                // disabled key with a guard on one half and not the other
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
                    location: value.location,
                    keyMinX: keyMinXInCanvas,
                    canvasWidth: keyboardCanvasWidth)
                // **The character goes in here, one line above the alternate that
                // may be about to replace it.** `endPress()` reports `.ended`,
                // which is what types a deferred letter, so an accent is still
                // the delete-then-retype `KeyboardView.alternateHandler` is
                // written for, and a grouped cap still has its stroke appended
                // before the popup pins a letter out of it. Doing it the other
                // way — dropping the pending character and inserting the accent
                // straight — would look tidier and would take `deletedWordPrefix`
                // with it, and `צ׳יפס`, `col·legi` and `café` are exactly the
                // words autocorrect destroys when it does not know a hand placed
                // them. See `.claude/rules/suggestion-bar.md`.
                endPress()
                // Rest is what the key would have done on its own — the character
                // it has just typed, or the default tone it has not run yet — so
                // lifting on that item means the long press changed nothing.
                // Slot 0 is that item for letters; the period popup puts `.`
                // later, so this is `alternateRestIndex`, not `> 0`.
                guard picked != alternateRestIndex else {
                    // The tap this key deferred. See `runsOnLift`. A character
                    // key's deferred tap was already paid by `endPress()` above,
                    // and `runsOnLift` is false for it, so it does not pay twice.
                    if runsOnLift { onPress(spec.cap, unitPoint(value.startLocation)) }
                    return
                }
                guard picked >= 0, picked < alternateItems.count else {
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
        location: CGPoint,
        keyMinX: CGFloat = 0,
        canvasWidth: CGFloat = 0
    ) -> Int {
        guard popupIsVisible, hasSlid(translation) else { return alternateRestIndex }
        return alternateIndex(at: location, keyMinX: keyMinX, canvasWidth: canvasWidth)
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
        wordRepeater.stop()
        alternatesTask?.cancel()
        alternatesTask = nil
        if wasPressed, slidesForLanguage { onSpaceTouch?(.cancelled) }
        // **Every way a character touch can end arrives here, and all of them
        // owe the character.** A lift, a gesture the system cancelled, a finger
        // that slid off the key, and the key being taken off screen mid-press
        // all land in this one function — which is exactly why the commit is
        // here and not in `onEnded`, where a cancelled touch would silently
        // swallow a keystroke the user had already felt the keyboard answer.
        // The pre-NIT-108 build had written the character on the way in, so
        // committing on every exit is the behaviour being preserved rather than
        // a new decision.
        //
        // `wasPressed` is what makes it fire once: a normal lift reaches this
        // twice, from `onEnded` and again from the gesture state resetting
        // behind it, and the second pass sees the flag already cleared.
        if wasPressed, defersCharacterToLift { onCharacterTouch?(.ended) }
    }

    /// Delete accelerates while held, the way every other keyboard behaves.
    private func startRepeatIfNeeded() {
        guard acceptsTouches, let onRepeat,
            spec.cap == .backspace || spec.cap == .deleteForward
        else { return }
        if spec.cap == .backspace {
            wordRepeater.start(onRepeat)
        } else {
            repeater.start(onRepeat)
        }
    }

    /// Holding a key with alternates opens them, the way it does on the system
    /// keyboard. Nothing happens for a key that has none, which is most of them.
    private func startAlternatesIfNeeded() {
        // `hasAlternates` reads `alternateItems` rather than `spec.alternates`,
        // because the rewrite key's registers and Fix's passes do not live on
        // the spec — they come from the controller. For a letter the two say
        // the same thing: the list is the character plus its alternates, so "more
        // than one" is exactly "has alternates".
        //
        // `acceptsTouches` first: both keys are disabled on an empty field,
        // so without this a disabled key would still open its popup — and a
        // popup pick reaches `onAlternate` on a path of its own.
        guard acceptsTouches, hasAlternates else { return }
        // Here rather than at the end of the wait below, so a finger that slides
        // before the popup arms keeps what it slid to. `@State` outlives the
        // press, so without a reset somewhere the next press on this key would
        // arm on whatever the last one chose.
        selectedAlternate = alternateRestIndex
        alternatesTask?.cancel()
        alternatesTask = Task { @MainActor in
            // Never zero: opening on finger-down flashes the popup on every
            // deliberate tap. `alternatesHoldDelay` carries why the wait is not
            // one number.
            try? await Task.sleep(for: alternatesHoldDelay)
            guard !Task.isCancelled else { return }
            Feedback.modifierPress()
            withAnimation(Theme.Motion.quick) { showsAlternates = true }
        }
    }
}
