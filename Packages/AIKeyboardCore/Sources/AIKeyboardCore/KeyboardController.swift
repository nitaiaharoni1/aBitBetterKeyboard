import SwiftUI
import UIKit
import Combine

// MARK: - Text target

/// Everything the keyboard needs from the document it is typing into.
///
/// `UITextDocumentProxy` satisfies this as-is. The companion app supplies its own
/// implementation so onboarding can show a working keyboard before the real one
/// has been installed.
@MainActor
public protocol TextTarget: AnyObject {
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }

    /// Whether this is a password field, as the host answered.
    ///
    /// `Bool?` rather than `Bool`, and the optionality is the whole point:
    /// `isSecureTextEntry` is declared inside an `@optional` block of
    /// `UITextInputTraits`, so a host that does not implement it answers nil and
    /// `SecureField` reads nil as "refuse". Anything conforming to this that
    /// positively knows it is not a secure field answers `false`; nothing may
    /// answer `false` to mean "I did not check".
    var isSecureTextEntry: Bool? { get }

    /// The second, independent refusal. `UITextContentType??` because both levels
    /// are real: the outer nil is a host that did not implement the property, the
    /// inner nil is one that implemented it and set nothing.
    var textContentType: UITextContentType?? { get }

    func insertText(_ text: String)
    func deleteBackward()
}

/// Bridges the system proxy to `TextTarget`. `UITextDocumentProxy` is itself a
/// protocol, so it cannot be given a new conformance in an extension.
@MainActor
public final class ProxyTextTarget: TextTarget {
    private let proxy: UITextDocumentProxy

    public init(_ proxy: UITextDocumentProxy) {
        self.proxy = proxy
    }

    public var documentContextBeforeInput: String? { proxy.documentContextBeforeInput }
    public var documentContextAfterInput: String? { proxy.documentContextAfterInput }
    public var selectedText: String? { proxy.selectedText }

    /// Forwarded exactly as the SDK declares them, optionals and all. Widening
    /// either of these to a non-optional here would put the "unknown permits"
    /// hole back in a place `SecureField`'s tests cannot see.
    public var isSecureTextEntry: Bool? { proxy.isSecureTextEntry }
    public var textContentType: UITextContentType?? { proxy.textContentType }

    public func insertText(_ text: String) { proxy.insertText(text) }
    public func deleteBackward() { proxy.deleteBackward() }
}

/// An in-memory document, so the companion app can demo the keyboard before the
/// extension is installed.
@MainActor
public final class MockTextTarget: TextTarget, ObservableObject {
    @Published public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public var documentContextBeforeInput: String? { text }
    public var documentContextAfterInput: String? { "" }
    public var selectedText: String? { nil }

    /// A positive `false`, not a shrug. This is a `String` in this process with
    /// no secure-entry behaviour anywhere near it, so it answers the question
    /// rather than declining to — which is what keeps the in-app playground and
    /// onboarding working under a guard that refuses on silence.
    public var isSecureTextEntry: Bool? { false }
    public var textContentType: UITextContentType?? { .some(.none) }

    public func insertText(_ newText: String) { text.append(newText) }
    public func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

// MARK: - Controller

/// All keyboard state and every text mutation. Views stay declarative and dumb.
@MainActor
public final class KeyboardController: ObservableObject {

    // MARK: Published state

    @Published public var language: KeyboardLanguage
    @Published public var plane: KeyboardPlane = .letters
    @Published public var shift: ShiftState = .on
    @Published public var overlay: KeyboardOverlay = .none
    @Published public var suggestions: [Suggestion] = []
    @Published public var pressedKeyID: String?

    /// True while a mock AI call is in flight.
    @Published public var isWorking = false
    @Published public var workingPhase: Double = 0

    @Published public var aiSourceText = ""
    @Published public var aiResultText = ""
    @Published public var variants: [RewriteVariant] = []
    @Published public var selectedTone: ToneStyle?
    @Published public var replies: [ReplyOption] = []

    /// The reading the replies on screen were written about. Held separately
    /// from `screenContext` because the screen moves on: by the time three
    /// replies come back, the strip may be showing a different message, and the
    /// panel has to restate the one it answered.
    @Published public var replyContext: ScreenContext?

    /// Why the last AI call produced nothing. The panel shows this instead of an
    /// empty result, which is the one outcome the user cannot act on.
    @Published public var aiError: AIEngineError?
    /// Which engine answered, so a best-effort answer can say so.
    @Published public var aiProvenance: AIProvenance?

    /// Mirrored from the capture session so views can observe one object.
    @Published public var screenContext: ScreenContextState = .off

