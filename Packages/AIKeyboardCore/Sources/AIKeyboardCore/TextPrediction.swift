import Foundation

/// An engine that can guess the next word or two.
///
/// **A protocol of its own rather than a fifth case on `AIAction`, and that is a
/// UI decision as much as an architectural one.** `AIAction` is `CaseIterable`
/// and the action row and the layout editor are both built by iterating it, so a
/// `.predict` case would put a "Predict" button on the keyboard and a draggable
/// Predict key in the editor — for something the user never invokes and can never
/// press. The routing it would have bought is not worth that: prediction's route
/// is genuinely simpler than `RoutedIntelligence.route`, because it has no
/// best-effort branch. A fix in the wrong language is still worth showing with a
/// label on it; three predicted words in the wrong language are noise above a
/// keyboard, so when no engine can serve the language the honest answer is
/// silence and the local tier's three slots stand.
public protocol TextPrediction: Sendable {

    /// Whether this engine has this language at all. Asked before the call so a
    /// keystroke is never spent discovering it does not.
    func canPredict(in language: KeyboardLanguage) -> Bool

    /// Up to three words that could come next, likeliest first.
    ///
    /// - Parameters:
    ///   - text: what has been typed so far, trimmed to the tail. Never the whole
    ///     field: the model is guessing the next word, and a thousand words of
    ///     earlier conversation buys nothing while costing the context window that
    ///     Apple's on-device model measures in four thousand tokens.
    ///   - context: the message being replied to, when a screen reading is live.
    ///     This is the part no other keyboard on iOS can do, and it is also the
    ///     part most likely to go wrong — see the reply note in
    ///     `Prompts.continuation`.
    ///   - language: the language the answer must be written in.
    func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String]
}
