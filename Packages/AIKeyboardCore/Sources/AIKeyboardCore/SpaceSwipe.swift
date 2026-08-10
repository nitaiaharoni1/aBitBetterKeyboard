import SwiftUI

// MARK: - The decision

/// Where a slide along the space bar lands: distance and direction in, a
/// language out.
///
/// **Arithmetic rather than a gesture, because a `DragGesture` cannot be asked
/// anything afterwards.** Every rule here is one a keyboard gets wrong in a way
/// the user reads as the keyboard being broken — a space bar that switches
/// language on the ordinary wobble of a tap, a swipe that types a space anyway, a
/// long swipe that wraps all the way round and lands back where it started. So
/// the rules live in a type a test can drive, and `KeyView` only forwards
/// translations into it.
///
/// **One slide can move more than one place, and with fourteen languages that is
/// the whole design.** Gboard steps once per swipe, which is fine for the two
/// keyboards it ships enabled by default and unusable for a list this long:
/// reaching the seventh language would be six separate swipes, each of them
/// changing the layout under the thumb on the way past. Here the distance
/// travelled *is* the number of places moved, so the list is scrubbed rather than
/// stepped, and `LanguageCallout` shows which language the finger is currently
/// pointing at before it commits.
public enum SpaceSwipe {

    /// How far a finger must travel along the space bar before the touch stops
    /// being a space and becomes a language switch.
    ///
    /// Well above the few points a thumb wanders during an ordinary tap, and well
    /// under half the width of the space bar, so a deliberate slide always makes
    /// it and a tap never does. SwiftUI's own default `minimumDistance` for a drag
    /// is 10 points, which is the floor this has to clear.
    public static let activation: CGFloat = 24

    /// How far the finger travels per language once the slide has started.
    ///
    /// It shrinks as the list grows, and both ends are clamped. A user with two
    /// languages wants a deliberate step that is hard to overshoot; a user with
    /// fourteen wants the far end of the list reachable inside one sweep of the
    /// thumb. `sweep` is the travel budgeted for a full traversal — about the
    /// width of a phone screen — and the clamp stops that budget from producing a
    /// step so short it is twitchy or so long the list cannot be crossed.
    static let sweep: CGFloat = 240
    static let widestStep: CGFloat = 44
    static let narrowestStep: CGFloat = 18

    static func step(languageCount: Int) -> CGFloat {
        let gaps = CGFloat(max(1, languageCount - 1))
        return min(widestStep, max(narrowestStep, sweep / gaps))
    }

    /// How many places along the enabled list a slide of this length moves.
    /// Signed: positive is a slide to the right, negative to the left. Zero means
    /// the touch was a tap, or that there is nowhere to go.
    ///
    /// **Capped at one short of a full lap, never wrapped.** Crossing `activation`
    /// is worth a whole place, so the shortest slide that counts moves one; from
    /// there each `step` adds another. Over-travel then stops at `count - 1`,
    /// which is what makes every other language reachable and none reachable
    /// twice: a modulo would let a long, enthusiastic swipe land back on the
    /// language the user started from, which reads as the gesture not working.
    public static func places(translation: CGFloat, languageCount: Int) -> Int {
        guard languageCount > 1 else { return 0 }
        let distance = abs(translation)
        guard distance >= activation else { return 0 }
        let beyond = distance - activation
        let moved = 1 + Int((beyond / step(languageCount: languageCount)).rounded(.down))
        let capped = min(moved, languageCount - 1)
        return translation < 0 ? -capped : capped
    }

    /// The language a slide of this length lands on, or nil when the touch was a
    /// tap or there is only one language to be in.
    public static func destination(
        from current: KeyboardLanguage, in enabled: [KeyboardLanguage], translation: CGFloat
    ) -> KeyboardLanguage? {
        language(
            from: current, in: enabled,
            places: places(translation: translation, languageCount: enabled.count))
    }

    /// Moves `places` along the enabled list, wrapping at both ends. Nil when
    /// there is nowhere to move: an empty or single-language list, or no movement.
    ///
    /// **Direction is physical and never mirrors for a right-to-left keyboard**,
    /// which is a decision rather than an oversight. The enabled list has one
    /// order and it does not flip when the user lands on Hebrew, so a mirrored
    /// gesture would make "right" mean *forwards* in English and *backwards* in
    /// Hebrew: two right swipes would go English → Hebrew → English and the user
    /// could never traverse the list by repeating one gesture. It also matches the
    /// row the gesture lives on, which `KeyboardView` already pins to
    /// left-to-right for every language — only the letters plane mirrors, never
    /// the function row that carries the space bar.
    public static func language(
        from current: KeyboardLanguage, in enabled: [KeyboardLanguage], places: Int
    ) -> KeyboardLanguage? {
        guard enabled.count > 1, places != 0 else { return nil }
        let start = enabled.firstIndex(of: current) ?? 0
        let count = enabled.count
        let index = ((start + places) % count + count) % count
        return enabled[index]
    }

    // MARK: What the space bar says before anyone touches it

