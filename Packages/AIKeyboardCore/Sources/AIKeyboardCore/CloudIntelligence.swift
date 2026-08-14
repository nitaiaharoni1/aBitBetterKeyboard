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

    public func fix(_ text: String, style: FixStyle = .proofread) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return text }
        // `corrections` is answered before `text` and is there to be answered
        // rather than shown: naming each mistake is what stops the model
        // respelling words that were already right, and `EditScope` holds the
        // corrected message to the list it just wrote. Same fields, same order,
        // as the on-device `FixDraft`.
        let fields = try await run(
            instructions: Prompts.fix(for: source, style: style),
            prompt: "Message:\n\(source)",
            fields: Self.fixFields(style: style)
        )
        let corrections = fields["corrections"]?.trimmed ?? ""
        guard let corrected = fields["text"]?.trimmed, !corrected.isEmpty else { throw AIEngineError.empty }
        // A leftover last sentence used to replace the whole field. Empty is the
        // existing "nothing usable" failure, so the document is left alone.
        // Skip that when the model named no mistakes: `applied` returns the
        // source anyway, and failing here would turn "nothing to fix" into an
        // error banner.
        guard EditScope.declaresNothing(corrections) || !EditScope.isFragment(corrected, of: source)
        else { throw AIEngineError.empty }
        let scoped = EditScope.applied(corrected, to: source, corrections: corrections)
        // Punctuate and Polish ask for marks the model will not name as a word
        // mistake. `applied` on `none` returns the source, which is right for a
        // tap and wrong for a pass whose whole job is the period. Keep the
        // candidate only when the words themselves did not move.
        if style.allowsUnnamedPunctuation, scoped == source, EditScope.sameWords(corrected, as: source) {
            // `repaired` still strips an added Hebrew full stop, which Punctuate
            // and Polish are told not to add and which the corpus refuses.
            return EditScope.repaired(corrected, to: source)
        }
        return scoped
    }

    /// Proofread's two descriptions are load-bearing and must stay byte for
    /// byte: tests pin the apostrophe wording and the jammed-word examples,
    /// and a rewrite here is how those silently died once already. The other
    /// styles only change what the list is allowed to contain.
    private static func fixFields(style: FixStyle) -> [CloudField] {
        let corrections: String
        let text: String
        switch style {
        case .proofread:
            corrections =
                "Every spelling and grammar mistake in the whole message, as `wrong -> right`, comma separated. Multi-word grammar counts as one: `dont -> don't`, `its not -> it doesn't`. Words stuck together with no space are a mistake: `hellothere -> hello there`, `מהקורה -> מה קורה`. Not mistakes: a correctly spelled word, an alternative accepted Hebrew spelling, slang, an abbreviation, an already-correct contraction, a deliberate lowercase, and a missing full stop. A missing apostrophe is a mistake. 'none' when nothing is wrong."
            text =
                "The whole message with exactly those corrections applied and nothing else changed, in its original language and script. Never return only the last sentence or a fragment."
        case .spelling:
            corrections =
                "Every spelling mistake in the whole message, as `wrong -> right`, comma separated. A missing apostrophe is spelling: `dont -> don't`. Words stuck together are spelling: `hellothere -> hello there`, `מהקורה -> מה קורה`. Not mistakes: grammar, punctuation, slang, an abbreviation, a deliberate lowercase, a missing full stop. 'none' when nothing is misspelled."
            text =
                "The whole message with exactly those spelling corrections applied and nothing else changed, in its original language and script. Never return only the last sentence or a fragment."
        case .punctuate:
            corrections =
                "Word changes: 'none'. This pass does not correct spelling or grammar. If a word is wrong it stays."
            text =
                "The whole message with missing punctuation, question marks and sentence capitals added, and every word left as it was, in its original language and script. Never return only the last sentence or a fragment."
        case .polish:
            corrections =
                "Every spelling and grammar mistake in the whole message, as `wrong -> right`, comma separated. Multi-word grammar counts as one: `dont -> don't`, `its not -> it doesn't`. Words stuck together with no space are a mistake: `hellothere -> hello there`, `מהקורה -> מה קורה`. A missing apostrophe is a mistake. A lowercase first word of an English sentence is a mistake. A missing full stop on an English statement is a mistake. Not mistakes: slang, an abbreviation, an already-correct contraction, an alternative accepted Hebrew spelling, a missing full stop on a Hebrew message. 'none' when nothing is wrong."
            text =
                "The whole message with those corrections applied and looking finished — first word capitalised, a statement ended, a question marked — in its original language and script. Never return only the last sentence or a fragment."
        }
        return [
            CloudField("corrections", corrections),
            CloudField("text", text)
        ]
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

    /// Everything a request needs to be correct — the Full Access check, the
    /// transport, the field ordering — lives in here, so a caller reaching
    /// around it would be reimplementing all three.
    private func run(
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
