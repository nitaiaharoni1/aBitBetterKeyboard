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

    /// Moves the insertion point, without changing the document.
    ///
    /// Here because there is no forward delete: `UITextDocumentProxy` offers
    /// `deleteBackward()` and nothing else, so replacing a sentence the cursor
    /// sits in the middle of means stepping past its tail first and then deleting
    /// the whole span backwards. `replaceTargetText` is the only caller.
    func adjustTextPosition(byCharacterOffset offset: Int)
}

/// Bridges the system proxy to `TextTarget`. `UITextDocumentProxy` is itself a
/// protocol, so it cannot be given a new conformance in an extension.
///
/// **The proxy is resolved per call, not captured once.** `textDocumentProxy` is
/// a `@dynamic` property on `UIInputViewController` and the object behind it is
/// the *current* input document: it is replaced when the host swaps fields, and a
/// copy taken at `viewDidLoad` addresses whichever field happened to be focused
/// then. Holding the input view controller and asking it every time is the only
/// spelling that stays correct across a field change, and it costs an
/// objc_msgSend per keystroke.
///
/// **The resolver may answer nil, and `weak` is why.** `unowned` would be a trap:
/// `KeyView`'s key-repeat is an unstructured `Task` cancelled only from
/// `DragGesture.onEnded`, so a gesture interrupted by teardown leaves a loop
/// calling back into the controller after the input view controller has gone.
/// Against `unowned` that is a crash; against `weak` it is a document that is not
/// there, which is the truth. Every accessor below therefore answers nil rather
/// than substituting a default: nil `isSecureTextEntry` is what `SecureField`
/// reads as *nobody told us*, which is exactly what a vanished host is. That
/// permits rather than refuses — see `SecureField`, where silence permitting is
/// the measured decision — but it is counted as `refusedSecureUnknown` and never
/// mistaken for a host that positively answered.
@MainActor
public final class ProxyTextTarget: TextTarget {
    private let resolve: () -> UITextDocumentProxy?

    private var proxy: UITextDocumentProxy? { resolve() }

    /// Fixed proxy. For callers that hold one directly and have no controller to
    /// ask, which in practice means tests.
    public init(_ proxy: UITextDocumentProxy) {
        self.resolve = { proxy }
    }

    /// The spelling the keyboard extension uses:
    /// `ProxyTextTarget { [weak self] in self?.textDocumentProxy }`.
    public init(resolving: @escaping () -> UITextDocumentProxy?) {
        self.resolve = resolving
    }

    public var documentContextBeforeInput: String? { proxy?.documentContextBeforeInput }
    public var documentContextAfterInput: String? { proxy?.documentContextAfterInput }
    public var selectedText: String? { proxy?.selectedText }

    /// Forwarded exactly as the SDK declares them, optionals and all. Widening
    /// either of these to a non-optional here would put the "unknown permits"
    /// hole back in a place `SecureField`'s tests cannot see.
    public var isSecureTextEntry: Bool? {
        guard let proxy else { return nil }
        return proxy.isSecureTextEntry
    }
    public var textContentType: UITextContentType?? {
        guard let proxy else { return UITextContentType??.none }
        return proxy.textContentType
    }