    /// The language codes the space bar prints, in the order they are drawn, and
    /// which of them is lit — the first entry is leftmost, and `active` is the one
    /// shown lit.
    ///
    /// **The gesture had no affordance at all, and that is the defect this
    /// answers.** `KeyboardController.announceLanguage` names the language for
    /// 1.4s *after* a switch and `LanguageCallout` names it *during* a slide;
    /// both of those are feedback for somebody who already knows the gesture
    /// exists. A user who does not sees a key captioned "space" — "רווח" in
    /// Hebrew — and no reason to think it does anything but insert a space. The
    /// owner of the first device this shipped to had to be told.
    ///
    /// So at rest the key prints a strip of language codes above its ordinary
    /// caption, with the one in use lit, and `showsSlideAffordance` puts a chevron
    /// at each end of the key: the lit code says which language is on, the unlit
    /// ones say which others the gesture reaches, and the chevrons say the way to
    /// reach them. It is the shape SwiftKey ships. It costs no permanent room in
    /// the suggestion bar and it answers a question — "which language am I in?" —
    /// that nothing at rest answered.
    ///
    /// **The first version of this replaced the caption with the language name**,
    /// which named the language on but never the ones off, so the chevrons pointed
    /// at nothing the user could see. The strip names both, and the caption goes
    /// back to being the word for space.
    ///
    /// **Above three enabled languages the strip is a window rather than a list**,
    /// because a phone's space bar has room for about three codes and this keyboard
    /// offers sixty-four languages. The window is what a swipe left reaches, where
    /// you are, and what a swipe right reaches — so it stays an answer to "where
    /// does this gesture go", which a truncated list would not be. It wraps at both
    /// ends exactly as `language(from:in:places:)` does, because a strip that
    /// stopped at the edge would promise a dead end the gesture does not have.
    ///
    /// **With one language enabled there is nothing to slide to**, so the strip is
    /// empty and the chevrons go: an affordance for a gesture that cannot move is
    /// worse than none. `SpaceSwipe.places` already returns 0 for that case, so the
    /// two agree.
    public static func codeStrip(
        active: KeyboardLanguage, in enabled: [KeyboardLanguage]
    ) -> [KeyboardLanguage] {
        guard enabled.count > 1 else { return [] }
        guard enabled.count > 3 else { return enabled }
        // Not `?? 0`: a language that is not in the list has no neighbours to
        // show, and centring the window on the first entry would light a code the
        // user is not typing in.
        guard let centre = enabled.firstIndex(of: active) else { return Array(enabled.prefix(3)) }
        let count = enabled.count
        return [-1, 0, 1].map { enabled[((centre + $0) % count + count) % count] }
    }

    /// Whether the space bar shows the two chevrons that say it slides, and what
    /// VoiceOver is told instead of seeing them.
    public static func showsSlideAffordance(languageCount: Int) -> Bool { languageCount > 1 }

    public static func slideHint(languageCount: Int) -> String {
        showsSlideAffordance(languageCount: languageCount)
            ? "Slide left or right to change language" : ""
    }

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

// MARK: - What the space bar says

/// What the space bar is saying about the keyboard's language right now.
///
/// Two moments, and they need different things. **While the finger is down**
/// (`isPending`) the user has not committed yet and the thumb is covering the
/// space bar, so the name has to appear above it. **After it lands** the finger is
/// gone, the layout under it has already changed, and what is needed is a short
/// confirmation of what just happened — which is what the space bar itself says,
/// the way Gboard names the language it has just moved to.
public struct LanguageSwitchIndication: Equatable, Sendable {

    public let language: KeyboardLanguage

    /// Where `language` sits in the user's enabled list, and how long that list
    /// is. Drawn as dots rather than as thirteen names: at two languages it says
    /// which of the two, at fourteen it says how far along the list the slide has
    /// got and which way is further — and it is the same fixed-height row either
    /// way.
    public let position: Int
    public let count: Int

    /// True while the finger is still on the space bar and could still move on.
    public let isPending: Bool

    public init(language: KeyboardLanguage, position: Int, count: Int, isPending: Bool) {
        self.language = language
        self.position = position
        self.count = count
        self.isPending = isPending
    }
}

/// The balloon above the space bar naming the language a slide is pointing at.
///
/// Deliberately an overlay rather than a row of its own: it appears and
/// disappears mid-gesture, and a keyboard whose keys jump down a few points every
/// time a language is being chosen is worse than no indication at all. Same
/// treatment as `KeyView`'s letter callout and its long-press popup, for the same
/// reason.
struct LanguageCallout: View {

    let indication: LanguageSwitchIndication

    var body: some View {
        VStack(spacing: 4) {
            Text("\(indication.language.flag) \(indication.language.nativeName)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.Keys.label)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            dots
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.Keys.letter)
                .shadow(color: Theme.Keys.shadow.opacity(0.35), radius: 5, y: 2)
        )
        // Position 0 is the leftmost dot whatever the keyboard's language,
        // because the gesture that moves through them is physical: sliding right
        // always moves right along this row. See `SpaceSwipe.language`.
        .environment(\.layoutDirection, .leftToRight)
    }

    private var dots: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, indication.count), id: \.self) { index in
                Circle()
                    .fill(
                        index == indication.position
                            ? Theme.Brand.solid : Theme.Keys.secondaryLabel.opacity(0.3)
                    )
                    .frame(width: 5, height: 5)
            }
        }
    }
}
