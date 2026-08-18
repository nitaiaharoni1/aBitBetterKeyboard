import Foundation
import SwiftUI

extension KeyboardController {

    /// The languages the globe and a slide along the space bar both move through.
    ///
    /// Public because the space bar prints their codes, not just their number: it
    /// says which language is on and which the slide reaches. See
    /// `SpaceSwipe.codeStrip`.
    public var enabledLanguages: [KeyboardLanguage] {
        store.storedEnabledLanguages
    }

    /// The BCP-47 tag the host is told this keyboard is, which is not always the
    /// language the keys are on.
    ///
    /// **`primaryLanguage` is the only sentence this process ever says to iOS
    /// about what keyboard it is, and a slide along the space bar is the only
    /// thing that changes it mid-session.** iOS is free to re-decide whether a
    /// third-party keyboard may serve the field it is standing over, and the
    /// moment its identity changes is the moment that decision can be taken
    /// again. So a field that declared it cannot hold another script keeps
    /// hearing a Latin tag even after the user slides the keys to Hebrew.
    ///
    /// `latinFieldTypes` is the same set `adoptFieldKeyboardType` already moves
    /// the *keys* for, so this is that decision carried through to the host
    /// rather than a second rule with its own list. The user may still type
    /// Hebrew into an address bar — nothing here touches the keys — and the
    /// address bar goes on laying text out the way an address bar does, which is
    /// what it would have done for Apple's own Hebrew keyboard anyway.
    ///
    /// **A Hebrew-only user is clamped too, and that is deliberate.**
    /// `adoptFieldKeyboardType` leaves their keys on Hebrew, because a keyboard
    /// they cannot get off is worse than the wrong keys, so the fallback here has
    /// no enabled Latin language to name and says `en-US` anyway. The field
    /// declared it holds an address or a URL; those read left to right whoever is
    /// typing them, and it is the one answer that does not put the risky write on
    /// the user who has the least room to recover from it.
    public func announcedInputModeTag(for language: KeyboardLanguage) -> String {
        guard language.script != .latin,
            let field = adoptedKeyboardType,
            Self.latinFieldTypes.contains(field)
        else { return language.inputModeTag }
        return (enabledLanguages.first { $0.script == .latin } ?? .english).inputModeTag
    }

    /// The globe key. One step per tap — the same step a slide makes, so the two
    /// ways of changing language walk the enabled list in the same order — and it
    /// still hands the keyboard over to iOS when the user has only enabled one of
    /// ours. The swipe is an addition to this, not a replacement, because
    /// `showsGlobeKey` is `needsInputModeSwitchKey` and on a phone with no other
    /// keyboard installed there is no globe to tap at all.
    public func advanceLanguage() {
        guard enabledLanguages.count > 1 else {
            onAdvanceToNextKeyboard?()
            return
        }
        stepLanguage(by: 1)
    }

    /// Moves `places` along the enabled languages, wrapping, and names where it
    /// landed on the space bar for a moment afterwards.
    public func stepLanguage(by places: Int) {
        let enabled = enabledLanguages
        guard let destination = SpaceSwipe.language(from: language, in: enabled, places: places)
        else { return }
        withAnimation(Theme.Motion.swipe) {
            languageSlideStep = places
            language = destination
            plane = .letters
        }
        announceLanguage(destination, in: enabled, pending: false, step: places)
        endGroupedWord()
        refreshSuggestions()
        reportInteraction(.languageSwitch)
    }

    /// One touch on the space bar, which is the only key whose meaning is not
    /// settled on finger-down.
    ///
    /// **The space is owed from the moment the finger lands and paid by whatever
    /// settles the touch**, which is a lift, another key, or nothing at all. A
    /// touch that turns into a slide types nothing; one that does not calls
    /// `press(.space)` on the way out, which is the ordinary path with the ordinary
    /// double-space rule and the ordinary correction; one interrupted by another
    /// key is paid inside `press`, before that key.
    ///
    /// This makes the controller order-dependent on four phases that a gesture
    /// recogniser is free to deliver in more than one order, so every order it can
    /// produce is pinned in `SpaceBarLanguageSwitchTests`: a key between `began`
    /// and `ended`, a delete between them, a second `began` before the first ends,
    /// an `ended` nobody began, and a `cancelled` on either side of the lift.
    public func spaceBarTouch(_ phase: SpaceTouchPhase) {
        switch phase {
        case .began:
            // Every touch starts from a known state, which is what lets a
            // cancellation clear only what is on screen. See `SpaceTouchPhase`.
            spaceTouch.began()
            clearPendingLanguageSwitch()

        case .moved(let travelled):
            guard spaceTouch.moved(to: travelled) else { return }
            showLanguageCandidate(travelled)

        case .cancelled:
            spaceTouch.cancelled()
            clearPendingLanguageSwitch()

        case .ended(let travelled):
            switch spaceTouch.lifted(after: travelled) {
            case .nothing:
                clearPendingLanguageSwitch()

            case .space:
                press(.space)

            case .slide(let distance):
                let places = SpaceSwipe.places(
                    translation: distance, languageCount: enabledLanguages.count)
                // A slide with nowhere to go — one language enabled, or a finger
                // that wandered out and came back — switches nothing, and still
                // types nothing. A space the user stopped asking for is worse
                // than silence.
                guard places != 0 else {
                    clearPendingLanguageSwitch()
                    return
                }
                stepLanguage(by: places)
            }
        }
    }

    private func showLanguageCandidate(_ travelled: CGFloat) {
        let enabled = enabledLanguages
        guard
            let candidate = SpaceSwipe.destination(
                from: language, in: enabled, translation: travelled)
        else {
            clearPendingLanguageSwitch()
            return
        }
        guard languageSwitchIndication?.language != candidate else { return }
        // One tick per language passed, the way a picker answers a scrolling
        // thumb. The finger is covering the space bar, so this is the half of the
        // indication the user can feel rather than read.
        Feedback.modifierPress()
        let step = SpaceSwipe.places(translation: travelled, languageCount: enabled.count)
        announceLanguage(candidate, in: enabled, pending: true, step: step)
    }

    private func clearPendingLanguageSwitch() {
        guard languageSwitchIndication?.isPending == true else { return }
        languageSwitchTask?.cancel()
        withAnimation(Theme.Motion.quick) { languageSwitchIndication = nil }
    }

    /// Names a language on the space bar: while a slide is choosing it, and for a
    /// moment after it lands. The second half is the only confirmation a user who
    /// switched by swiping ever gets, and it is what the globe key was missing
    /// too — a layout that changes under the thumb with nothing saying to what.
    func announceLanguage(
        _ named: KeyboardLanguage, in enabled: [KeyboardLanguage], pending: Bool, step: Int
    ) {
        languageSwitchTask?.cancel()
        let indication = LanguageSwitchIndication(
            language: named,
            position: enabled.firstIndex(of: named) ?? 0,
            count: enabled.count,
            isPending: pending,
            step: step)
        // Finger-down tracking stays `quick` so the balloon stays glued to the
        // thumb; the landing uses `swipe` so it shares the same 80ms beat as
        // the keys. Both tokens are that beat — the names say which change.
        let motion = pending ? Theme.Motion.quick : Theme.Motion.swipe
        withAnimation(motion) { languageSwitchIndication = indication }

        // A pending name stays until the finger decides. A landed one is a
        // confirmation, and a confirmation that never leaves is a caption.
        guard !pending else { return }
        languageSwitchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.quick) { self?.languageSwitchIndication = nil }
        }
    }

}
