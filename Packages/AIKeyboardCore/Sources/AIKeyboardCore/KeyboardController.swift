import SwiftUI
import UIKit
import Combine

/// A keyboard interaction that an in-app host can use to guide a demo.
///
/// The keyboard itself never branches on this value. It reports only interactions
/// that cannot be inferred reliably from the document text, such as choosing a
/// suggestion or inserting an emoji.
public struct KeyboardInteraction: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case suggestion
        case emoji
        case dictation
        case languageSwitch
    }

    /// Unique so two consecutive interactions of the same kind still publish a change.
    public let id = UUID()
    public let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }
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
    @Published public private(set) var lastInteraction: KeyboardInteraction?

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

    /// An action the user tapped that refused to start.
    ///
    /// Beside `aiError` because it is the same kind of fact about a different
    /// moment: `aiError` is a call that failed, this is a call that never began.
    /// Both are sentences the banner prints; neither is an overlay any more.
    @Published public var block: BannerState.Block?
    /// Which engine answered, so a best-effort answer can say so.
    @Published public var aiProvenance: AIProvenance?

    /// The last Fix or Rewrite that was written straight into the field, and what
    /// was there before it.
    ///
    /// **Fix and Rewrite no longer offer their answer, they make it**, so the user
    /// reads the corrected sentence in their own message rather than on a strip
    /// above the keys — which is where they were going to read it anyway before
    /// sending. An edit made without being asked has to be undoable, and this is
    /// the whole of that: the text that was replaced, the text that replaced it,
    /// and which action did it. `SuggestionBar` draws a revert control while it is
    /// set, and the next keystroke clears it — see `clearRevertibleEdit`.
    /// `internal(set)` for the reason `emojiQuery` is: it is written from
    /// `KeyboardController+AI`, which is a different file, and closed to the app and
    /// the extension — nothing outside this package may claim an edit is undoable.
    @Published public internal(set) var revertibleEdit: AIEdit?

    /// Whether the field holds anything the text actions could work on.
    ///
    /// **A mirror of `hasTextToWorkWith`, and it exists because that one is a
    /// question about the host's document rather than about this object.** Fix and
    /// Rewrite are drawn disabled on an empty field, so their keys have to redraw
    /// the moment the first character lands — and a `View` body reading
    /// `hasTextToWorkWith` would be re-evaluated only when something else this
    /// controller publishes happened to change. Filled by `refreshSuggestions`,
    /// which the extension already calls from `textDidChange`, so it follows the
    /// document however it moved: a keystroke, a cursor tap, or the host clearing
    /// the field after the message was sent.
    @Published public internal(set) var documentHasText = false

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

    /// Which way the transcript reads.
    ///
    /// **Nothing draws this today, and it is kept on purpose rather than by
    /// oversight.** Its reader was the deleted strip, which laid a transcript out
    /// in its own direction while it sat above the keys; the words go straight into
    /// the field now, and a text field decides its own direction. What stops it
    /// being deleted is the chain underneath: it is the only consumer of
    /// `DictationSession.transcriptLanguages`, which is the only consumer of
    /// `DictationTranscriptRecord.languages` and `DictationPartialRecord.languages`
    /// — real data crossing the App Group that the transcriber went to the trouble
    /// of reporting. `KeyboardController.isRightToLeft(reported:text:)` also holds
    /// a measured trap that would be lost with it, and `DictationKeyboardTests` is
    /// what holds it: the direction has to come from the *reported* languages,
    /// because counting letters lays `בוא נעשה sync על ה-roadmap` out left to right.
    @Published public var dictationIsRightToLeft = false
    /// Why there is no transcript, in a sentence fit to show. Empty otherwise.
    @Published public var dictationFailure = ""

    /// What the keyboard can do about dictation right now.
    ///
    /// **Mirrored rather than read through, and the reason is the strip that is no
    /// longer there.** This was a computed property forwarding to
    /// `DictationSession`, and it worked only because the deleted waveform
    /// republished `waveformPhase` twenty times a second, dragging every other
    /// dictation reading onto the screen with it. With the recording drawn on the
    /// microphone key and the pause control in the suggestion bar, nothing else
    /// publishes: a tap on Pause would change `availability` on another object and
    /// leave both surfaces showing the state before it. Subscribed in `init`, not
    /// in `observeDictation()`, so a controller that has never started a recording
    /// still reports what the session can see.
    @Published public private(set) var dictationAvailability: DictationSession.Availability =
        .noSession(.notEnded)
    /// Seconds before the session closes itself, when it will. The microphone key
    /// counts the last minute of it — see `DictationKeyState`.
    ///
    /// **Mirrored a whole second at a time.** `DictationSession` republishes this
    /// on every one of its ten polls a second; the caption it feeds counts in
    /// seconds, so forwarding each tick would re-render the entire keyboard ten
    /// times a second to redraw the same three characters.
    @Published public private(set) var dictationRemainingSeconds: Double?

    /// The emoji last inserted, most recent first. Seeded from `SharedStore` in
    /// `init` and written back by `insertEmoji`, so the Recent tab survives iOS
    /// tearing the extension down.
    @Published public var recentEmoji: [String] = SharedStore.shippedRecentEmoji

    /// What has been typed into the emoji search box. Empty unless `overlay` is
    /// `.emojiSearch`; `show(_:)` is what clears it.
    /// `internal(set)`, not `private(set)`: `setEmojiQuery` lives in
    /// `KeyboardController+Typing`, which is a different file. Still closed to the
    /// app and the extension, which is the boundary that matters — nothing outside
    /// this package may set a query without the results being rescored with it.
    @Published public internal(set) var emojiQuery = ""

    /// Matches for `emojiQuery`, best first.
    ///
    /// Stored rather than computed, because a `View` body reads it and SwiftUI
    /// evaluates bodies far more often than the query changes — scanning 1,870
    /// emoji on every redraw would be a keyboard that stutters while it is being
    /// typed into.
    @Published public internal(set) var emojiResults: [String] = []

    /// Set by the host controller. False in the app preview, where there is no
    /// keyboard to switch to.
    public var showsGlobeKey = false

    /// Called when the globe key is tapped inside the real extension.
    public var onAdvanceToNextKeyboard: (() -> Void)?

    /// Called when a Hide keyboard key is tapped inside the real extension.
    ///
    /// Nothing in this package can dismiss a keyboard: only
    /// `UIInputViewController.dismissKeyboard()` can, and the package does not
    /// have one. Nil in the app preview, where there is nothing to dismiss.
    public var onDismissKeyboard: (() -> Void)?

    /// Called automatically on the first no-session dictation tap so the host
    /// can attempt to bring the containing app to the foreground.
    ///
    /// Nil in the in-app playground. Wired by `KeyboardViewController` using
    /// `extensionContext?.open(_:)` with a responder-chain fallback. The banner
    /// also shows a `Link` as a secondary user-tapped path; both record a
    /// timestamped handoff request the app consumes on launch.
    public var onOpenContainingApp: ((URL) -> Void)?

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
    var target: TextTarget?
    let store: SharedStore
    let engine: RoutedIntelligence

    /// The keyboard's end of the dictation channel. Injectable for the same
    /// reason `engine` is: `AIKeyboardCoreTests` carries no App Group
    /// entitlement, so a test drives both ends of a real channel rooted in a
    /// temporary directory.
    let dictation: DictationSession

    var workingTask: Task<Void, Never>?
    var languageSwitchTask: Task<Void, Never>?
    /// The user tapped Stop and the words have not arrived yet. Insertion is
    /// deferred because the recording is transcribed in another process.
    ///
    /// **Published, because the microphone key draws this state.** It is what
    /// `dictationKeyState` answers `.finishing` on, and the strip that used to say
    /// "Transcribing" is gone — a plain `var` would leave the key showing Stop over
    /// a recording that had already stopped until some unrelated publish happened
    /// to redraw it.
    @Published var pendingDictationInsert = false

    /// Exactly what the open recording has written into the field, the space in
    /// front of it included, or empty when it has written nothing.
    ///
    /// **It is a record of an edit this keyboard made, held for the same reason
    /// `revertibleEdit` is one**: `UITextDocumentProxy` offers no undo and no way
    /// to address a range, so replacing what was streamed a moment ago means
    /// knowing character for character what it was. See
    /// `KeyboardController.replaceStreamedDictation`.
    var streamedDictation = ""

    /// True once the field has moved out from under what this recording streamed —
    /// the user typed, moved the caret, or the host rewrote it. No more partials
    /// are written after that, because each would land as a fresh copy rather than
    /// replacing the last.
    var dictationStreamAbandoned = false

    var dictationObservers = Set<AnyCancellable>()
    var lastSpaceTapAt: Date?
    var spaceTouch = SpaceSwipe.Touch()
    private var cancellables = Set<AnyCancellable>()

    /// Names and shortcuts from `UILexicon`, read once by `KeyboardViewController`
    /// via `requestSupplementaryLexicon` and handed down. Empty until that
    /// callback returns, and empty for good in the app's playground, which has
    /// no host to ask.
    var supplementaryWords: [String] = []

    /// The async half of the suggestion bar.
    ///
    /// Optional because most callers do not want one: `AIKeyboardCoreTests` and
    /// the app's playground both drive a real controller, and neither should be
    /// making model calls on a typing pause. `nil` means the bar is purely local,
    /// which is a complete, shipping behaviour rather than a degraded one — see
    /// `PredictiveRefiner` for what the second tier is and is not allowed to
    /// change.
    var refiner: PredictiveRefiner?

    /// What this user's typing has taught the keyboard.
    ///
    /// **`.shared` only for the real keyboard, and a throwaway for everybody
    /// else.** The app's onboarding playground and every unit test drive a real
    /// `KeyboardController` and press real space bars, and for a while all of them
    /// wrote into the persisted store: the test suite alone had taught it `Handi`
    /// ten times and `Nitai` nine, which is past `protectThreshold`, so
    /// `PersonalDictionaryTests` stopped being able to show that the personal
    /// dictionary does anything — the words it was checking were being defended by
    /// a store the tests had filled themselves. Scripted demo words are not
    /// somebody's vocabulary either.
    let personal: PersonalLanguageModel

    /// The word being typed on grouped keys, when that feature is on. Empty and
    /// inert otherwise. See `KeyboardController+Grouped.swift`.
    let grouped = GroupedInput()

    public init(
        target: TextTarget?,
        store: SharedStore = .shared,
        language: KeyboardLanguage = .english,
        engine: RoutedIntelligence? = nil,
        dictation: DictationSession = .shared,
        isSystemKeyboard: Bool = false
    ) {
        self.target = target
        self.store = store
        self.language = language
        self.dictation = dictation
        self.personal = isSystemKeyboard ? .shared : PersonalLanguageModel(url: nil)
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

        // Built after `engine`, and out of the same transport, so the keyboard has
        // exactly one opinion about where the cloud is.
        if isSystemKeyboard {
            let cloud = BackendTransport.configured().map { CloudIntelligence(transport: $0) }
            refiner = PredictiveRefiner.standard(cloud: cloud) { [weak self] words, askedAbout in
                self?.applyRefinement(words, for: askedAbout)
            }
        }

        // See `dictationAvailability`. Here rather than in `observeDictation()`
        // because a controller that has never opened an utterance still has to
        // report what the session can see, and because the sink is what makes a
        // pause visible on the two surfaces that draw one.
        dictationAvailability = dictation.availability
        dictation.$availability
            .sink { [weak self] availability in self?.dictationAvailability = availability }
            .store(in: &cancellables)
        dictation.$remainingSeconds
            .sink { [weak self] seconds in
                guard let self else { return }
                let whole = seconds.map { $0.rounded(.down) }
                guard whole != self.dictationRemainingSeconds else { return }
                self.dictationRemainingSeconds = whole
            }
            .store(in: &cancellables)

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

        // Read through the store rather than off its `@Published` copy, for the
        // reason `storedKeyboardLayout` is on the line above: this is a second
        // process, and `load()` filled that copy whenever *this* process launched.
        recentEmoji = store.storedRecentEmoji

        apply(store.storedKeyboardLayout)
        refreshSuggestions()
    }

    // MARK: Layout

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

    public func attach(target: TextTarget) {
        self.target = target
        refreshSuggestions()
    }

    func reportInteraction(_ kind: KeyboardInteraction.Kind) {
        lastInteraction = KeyboardInteraction(kind)
    }
}

// MARK: - Previews

#if DEBUG

extension KeyboardController {

    /// A controller typing into an in-memory document, for `#Preview` only.
    static func preview(
        language: KeyboardLanguage = .english,
        text: String = ""
    ) -> KeyboardController {
        let controller = KeyboardController(
            target: MockTextTarget(text: text),
            language: language
        )
        return controller
    }
}

#endif
