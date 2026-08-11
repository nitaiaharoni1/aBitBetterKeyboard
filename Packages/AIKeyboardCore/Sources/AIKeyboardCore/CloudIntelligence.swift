import Foundation

// MARK: - Engine

/// The cloud path, which exists because Apple's on-device model does not list
/// Hebrew — the language most of this keyboard's traffic is in.
///
/// It shares `Prompts` and the field names with the on-device engine on purpose:
/// two engines with two prompt sets would drift, and the prompts are where the
/// language guarantees actually live.
public struct CloudIntelligence: TextIntelligence {
    private let transport: any CloudTransport
    /// A keyboard extension has no network at all until the user grants Full
    /// Access, so this is asked before the request rather than after it fails.
    private let networkAllowed: @Sendable () -> Bool

    public init(transport: any CloudTransport, networkAllowed: @escaping @Sendable () -> Bool = { true }) {
        self.transport = transport
        self.networkAllowed = networkAllowed
    }

    /// The cloud model has no script and no action it will not take. That is the
    /// entire reason this path exists.
    public func canHandle(_ text: String, action: AIAction) -> Bool { true }

    public func fix(_ text: String) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return text }
        // `corrections` is answered before `text` and is there to be answered
        // rather than shown: naming each mistake is what stops the model
        // respelling words that were already right, and `EditScope` holds the
        // corrected message to the list it just wrote. Same fields, same order,
        // as the on-device `FixDraft`.
        let fields = try await run(
            instructions: Prompts.fix(for: source),
            prompt: "Message:\n\(source)",
            fields: [
                CloudField(
                    "corrections",
                    "Every mistake in the message, as `wrong -> right`, comma separated. Only real mistakes: a correctly spelled word, an alternative accepted spelling, slang, an abbreviation, a contraction, a deliberate lowercase and a missing full stop are not mistakes. 'none' when nothing is wrong."
                ),
                CloudField(
                    "text",
                    "The message with exactly those corrections applied and nothing else changed, in its original language and script."
                )
            ]
        )
        guard let corrected = fields["text"]?.trimmed, !corrected.isEmpty else { throw AIEngineError.empty }
        return EditScope.applied(
            corrected, to: source, corrections: fields["corrections"]?.trimmed ?? "")
    }

    /// The engine that can honour a user-authored register, because the cloud
    /// model has no supported-language list to fall outside of. Nothing else
    /// changes with one: `OutputGuard.addedSpecifics` still vets the answer, so a
    /// register the user wrote does not get to loosen the rule that Tone may not
    /// invent a time, a day or a number.
    public func variants(
        for text: String, tone: ToneStyle?, instruction: String? = nil
    ) async throws -> [RewriteVariant] {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw AIEngineError.empty }

        if let tone {
            let fields = try await run(
                instructions: Prompts.tone(tone, for: source, instruction: instruction),
                prompt: "Message:\n\(source)",
                fields: [CloudField("text", "The message rewritten in the requested register.")]
            )
            guard let rewritten = fields["text"]?.trimmed, !rewritten.isEmpty else {
                throw AIEngineError.empty
            }
            // Tone replaces what the user typed with one string and no choice,
            // so an invented commitment here is the one they send.
            guard OutputGuard.addedSpecifics(in: rewritten, notIn: source).isEmpty else {
                throw AIEngineError.invented
            }
            return [RewriteVariant(tone: tone, text: rewritten)]
        }

        // The first two fields are answered before the three versions are
        // written, and are there to be answered rather than shown: naming the
        // decision once is what stops three phrasings of it, and listing the
        // specifics once is what stops the third version dropping the deadline
        // the message was about. Same fields, same order, as the on-device
        // `RewriteDraft`.
        let fields = try await run(
            instructions: Prompts.rewrite(for: source),
            prompt: "Message:\n\(source)",
            fields: [
                CloudField(
                    "decision",
                    "What the message decides or asks for, in a few words. 'nothing' when it only thanks, informs or shares news."
                ),
                CloudField(
                    "specifics",
                    "Every time, date, name and number in the message, comma separated. 'none' if it has none. Each one appears in all three versions."
                ),
                CloudField(
                    "firstLabel", "Two or three words in English naming the decision this version takes."),
                CloudField(
                    "firstText",
                    "The message rewritten to take that decision as directly as it can be taken. It is still a rewrite: when the message already says it directly, tighten it, and never return it word for word."
                ),
                CloudField("secondLabel", "Two or three words in English naming a different decision."),
                CloudField(
                    "secondText",
                    "The message rewritten to hand the decision back rather than settle it, asking the other person for what would settle it. When the message decides nothing, the same message, shorter and plainer."
                ),
                CloudField("thirdLabel", "Two or three words in English naming a third decision."),
                CloudField(
                    "thirdText",
                    "The message rewritten to keep the position but put a different option on the table. When the message decides nothing, the same message, warmer — and no longer than the original."
                )
            ]
        )
        return try RewriteVariant.vetted(
            [
                (label: fields["firstLabel"]?.trimmed ?? "", text: fields["firstText"]?.trimmed ?? ""),
                (label: fields["secondLabel"]?.trimmed ?? "", text: fields["secondText"]?.trimmed ?? ""),
                (label: fields["thirdLabel"]?.trimmed ?? "", text: fields["thirdText"]?.trimmed ?? "")
            ],
            against: source
        )
    }

    public func replies(to context: ScreenContext) async throws -> [ReplyOption] {
        // `unnamed` leads for the same reason `decision` leads Rewrite: whether
        // the message can be agreed to at all has to be settled before the reply
        // that agrees to it is written.
        let fields = try await run(
            instructions: Prompts.reply(for: context),
            prompt: "From \(context.sender):\n\(context.message)",
            fields: [
                CloudField(
                    "unnamed",
                    "The task, file or item the sender refers to but never identifies — 'this', 'it' — when agreeing would mean taking on something the user cannot see. Empty when the message says what it is about, and empty when it only asks for time or attention: agreeing to talk hides nothing."
                ),
                CloudField(
                    "addressee",
                    "The grammatical gender to address the sender in, worked out from their name: 'feminine' or 'masculine'. 'none' when the reply is in a language that does not inflect for it."
                ),
                CloudField(
                    "accept",
                    "A reply that agrees or accepts. If something is unnamed above, it still asks what it is. Address the sender in the gender named above, never with a slash form."
                ),
                CloudField(
                    "pushBack",
                    "A reply that declines, disagrees or negotiates. If something is unnamed above, it refuses to commit until it knows what it is, and asks. Same gender as above."
                ),
                CloudField(
                    "ask",
                    "A reply that asks the one question needed before answering, addressing the sender in the gender named above."
                )
            ]
        )
        return try ReplyOption.vetted(
            accept: fields["accept"]?.trimmed ?? "",
            pushBack: fields["pushBack"]?.trimmed ?? "",
            ask: fields["ask"]?.trimmed ?? "",
            against: context.message,
            unnamed: fields["unnamed"]?.trimmed ?? ""
        )
    }

    /// Internal rather than private since `CloudIntelligence+Prediction` became
    /// the second caller. Everything a request needs to be correct — the Full
    /// Access check, the transport, the field ordering — lives in here, so a
    /// caller reaching around it would be reimplementing all three.
    func run(
        instructions: String,
        prompt: String,
        fields: [CloudField]
    ) async throws -> [String: String] {
        guard networkAllowed() else { throw AIEngineError.needsFullAccess }
        return try await transport.send(
            CloudRequest(instructions: instructions, prompt: prompt, fields: fields)
        )
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
