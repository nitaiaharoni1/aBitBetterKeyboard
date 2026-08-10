import SwiftUI

extension SpaceSwipe {

    // MARK: One touch

    /// One touch on the space bar, from the finger landing to whatever ends it.
    ///
    /// **A state machine rather than a flag, because a space bar touch owes the
    /// document something and four different things can settle the debt.** It
    /// lifts and pays a space. It travels far enough to be a language slide and
    /// owes nothing. It is *interrupted* by another key, which on a phone keyboard
    /// happens whenever two thumbs overlap, and the space has to be paid then and
    /// there or it lands after the character that displaced it. Or it is abandoned
    /// and pays nothing at all.
    ///
    /// Sticky in one direction on purpose: once a touch is a slide it never
    /// becomes a space again, because a finger that wandered out and came back has
    /// stopped asking for a language and never asked for a space.
    public struct Touch: Equatable, Sendable {

        public enum State: Equatable, Sendable {
            /// No finger on the space bar.
            case away
            /// A finger is down and the document is owed a space.
            case owesSpace
            /// The touch has travelled far enough to be a language slide.
            case sliding
            /// Another key was pressed while this one was down, so the space has
            /// already been typed. The lift owes nothing and switches nothing.
            case spent
        }

        public private(set) var state: State = .away

        /// True once the key has reported this touch gone without a lift.
        ///
        /// It does **not** cancel the debt, because a cancellation can arrive
        /// immediately *before* the lift it belongs to rather than instead of it —
        /// see `SpaceTouchPhase.cancelled` — and a tap whose debt was cancelled
        /// half a millisecond early would type nothing at all. What it does stop
        /// is `interrupted`: a key pressed after this point must not pay a space
        /// for a touch that may never lift.
        public private(set) var isAbandoned = false

        public var isSliding: Bool { state == .sliding }

        public init() {}

        public mutating func began() {
            state = .owesSpace
            isAbandoned = false
        }

        /// Call on every movement. True once this touch is a language slide, at
        /// which point the caller should show the candidate rather than type.
        @discardableResult
        public mutating func moved(to translation: CGFloat) -> Bool {
            if state == .owesSpace, abs(translation) >= SpaceSwipe.activation {
                state = .sliding
            }
            return state == .sliding
        }

        public mutating func cancelled() {
            isAbandoned = true
        }

        /// Another key was pressed while this touch was still down. True when it
        /// still owed a space, which the caller must type **before** the character
        /// that displaced it — both so the two land in the order the user's
        /// fingers made them, and so the space commits the autocorrect candidate
        /// that was on screen when they pressed it rather than the one the
        /// intervening character has since re-scored.
        public mutating func interrupted() -> Bool {
            guard state == .owesSpace, !isAbandoned else { return false }
            state = .spent
            return true
        }

        public enum Outcome: Equatable, Sendable {
            /// Nothing is owed: the touch was already spent, or was never seen to
            /// begin.
            case nothing
            case space
            case slide(CGFloat)
        }

        public mutating func lifted(after translation: CGFloat) -> Outcome {
            // The lift carries the distance because it may be the only event that
            // does. A touch delivered as one `onChanged` and then `onEnded` never
            // reports its travel any other way, and without this a swipe that
            // arrives that way types a space.
            moved(to: translation)

            let outcome: Outcome
            switch state {
            case .sliding: outcome = .slide(translation)
            case .owesSpace: outcome = .space
            case .spent, .away: outcome = .nothing
            }
            state = .away
            isAbandoned = false
            return outcome
        }
    }
}

// MARK: - What the key reports

/// One touch on the space bar, forwarded from `KeyView` to `KeyboardController`.
///
/// The space bar is the only key whose meaning is not settled on finger-down, so
/// it is the only key that reports a touch instead of a press. Every other key
/// commits immediately, which is what makes typing feel instant.
///
/// **Insert-on-down with a repair on the slide was possible and was rejected, not
/// ruled out.** `KeyboardController.insertSpace` holds the prefix and the
/// candidate before it mutates and `replaceCurrentWord` is its inverse, so the
/// autocorrect commit *can* be undone — `KeyboardView` does exactly that shape one
/// gesture over, repairing a letter when a long press picks an alternate. Three
/// things decided against it here. The repair would rewrite the document under the
/// user's eye mid-gesture, on every swipe: `sched` becomes `schedule ` becomes
/// `sched` again, which is the behaviour that makes people switch autocorrect off,
/// where the alternates repair swaps one character on lift under a popup that
/// already covers it. The repair has three shapes, not one — a plain space, the
/// double-space full stop that deleted a character before inserting `". "`, and
/// the autocorrect commit — each needing state carried from the insert. And it
/// does not remove the ordering question, it moves it: a character arriving
/// between the insert and the repair makes the repair delete a letter the user
/// typed, which is worse than a space landing late. Deferring keeps the failure
/// on the side where `interrupted` can fix it.
public enum SpaceTouchPhase: Equatable, Sendable {
    /// A finger landed. Nothing happens yet; this exists so the touch starts from
    /// a known state rather than from whatever the last one left behind.
    case began
    /// The finger has moved this far, horizontally, since it landed.
    case moved(CGFloat)
    /// The finger lifted after travelling this far.
    case ended(CGFloat)
    /// The touch went away without lifting — a banner, a Control Centre pull, the
    /// keyboard being dismissed. Nothing is typed and nothing is switched.
    ///
    /// **May arrive immediately before `ended` rather than instead of it**, and
    /// that is why `began` exists. SwiftUI resets a `@GestureState` when a gesture
    /// ends *or* is cancelled, and does not promise which of that reset and
    /// `onEnded` runs first; a cancellation that threw the touch away would then
    /// turn every completed swipe back into a space. So this clears what is on
    /// screen and nothing else, and `began` is what clears the touch.
    case cancelled
}
