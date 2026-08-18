import Foundation

/// What the companion app ships, for the surfaces that live only in this target.
///
/// **This is the same idea as `FeatureFlags` in `AIKeyboardShared` and it is
/// here for one reason: the flag below governs screens the package cannot see.**
/// The rules are that file's, unchanged — a compile-time constant, a dated
/// reason, and a named condition for flipping it, because the only thing a flag
/// may mean in this project is "the code is finished, the evidence is not". This
/// enum should be folded into `FeatureFlags` next to `screenCaptureReply` the
/// moment anything outside the app target needs to read one of these, so there
/// is one list of what the build ships rather than two.
enum AppFeatureFlags {

    /// Whether the subscription screen is reachable.
    ///
    /// **Off for v1, and `SubscriptionView` stays.** Nothing behind it is real:
    /// the screen says "MOCK PAYWALL" on itself, the CTA toggles
    /// `SharedStore.isSubscribed` instead of charging anything, the two prices
    /// (₪24.90 / ₪179) are invented, and nothing anywhere in this build is gated
    /// on the flag it sets. NIT-20 — wire real StoreKit and decide the pricing
    /// model — is in Backlog at Low priority, so no part of that is arriving
    /// before v1.
    ///
    /// Shipping it anyway costs twice. App Store review reads a purchase screen
    /// that makes no purchase as a broken or deceptive one, and it is the
    /// paid-app review path rather than the free one. And a launch user who taps
    /// "Start 7 days free" and is charged nothing, told nothing, and given
    /// nothing new learns in one tap that this app's screens do not mean what
    /// they say — on the single screen where a claim about money is being made.
    ///
    /// **Flip this to `true` when NIT-20 lands**: a real StoreKit 2 product, a
    /// real transaction, and something in the build that `isSubscribed`
    /// genuinely gates. Not before, and not because the screen looks finished.
    ///
    /// What this flag does **not** touch: the copy inside `SubscriptionView`,
    /// which is written and will be needed intact, or `SharedStore.isSubscribed`,
    /// which stays false for everyone and gates nothing either way.
    static let subscriptionPaywall = false
}
