import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Three next words, from the model on the device.
///
/// Flat and named rather than an array, for the reason `RewriteDraft` is flat:
/// the model fills fields in the order they are declared, so "likeliest" is a
/// position in the schema instead of a sort the model has to be trusted to do.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct ContinuationDraft {
    @Guide(description: "The single likeliest next word. One word, occasionally two.")
    var first: String
    @Guide(
        description:
            "A different likely next word. Not a variation or inflection of the first.")
    var second: String
    @Guide(
        description:
            "A third next word, taking the sentence somewhere neither of the others does.")
    var third: String
}

@available(iOS 26.0, macOS 26.0, *)
extension FoundationModelsEngine: TextPrediction {

    /// **The scripts Apple lists, and prediction gets no best-effort branch.**
    /// Everywhere else in this repo a language outside the list still reaches
    /// this model, labelled `onDeviceBestEffort`, because a flawed fix is worth
    /// more than no fix. Prediction is the opposite: three wrong-language words
    /// sitting above the keys are not a degraded answer, they are noise the
    /// user has to read past on every keystroke. So Hebrew goes to the cloud or
    /// nowhere, and this returns a plain false rather than a hedge.
    public func canPredict(in language: KeyboardLanguage) -> Bool {
        guard unavailableReason == nil else { return false }
        return supportsScript(language.script)
    }

    public func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] {
        let draft: ContinuationDraft = try await generate(
            instructions: Prompts.continuation(for: text, replyingTo: context),
            prompt: prompt(for: text, context: context),
            source: text)
        return [draft.first, draft.second, draft.third]
    }

    /// Labelled rather than concatenated, for the same reason the cloud engine
    /// labels it: handed two bare paragraphs the model has to guess which one it
    /// is continuing, and it guesses wrong often enough to matter.
    private func prompt(for text: String, context: ScreenContext?) -> String {
        guard let context else { return "Typed so far:\n\(text)" }
        return """
            They received this message from \(context.sender):
            \(context.message)

            Typed so far, as their reply:
            \(text)
            """
    }
}
#endif