    /// Also mirrored, and separately, because the two move independently: the
    /// scripted sample handing over to a real session changes what the strip may
    /// claim without changing the state it is showing.
    @Published public var screenContextSource: ScreenContextSession.Source = .none

    /// The last Reply tap asked the capture process for a read and got nothing
    /// back. Mirrored so the strip and the AI menu can stop offering a read the
    /// build has just demonstrated it cannot do. See
    /// `ScreenContextSession.lastReadWentUnanswered`.
    @Published public var screenReadWentUnanswered = false

    @Published public var isDictating = false
    @Published public var dictationTranscript = ""
    @Published public var dictationIsRightToLeft = false
    @Published public var waveformPhase: Double = 0

    @Published public var recentEmoji: [String] = ["😂", "🙏", "❤️", "👍", "🔥", "😅"]

    /// Set by the host controller. False in the app preview, where there is no
    /// keyboard to switch to.
    public var showsGlobeKey = true

    /// Called when the globe key is tapped inside the real extension.
    public var onAdvanceToNextKeyboard: (() -> Void)?

    // MARK: Dependencies

    private weak var target: TextTarget?
    private let store: SharedStore
    private let engine: RoutedIntelligence

    private var dictationTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var workingTask: Task<Void, Never>?
    private var scriptIndex = 0
    private var lastSpaceTapAt: Date?
    private var cancellables = Set<AnyCancellable>()

    /// Names and shortcuts from `UILexicon`, read once by `KeyboardViewController`
    /// via `requestSupplementaryLexicon` and handed down. Empty until that
    /// callback returns, and empty for good in the app's playground, which has
    /// no host to ask.
    private var supplementaryWords: [String] = []

    public init(
        target: TextTarget?,
        store: SharedStore = .shared,
        language: KeyboardLanguage = .english,
        engine: RoutedIntelligence? = nil
    ) {
        self.target = target
        self.store = store
        self.language = language
        // No backend URL ships in this build, so the cloud half is usually nil
        // and Hebrew reports why rather than being handed to a model that would
        // answer it in English.
        self.engine =
            engine
            ?? RoutedIntelligence.standard(
                cloud: BackendTransport.configured().map { CloudIntelligence(transport: $0) }
            )

        let session = ScreenContextSession.shared
        screenContext = session.state
        screenContextSource = session.source
        screenReadWentUnanswered = session.lastReadWentUnanswered
        session.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                withAnimation(Theme.Motion.panel) { self.screenContext = state }
            }
            .store(in: &cancellables)
        session.$source
            .receive(on: RunLoop.main)
            .sink { [weak self] source in self?.screenContextSource = source }
            .store(in: &cancellables)
        session.$lastReadWentUnanswered
            .receive(on: RunLoop.main)
            .sink { [weak self] unanswered in self?.screenReadWentUnanswered = unanswered }
            .store(in: &cancellables)

        refreshSuggestions()
    }

    /// Reply is worth offering for as long as a session is live, whether or not
    /// anything has been read yet.
    ///
    /// It used to require a reading. That was right when the session read every
    /// frame speculatively and is wrong now: there is one trigger for a read and
    /// it is this tap, so waiting for a reading before showing the button would
    /// mean never showing it. The tap raises `intent.readNow` and waits.
    public var canReply: Bool {
        screenContextIsPermitted && screenContext.isLive
    }

    /// The strip earns its height whenever screen context has something to say,
    /// which includes having stopped: an ending that hides itself has told the
    /// user screen context is off.
    public var showsScreenContextStrip: Bool {
        screenContextIsPermitted && screenContext.isVisible
    }

    /// Whether a capture session is running right now, as opposed to the scripted
    /// sample. The recording indicator keys off this and nothing else: a red dot
    /// over a demo claims the screen is being watched when it is not.
    public var isCapturingScreen: Bool {
        screenContextSource == .capture && screenContext.isLive
    }

    /// Whether the strip may offer to stop the session. Only the scripted demo
    /// can be stopped from in here: a broadcast is ended by the user in iOS's own
    /// UI, and this process has no way to end one.
    public var canStopScreenContext: Bool {
        screenContextSource == .scripted && screenContext.isVisible
    }

    /// A real capture session is its own permission. The stored setting is the
    /// opt-in for the scripted in-app demo; a broadcast the user started in
    /// Apple's picker, with iOS showing the red pill for as long as it runs, is a
    /// stronger signal than any switch of ours and is not second-guessed here.
    private var screenContextIsPermitted: Bool {
        screenContextSource == .capture || store.screenContextAllowed
    }

