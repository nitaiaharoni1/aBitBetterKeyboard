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

    /// Mirrored from the capture session so views can observe one object.
    @Published public var screenContext: ScreenContextState = .off

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

    private var dictationTask: Task<Void, Never>?
    private var waveformTask: Task<Void, Never>?
    private var workingTask: Task<Void, Never>?
    private var scriptIndex = 0
    private var lastSpaceTapAt: Date?
    private var cancellables = Set<AnyCancellable>()

    public init(target: TextTarget?, store: SharedStore = .shared, language: KeyboardLanguage = .english) {
        self.target = target
        self.store = store
        self.language = language

        let session = ScreenContextSession.shared
        screenContext = session.state
        session.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                withAnimation(Theme.Motion.panel) { self.screenContext = state }
            }
            .store(in: &cancellables)

        refreshSuggestions()
    }

    /// Reply is only worth offering when a session has actually read something.
    public var canReply: Bool {
        store.screenContextAllowed && screenContext.context != nil
    }

    /// The strip only earns its height once the user has opted in.
    public var showsScreenContextStrip: Bool {
        store.screenContextAllowed && screenContext.isLive
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
           !contextBefore.hasSuffix("  ") {
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
           candidate.text.lowercased() != currentWordPrefix.lowercased() {
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
        suggestions = MockSuggestionEngine.suggestions(
            prefix: prefix,
            context: context,
            languages: store.enabledLanguages
        )
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
            selectedTone = nil
            isWorking = false
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
            beginWork(showing: .aiResult(.fix)) { [weak self] in
                guard let self else { return }
                aiResultText = MockAI.fix(aiSourceText)
            }
        case .rewrite:
            selectedTone = nil
            beginWork(showing: .aiResult(.variants(nil))) { [weak self] in
                guard let self else { return }
                variants = MockAI.variants(for: aiSourceText)
            }
        case .tone:
            selectedTone = nil
            variants = []
            withAnimation(Theme.Motion.panel) { overlay = .aiResult(.variants(nil)) }
        }
    }

    private func runReply() {
        guard let context = screenContext.context, store.screenContextAllowed else {
            // No session, so say so and offer to start one, rather than showing
            // an empty result the user cannot explain.
            withAnimation(Theme.Motion.panel) { overlay = .aiResult(.needsScreenContext) }
            return
        }

        // A reply replaces nothing; it is inserted where the cursor already is.
        aiSourceText = ""
        beginWork(showing: .aiResult(.replies)) { [weak self] in
            self?.replies = MockAI.replies(to: context)
        }
    }

    /// Starts a session from inside the keyboard. The extension cannot open a
    /// capture stream itself, so the real build hands off to the app the same way
    /// dictation does.
    public func requestScreenContext() {
        Feedback.actionPress()
        store.screenContextAllowed = true
        ScreenContextSession.shared.start()
        withAnimation(Theme.Motion.panel) { overlay = .none }
    }

    public func selectTone(_ tone: ToneStyle) {
        Feedback.modifierPress()
        selectedTone = tone
        aiSourceText = aiSourceText.isEmpty ? aiTargetText : aiSourceText
        beginWork(showing: .aiResult(.variants(tone))) { [weak self] in
            guard let self else { return }
            variants = MockAI.variants(for: aiSourceText, tone: tone)
        }
    }

    /// Runs the pretend model call, keeping the loading state on screen long
    /// enough that the real latency will not come as a surprise later.
    private func beginWork(showing destination: KeyboardOverlay, work: @MainActor @escaping () -> Void) {
        workingTask?.cancel()
        isWorking = true
        withAnimation(Theme.Motion.panel) { overlay = destination }

        workingTask = Task { [weak self] in
            guard let self else { return }
            let animation = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.workingPhase += 0.03
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
            try? await Task.sleep(for: MockAI.simulatedLatency)
            animation.cancel()
            guard !Task.isCancelled else { return }
            work()
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
