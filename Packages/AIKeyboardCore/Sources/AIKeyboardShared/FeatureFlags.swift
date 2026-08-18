import Foundation

/// What this build ships, as distinct from what this repository contains.
///
/// **This is not a settings screen and it is not an experiment framework.** Every
/// flag here is a compile-time constant with a dated reason and a named condition
/// for flipping it, because the only thing a flag is allowed to mean in this
/// project is "the code is finished, the evidence is not." A flag with no stated
/// condition is a feature nobody ever turns back on, and a flag a user can toggle
/// is a second product to support.
public enum FeatureFlags {

    /// Whether Reply may be sourced from a ReplayKit screen recording.
    ///
    /// **Off for v1, and the code stays.** `AIKeyboardBroadcast`,
    /// `CaptureChannel`, `RoutedScreenReader` and `ScreenContextSession`'s capture
    /// half are complete and, in the reading half, measured against
    /// `Bar/screen-context/`. What none of it has is a single execution: the iOS
    /// Simulator ships no `replayd`, so `SampleHandler` has never been called, no
    /// frame has ever reached the reader through the broadcast path, and four
    /// open questions (NIT-6, NIT-12, NIT-13, NIT-14) can only be answered by a
    /// physical phone.
    ///
    /// Shipping it anyway would put the product's least proven path behind its
    /// most expensive ask: a user is invited to start a **screen recording**, on
    /// top of Full Access, to get a text reply. That is the hardest trust sell in
    /// this product attached to the one feature that has never run. `ReplySource`
    /// answers the same question from the pasteboard instead, which needs no
    /// entitlement, no broadcast and no permission dialog.
    ///
    /// **Flip this to `true` when NIT-6 passes on a real device** — a broadcast
    /// actually starts from the keyboard's picker, `SampleHandler` is actually
    /// invoked, a frame actually reaches `RoutedScreenReader`, and the extension
    /// is measured under the ~50 MB cap (NIT-12). Not before, and not because the
    /// code compiles.
    ///
    /// What this flag does **not** turn off: the scripted in-app sample. That is
    /// `ScreenContextSource.scripted`, it photographs nothing, and it is what the
    /// playground and the Screen Context screen demonstrate with. It is gated by
    /// `SharedStore.screenContextAllowed` and always was.
    public static let screenCaptureReply = false
}
