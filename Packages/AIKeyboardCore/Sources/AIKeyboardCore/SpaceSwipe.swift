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
/// **One slide is one language, and the distance is only a threshold.** The
/// first version made the travel carry the count — past `activation`, every
/// further `step` points was another language — so that a long list could be
/// crossed in a single sweep. It cost the gesture its order. The same flick meant
/// a different thing depending on how far a thumb happened to travel: 60 points
/// moved one place and 140 moved three, nothing on screen said which before the
/// finger lifted, and repeating the gesture therefore did not walk the list. A
/// list the user cannot walk is not an order. So the slide steps, the way the
/// globe key already did, and `LanguageCallout` names the one language it is
/// about to land on while the finger is still down.
public enum SpaceSwipe {

    /// How far a finger must travel along the space bar before the touch stops
    /// being a space and becomes a language switch.
    ///
    /// Well above the few points a thumb wanders during an ordinary tap, and well
    /// under half the width of the space bar, so a deliberate slide always makes
    /// it and a tap never does. SwiftUI's own default `minimumDistance` for a drag
    /// is 10 points, which is the floor this has to clear.
    public static let activation: CGFloat = 24

    /// Which way along the enabled list a slide moves the language: `1` to the
    /// right, `-1` to the left, `0` when the touch was a tap or there is nowhere
    /// to go.
    ///
    /// **How far past `activation` the finger travelled changes nothing**, which
    /// is what makes the enabled list an order the user can walk: one slide is
    /// always the next language, so three slides are always the third one along
    /// and coming back is always the same number the other way. It also makes
    /// `codeStrip` honest — the unlit code either side of the lit one is exactly
    /// what a slide that way reaches, which it could not promise while the landing
    /// depended on distance.
    ///
    /// A long list is now crossed by repeating the gesture rather than by one long
    /// sweep. That is the cost, it is deliberate, and the strip of codes on the key
    /// is what makes the repetition legible.
    public static func places(translation: CGFloat, languageCount: Int) -> Int {
        guard languageCount > 1, abs(translation) >= activation else { return 0 }
        return translation < 0 ? -1 : 1
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

    // MARK: How the keys move

    /// Which edges a slide of this step enters and leaves by.
    ///
    /// **The letter keys follow the strip, not a pager's finger.** A right swipe
    /// lights the code on the right of the space bar, so the new keys enter from
    /// the right; content-follows-finger would bring in the *left* neighbour and
    /// fight the affordance the key already printed. Nil when there is no step,
    /// which is the resting crossfade.
    public static func slideEdges(step: Int) -> (incoming: Edge, outgoing: Edge)? {
        if step > 0 { return (.trailing, .leading) }
        if step < 0 { return (.leading, .trailing) }
        return nil
    }

    /// The letter rows replacing each other. Opacity alone when Reduce Motion is
    /// on, or when there is no direction to honour.
    public static func letterTransition(step: Int, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion, let edges = slideEdges(step: step) else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: edges.incoming).combined(with: .opacity),
            removal: .move(edge: edges.outgoing).combined(with: .opacity)
        )
    }

    /// The balloon is pulled out of the space bar in the same direction the
    /// finger just travelled.
    public static func calloutTransition(step: Int, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion, let edges = slideEdges(step: step) else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: edges.incoming)
                .combined(with: .scale(scale: 0.88, anchor: .bottom))
                .combined(with: .opacity),
            removal: .opacity
        )
    }
}
