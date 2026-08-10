import Foundation
import SwiftUI

extension KeyboardController {

    /// The languages the globe and a slide along the space bar both move through.
    ///
    /// Public because the space bar prints their codes, not just their number: it
    /// says which language is on and which the slide reaches. See
    /// `SpaceSwipe.codeStrip`.
    public var enabledLanguages: [KeyboardLanguage] {
        store.enabledLanguages.isEmpty ? [.english, .hebrew] : store.enabledLanguages
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
        withAnimation(Theme.Motion.quick) {
            language = destination
            plane = .letters
        }
        announceLanguage(destination, in: enabled, pending: false)
        refreshSuggestions()
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
        announceLanguage(candidate, in: enabled, pending: true)
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
        _ named: KeyboardLanguage, in enabled: [KeyboardLanguage], pending: Bool
    ) {
        languageSwitchTask?.cancel()
        let indication = LanguageSwitchIndication(
            language: named,
            position: enabled.firstIndex(of: named) ?? 0,
            count: enabled.count,
            isPending: pending)
        withAnimation(Theme.Motion.quick) { languageSwitchIndication = indication }

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
