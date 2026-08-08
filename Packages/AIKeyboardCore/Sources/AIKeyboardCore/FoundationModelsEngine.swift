import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device model behind the four actions.
///
/// Two things measured against the real model shaped this file.
///
/// One: every action asks for `@Generable` structured output rather than free
/// text. Asked for free text, the model answers the message instead of
/// editing it ("אתה יכול להעביר לי את הקובץ" comes back as "I'm sorry, but I
/// can't send you the file from yesterday"), and on an already-correct input
/// it will happily expand a one-line message into a five-section plan. A
/// typed field it has to fill does not leave that room.
///
/// Two: the instructions are chosen per language and never merged. A prompt
/// carrying Hebrew examples translated all ten English test inputs into
/// Hebrew; the same prompt in reverse translates Hebrew into English. There
/// is no single prompt that is safe for both.
@available(iOS 26.0, macOS 26.0, *)
public struct FoundationModelsEngine: TextIntelligence {

    private let model: SystemLanguageModel

    public init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    // MARK: Availability

    /// Whether Apple lists every script in this text as one it supports.
    ///
    /// Derived from `supportedLanguages` rather than hard-coded, so the day
    /// Apple adds Hebrew this starts returning true on its own. Today that
    /// set is 23 locales across Latin, Han, Kana and Hangul — no Hebrew.
    public func canHandle(_ text: String, action: AIAction) -> Bool {
        guard Self.competentActions.contains(action) else { return false }
        let scripts = LanguageDetector.scripts(in: text)
        guard !scripts.isEmpty else { return true }
        return scripts.isSubset(of: supportedScripts)
    }

    /// Fix and Tone only, measured rather than assumed.
    ///
    /// Scored against `Bar/ai-text` on the languages Apple *does* support, this
    /// model is good at correcting a sentence and at shifting its register. It is
    /// not good at the two actions that require deciding something: on Rewrite it
    /// returned the uncorrected original as one of its three "different"
    /// versions, and on Reply it produced three variations of the same answer.
    /// Both scored worse than the cloud model does on Hebrew, which is the harder
    /// language — so the bottleneck is the model, not the script.
    ///
    /// With no cloud engine configured these still run, on the best-effort branch,
    /// labelled as such. Declining here changes which engine is *preferred*, not
    /// whether the user gets an answer.
    static let competentActions: Set<AIAction> = [.fix, .tone]

    private var supportedScripts: Set<TextScript> {
        var found: Set<TextScript> = []
        for language in model.supportedLanguages {
            switch language.script?.identifier {
            case "Latn": found.insert(.latin)
            case "Hebr": found.insert(.hebrew)
            default: found.insert(.other)
            }
        }
        return found
    }

    /// The reason the model cannot run at all, if there is one.
    ///
    /// Note this is not sufficient on its own. Every iOS Simulator reports
    /// `.available` here and then throws on the first `respond` call, so the
    /// generation path has to handle failure regardless of what this says.
    public var unavailableReason: AIEngineError? {
        #if targetEnvironment(simulator)
        // No simulator runtime ships model assets, and the framework does not
        // say so: `availability` reports `.available`, and the first
        // `respond` call then blocks rather than throwing. A blocked call
        // takes the app down with it — the panel sits on its shimmer and iOS
        // kills the process — so the simulator is refused up front instead.
        // This is the reason on-device answers never appear in a simulator
        // run; measure the engine on macOS via Bar/ai-text/harness/run-real.sh.
        return .modelNotReady
        #else
        return liveAvailability
        #endif
    }