    public func insertText(_ text: String) { proxy?.insertText(text) }
    public func deleteBackward() { proxy?.deleteBackward() }
    public func adjustTextPosition(byCharacterOffset offset: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: offset)
    }
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
    /// No-op, and honestly so: this document has no cursor to move, which is why
    /// `documentContextAfterInput` is always empty. There is never a tail to step
    /// over here.
    public func adjustTextPosition(byCharacterOffset offset: Int) {}
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

    /// The language a slide along the space bar is pointing at, or the one the
    /// keyboard has just landed on. Nil the rest of the time, which is when the
    /// space bar says "space". See `LanguageSwitchIndication`.
    @Published public var languageSwitchIndication: LanguageSwitchIndication?

    /// True while a mock AI call is in flight.
    @Published public var isWorking = false
    @Published public var workingPhase: Double = 0

    @Published public var aiSourceText = ""
    @Published public var aiResultText = ""
    @Published public var variants: [RewriteVariant] = []
    @Published public var selectedTone: ToneStyle?
    /// Whether the tone now running is the one the user wrote. Separate from
    /// `selectedTone`, which still names the built-in register the answer is
    /// labelled with and the one an engine falls back to.
    @Published public var selectedToneIsCustom = false
    @Published public var replies: [ReplyOption] = []

    /// The reading the replies on screen were written about. Held separately
    /// from `screenContext` because the screen moves on: by the time three
    /// replies come back, the strip may be showing a different message, and the
    /// panel has to restate the one it answered.
    @Published public var replyContext: ScreenContext?

    /// Which action the banner is currently reporting on, or nil when nothing has
    /// been asked for.
    ///
    /// **The banner is the only surface that has to name the action, and it is the
    /// first one that could not work it out from what it was showing.** A panel
    /// carried its own title because it was pushed by the tap; a strip that is
    /// always on screen is handed three replies with nothing saying whether they
    /// came from Reply or from Rewrite. Set by `beginWork` and cleared by
    /// `clearBanner`, so it cannot outlive the answers it labels.
    @Published public var runningAction: AIAction?

    /// Which of the answers the banner is showing. Always a valid index into
    /// `bannerOptions`, because `BannerState.resolve` clamps it — an action that
    /// returns fewer options than the last one would otherwise page past the end.
    @Published public var bannerIndex = 0

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
    /// Why there is no transcript, in a sentence fit to show. Empty otherwise.
    @Published public var dictationFailure = ""
    @Published public var waveformPhase: Double = 0

    /// What the keyboard can do about dictation right now. The panel reads it
    /// directly; there is nothing to mirror, and mirroring it would be a second
    /// copy of a state that changes ten times a second.
    public var dictationAvailability: DictationSession.Availability { dictation.availability }
    public var dictationLevel: Double { dictation.level }
    public var dictationRemainingSeconds: Double? { dictation.remainingSeconds }

    @Published public var recentEmoji: [String] = ["😂", "🙏", "❤️", "👍", "🔥", "😅"]

    /// Set by the host controller. False in the app preview, where there is no
    /// keyboard to switch to.
    public var showsGlobeKey = true

    /// Called when the globe key is tapped inside the real extension.
    public var onAdvanceToNextKeyboard: (() -> Void)?

    /// Called when a Hide keyboard key is tapped inside the real extension.
    ///
    /// Nothing in this package can dismiss a keyboard: only
    /// `UIInputViewController.dismissKeyboard()` can, and the package does not
    /// have one. Nil in the app preview, where there is nothing to dismiss.
    public var onDismissKeyboard: (() -> Void)?

    /// The shape of the keyboard right now.
    ///
    /// Published so the view redraws when the app changes it, and
    /// `private(set)` so the only way in is `apply(_:)` — which is where the
    /// repair that only this process can make happens.
    @Published public private(set) var customization: KeyboardCustomization = .default

    // MARK: Dependencies

    /// **Strong, and that is the bug fix.** This was `weak`, and the keyboard
    /// extension's only caller built its target inline —
    /// `KeyboardController(target: ProxyTextTarget(textDocumentProxy))` — so
    /// nothing else on the device held it and it was gone before the first
    /// keystroke. Every `target?.insertText` after that was a no-op against nil:
    /// the real keyboard drew, animated, clicked, and typed nothing at all. The
    /// in-app playground was unaffected and hid it for the whole of development,
    /// because `KeyboardPreview` holds its `MockTextTarget` as a `@StateObject`.
    ///
    /// Nothing conforming to `TextTarget` references the controller back, so a
    /// strong reference here closes no cycle. `KeyboardControllerTargetTests`
    /// holds the failing case.
    private var target: TextTarget?
    private let store: SharedStore
    private let engine: RoutedIntelligence

    /// The keyboard's end of the dictation channel. Injectable for the same
    /// reason `engine` is: `AIKeyboardCoreTests` carries no App Group
    /// entitlement, so a test drives both ends of a real channel rooted in a
    /// temporary directory.
    let dictation: DictationSession

    private var waveformTask: Task<Void, Never>?
    private var workingTask: Task<Void, Never>?
    private var languageSwitchTask: Task<Void, Never>?
    /// The user tapped Insert and the words have not arrived yet. Insertion is
    /// deferred because the recording is transcribed in another process.
    private var pendingDictationInsert = false
    private var dictationObservers = Set<AnyCancellable>()
    private var lastSpaceTapAt: Date?
    private var spaceTouch = SpaceSwipe.Touch()
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
        engine: RoutedIntelligence? = nil,
        dictation: DictationSession = .shared
    ) {
        self.target = target
        self.store = store
        self.language = language
        self.dictation = dictation
        // This build ships pointing at a deployed backend
        // (`BackendTransport.bundledDefaultURL`), so the cloud half is normally
        // present and Hebrew has somewhere to run. It was nil for the life of
        // every install before 2026-08-10: the service existed in `Backend/` and
        // had never been deployed, so `configured()` answered nil, Hebrew Fix,
        // Rewrite, Tone and Reply had no engine at all, and the best-effort branch
        // could not save them either — Apple's model rejects a whole session whose
        // *instructions* are Hebrew. That is what "the AI does not work" was.
        //
        // Resolved once, here, at construction. A URL typed into settings while the
        // keyboard is already on screen is not picked up until the extension is
        // rebuilt by iOS, which is the ordinary case anyway — the host app changing
        // a field tears the keyboard down first.
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

        apply(store.storedKeyboardLayout)
        refreshSuggestions()
    }

    // MARK: The layout

    /// Takes a layout, repairing what only this process knows.
    ///
    /// **The globe is put back here and nowhere else.** Whether the key is
    /// required is `needsInputModeSwitchKey`, which is a property of the *device*
    /// and unknown to the store: a layout saved on a phone with one keyboard
    /// installed is missing nothing, and becomes a trap the day a second one is
    /// added. `SharedStore.decodeLayout` therefore validates with
    /// `showsGlobe: false`, and this is where the device's own answer is applied.
    ///
    /// A layout that is still unusable after the repair falls all the way back to
    /// the default, because a keyboard that cannot draw itself is not a state the
    /// user can get out of from inside the keyboard.
    public func apply(_ layout: KeyboardCustomization) {
        var repaired = layout
        let hasGlobe = (repaired.bottomRow + repaired.cursorRow).contains { $0.action == .globe }
        if showsGlobeKey, !hasGlobe {
            // Second from the start, which is where it stands in every preset:
            // beside the plane key and away from the space bar.
            let index = min(1, repaired.bottomRow.count)
            repaired.bottomRow.insert(SlotSpec(action: .globe, width: .units(1.0)), at: index)
        }
        guard LayoutValidator.isUsable(repaired, showsGlobe: showsGlobeKey) else {
            customization = .default
            return
        }
        customization = repaired
    }

    /// Re-reads the layout from the shared store.
    ///
    /// Called when the keyboard comes on screen, because that is the moment after
    /// the app — a different process — may have changed it. See
    /// `SharedStore.storedKeyboardLayout`.
    public func reloadCustomization() {
        apply(store.storedKeyboardLayout)
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

    /// What screen context has to say when it has not read anything, or nil when
    /// it has nothing to say at all.
    ///
    /// **This is what is left of `ScreenContextStrip`, and the strip is gone.** It
    /// was a 30pt row that appeared and disappeared with the session; the banner is
    /// always drawn and already shows the reading itself, so the only part that
    /// needed a home was the five states that are not a reading. The strip's own
    /// restart button is not reproduced: it offered the same `BroadcastPickerButton`
    /// the setup panel holds, and Reply reaches that panel in one tap through the
    /// banner's own Set up button — see `ScreenContextPrompt`, which is the single
    /// place that decides whether starting a broadcast could get anywhere.
    ///
    /// `.off` returns nil rather than a sentence, because a phone that has never
    /// started a broadcast is not in an error state and the banner has an ordinary
    /// hint to show instead.
    public var screenContextHint: String? {
        guard screenContextIsPermitted else { return nil }
        switch screenContext {
        case .off:
            return nil
        case .starting:
            return "Starting screen context…"
        case .watching:
            // The offer, not a claim: nothing has been read, because a read only
            // ever happens in answer to a tap on Reply.
            return screenReadWentUnanswered
                ? "The last screen read didn't work" : "Tap Reply to answer what's on screen"
        case .ready:
            return nil
        case .paused:
            return "Screen context is paused"
        case .ended(let reason):
            return reason.explanation
        }
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

    /// Where one sentence ends and the next begins.
    private static let sentenceTerminators = CharacterSet(charactersIn: ".!?\n")

    /// **The sentence reads through the cursor, not up to it.** It used to stop at
    /// `contextBefore`, so tapping Fix with the caret in the middle of "hey can
    /// you| send me the deck" handed the model "hey can you" and left the rest of
    /// the line hanging off the end of whatever came back. What is in front of the
    /// caret is the same sentence and the user means all of it.
    private var currentSentence: String {
        (headBeforeCursor + tailAfterCursor).trimmingCharacters(in: .whitespaces)
    }

    /// The part of the current sentence behind the cursor, leading whitespace and
    /// all — so the character count is a span in the document rather than a
    /// trimmed string.
    private var headBeforeCursor: String {
        let before = contextBefore
        guard
            let range = before.rangeOfCharacter(from: Self.sentenceTerminators, options: .backwards)
        else { return before }
        return String(before[range.upperBound...])
    }

    /// The part in front of the cursor, up to but not including the terminator
    /// that ends the sentence.
    private var tailAfterCursor: String {
        let after = contextAfter
        guard let range = after.rangeOfCharacter(from: Self.sentenceTerminators) else { return after }
        return String(after[..<range.lowerBound])
    }

    /// How many `deleteBackward()` calls it takes to remove the part of the
    /// sentence behind the cursor.
    ///
    /// Counted from the sentence's first real character, so whatever separated it
    /// from the sentence before is left alone; trailing whitespace is inside the
    /// span, which is what the old `original.count + 1` was reaching for and
    /// getting wrong whenever there was more than one space.
    ///
    /// **UTF-16, because that is the unit the host counts in and Swift's default
    /// unit is not.** `String.count` is grapheme clusters:
    /// `offset(from: beginningOfDocument, to: endOfDocument)` on a real
    /// `UITextView` reports 4 for `a😀b`, 4 for a flag, 5 for a ZWJ sequence, 2
    /// for a decomposed `à` and 3 for `שָׁ`, where Swift counts 3, 1, 1, 1 and 1.
    /// Every number this function feeds — the step over the tail and the budget
    /// the backspace loop spends — is in the host's unit, so there is no
    /// conversion left anywhere to get wrong.
    private var sentenceSpanBeforeCursor: Int {
        let head = headBeforeCursor
        let start = head.firstIndex { !$0.isWhitespace } ?? head.endIndex
        return head[start...].utf16.count
    }

    /// And the part in front of it, in the same unit. This is the *step*, so it
    /// covers the whole tail: the point of it is to reach the end of the sentence.
    private var sentenceSpanAfterCursor: Int { tailAfterCursor.utf16.count }

    /// How much of the tail is sentence rather than the gap in front of it.
    ///
    /// **The counterpart to the leading-whitespace skip in
    /// `sentenceSpanBeforeCursor`, and it was missing.** That one starts the span
    /// at the sentence's first real character so the separator from the sentence
    /// before survives. With the cursor sitting immediately after a full stop the
    /// head is empty, the sentence's first real character is in the *tail*, and
    /// the separator fell inside the delete span while staying outside the string
    /// sent to the model: `Hi.| see you at six` came back `Hi.See you at 6.`, and
    /// `היי.| נדבר בשש` lost its space the same way. Only when the head
    /// contributes nothing — anywhere else the tail's leading space is inside the
    /// sentence and has to go with it.
    private var sentenceDeleteSpanAfterCursor: Int {
        let tail = tailAfterCursor
        guard sentenceSpanBeforeCursor == 0 else { return tail.utf16.count }
        let start = tail.firstIndex { !$0.isWhitespace } ?? tail.endIndex
        return tail[start...].utf16.count
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

    /// **A space bar touch that is still open pays what it owes before this key.**
    /// The space bar commits on lift rather than on finger-down (see
    /// `spaceBarTouch`), and two thumbs overlap constantly on a phone keyboard: a
    /// finger lands on space, the other thumb taps a letter, and only then does the
    /// first lift. Without this line the letter goes in first and the space lands
    /// after it — and worse, `insertSpace` would read `currentWordPrefix` and
    /// `suggestions` *after* that letter had re-scored both, so `sched` + space +
    /// `t` comes back as one word autocorrected from `schedt`. Paying here means
    /// the space is typed in the order the fingers made it and against the
    /// candidate that was on screen when it was pressed.
    public func press(_ cap: KeyCap) {
        if cap != .space, spaceTouch.interrupted() { insertSpace() }

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
        case .emoji:
            Feedback.modifierPress()
            show(overlay == .emoji ? .none : .emoji)
        case .aiMenu:
            Feedback.modifierPress()
            show(overlay == .aiMenu ? .none : .aiMenu)
        case .aiReply:
            // Straight to the action. Reply is deliberately not guarded on
            // `hasTextToWorkWith` — answering a message you have not started
            // writing is the whole point of it — and `run(_:)` already carries
            // that exception, plus the explanation for a tap with no session
            // behind it.
            run(.reply)
        case .aiFix:
            run(.fix)
        case .quickTone:
            Feedback.actionPress()
            // The same three-way answer `SuggestionBar`'s own button gives, asked
            // of the same function, so the key and the button cannot disagree
            // about what a tap does on an empty field. That divergence has already
            // shipped once between the bar and the panel behind it.
            switch SuggestionBar.toneTap(
                hasTextToWorkWith: hasTextToWorkWith, isWorking: isWorking)
            {
            case .rewrite: runDefaultTone()
            case .openMenu: show(.aiMenu)
            case .ignore: break
            }
        case .cursorLeft:
            Feedback.keyPress()
            target?.adjustTextPosition(byCharacterOffset: -1)
            refreshSuggestions()
        case .cursorRight:
            Feedback.keyPress()
            target?.adjustTextPosition(byCharacterOffset: 1)
            refreshSuggestions()
        case .hideKeyboard:
            Feedback.modifierPress()
            onDismissKeyboard?()
        }
    }

    /// Shifted through `KeyboardLanguage.uppercased`, which is the one place that
    /// knows Turkish has two i's — and the one place that holds the language's
    /// `Locale`, so this does not build one per keystroke. The key cap, the
    /// callout and the long-press popup go through the same call, or the key
    /// shows one letter and types another.
    private func insertCharacter(_ value: String) {
        Feedback.keyPress()
        Feedback.keyClick()
        let output = shift.isUppercase ? language.uppercased(value) : value
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
        //
        // Not over a selection: there the space replaces what is selected, the
        // way it does on the system keyboard, and the partial word in front of
        // the selection is not what the user is typing over.
        if store.autocorrect,
            selection == nil,
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

    /// The languages the globe and a slide along the space bar both move through.
    ///
    /// Public because the space bar prints their codes, not just their number: it
    /// says which language is on and which the slide reaches. See
    /// `SpaceSwipe.codeStrip`.
    public var enabledLanguages: [KeyboardLanguage] {
        store.enabledLanguages.isEmpty ? [.english, .hebrew] : store.enabledLanguages
    }

    /// The globe key. Still one step per tap, and still hands the keyboard over to
    /// iOS when the user has only enabled one of ours — the swipe is an addition
    /// to this, not a replacement, because `showsGlobeKey` is
    /// `needsInputModeSwitchKey` and on a phone with no other keyboard installed
    /// there is no globe to tap at all.
    public func advanceLanguage() {
        guard enabledLanguages.count > 1 else {
            onAdvanceToNextKeyboard?()
            return
        }
        stepLanguage(by: 1)
    }

    /// Moves `places` along the enabled languages, wrapping, and names where it
    /// landed on the space bar for a moment afterwards.
    public func stepLanguage(by places: Int) {
        let enabled = enabledLanguages
        guard let destination = SpaceSwipe.language(from: language, in: enabled, places: places)
        else { return }
        withAnimation(Theme.Motion.quick) {
            language = destination
            plane = .letters
        }
        announceLanguage(destination, in: enabled, pending: false)
        refreshSuggestions()
    }

    /// One touch on the space bar, which is the only key whose meaning is not
    /// settled on finger-down.
    ///
    /// **The space is owed from the moment the finger lands and paid by whatever
    /// settles the touch**, which is a lift, another key, or nothing at all. A
    /// touch that turns into a slide types nothing; one that does not calls
    /// `press(.space)` on the way out, which is the ordinary path with the ordinary
    /// double-space rule and the ordinary correction; one interrupted by another
    /// key is paid inside `press`, before that key.
    ///
    /// This makes the controller order-dependent on four phases that a gesture
    /// recogniser is free to deliver in more than one order, so every order it can
    /// produce is pinned in `SpaceBarLanguageSwitchTests`: a key between `began`
    /// and `ended`, a delete between them, a second `began` before the first ends,
    /// an `ended` nobody began, and a `cancelled` on either side of the lift.
    public func spaceBarTouch(_ phase: SpaceTouchPhase) {
        switch phase {
        case .began:
            // Every touch starts from a known state, which is what lets a
            // cancellation clear only what is on screen. See `SpaceTouchPhase`.
            spaceTouch.began()
            clearPendingLanguageSwitch()

        case .moved(let travelled):
            guard spaceTouch.moved(to: travelled) else { return }
            showLanguageCandidate(travelled)

        case .cancelled:
            spaceTouch.cancelled()
            clearPendingLanguageSwitch()

        case .ended(let travelled):
            switch spaceTouch.lifted(after: travelled) {
            case .nothing:
                clearPendingLanguageSwitch()

            case .space:
                press(.space)

            case .slide(let distance):
                let places = SpaceSwipe.places(
                    translation: distance, languageCount: enabledLanguages.count)
                // A slide with nowhere to go — one language enabled, or a finger
                // that wandered out and came back — switches nothing, and still
                // types nothing. A space the user stopped asking for is worse
                // than silence.
                guard places != 0 else {
                    clearPendingLanguageSwitch()
                    return
                }
                stepLanguage(by: places)
            }
        }
    }

    private func showLanguageCandidate(_ travelled: CGFloat) {
        let enabled = enabledLanguages
        guard
            let candidate = SpaceSwipe.destination(
                from: language, in: enabled, translation: travelled)
        else {
            clearPendingLanguageSwitch()
            return
        }
        guard languageSwitchIndication?.language != candidate else { return }
        // One tick per language passed, the way a picker answers a scrolling
        // thumb. The finger is covering the space bar, so this is the half of the
        // indication the user can feel rather than read.
        Feedback.modifierPress()
        announceLanguage(candidate, in: enabled, pending: true)
    }

    private func clearPendingLanguageSwitch() {
        guard languageSwitchIndication?.isPending == true else { return }
        languageSwitchTask?.cancel()
        withAnimation(Theme.Motion.quick) { languageSwitchIndication = nil }
    }

    /// Names a language on the space bar: while a slide is choosing it, and for a
    /// moment after it lands. The second half is the only confirmation a user who
    /// switched by swiping ever gets, and it is what the globe key was missing
    /// too — a layout that changes under the thumb with nothing saying to what.
    private func announceLanguage(
        _ named: KeyboardLanguage, in enabled: [KeyboardLanguage], pending: Bool
    ) {
        languageSwitchTask?.cancel()
        let indication = LanguageSwitchIndication(
            language: named,
            position: enabled.firstIndex(of: named) ?? 0,
            count: enabled.count,
            isPending: pending)
        withAnimation(Theme.Motion.quick) { languageSwitchIndication = indication }

        // A pending name stays until the finger decides. A landed one is a
        // confirmation, and a confirmation that never leaves is a caption.
        guard !pending else { return }
        languageSwitchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.quick) { self?.languageSwitchIndication = nil }
        }
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
            // The layout on screen leads, and the rest of the enabled list
            // follows. Characters name a script, never a language, so eight Latin
            // languages, two Cyrillic and two Arabic-script ones are
            // indistinguishable to the engine and it takes the first candidate
            // written in the script it sees. Passing the stored list alone meant
            // that was whichever language happened to be enabled earliest —
            // English for anyone who left the shipped default on — so a French
            // user on AZERTY was spell-checked against `en_US` and space
            // committed `don't` into `le livre dont je parle`.
            languages: [language] + store.enabledLanguages.filter { $0 != language },
            // **The user's own dictionary leads, and it used to be missing
            // entirely.** `SharedStore.personalDictionary` was written, persisted,
            // reset and displayed with a count in Settings, and read by nothing:
            // the slot it belongs in was already here, filled only by `UILexicon`.
            // So on a stock install the three names the app itself ships in that
            // list were destroyed by its own autocorrect — `Nitai` committed as
            // `Nit` on the space bar — while the screen that holds them said
            // "Names and words we should never correct". Read through the store
            // rather than off the published copy, because Settings is the other
            // process; see `SharedStore.storedPersonalDictionary`.
            supplementary: store.storedPersonalDictionary + supplementaryWords
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

    /// Swaps the partial word behind the cursor for a candidate.
    ///
    /// **The same two rules as `replaceTargetText`, and this is where they were
    /// missed for longer.** `prefix.count` is grapheme clusters and one press is
    /// not one cluster: measured on a real `UITextView`, `שָׁ` takes three presses,
    /// `مُ` two, `مَّ` three and `क्षि` four, so a loop sized in clusters stops
    /// short on every script that combines marks — Hebrew, Arabic, Persian and
    /// Hindi are four of the fourteen this keyboard draws. `hi שָׁלומ` plus the
    /// space bar came out as `hi שָשָׁלום`, and the correction it mangles is
    /// `hebrewFinalFormCorrection`, written for this keyboard's first language.
    /// This is the path that runs on every space and every suggestion tap.
    private func replaceCurrentWord(with replacement: String) {
        // Typing over a selection replaces the selection and nothing else, and a
        // candidate is typing. The partial word in front of a selection is not
        // the word under the cursor — there is no cursor, there is a range — so
        // it is left where it is. The old loop deleted the selection with its
        // first press and then ate real text with the rest.
        if selection != nil {
            target?.deleteBackward()
            target?.insertText(replacement)
            return
        }
        let typed = currentWordPrefix
        deleteBackward(utf16Units: typed.utf16.count)
        target?.insertText(Self.restoringTrailingMarks(of: typed, to: replacement))
    }

    /// A candidate with the punctuation the user typed after the word put back on
    /// the end of it.
    ///
    /// **The word under the cursor includes what ended the sentence, and this
    /// deletes all of it.** `currentWordPrefix` runs back to the last whitespace,
    /// so `Hi recieve,` is one prefix and correcting it wrote `receive` over
    /// `recieve,` — comma and all. Measured with no personal dictionary anywhere
    /// near it: `recieve,` committed as `receive `, `helo,` as `help `, `sched,`
    /// as `she'd `. There is no forward delete on `UITextDocumentProxy`, so the
    /// marks cannot be stepped over; they have to be deleted with the word and
    /// typed again.
    ///
    /// Nothing is appended when the candidate already ends in those marks, which
    /// is every time the user taps the first candidate: that one *is* the literal
    /// keystrokes, punctuation included, and appending would double it. An empty
    /// run makes `hasSuffix("")` true, so the ordinary no-punctuation case falls
    /// out of the same line.
    static func restoringTrailingMarks(of typed: String, to replacement: String) -> String {
        let marks = String(typed.reversed().prefix { $0.isPunctuation }.reversed())
        return replacement.hasSuffix(marks) ? replacement : replacement + marks
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
            clearBannerState()
        }
    }

    /// Everything one action leaves behind, cleared together.
    ///
    /// **Extracted because there are now two ways to finish an action and only one
    /// of them closes a panel.** A result used to live in an overlay, so dismissing
    /// the overlay was the same event as discarding the answer; with results in the
    /// banner, accepting one or dismissing a failure has to clear the same eight
    /// properties without touching `overlay`. Two spellings of this list is how a
    /// stale `variants` array survives into the next action and gets shown under
    /// its name.
    private func clearBannerState() {
        variants = []
        replies = []
        replyContext = nil
        selectedTone = nil
        selectedToneIsCustom = false
        isWorking = false
        aiError = nil
        aiProvenance = nil
        runningAction = nil
        bannerIndex = 0
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
            // **No overlay.** Fix, Rewrite and Reply now report in the banner, so
            // the keys stay visible and usable while the call runs — the user can
            // see the sentence being corrected, which is the one thing the panel
            // that used to cover them hid. `AIResultPanel` survives for the single
            // case that cannot be a strip: the screen-context setup screen, which
            // holds `BroadcastPickerButton`, a real `UIView`.
            beginWork(.fix, showing: .none) { [engine] in
                try await engine.fix(source)
            } apply: { controller, text in
                controller.aiResultText = text
            }
        // **Both of these clear `selectedToneIsCustom`, and forgetting it left the
        // flag lit across a Back.** It is set by `runTone` and only ever cleared by
        // `dismissOverlay`, but the panel's Back button goes to the AI menu without
        // dismissing anything — so running the user's own tone, tapping Back and
        // then Rewrite titled a plain three-decision Rewrite "My tone" and lit the
        // custom chip under it. `selectedTone = nil` alone does not cover it:
        // `AIResultPanel.title` reads the flag first.
        case .rewrite:
            selectedTone = nil
            selectedToneIsCustom = false
            let source = aiSourceText
            beginWork(.rewrite, showing: .none) { [engine] in
                try await engine.variants(for: source, tone: nil)
            } apply: { controller, variants in
                controller.variants = variants
            }
        case .tone:
            selectedTone = nil
            selectedToneIsCustom = false
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
            // Named, so the banner can label the refusal with the action that was
            // refused. Without it `BannerState.resolve` has an error and nothing to
            // attribute it to, and falls back to the idle hint — which would make a
            // refusal look like nothing having happened at all.
            runningAction = .reply
            return
        }

        // A reply replaces nothing; it is inserted where the cursor already is.
        aiSourceText = ""
        replyContext = nil
        beginWork(.reply, showing: .none) { [engine, weak self] in
            let context = try await session.contextForReply()
            await MainActor.run { self?.replyContext = context }
            return try await engine.replies(to: context)
        } apply: { controller, replies in
            controller.replies = replies
        }
    }

    public func selectTone(_ tone: ToneStyle) {
        Feedback.modifierPress()
        aiSourceText = aiSourceText.isEmpty ? aiTargetText : aiSourceText
        runTone(.builtIn(tone))
    }

    /// The registers a long press on the one-tap rewrite key offers, in the order
    /// the popup draws them.
    ///
    /// **The default leads, because index 0 of an alternates popup is the no-op.**
    /// `KeyView` treats lifting on the first item as "the long press changed
    /// nothing", which for a letter means the character it already inserted. The
    /// same rule has to hold here or a user who holds the key, looks, and lifts
    /// without moving gets a register they did not pick — so the first item is
    /// what a plain tap would have run.
    ///
    /// The user's own tone sits second when it is *selected* and is not already the
    /// default. Written but switched off is deliberately absent: `ToneSetting` only
    /// resolves to `.custom` when `prefersCustomTone` is on, so with the switch off
    /// there is no instruction to send and the entry would be a name drawn over the
    /// built-in register standing behind it. `AIResultPanel.toneChips` draws its
    /// custom chip on exactly the same condition, and the two surfaces disagreeing
    /// about which registers exist is drift this repo has shipped once already.
    /// It cannot be a seventh `ToneStyle` either: that enum's raw values are the
    /// persisted setting. See `ToneSetting`.
    ///
    /// Read through the store rather than off a published copy, for the reason
    /// `defaultTone` gives — Settings is a different process.
    public var toneAlternates: [String] {
        let setting = store.toneSetting
        var titles = [setting.title]
        if setting.instruction == nil, customTone != nil { titles.append(ToneSetting.customTitle) }
        titles += ToneStyle.allCases.map(\.title).filter { $0 != setting.title }
        return titles
    }

    /// Runs one of `toneAlternates` by the name the popup drew.
    ///
    /// By title rather than by index, because the popup and the controller would
    /// otherwise have to agree about an ordering that `toneAlternates` builds from
    /// a stored setting — and they would disagree the moment the default tone
    /// changed between the key being drawn and the finger lifting.
    ///
    /// The same two refusals as `runDefaultTone`: nothing to rewrite is a key that
    /// should not have fired, and a call in flight must not be thrown away by a
    /// second one.
    public func selectTone(named title: String) {
        guard hasTextToWorkWith, !isWorking else { return }
        if title == ToneSetting.customTitle, let custom = customTone {
            selectTone(custom)
            return
        }
        guard let tone = ToneStyle.allCases.first(where: { $0.title == title }) else { return }
        selectTone(tone)
    }

    /// The same, for the tone the user wrote. The panel's seventh chip.
    public func selectTone(_ setting: ToneSetting) {
        Feedback.modifierPress()
        aiSourceText = aiSourceText.isEmpty ? aiTargetText : aiSourceText
        runTone(setting)
    }

    /// The user's own tone, or nil when they have not written one. The tone panel
    /// shows a chip for it only when there is one to show.
    public var customTone: ToneSetting? {
        let setting = store.toneSetting
        return setting.instruction == nil ? nil : setting
    }

    /// The tone the one-tap rewrite would run in right now.
    ///
    /// Read out of `UserDefaults` on every call rather than off a cached copy, and
    /// that goes for all three halves of it: Settings lives in the other process,
    /// the App Group is how a change gets here, and `SharedStore.load()` fills the
    /// `@Published` properties once at launch. A keyboard already on screen when
    /// the tone changed would otherwise answer with the one that was stored when
    /// it started. See `SharedStore.storedDefaultTone`.
    public var defaultTone: ToneSetting { store.toneSetting }

    /// Rewrite what the user has typed, in their default tone, straight from the
    /// suggestion bar — no menu, and no register to pick.
    ///
    /// **Rewrite rather than Fix, and the defect's own words decide it.** D6 asks
    /// for a quick action "that is logic is by our default tone", and a tone is
    /// exactly what Fix has none of: `Prompts.fix` rule 5 keeps the writer's
    /// register on purpose, and `EditScope` undoes any change the model cannot name
    /// as a mistake. Pointing a default tone at Fix would leave it with nothing to
    /// do. Rewrite is also the action the extra tap actually costs something on —
    /// Fix opens, runs and shows one answer, while Rewrite makes the user choose a
    /// register first, which is the decision a default is for. This is additionally
    /// the first code in the build that reads `SharedStore.defaultTone` at all; the
    /// setting existed, the app wrote it, and nothing had ever consulted it.
    ///
    /// The two refusals are separate on purpose. Nothing to work with is not an
    /// error, it is a button that should not have fired; a call already in flight
    /// is refused because `beginWork` cancels its predecessor, so a second tap
    /// would silently throw away the answer the first one is waiting for.
    public func runDefaultTone() {
        guard hasTextToWorkWith, !isWorking else { return }
        Feedback.actionPress()
        // The same first move `run(_:)` makes, and it has to be made here too: the
        // bar enters this with no menu in front of it, so nothing has refreshed the
        // sentence being worked on. `selectTone` deliberately keeps whatever is
        // already in `aiSourceText`, which after an earlier action is the
        // *previous* sentence — and `replaceTargetText` then deletes that many
        // characters out of the new one.
        aiSourceText = aiTargetText
        runTone(store.toneSetting)
    }

    /// One tone call, however the tone was chosen.
    ///
    /// `selectedTone` stays a `ToneStyle` because that is what the six chips
    /// compare against and what `RewriteVariant` is tagged with; a custom tone is
    /// reported separately rather than by widening it, so nothing downstream has
    /// to change to keep working.
    private func runTone(_ setting: ToneSetting) {
        let tone = setting.style
        let instruction = setting.instruction
        selectedTone = tone
        selectedToneIsCustom = instruction != nil
        let source = aiSourceText
        // **The one call with two callers and two homes.** From the action row's
        // one-tap key there is no panel and the answer belongs in the banner; from
        // `AIMenuPanel`'s Tone row the user is standing in a panel of tone chips
        // and taking it away under them would be a screen that vanishes when you
        // use it. So the destination is wherever the user already is, with the
        // title re-tagged to the register that is now running.
        let destination: KeyboardOverlay
        if case .aiResult(.variants) = overlay {
            destination = .aiResult(.variants(tone))
        } else {
            destination = overlay
        }
        beginWork(.rewrite, showing: destination) { [engine] in
            try await engine.variants(for: source, tone: tone, instruction: instruction)
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
        _ action: AIAction,
        showing destination: KeyboardOverlay,
        work: @escaping @Sendable () async throws -> AIOutput<Value>,
        apply: @MainActor @escaping (KeyboardController, Value) -> Void
    ) {
        workingTask?.cancel()
        isWorking = true
        aiError = nil
        aiProvenance = nil
        // Named here rather than at the four call sites, so an action that reports
        // in the banner cannot be started without saying which action it is.
        runningAction = action
        // Back to the first answer. Kept from the previous action this would page
        // straight to option 3 of a set that now has one member — clamped rather
        // than crashing, but showing the wrong thing.
        bannerIndex = 0
        // The previous action's answers, gone before this one's arrive. `apply`
        // only ever sets its own kind, so a Rewrite after a Reply would otherwise
        // leave three replies sitting in `replies` for `bannerOptions` to find.
        variants = []
        replies = []
        aiResultText = ""
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

    // MARK: The banner

    /// Whatever the last action produced, flattened into one list the banner can
    /// page through.
    ///
    /// **Three differently-shaped results, one shape here.** Fix answers with a
    /// single corrected sentence, Rewrite with three versions labelled by the
    /// decision each takes, Reply with three answers labelled by intent. The
    /// banner shows one at a time and applies whichever is showing, so it needs
    /// them to be one type; teaching it about `RewriteVariant` and `ReplyOption`
    /// separately would mean three copies of the paging and three of the Use
    /// button.
    ///
    /// **Empty while a result panel is open**, because `AIMenuPanel`'s Tone row
    /// still runs a rewrite into `AIResultPanel` and the answer must not be drawn
    /// twice, once in the panel the user is standing in and once in the strip
    /// above it.
    public var bannerOptions: [BannerOption] {
        if case .aiResult(let kind) = overlay, kind != .needsScreenContext { return [] }

        if !replies.isEmpty {
            // The reading the replies were written about, not whatever the screen
            // has moved on to — same reason `replyContext` is held separately from
            // `screenContext`.
            let language = replyContext?.language ?? screenContext.context?.language ?? .english
            return replies.map {
                BannerOption(id: $0.id, label: $0.intent, text: $0.text, language: language)
            }
        }
        if !variants.isEmpty {
            return variants.map {
                BannerOption(
                    id: $0.id,
                    label: $0.label ?? $0.tone.title,
                    text: $0.text,
                    language: Self.language(of: $0.text, fallback: language))
            }
        }
        guard !aiResultText.isEmpty else { return [] }
        // Fix has one answer and no label: there is nothing to tell it apart from,
        // and "FIXED" over the corrected sentence is a word that earns none of the
        // room it costs on a one-line strip.
        return [
            BannerOption(
                label: "",
                text: aiResultText,
                language: Self.language(of: aiResultText, fallback: language))
        ]
    }

    /// Which language a generated sentence is written in.
    ///
    /// The keyboard's own layout is the fallback and deliberately not the answer:
    /// a rewrite of a Hebrew sentence is Hebrew whichever layout is on screen when
    /// it lands, and a slide along the space bar mid-call would otherwise flip the
    /// alignment of an answer that had already arrived.
    static func language(of text: String, fallback: KeyboardLanguage) -> KeyboardLanguage {
        SuggestionEngine.languages(in: text).first ?? fallback
    }

    /// Accepts the answer the banner is showing.
    public func useBannerOption() {
        let options = bannerOptions
        guard options.indices.contains(bannerIndex) else { return }
        applyResult(options[bannerIndex].text)
    }

    /// Pages to one of the other answers.
    public func showBannerOption(_ index: Int) {
        guard bannerOptions.indices.contains(index), index != bannerIndex else { return }
        Feedback.modifierPress()
        withAnimation(Theme.Motion.content) { bannerIndex = index }
    }

    /// Throws the last action's answer away without accepting it.
    ///
    /// Separate from `dismissOverlay` because there is usually no overlay: this is
    /// what the banner's Dismiss button calls after a failure, and closing a panel
    /// that is not open would take the emoji grid down with it if one happened to
    /// be.
    public func clearBanner() {
        Feedback.modifierPress()
        withAnimation(Theme.Motion.content) { clearBannerState() }
    }

    /// Puts the answer where the text that was sent came from.
    ///
    /// **The span is measured on the document, not counted off the string that was
    /// sent, and three things went wrong when it was.** `aiSourceText` is what
    /// `aiTargetText` trimmed and handed to the model; the document it came out of
    /// is a different length.
    ///
    /// 1. **A selection is one backspace, not `n`.** `deleteBackward()` against a
    ///    live selection removes the whole selection, so counting characters ate
    ///    `original.count - 1` more in front of it.
    /// 2. **Trailing whitespace is not one space.** `currentSentence` drops one
    ///    trailing space and then trims what is left, so two spaces after the
    ///    sentence made `original.count + 1` one short and stranded the sentence's
    ///    first character ahead of the replacement.
    /// 3. **The tail after the cursor is part of the sentence.** With the cursor
    ///    mid-sentence the model was handed the head only, and the tail was left
    ///    hanging off the end of the answer. `aiTargetText` now reads through the
    ///    cursor, and this steps past the tail before deleting so the whole
    ///    sentence goes.
    ///
    /// **Nothing here deletes text it has not confirmed is behind the cursor.**
    /// The step over the tail is a request to the host, and `UITextDocumentProxy`
    /// gives no acknowledgement: if it has not been applied when the backspace
    /// loop runs, a loop sized `head + tail` takes `tail` characters out of
    /// whatever precedes the sentence, and a keyboard extension cannot offer an
    /// undo. There is no way to make that ordering certain with an API of
    /// `insertText`, `deleteBackward` and `adjustTextPosition`, so it is confirmed
    /// by content instead: after the step, the text behind the cursor has to
    /// *end with the tail*, or the loop does not run at all. The three outcomes,
    /// in order of likelihood:
    ///
    /// - Confirmed: the sentence is replaced exactly.
    /// - The step has not landed, or the context has not caught up with it:
    ///   nothing is deleted and the answer is inserted where the cursor is. The
    ///   user sees the sentence twice, which is wrong, obvious and repairable.
    ///   Every character they typed is still there.
    ///
    /// The one input that could defeat the check is a sentence whose head already
    /// ends with the same string as its tail, and the damage there is bounded by
    /// the length of the tail rather than open-ended.
    ///
    /// **`adjustTextPosition` is the one call in this file still asserted by a
    /// double rather than by a host.** That the host counts UTF-16 in it is read
    /// off `UITextView` and `UITextField`, not off a `UITextDocumentProxy`, and it
    /// cannot be read off one here: nothing a user can reach calls it without an
    /// AI answer in hand, and no simulator can produce one — the on-device model
    /// ships no assets there and no backend URL ships at all. The sibling
    /// assumption *is* measured through a real proxy, in
    /// `deleteBackward(utf16Units:)`.
    private func replaceTargetText(with replacement: String) {
        guard !aiSourceText.isEmpty else {
            target?.insertText(replacement)
            return
        }
        // Whatever is selected is what the host replaces, in one step.
        if selection != nil {
            target?.deleteBackward()
            target?.insertText(replacement)
            refreshSuggestions()
            return
        }
        let head = sentenceSpanBeforeCursor
        let tail = sentenceSpanAfterCursor
        guard tail > 0 else {
            deleteBackward(utf16Units: head)
            target?.insertText(replacement)
            refreshSuggestions()
            return
        }
        let tailText = tailAfterCursor
        let tailDeletes = sentenceDeleteSpanAfterCursor
        target?.adjustTextPosition(byCharacterOffset: tail)
        if contextBefore.hasSuffix(tailText) {
            deleteBackward(utf16Units: head + tailDeletes)
        }
        target?.insertText(replacement)
        refreshSuggestions()
    }

    /// Backspaces until `count` UTF-16 units have gone, measuring after each press
    /// rather than assuming what one press removes.
    ///
    /// **One `deleteBackward()` is not one of anything in particular, and this was
    /// measured rather than reasoned.** On a real `UITextView` an emoji, a flag and
    /// a ZWJ sequence each go in a single press — 2, 4 and 5 UTF-16 units — while
    /// Hebrew niqqud goes one combining mark at a time, so `שָׁ` takes three. A
    /// fixed loop of `n` presses therefore removes a different amount depending on
    /// what it lands on: sized in clusters it under-deletes Hebrew, sized in UTF-16
    /// it over-deletes emoji, and over-deleting eats the sentence in front. Asking
    /// the document how much actually went is the only sizing that is right for
    /// both, and it is what caught this.
    ///
    /// It stops rather than pressing on when it cannot tell what one press did.
    /// Over-deleting cannot be undone from a keyboard extension; stopping leaves
    /// the sentence half-removed, which is visible and repairable.
    ///
    /// **Measuring per press needs the context to be fresh per press, and that is
    /// now measured rather than assumed.** `UITextDocumentProxy` documents its
    /// context as a snapshot and acknowledges nothing, so a proxy that lagged one
    /// mutation would make this read zero and give up after a single press.
    /// `KeyboardTypesIntoHostTests.testCommittingACandidateReplacesTheFragmentRatherThanAppendingToIt`
    /// commits a candidate through the real extension over a real `UITextField`
    /// and reads the field back: the fragment is gone, so the proxy's context does
    /// reflect each deletion by the time the next line runs. No double could
    /// answer that — `AIKeyboardCoreTests` drives a `UITextView`, which is
    /// synchronous by construction.
    private func deleteBackward(utf16Units count: Int) {
        var remaining = count
        var presses = 0
        while remaining > 0, presses < count + 8 {
            let before = Array(contextBefore.utf16)
            target?.deleteBackward()
            presses += 1
            let removed = Self.unitsRemoved(from: before, to: Array(contextBefore.utf16))
            guard removed > 0 else { return }
            remaining -= removed
        }
    }

    /// How much one backspace actually removed, read off the shape of the text
    /// rather than off its length.
    ///
    /// **`documentContextBeforeInput` is a window, not the document.** When it is
    /// full it refills from the left as characters leave the right, so after a
    /// real deletion the two lengths come out equal, a length comparison reads
    /// zero, and the loop stops believing nothing happened — having already
    /// destroyed one cluster. `Hi. see you at six tomorrow` against a 20-character
    /// window came back as `Hi. see you at six tomorroR`.
    ///
    /// Whatever the window does, a backspace is a *suffix* truncation: the old
    /// window minus its last k units is still a suffix of the new one. The
    /// smallest k that satisfies that is what went, and it is exact whether the
    /// window refilled, was never full, or is the whole document. `k == 0` means
    /// nothing was removed — or that the context has not caught up — and either
    /// way it is the signal to stop.
    ///
    /// The ceiling is the longest single press this can face: a ZWJ family emoji
    /// is 11 UTF-16 units and goes in one press.
    private static func unitsRemoved(from before: [UInt16], to after: [UInt16]) -> Int {
        for k in 0...16 where before.count >= k {
            let kept = before.prefix(before.count - k)
            if after.count >= kept.count, after.suffix(kept.count).elementsEqual(kept) { return k }
        }
        return 0
    }

    // MARK: Dictation

    /// Opens an utterance in the containing app's session, or explains why it
    /// cannot.
    ///
    /// **Two destinations now, chosen by whether there is anything to record
    /// into.** A live session reports in the banner, so the keys stay under the
    /// user's thumb while they speak and the transcript lands in the field they can
    /// see. Anything else opens the panel, because the useful thing to say then is
    /// three sentences long and names an app, a screen and a button: nothing in an
    /// app extension can start a recording session or launch its own app, so it is
    /// a dead end the user has to be walked out of by hand. `DictationPanel
    /// .explanation` is that text, and a one-line strip cannot hold it.
    ///
    /// Failing silently, or playing something that looks like dictation, is what
    /// both of these replaced.
    public func startDictation() {
        if !dictation.availability.isLive {
            withAnimation(Theme.Motion.panel) { overlay = .dictation }
        }
        dictationTranscript = ""
        dictationFailure = ""
        pendingDictationInsert = false

        dictation.startWatching()
        observeDictation()
        isDictating = dictation.beginUtterance()
        if isDictating { Feedback.modifierPress() }

        waveformTask?.cancel()
        waveformTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Driven by the level the recorder publishes rather than by a
                // constant, so the bars answer the room. They used to advance at
                // a fixed rate whatever was happening, which is the tell that a
                // waveform is a decoration; this one stops moving in silence.
                guard let self else { return }
                self.waveformPhase += 0.05 + self.dictation.level * 0.5
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
    }

    /// `insert: true` finishes the utterance and inserts whatever comes back.
    ///
    /// **The insertion is deferred, because the words do not exist yet.** The
    /// recording is closed here and transcribed in the containing app, so this
    /// arms `pendingDictationInsert` and the transcript is inserted by
    /// `observeDictation` when it lands. Nothing is inserted for a recording that
    /// had no speech in it or that failed — the panel says which, and the user
    /// keeps whatever they had already typed.
    public func stopDictation(insert: Bool) {
        waveformTask?.cancel()
        waveformTask = nil

        if insert, isDictating {
            pendingDictationInsert = true
            isDictating = false
            dictation.stopUtterance()
            return
        }

        // **Nothing to stop, nothing to write.** `dismissOverlay()` calls this on
        // every panel close, including the emoji and AI panels, and an
        // unconditional `cancelUtterance()` would take the channel's write lock
        // and bump a sequence in a shared page every time somebody shut the emoji
        // grid. Worse, it would cancel an utterance that a *different* panel
        // close has nothing to do with.
        guard isDictating || pendingDictationInsert || overlay == .dictation else { return }

        pendingDictationInsert = false
        isDictating = false
        dictation.cancelUtterance()
        dictation.stopWatching()
        dictationTranscript = ""
        dictationFailure = ""
    }

    /// Which way to lay the transcript out.
    ///
    /// **The transcriber's own answer first, a letter count only as a fallback.**
    /// Counting letters gets the sentence this product exists for backwards:
    /// `בוא נעשה sync על ה-roadmap` carries ten Hebrew letters and eleven Latin
    /// ones, so `SuggestionEngine.languages(in:)` — which counts, deliberately,
    /// for the suggestion bar's purposes — calls it English and the panel laid a
    /// Hebrew sentence out left to right. The model reports what it *heard*,
    /// most-spoken first, and speech has no such tie.
    static func isRightToLeft(reported: String, text: String) -> Bool {
        if let tag = reported.split(separator: ",").first,
            let language = KeyboardLanguage(languageTag: String(tag))
        {
            return language.isRightToLeft
        }
        return SuggestionEngine.languages(in: text).first?.isRightToLeft == true
    }

    /// Mirrors the session's published state onto this controller, which is what
    /// the panel is bound to, and performs the deferred insertion.
    private func observeDictation() {
        guard dictationObservers.isEmpty else { return }

        dictation.$transcript
            .sink { [weak self] text in
                guard let self, !text.isEmpty else { return }
                self.dictationTranscript = text
                self.dictationIsRightToLeft = Self.isRightToLeft(
                    reported: self.dictation.transcriptLanguages, text: text)
                guard self.pendingDictationInsert else { return }
                self.pendingDictationInsert = false
                Feedback.success()
                let needsSpace = !self.contextBefore.isEmpty && !self.contextBefore.hasSuffix(" ")
                self.target?.insertText((needsSpace ? " " : "") + text)
                self.refreshSuggestions()
                self.dictation.stopWatching()
                withAnimation(Theme.Motion.panel) { self.overlay = .none }
            }
            .store(in: &dictationObservers)

        dictation.$failure
            .sink { [weak self] detail in
                guard let self, !detail.isEmpty else { return }
                self.pendingDictationInsert = false
                self.isDictating = false
                self.dictationFailure = detail
            }
            .store(in: &dictationObservers)
    }
}
