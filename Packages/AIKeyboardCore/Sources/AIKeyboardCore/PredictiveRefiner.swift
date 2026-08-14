import Foundation

/// The second tier of the suggestion bar: the on-device model, asked once the
/// user pauses.
///
/// The local tier fills all three slots on every keystroke. This runs hundreds
/// of milliseconds later and may replace the side words *and* the bold one.
/// Slot 0 stays the typed keystrokes. Space still only inserts the bold word
/// when Autocorrect is on; Complete on pause and Space on pause are separate
/// switches. There is no cloud engine here. Hebrew has no on-device predictor,
/// so this tier is silent there and the dictionary stands.
///
/// **When it runs.** On a 300 ms idle after the last keystroke, and only when the
/// answer could plausibly beat what is already on screen. The guards are in
/// `shouldRefine` and each of them is a case where the call would be waste, harm,
/// or both.
@MainActor
public final class PredictiveRefiner {

    /// How long the user has to stop typing before the model is asked.
    ///
    /// 300 ms is a pause in thought rather than a gap between keys: ordinary
    /// typing runs at 100-200 ms per keystroke, so a shorter window fires
    /// mid-word constantly and a longer one arrives after the user has already
    /// moved on. Nothing about this number is measured against real users yet, and
    /// it is the first thing to tune when there is data.
    public static let idleDelay = Duration.milliseconds(300)

    /// The tail of the message handed to the model.
    ///
    /// **iOS already windows `documentContextBeforeInput`.** That window *is*
    /// the full typed input a keyboard can see, and chopping it again to 40
    /// words threw away the start of any message longer than a short paragraph
    /// — the names, the question, the reason the current sentence exists.
    /// Apple's on-device window is four thousand tokens; a chat field that has
    /// already been truncated by the host will not fill it. A notes document
    /// that somehow arrives whole is still a string already in memory.
    static func tail(of text: String) -> String { text }

    private static let cacheLimit = 128

    private let predictor: (any TextPrediction)?
    /// Answers already paid for, keyed by exactly what was asked, oldest evicted
    /// first once `cacheLimit` is reached.
    ///
    /// Bounded because a keyboard extension is capped around 50 MB and this grows
    /// by one entry per model call for as long as the process lives — "it is only
    /// a few strings" is the argument that ends with the keyboard being killed
    /// mid-sentence. Insertion order rather than least-recently-used: the thing
    /// being cached is a sentence somebody is still typing, so the oldest key is
    /// almost always the least useful one, and an LRU would need an order to
    /// maintain on the keystroke path to say the same thing.
    private var cache: [String: [String]] = [:]
    private var cacheOrder: [String] = []
    private var inFlight: Task<Void, Never>?

    /// Called with the refined words and the word-in-progress they were asked
    /// about.
    ///
    /// **The prefix is handed back rather than re-read by the receiver, and that
    /// is the difference between a staleness check and a no-op.** The first
    /// version of this let the caller read `currentWordPrefix` at apply time and
    /// compare it against `currentWordPrefix` — always equal, so an answer to a
    /// question asked four keystrokes ago was applied as if it were fresh.
    private let apply: ([String], String) -> Void

    public init(
        onDevice: (any TextPrediction)? = nil,
        apply: @escaping ([String], String) -> Void
    ) {
        self.predictor = onDevice
        self.apply = apply
    }

    /// The shipping configuration: Apple's on-device model where it lists the
    /// script, and silence everywhere else (Hebrew included).
    public static func standard(
        apply: @escaping ([String], String) -> Void
    ) -> PredictiveRefiner {
        var local: (any TextPrediction)?
        if #available(iOS 26.0, macOS 26.0, *) { local = FoundationModelsEngine() }
        return PredictiveRefiner(onDevice: local, apply: apply)
    }

    /// Everything the refiner needs to decide whether to run and what to ask.
    public struct Request: Sendable {
        public let textBefore: String
        public let wordInProgress: String
        public let language: KeyboardLanguage
        public let screenContext: ScreenContext?
        /// Whether recording or sending anything from this field is allowed at
        /// all. Passed in rather than asked here, because the two things it
        /// depends on both live in `KeyboardController`.
        public let permitted: Bool

        public init(
            textBefore: String, wordInProgress: String, language: KeyboardLanguage,
            screenContext: ScreenContext?, permitted: Bool
        ) {
            self.textBefore = textBefore
            self.wordInProgress = wordInProgress
            self.language = language
            self.screenContext = screenContext
            self.permitted = permitted
        }