    private var liveAvailability: AIEngineError? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return .deviceNotSupported
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceOff
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .modelNotReady
        @unknown default:
            return .modelNotReady
        }
    }

    // MARK: Fix

    public func fix(_ text: String) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return text }

        let draft: FixDraft = try await generate(
            instructions: Prompts.fix(for: source),
            prompt: "Message:\n\(source)",
            source: source
        )
        let corrected = clean(draft.text)
        // A blank or wildly truncated answer is worse than no answer: the
        // panel would offer to replace the user's sentence with a fragment.
        guard !corrected.isEmpty else { throw AIEngineError.empty }
        // No list of corrections is asked for on this path — see `EditScope` for
        // what asking cost — so only the changes that are always wrong go back.
        return EditScope.repaired(corrected, to: source)
    }

    // MARK: Rewrite and tone

    public func variants(for text: String, tone: ToneStyle?) async throws -> [RewriteVariant] {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw AIEngineError.empty }

        if let tone {
            let draft: ToneDraft = try await generate(
                instructions: Prompts.tone(tone, for: source),
                prompt: "Message:\n\(source)",
                source: source
            )
            let rewritten = clean(draft.text)
            guard !rewritten.isEmpty else { throw AIEngineError.empty }
            // Tone replaces what the user typed with one string and no choice,
            // so an invented commitment here is the one they send.
            guard OutputGuard.addedSpecifics(in: rewritten, notIn: source).isEmpty else {
                throw AIEngineError.invented
            }
            return [RewriteVariant(tone: tone, text: rewritten)]
        }

        let draft: RewriteDraft = try await generate(
            instructions: Prompts.rewrite(for: source),
            prompt: "Message:\n\(source)",
            source: source
        )
        return try RewriteVariant.vetted(
            [
                (label: clean(draft.firstLabel), text: clean(draft.firstText)),
                (label: clean(draft.secondLabel), text: clean(draft.secondText)),
                (label: clean(draft.thirdLabel), text: clean(draft.thirdText))
            ],
            against: source
        )
    }

    // MARK: Reply

    public func replies(to context: ScreenContext) async throws -> [ReplyOption] {
        let draft: ReplyDraft = try await generate(
            instructions: Prompts.reply(for: context),
            prompt: "From \(context.sender):\n\(context.message)",
            source: context.message
        )
        return try ReplyOption.vetted(
            accept: clean(draft.accept),
            pushBack: clean(draft.pushBack),
            ask: clean(draft.ask),
            against: context.message,
            unnamed: clean(draft.unnamed)
        )
    }

    // MARK: Generation

    /// One call, one fresh session. Nothing is carried between actions, so a
    /// refusal on one message cannot poison the next and the context window
    /// only ever holds the sentence being worked on.
    private func generate<Content: Generable>(
        instructions: String,
        prompt: String,
        source: String
    ) async throws -> Content {
        if let unavailableReason { throw unavailableReason }
        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            return try await session.respond(to: prompt, generating: Content.self).content
        } catch let error as LanguageModelSession.GenerationError {
            var mapped = Self.mapped(error)
            // The framework rejects a whole session whose *instructions* are in a
            // language it does not list — measured: Hebrew instructions fail even
            // with English input, while English instructions accept Hebrew input.
            // It cannot tell us which language it objected to, so name the one the
            // text is actually in; "Hebrew isn't supported" is worth reading and
            // "this language isn't supported" is not.
            if case .unsupportedLanguage = mapped,
                let script = LanguageDetector.scripts(in: source).subtracting([.latin]).first
            {
                mapped = .unsupportedLanguage(script)
            }
            throw mapped
        } catch {
            throw AIEngineError.failed(error.localizedDescription)
        }
    }

    static func mapped(_ error: LanguageModelSession.GenerationError) -> AIEngineError {
        // Checked ahead of the switch because of the simulator: `availability`
        // reports `.available`, generation then throws a GenerationError wrapping
        // ModelManagerError 1026 — no simulator runtime ships model assets — and
        // it does not arrive as `.assetsUnavailable`.
        if isMissingAssets(error) { return .modelNotReady }

        switch error {
        case .exceededContextWindowSize:
            return .inputTooLong
        case .guardrailViolation, .refusal:
            return .refused
        case .unsupportedLanguageOrLocale:
            return .unsupportedLanguage(.other)
        case .assetsUnavailable:
            return .modelNotReady
        case .rateLimited, .concurrentRequests:
            return .failed("The model is busy. Try again in a moment.")
        case .unsupportedGuide, .decodingFailure:
            return .failed("The model returned something unusable.")
        @unknown default:
            return .failed(error.localizedDescription)
        }
    }

    private static func isMissingAssets(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain.contains("ModelManager") { return true }
        let nested = nsError.userInfo[NSMultipleUnderlyingErrorsKey] as? [Error] ?? []
        let underlying = nsError.userInfo[NSUnderlyingErrorKey].map { [$0 as! Error] } ?? []
        return (nested + underlying).contains { isMissingAssets($0) }
    }

    /// Strips the wrappers a model reaches for even when told not to: a fully
    /// quoted answer, a "Corrected:" lead-in, surrounding whitespace.
    private func clean(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Output:", "Corrected:", "Answer:", "Reply:"] where out.hasPrefix(prefix) {
            out = String(out.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        if out.count > 1, out.hasPrefix("\""), out.hasSuffix("\"") {
            out = String(out.dropFirst().dropLast())
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Generated shapes

/// One field, unlike the cloud engine's two.
///
/// The cloud model is asked to list every mistake before it writes the corrected
/// message, which is what lets `EditScope` hold it to that list. This model was
/// asked the same and got worse at the job it was already doing: over the ten
/// English Fix entries in `Bar/ai-text` it began dropping words from the message
/// — "can you send me the id" came back as "you send me the id" — and correcting
/// things it had corrected properly before. Its context is small and its
/// attention is finite; a second field spends both. So it is asked for the
/// message alone, and `EditScope.repaired` cleans up after it without a list.
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct FixDraft {
    @Guide(
        description:
            "The message with spelling and grammar corrected, in the same language and script it arrived in. Correct only what is wrong: a word that is already right, a slang spelling, an abbreviation and a contraction stay as they are."
    )
    var text: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct ToneDraft {
    @Guide(description: "The message rewritten in the requested register, in its original language.")
    var text: String
}

/// Flat rather than an array of a nested `@Generable`, because three named
/// slots with their own guides is what stops the model from returning one
/// answer reworded three times.
///
/// `decision` and `specifics` come first because the fields are filled in the
/// order they are declared, so anything written down here is available to the
/// three versions below it. Both were added against measured failures: asked
/// straight out for three versions, the model produced three phrasings of one
/// refusal, and its negotiating version dropped the deadline the message was
/// about. Naming the decision once and listing the specifics once fixes both
/// without a second round trip.
///
/// The guides carry no worked examples on purpose. An earlier version offered
/// 'Direct no' and 'Counter-proposal' as illustrations, and the model copied
/// them verbatim into every result — including onto a thank-you note, which it
/// then rewrote as declining an offer that did not exist.
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct RewriteDraft {
    @Guide(
        description:
            "What the message decides or asks for, in a few words. Write 'nothing' when it only thanks, informs or shares news."
    )
    var decision: String
    @Guide(
        description:
            "Every time, date, name and number in the message, comma separated. Write 'none' if it has none. Each one has to appear in all three versions below."
    )
    var specifics: String
    @Guide(description: "Two or three words in English naming what this version commits to.")
    var firstLabel: String
    @Guide(
        description:
            "The whole message, rewritten to take that decision as directly as it can be taken. It is still a rewrite: when the message already says it directly, tighten it. Returning the message word for word is not a version. Use only facts already in the message."
    )
    var firstText: String
    @Guide(description: "Two or three words in English naming a different decision this version takes.")
    var secondLabel: String
    @Guide(
        description:
            "The whole message, rewritten to hand the decision back rather than settle it: it asks the other person for what would settle it. When the message decides nothing, this is the same message, shorter and plainer."
    )
    var secondText: String
    @Guide(description: "Two or three words in English naming a third decision this version takes.")
    var thirdLabel: String
    @Guide(
        description:
            "The whole message, rewritten to keep the position but put a different option on the table. When the message decides nothing, this is the same message, warmer — and no longer than the original. Invent no times, names or numbers."
    )
    var thirdText: String
}

/// `unnamed` is first for the same reason `decision` is: the model has to
/// establish whether the message can be agreed to before it writes something
/// that agrees to it. Measured — asked for an accept/push back/ask set on "can
/// you look at this when you get a chance?", the model accepted a task nobody
/// had described and promised when it would be done.
@available(iOS 26.0, macOS 26.0, *)
@Generable
private struct ReplyDraft {
    @Guide(
        description:
            "The task, file or item the sender refers to but never identifies — 'this', 'it' — when agreeing would mean taking on something the user cannot see. Empty when the message says what it is about, and empty when it only asks for time or attention: agreeing to talk hides nothing."
    )
    var unnamed: String
    @Guide(
        description:
            "The grammatical gender to address the sender in, worked out from their name: 'feminine' or 'masculine'. 'none' when the reply is in a language that does not inflect for it."
    )
    var addressee: String
    @Guide(
        description:
            "A reply that agrees or accepts. Use only times and dates the message already named. If something is unnamed above, this reply still asks what it is. Address the sender in the gender named above, never with a slash form."
    )
    var accept: String
    @Guide(
        description:
            "A reply that declines, disagrees or negotiates. Do not offer a different time; if one is needed, ask for it. If something is unnamed above, this reply refuses to commit until it knows what it is, and asks. Same gender as above."
    )
    var pushBack: String
    @Guide(
        description:
            "A reply that asks the one question needed before answering, addressing the sender in the gender named above."
    )
    var ask: String
}

#endif
