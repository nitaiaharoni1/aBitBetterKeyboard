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
    /// Apple adds Hebrew this starts returning true on its own. Measured on
    /// 2026-08-09 against Xcode 26.2, on macOS 26.5 and inside the iOS 26.2
    /// Simulator, which agree exactly: 23 locales over the language codes
    /// `da de en es fr it ja ko nb nl pt sv tr vi zh`, whose scripts are
    /// `Latn`, `Hans`, `Hant`, `Jpan` and `Kore`. No Hebrew, no Arabic, no
    /// Cyrillic, no Greek, no Devanagari.
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

    /// The scripts Apple's list names that this product can also name.
    ///
    /// **A script we cannot name is never added here, and that line is the whole
    /// fix.** This used to read `default: found.insert(.other)`, so Japanese,
    /// Korean and Chinese — which had no case in `TextScript` — each put `.other`
    /// into the supported set. `.other` is also what `LanguageDetector` answers
    /// for any script it cannot name, so Russian, Greek, Arabic and Hindi all
    /// passed `isSubset(of:)` and routed on-device to a model with no word of any
    /// of them. Naming the shipped scripts individually fixed the detector half;
    /// this fixes the other.
    ///
    /// `TextScript`'s raw values are ISO 15924 codes and `Locale.Language.script`
    /// reports the same identifiers, so the mapping is a lookup rather than a
    /// table that can go stale. The cost is that Japanese, Korean and Chinese now
    /// prefer the cloud — they are outside the scripts this keyboard can type in
    /// at all, they still get an answer, and the alternative is the bug above.
    private var supportedScripts: Set<TextScript> {
        var found: Set<TextScript> = []
        for language in model.supportedLanguages {
            guard let identifier = language.script?.identifier,
                let script = TextScript(rawValue: identifier), script != .other
            else { continue }
            found.insert(script)
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

    public func variants(
        for text: String, tone: ToneStyle?, instruction: String? = nil
    ) async throws -> [RewriteVariant] {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw AIEngineError.empty }

        if let tone {
            let draft: ToneDraft = try await generate(
                // Nothing is filtered here. `Prompts.tone` drops a register whose
                // script the instruction set it picked does not speak, which is
                // the rule that keeps a Hebrew register out of this session — and
                // it has to live there rather than here, because the cloud engine
                // needs the same rule and had no filter of its own.
                instructions: Prompts.tone(tone, for: source, instruction: instruction),
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

#endif
