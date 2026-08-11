import Foundation

extension CloudIntelligence: TextPrediction {

    /// Every language, because the backend model has every language.
    ///
    /// This is the asymmetry that makes the cloud engine the important half of
    /// prediction rather than the fallback: Apple's on-device model does not list
    /// Hebrew, and Hebrew is two thirds of what this keyboard is for.
    public func canPredict(in language: KeyboardLanguage) -> Bool { true }

    public func continuations(
        after text: String, replyingTo context: ScreenContext?, language: KeyboardLanguage
    ) async throws -> [String] {
        // Three separate fields rather than one list, for the reason every other
        // action here uses separate fields: the model fills them in order and the
        // transport sends `propertyOrdering`, so "the likeliest" is a position
        // rather than something the model has to be asked to sort. A single array
        // field comes back in whatever order it was generated.
        let fields = try await run(
            instructions: Prompts.continuation(for: text, replyingTo: context),
            prompt: prompt(for: text, context: context),
            fields: [
                CloudField("first", "The single likeliest next word."),
                CloudField(
                    "second",
                    "A different likely next word. Not a variation or inflection of the first."),
                CloudField(
                    "third",
                    "A third next word, taking the sentence somewhere neither of the others does.")
            ])
        return ["first", "second", "third"].compactMap { fields[$0] }
    }

    /// The typed text, and the message being answered when there is one.
    ///
    /// Labelled rather than concatenated. Handed a bare pair of paragraphs the
    /// model has to guess which one it is continuing, and it guesses wrong often
    /// enough to matter — it starts predicting the received message back at the
    /// person who received it.
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