        /// What two requests must share to be the same question. Deliberately not
        /// `self`: the screen context is carried by identity and the permission is
        /// not part of the question, so including them would miss cache hits the
        /// model has already been paid for.
        var cacheKey: String {
            [
                language.rawValue, wordInProgress, textBefore,
                screenContext.map { "\($0.sender)|\($0.message)" } ?? ""
            ].joined(separator: "\u{1F}")
        }
    }

    /// Ask, once the user has stopped typing.
    ///
    /// Cancels whatever was in flight first. A prediction for a sentence the user
    /// has already added two words to is worse than no prediction, and paying for
    /// it twice over is the second reason.
    public func refine(_ request: Request) {
        inFlight?.cancel()
        inFlight = nil
        guard shouldRefine(request) else { return }

        if let cached = cache[request.cacheKey] {
            apply(cached, request.wordInProgress)
            return
        }

        inFlight = Task { [weak self] in
            try? await Task.sleep(for: Self.idleDelay)
            guard !Task.isCancelled, let self else { return }
            guard let words = await self.ask(request), !Task.isCancelled else { return }
            self.store(words, for: request.cacheKey)
            self.apply(words, request.wordInProgress)
        }
    }

    /// Keeps the extension's paid-answer cache useful without letting a long-lived
    /// keyboard process grow it forever.
    private func store(_ words: [String], for key: String) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > Self.cacheLimit {
                cache.removeValue(forKey: cacheOrder.removeFirst())
            }
        }
        cache[key] = words
    }

    /// Stop waiting and forget what was asked. Called when the keyboard goes away
    /// or the field changes, so an answer cannot arrive into a different document.
    public func cancel() {
        inFlight?.cancel()
        inFlight = nil
    }

    /// Whether this request is worth a model call.
    ///
    /// Every clause is a case where the call is waste, harm, or both, and none of
    /// them is a tuning knob:
    ///
    /// - **No engine for the language.** Three words of the wrong language above
    ///   the keys are noise, not a degraded answer.
    /// - **A credential field.** The same question `SecureField` answers for a
    ///   screen read: a password must not be sent anywhere, and a half-typed one
    ///   is still a password.
    /// - **Nothing to predict from.** An empty field with no message on screen has
    ///   no context at all, and a model asked to guess from nothing returns the
    ///   same three openers the local tier already has.
    func shouldRefine(_ request: Request) -> Bool {
        guard request.permitted else { return false }
        guard let predictor, predictor.canPredict(in: request.language) else {
            return false
        }
        let hasText = !request.textBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || request.screenContext != nil else { return false }
        return true
    }

    /// The on-device engine, or silence. No fallback chain.
    ///
    /// A failure here is silent on purpose. The bar is already full — the local
    /// tier filled it before this was ever asked — so there is nothing to report
    /// and nobody to report it to. Every other action in this repo surfaces its
    /// errors because the user pressed a button and is waiting; nobody pressed
    /// anything here.
    private func ask(_ request: Request) async -> [String]? {
        guard let predictor, predictor.canPredict(in: request.language) else { return nil }
        let text = Self.tail(of: request.textBefore + request.wordInProgress)
        guard
            let words = try? await predictor.continuations(
                after: text, replyingTo: request.screenContext, language: request.language)
        else { return nil }
        let cleaned = Self.cleaned(words, continuing: request.wordInProgress)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// What survives of a model's answer.
    ///
    /// **A vetting step rather than a formatting one, and it is here because the
    /// model is answering into a three-slot bar it cannot see.** Asked for one
    /// word it will sometimes return a sentence, sometimes repeat itself, and —
    /// when there is a word in progress — sometimes return something that does not
    /// continue it at all, which would put a word in the bar that replaces the
    /// letters the user is still typing rather than completing them.
    static func cleaned(_ words: [String], continuing prefix: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in words {
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
            guard !word.isEmpty, word.split(whereSeparator: \.isWhitespace).count <= 2 else {
                continue
            }
            // Mid-word, a suggestion that does not start with what has been typed
            // is not a suggestion for this word.
            if !prefix.isEmpty {
                guard SeedLanguageModel.fold(word).hasPrefix(SeedLanguageModel.fold(prefix)) else {
                    continue
                }
            }
            let key = SeedLanguageModel.fold(word)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(word)
            if out.count == 2 { break }
        }
        return out
    }
}