    public func attach(target: TextTarget) {
        self.target = target
        refreshSuggestions()
    }

    // MARK: Derived text

    public var contextBefore: String { target?.documentContextBeforeInput ?? "" }
    public var contextAfter: String { target?.documentContextAfterInput ?? "" }
    public var selection: String? {
        guard let text = target?.selectedText, !text.isEmpty else { return nil }
        return text
    }

    /// The partial word under the cursor.
    public var currentWordPrefix: String {
        let before = contextBefore
        guard let last = before.last, !last.isWhitespace else { return "" }
        return String(before.reversed().prefix { !$0.isWhitespace }.reversed())
    }

    /// What the AI actions operate on: the selection if there is one, otherwise
    /// the sentence the cursor sits in.
    public var aiTargetText: String {
        if let selection { return selection }
        return currentSentence
    }

    private var currentSentence: String {
        let before = contextBefore
        guard !before.isEmpty else { return "" }
        let terminators = CharacterSet(charactersIn: ".!?\n")
        let trimmed = before.hasSuffix(" ") ? String(before.dropLast()) : before
        if let range = trimmed.rangeOfCharacter(from: terminators, options: .backwards) {
            return String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed.trimmingCharacters(in: .whitespaces)
    }

    public var hasTextToWorkWith: Bool {
        !aiTargetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The focused field's content type, flattened past the optional that having
    /// no target at all adds. No target is a question nobody answered, which is
    /// the outer nil and which `SecureField` refuses like any other silence.
    private var fieldContentType: UITextContentType?? {
        guard let target else { return UITextContentType??.none }
        return target.textContentType
    }

    // MARK: Typing

    public func press(_ cap: KeyCap) {
        switch cap {
        case .character(let value):
            insertCharacter(value)
        case .shift:
            toggleShift()
        case .backspace:
            deleteBackward()
        case .plane(let destination, _):
            Feedback.modifierPress()
            withAnimation(Theme.Motion.quick) { plane = destination }
        case .globe:
            Feedback.modifierPress()
            advanceLanguage()
        case .space:
            insertSpace()
        case .ret:
            Feedback.keyPress()
            Feedback.keyClick()
            target?.insertText("\n")
            shift = store.autocapitalise ? .on : .off
            refreshSuggestions()
        case .dictation:
            Feedback.actionPress()
            startDictation()
        }
    }

    private func insertCharacter(_ value: String) {
        Feedback.keyPress()
        Feedback.keyClick()
        let output = shift.isUppercase ? value.uppercased() : value
        target?.insertText(output)
        if shift == .on { shift = .off }
        refreshSuggestions()
    }

    private func insertSpace() {
        Feedback.keyPress()
        Feedback.keyClick()

        // Two spaces in quick succession become a full stop, as on the system keyboard.
        let now = Date()
        if let last = lastSpaceTapAt,
            now.timeIntervalSince(last) < 0.6,
            contextBefore.hasSuffix(" "),
            !contextBefore.hasSuffix("  ")
        {
            target?.deleteBackward()
            target?.insertText(". ")
            lastSpaceTapAt = nil
            shift = store.autocapitalise ? .on : .off
            refreshSuggestions()
            return
        }
        lastSpaceTapAt = now

        // A space commits the highlighted candidate, which is what makes a
        // suggestion bar worth having.
        if store.autocorrect,
            let candidate = suggestions.first(where: \.isDefault),
            !currentWordPrefix.isEmpty,
            candidate.text.lowercased() != currentWordPrefix.lowercased()
        {
            replaceCurrentWord(with: candidate.text)
        }

        target?.insertText(" ")
        refreshSuggestions()
    }

    public func deleteBackward() {
        Feedback.keyPress()
        target?.deleteBackward()
        refreshSuggestions()
    }

    public func toggleShift() {
        Feedback.modifierPress()
        switch shift {
        case .off: shift = .on
        case .on: shift = .locked
        case .locked: shift = .off
        }
    }

    public func advanceLanguage() {
        let enabled = store.enabledLanguages.isEmpty ? [.english, .hebrew] : store.enabledLanguages
        guard enabled.count > 1 else {
            onAdvanceToNextKeyboard?()
            return
        }
        let index = enabled.firstIndex(of: language) ?? 0
        withAnimation(Theme.Motion.quick) {
            language = enabled[(index + 1) % enabled.count]
            plane = .letters
        }
        refreshSuggestions()
    }

    // MARK: Suggestions

    public func refreshSuggestions() {
        guard store.predictions else {
            suggestions = []
            return
        }
        let prefix = currentWordPrefix
        let before = contextBefore
        let context = prefix.isEmpty ? before : String(before.dropLast(prefix.count))
        suggestions = SuggestionEngine.suggestions(
            prefix: prefix,
            context: context,
            languages: store.enabledLanguages,
            supplementary: supplementaryWords
        )
    }

    /// Called by `KeyboardViewController` once `requestSupplementaryLexicon`
    /// answers. Re-scores immediately rather than waiting for the next
    /// keystroke, since the lexicon usually lands while the user is already
    /// mid-word.
    public func updateSupplementaryLexicon(_ words: [String]) {
        supplementaryWords = words
        refreshSuggestions()
    }

    public func apply(_ suggestion: Suggestion) {
        Feedback.keyPress()
        replaceCurrentWord(with: suggestion.text)
        target?.insertText(" ")
        refreshSuggestions()
    }

    private func replaceCurrentWord(with replacement: String) {
        let prefix = currentWordPrefix
        for _ in 0..<prefix.count { target?.deleteBackward() }
        target?.insertText(replacement)
    }

    // MARK: Emoji

    public func insertEmoji(_ emoji: String) {
        Feedback.keyPress()
        target?.insertText(emoji)
        recentEmoji.removeAll { $0 == emoji }
        recentEmoji.insert(emoji, at: 0)
        recentEmoji = Array(recentEmoji.prefix(24))
        refreshSuggestions()
    }

    // MARK: Overlays

    public func show(_ newOverlay: KeyboardOverlay) {
        Feedback.modifierPress()
        withAnimation(Theme.Motion.panel) { overlay = newOverlay }
    }

    public func dismissOverlay() {
        stopDictation(insert: false)
        withAnimation(Theme.Motion.panel) {
            overlay = .none
            variants = []
            replies = []
            replyContext = nil
            selectedTone = nil
            isWorking = false
            aiError = nil
            aiProvenance = nil
        }
    }

    // MARK: AI

    public func run(_ action: AIAction) {
        // Reply works on an empty field on purpose: answering a message you have
        // not started writing is the whole point of it.
        if action == .reply {
            Feedback.actionPress()
            runReply()
            return
        }

        guard hasTextToWorkWith else { return }
        Feedback.actionPress()
        aiSourceText = aiTargetText

        switch action {
        case .reply:
            break
        case .fix:
            let source = aiSourceText
            beginWork(showing: .aiResult(.fix)) { [engine] in
                try await engine.fix(source)
            } apply: { controller, text in
                controller.aiResultText = text
            }
        case .rewrite:
            selectedTone = nil
            let source = aiSourceText
            beginWork(showing: .aiResult(.variants(nil))) { [engine] in
                try await engine.variants(for: source, tone: nil)
            } apply: { controller, variants in
                controller.variants = variants
            }
        case .tone:
            selectedTone = nil
            variants = []
            withAnimation(Theme.Motion.panel) { overlay = .aiResult(.variants(nil)) }
        }
    }

    /// Reply, against whatever is on screen at the moment of the tap.
    ///
    /// The reading is asked for here rather than read off the state, and the two
    /// are not the same thing: `screenContext` may be showing a reading the
    /// freshness gate has since refused, and `contextForReply()` will raise a new
    /// read and wait rather than answer the wrong message. The wait happens
    /// inside `beginWork`, so the panel shimmers through it exactly as it does
    /// through a model call.
    private func runReply() {
        guard screenContextIsPermitted, screenContext.isLive || screenContext.context != nil else {
            // No session, so say so, rather than showing an empty result the
            // user cannot explain.
            withAnimation(Theme.Motion.panel) { overlay = .aiResult(.needsScreenContext) }
            return
        }

        let session = ScreenContextSession.shared

        // §3.3.1's guard, asked here because this is the only process that can
        // see the focused field and this is the only moment at which the field
        // is the one the user tapped in. It fails closed: a host that does not
        // answer is refused, so a Reply in a password field never becomes a
        // screenshot of a password field, and a host that answers nothing at all
        // disables the feature *visibly* — as a refusal the user reads and a
        // counter the next device run can be checked against.
        //
        // It refuses the whole action rather than only the read, which is a
        // little wider than §3.3.1 asks. Deliberate: the branch it would
        // otherwise leave open is an already-offerable reading, and writing a
        // generated sentence into a password field is not an improvement on
        // photographing one.
        guard session.permitsRead(secure: target?.isSecureTextEntry ?? nil, contentType: fieldContentType)
        else {
            replies = []
            replyContext = nil
            isWorking = false
            aiError = .screenNotRead(
                "Screen context does not read password fields, and this field either is one or would not say."
            )
            withAnimation(Theme.Motion.panel) { overlay = .aiResult(.replies) }
            return
        }

        // A reply replaces nothing; it is inserted where the cursor already is.
        aiSourceText = ""
        replyContext = nil
        beginWork(showing: .aiResult(.replies)) { [engine, weak self] in
            let context = try await session.contextForReply()
            await MainActor.run { self?.replyContext = context }
            return try await engine.replies(to: context)
        } apply: { controller, replies in
            controller.replies = replies
        }
    }

    public func selectTone(_ tone: ToneStyle) {
        Feedback.modifierPress()
        selectedTone = tone
        aiSourceText = aiSourceText.isEmpty ? aiTargetText : aiSourceText
        let source = aiSourceText
        beginWork(showing: .aiResult(.variants(tone))) { [engine] in
            try await engine.variants(for: source, tone: tone)
        } apply: { controller, variants in
            controller.variants = variants
        }
    }

    /// Runs one model call. The latency here is the model's, not a sleep: the
    /// shimmer runs until the answer lands, however long that takes.
    ///
    /// A failure sets `aiError` rather than leaving the panel empty, because
    /// every one of these calls can fail for a reason the user can act on —
    /// Apple Intelligence switched off, a language no engine covers, a guardrail
    /// that fires on a benign Hebrew sign-off.
    private func beginWork<Value: Sendable>(
        showing destination: KeyboardOverlay,
        work: @escaping @Sendable () async throws -> AIOutput<Value>,
        apply: @MainActor @escaping (KeyboardController, Value) -> Void
    ) {
        workingTask?.cancel()
        isWorking = true
        aiError = nil
        aiProvenance = nil
        withAnimation(Theme.Motion.panel) { overlay = destination }

        workingTask = Task { [weak self] in
            guard let self else { return }
            let animation = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.workingPhase += 0.03
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            defer { animation.cancel() }

            do {
                let output = try await work()
                guard !Task.isCancelled else { return }
                apply(self, output.value)
                aiProvenance = output.provenance
            } catch let error as AIEngineError {
                guard !Task.isCancelled else { return }
                aiError = error
            } catch {
                guard !Task.isCancelled else { return }
                aiError = .failed(error.localizedDescription)
            }
            withAnimation(Theme.Motion.content) { self.isWorking = false }
        }
    }

    public func applyResult(_ text: String) {
        Feedback.success()
        replaceTargetText(with: text)
        dismissOverlay()
    }

    private func replaceTargetText(with replacement: String) {
        let original = aiSourceText
        guard !original.isEmpty else {
            target?.insertText(replacement)
            return
        }
        // Walk back over exactly what was sent, including any trailing space the
        // sentence scan trimmed off.
        var toDelete = original.count
        if contextBefore.hasSuffix(" ") { toDelete += 1 }
        for _ in 0..<toDelete { target?.deleteBackward() }
        target?.insertText(replacement)
        refreshSuggestions()
    }

    // MARK: Dictation

    public func startDictation() {
        withAnimation(Theme.Motion.panel) { overlay = .dictation }
        isDictating = true
        dictationTranscript = ""

        let script = MockDictation.script(at: scriptIndex)
        scriptIndex += 1
        dictationIsRightToLeft = script.isRightToLeft

        waveformTask?.cancel()
        waveformTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.waveformPhase += 0.14
                try? await Task.sleep(for: .milliseconds(45))
            }
        }

        dictationTask?.cancel()
        dictationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            for (index, word) in script.words.enumerated() {
                guard !Task.isCancelled, let self else { return }
                withAnimation(.easeOut(duration: 0.14)) {
                    self.dictationTranscript += self.dictationTranscript.isEmpty ? word : " " + word
                }
                try? await Task.sleep(for: MockDictation.delay(forWordAt: index))
            }
        }
    }

    public func stopDictation(insert: Bool) {
        dictationTask?.cancel()
        waveformTask?.cancel()
        dictationTask = nil
        waveformTask = nil

        let transcript = dictationTranscript
        isDictating = false

        if insert, !transcript.isEmpty {
            Feedback.success()
            let needsSpace = !contextBefore.isEmpty && !contextBefore.hasSuffix(" ")
            target?.insertText((needsSpace ? " " : "") + transcript)
            refreshSuggestions()
        }
        dictationTranscript = ""

        if insert {
            withAnimation(Theme.Motion.panel) { overlay = .none }
        }
    }
}
