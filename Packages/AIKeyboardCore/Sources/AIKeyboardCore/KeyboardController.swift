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
        case copyclip
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

    @Published public var language: KeyboardLanguage {
        didSet { hostLanguage = language }
    }
    /// Content direction for the companion app's keyboard previews. Usually the
    /// keys; generated text may temporarily use another language without changing
    /// the runtime input-mode identity published by the real extension.
    @Published public private(set) var hostLanguage: KeyboardLanguage
    @Published public var plane: KeyboardPlane = .letters
    @Published public var shift: ShiftState = .on
    /// **The observer is the fix, and the four writers are the reason.** A search
    /// box has to start with shift off — it is a query, not prose — and it has to
    /// give the document's shift back on the way out, or a sentence start loses
    /// its capital. Doing that at the call sites means catching `show(_:)`,
    /// `dismissOverlay()`, `KeyboardController+AI` and `KeyboardController+Dictation`,
    /// all four of which write this property directly, and missing one leaves
    /// shift stuck off in the core typing path — a real bug traded for a cosmetic
    /// one. A `didSet` cannot be missed by a fifth writer that has not been written
    /// yet. See `adoptSearchShift(from:)`.
    @Published public var overlay: KeyboardOverlay = .none {
        didSet { adoptSearchShift(from: oldValue) }
    }

    /// The document's shift, parked for as long as a search box owns the keys.
    /// Nil whenever no box does.
    ///
    /// It is the document's answer while it is parked, not a frozen copy of one:
    /// `adoptFieldAutocapitalization` writes here rather than to `shift` when a
    /// box is open, so a keyboard that comes back on screen over a still-open box
    /// reads the new field's trait without capitalising the query.
    var shiftBeforeSearch: ShiftState?
    @Published public var suggestions: [Suggestion] = []
    @Published public private(set) var lastInteraction: KeyboardInteraction?

    /// The language a slide along the space bar is pointing at, or the one the
    /// keyboard has just landed on. Nil the rest of the time, which is when the
    /// space bar says "space". See `LanguageSwitchIndication`.
    @Published public var languageSwitchIndication: LanguageSwitchIndication?

    /// Which way the letter keys should slide for the language currently on
    /// screen: `1` incoming from the right, `-1` from the left. Held separately
    /// from `languageSwitchIndication` because the confirmation balloon clears
    /// after 1.4s and the next switch still needs the last step to pick an edge.
    @Published var languageSlideStep = 0

    /// True while a mock AI call is in flight.
    @Published public var isWorking = false
    /// The action whose answer just landed, for the half-second the rim takes
    /// to close (`ControlArrivalRim`). Set by `beginArrival` on success only —
    /// failures never enter it — and read by `activeAIAction`, so the cap
    /// stays lit while the rim fades rather than flashing white on a key that
    /// has already gone pale.
    @Published public var arrivingAction: AIAction?

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

    /// The last thing this keyboard wrote into the field by itself, and what was
    /// there before it.
    ///
    /// **Fix and Rewrite no longer offer their answer, they make it**, so the user
    /// reads the corrected sentence in their own message rather than on a strip
    /// above the keys — which is where they were going to read it anyway before
    /// sending. An edit made without being asked has to be undoable, and this is
    /// the whole of that: the text that was replaced, the text that replaced it,
    /// and which key did it. `SuggestionBar` draws a revert control while it is
    /// set, and `expireRevertibleEditIfUnusable` retires it once what it wrote can
    /// no longer be found where it wrote it — which outlasts ordinary typing, and
    /// used to be the next keystroke (NIT-154).
    ///
    /// **One slot, and CopyClip shares it rather than growing a second.** Tapping
    /// a clip is the same event as a Fix from the field's point of view — text the
    /// user did not type, arriving whole, gone from reach the moment it lands —
    /// and its undo expires the same way. See `RevertibleEdit`.
    ///
    /// `internal(set)` for the reason `emojiQuery` is: it is written from
    /// `KeyboardController+AI`, which is a different file, and closed to the app and
    /// the extension — nothing outside this package may claim an edit is undoable.
    @Published public internal(set) var revertibleEdit: RevertibleEdit?

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
    @Published public var screenContext: ScreenContextState = .off {
        didSet { dropStaleReplyBroadcastRefusal() }
    }

    /// Also mirrored, and separately, because the two move independently: the
    /// scripted sample handing over to a real session changes what the strip may
    /// claim without changing the state it is showing.
    @Published public var screenContextSource: ScreenContextSession.Source = .none

    /// The last Reply tap asked the capture process for a read and got nothing
    /// back. Mirrored so the strip and the AI menu can stop offering a read the
    /// build has just demonstrated it cannot do. See
    /// `ScreenContextSession.lastReadWentUnanswered`.
    @Published public var screenReadWentUnanswered = false

    /// The microphone is open and samples are being kept.
    @Published public var isDictating = false {
        didSet {
            if !isDictating, !dictationLevels.isEmpty {
                dictationLevels = []
            }
        }
    }
    @Published public var dictationTranscript = ""

    /// Which way the transcript reads.
    ///
    /// **Nothing draws this today, and it is kept on purpose rather than by
    /// oversight.** Its reader was the deleted strip, which laid a transcript out
    /// in its own direction while it sat above the keys; the words go straight into
    /// the field now. `hostLanguage` still uses this evidence to lay generated
    /// text out correctly in the companion app's previews. What stops it being
    /// deleted is the chain underneath: it is the only
    /// consumer of
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

    /// The last few loudness readings, oldest first, for the waveform the
    /// microphone key (and its bar copy) draw while somebody is speaking.
    ///
    /// **A history rather than the current level, because one number is not a
    /// wave.** `DictationSession.level` is a single peak per poll; drawing it
    /// alone gives one bar pumping in place, which reads as a progress indicator
    /// rather than as sound. Keeping the last `dictationLevelHistory` of them and
    /// scrolling them leftwards is what makes it look like a voice.
    @Published public private(set) var dictationLevels: [Double] = []

    /// How many readings the sliver keeps. At the session's 10 Hz poll this is
    /// roughly the last three seconds.
    public static let dictationLevelHistory = 30

    /// The emoji last inserted, most recent first. Seeded from `SharedStore` in
    /// `init` and written back by `insertEmoji`, so the Recent tab survives iOS
    /// tearing the extension down.
    ///
    /// **This is the record, not the picture.** Nothing on screen may read it —
    /// the Recent tab and the search strip both draw `visibleRecentEmoji`. See
    /// that property for why the two are separate.
    @Published public var recentEmoji: [String] = SharedStore.shippedRecentEmoji

    /// The Recent order as it is currently drawn, frozen for as long as the emoji
    /// surface stays open.
    ///
    /// **A grid that re-sorts under the finger is the picker losing its place.**
    /// `insertEmoji` moves the emoji it just inserted to the front of
    /// `recentEmoji`, and while that is the right thing to *remember*, doing it
    /// live means every tap in the Recent tab shuffles the keys around the one
    /// that was tapped: the second 😂 of a row of three is somewhere else by the
    /// time the thumb comes back down, and the emoji beside it is a different
    /// emoji. The picker is muscle memory — that is the whole reason a Recent tab
    /// exists — so the order it shows is settled when the surface becomes visible
    /// (`settleRecentEmoji`, which names its two call sites) and left alone until
    /// it becomes visible again. An emoji picked this visit is still recorded and
    /// still persisted; it simply takes its new place the next time the user comes
    /// to look.
    ///
    /// Search is one surface with the grid here: opening the box and coming back
    /// (`.emoji` ⟷ `.emojiSearch`) does not re-settle, or the strip and the grid
    /// would reorder around a backspace.
    ///
    /// It also costs less. `EmojiPanel` rebuilds all 1,870 cells whenever this
    /// changes, and that used to be once per emoji picked.
    ///
    /// `internal(set)` rather than `private(set)` for the reason `emojiQuery` is:
    /// `settleRecentEmoji` lives in `KeyboardController+Typing`. The extension
    /// reaches that method and not this property, which is the boundary that
    /// matters — outside this package the order can be settled, never set, so
    /// there is no way to put an arbitrary list under the finger.
    @Published public internal(set) var visibleRecentEmoji: [String] = SharedStore
        .shippedRecentEmoji

    /// The skin tone every tonable cell in the emoji grid is drawn in, and the
    /// one every emoji picked from it is inserted with.
    ///
    /// **The grid stores nothing toned; this is applied at the last moment.**
    /// `EmojiCatalog.all`, `recentEmoji` and the search index are all untoned
    /// spellings, and `EmojiCatalog.toned(_:_:)` is what puts the modifier on as
    /// a cell is drawn and again as it is inserted. So changing this repaints
    /// 304 cells and rewrites no stored list — and a user who goes back to
    /// plain gets their recents back as they were rather than as five different
    /// spellings of the same wave.
    ///
    /// Seeded from `SharedStore` in `init` and written back by
    /// `setEmojiSkinTone`, because the extension is killed without teardown.
    ///
    /// `internal(set)` rather than `private(set)`, for the reason
    /// `visibleRecentEmoji` is: the setter lives in `KeyboardController+Typing`,
    /// which is a different file. Still closed to the app and the extension,
    /// which is the boundary that matters — outside this package a tone can be
    /// read and never assigned without being written through to the store.
    @Published public internal(set) var emojiSkinTone: EmojiSkinTone = .generic

    /// Copied texts this keyboard has snapshotted, newest first. Seeded from
    /// `SharedStore` in `init` and written back on every mutation: the extension
    /// dies without teardown.
    @Published public var clips: [Clip] = []

    /// Last `UIPasteboard.changeCount` this process reconciled. Seeded from
    /// the store so Clear survives a killed extension.
    @Published public var lastChangeCount = -1

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

    /// What has been typed into the CopyClip search box. Empty unless
    /// `overlay` is `.copyclipSearch`; `show(_:)` is what clears it.
    @Published public internal(set) var copyclipQuery = ""

    /// Clips that match `copyclipQuery`, newest first.
    @Published public internal(set) var copyclipResults: [Clip] = []

    /// Set by the host controller. False in the app preview, where there is no
    /// keyboard to switch to.
    public var showsGlobeKey = false

    /// Called when the globe key is tapped inside the real extension.
    public var onAdvanceToNextKeyboard: (() -> Void)?

    /// Called when a user choice, or a changed field trait, changes the input
    /// mode identity the extension should publish to iOS.
    ///
    /// This is deliberately separate from `hostLanguage`. AI and dictation can
    /// insert text in another language without changing which keyboard the user
    /// selected, and publishing those results as a new input mode can make iOS
    /// replace an already-visible extension.
    public var onInputModeLanguageChange: (() -> Void)?

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
    private let injectedEngine: RoutedIntelligence?
    lazy var engine: RoutedIntelligence =
        injectedEngine
        ?? RoutedIntelligence.standard(
            cloud: BackendTransport.configured().map {
                CloudIntelligence(transport: $0, networkAllowed: { SharedContainer.url != nil })
            }
        )

    /// The keyboard's end of the dictation channel. Injectable for the same
    /// reason `engine` is: `AIKeyboardCoreTests` carries no App Group
    /// entitlement, so a test drives both ends of a real channel rooted in a
    /// temporary directory.
    let dictation: DictationSession

    var workingTask: Task<Void, Never>?
    /// Clears `arrivingAction` when the rim has closed. See `beginArrival`.
    var arrivalTask: Task<Void, Never>?
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

    var isReplacingStreamedDictation = false

    /// True once the field has moved out from under what this recording streamed —
    /// the user typed, moved the caret, or the host rewrote it. No more partials
    /// are written after that, because each would land as a fresh copy rather than
    /// replacing the last.
    var dictationStreamAbandoned = false

    var dictationObservers = Set<AnyCancellable>()
    var lastSpaceTapAt: Date?
    var spaceTouch = SpaceSwipe.Touch()

    /// The character key that is down and has not typed anything yet.
    ///
    /// **One slot, on the controller, because rollover cannot be settled inside a
    /// key.** A character key defers its letter to the lift (NIT-108, see
    /// `KeyView.defersCharacterToLift`), and a fast typist has the next key down
    /// before the last one is up — so the order the letters land in has to be
    /// decided by something both keys can reach, exactly as the space bar's debt
    /// already is one property above. Nothing draws this, so it is not
    /// `@Published`. See `beginCharacterTouch`.
    var pendingCharacter: (cap: KeyCap, unitPoint: CGPoint?)?

    /// A word somebody is deleting from is a word they are correcting on
    /// purpose, and the space bar must not overrule them. See `isCorrectingWordByHand`.
    var deletedWordPrefix: String?

    /// The last space-bar swap, while it can still be taken back. Nil when
    /// space did not replace anything, or once a later word, a caret jump,
    /// Return, a tap, or another space has moved on. Not `revertibleEdit`:
    /// that slot is Fix / Rewrite.
    ///
    /// **`contextAfterSwap` is what the text in front of the swap must read
    /// once it has genuinely landed, not merely `replacement`.** The claim used
    /// to be `contextBefore.hasSuffix(replacement + " ")`, which is blind to
    /// *where* — any earlier, unrelated sentence ending in the same word
    /// satisfies it, and a caret tapped there resurrects `original` in the
    /// wrong place. No keystroke can land between the swap and an undo (every
    /// character key, Return and both cursor keys already clear this pair
    /// outright), so nothing can legitimately have been typed since — an exact
    /// match is therefore the whole claim check, not merely the closest one
    /// that still allows typing on, the way `RevertibleEdit.spanUndo` needs.
    ///
    /// **It is built from the pre-swap `contextBefore` plus the replacement and
    /// a space, never re-asked of the proxy after the swap or the space have
    /// landed.** A build over 2026-08-24's shape did exactly that — read
    /// `contextBefore` once more right after `target?.insertText(" ")` — and
    /// `insertCommittalSpace`'s own doc comment already names the reason that
    /// is unsound: "this keyboard's own delete-then-insert can leave the proxy
    /// reporting stale context for a moment right after a write it just made."
    /// A stale read there costs one skipped hop; a stale read here is worse,
    /// because the wrong string becomes the permanent baseline every later,
    /// honest read is compared against — so on a host whose proxy genuinely
    /// echoes asynchronously, the very first backspace after a swap can find
    /// the pair already unrecoverable, deleting only the space rather than
    /// restoring the typed word. `insertSpace` already holds the fresh,
    /// pre-write `contextBefore` it needs (`contextBeforeSwap`, captured before
    /// `original` is replaced), so the snapshot is arithmetic on a string this
    /// function already has — `contextBeforeSwap` with `original` dropped off
    /// the end, then `replacement + " "` — not a second question to `target`.
    /// Do not "simplify" this back to a post-write read: do the same arithmetic
    /// locally, or reopen the regression `PendingAutocorrectClaimTests
    /// .testTheUndoSnapshotSurvivesAProxyThatEchoesStaleContextRightAfterTheWrite`
    /// exists to close.
    struct LearnedCommit {
        let word: String
        let previous: String?
        let language: KeyboardLanguage
        let permitted: Bool
    }

    struct PendingAutocorrectUndo {
        let original: String
        let replacement: String
        let contextAfterSwap: String
        let documentIdentifier: UUID?
        let learnedCommit: LearnedCommit
        let shouldLearn: Bool
    }

    enum PendingAutocorrectRetirement {
        case acceptLearning
        case discardLearningForUndo
    }

    var pendingAutocorrectUndo: PendingAutocorrectUndo?

    /// Spellings whose automatic swap the user already undid this session.
    /// Space must not put the same correction back. Folded, no timestamps.
    var undoneAutocorrectSpellings: Set<String> = []

    /// The last word written into the learned store, folded. Stops Return,
    /// a full stop, and the keyboard going away from counting the same open
    /// word three times; cleared once a terminator has moved on to the next
    /// word, so a repeated `hello hello` still counts twice.
    var lastLearnedFolded: String?

    /// The word still being typed, updated on every document read. A chat Send
    /// that empties the field never presses space, so `learnWordJustCommitted`
    /// would see nothing; this is what that send still has to count.
    var openWord: String = ""
    /// Whether `openWord` was typed somewhere `SecureField.permitsRead` allowed,
    /// captured the moment it was adopted rather than re-derived when it is
    /// finally committed.
    ///
    /// **The controller outlives the field it is typing into, and `target` moves
    /// on before any commit does.** iOS keeps one extension instance across
    /// fields and across host apps, so a word left open in a credential field —
    /// never finished with a space or a Return before the keyboard came up over
    /// a *different*, permitting field — used to be judged by `target`'s
    /// permission at commit time, which by then was the new field's. Recording
    /// the answer at adoption time, while `target` still is the field the letters
    /// were typed into, is what keeps a word typed under a refusing field from
    /// being learned on the next one's say-so — and, the other way round, what
    /// lets an ordinary word typed under a permitting field still be learned
    /// after the keyboard moves on, which a blanket wipe on every field change
    /// would have cost for no security reason at all.
    var openWordPermitted = true
    private var cancellables = Set<AnyCancellable>()

    /// Names and shortcuts from `UILexicon`, read once by `KeyboardViewController`
    /// via `requestSupplementaryLexicon` and handed down. Empty until that
    /// callback returns, and empty for good in the app's playground, which has
    /// no host to ask.
    var supplementaryWords: [String] = []

    /// The last question `refreshSuggestions` put to `SuggestionEngine`, and the
    /// answer it came back with.
    ///
    /// **One keystroke asks that question two or three times, and nothing in the
    /// engine can tell.** `insertCharacter` refreshes as soon as the text is in
    /// the document, and then the host tells us the same news again through
    /// `textDidChange` and once more through `selectionDidChange`, both of which
    /// `KeyboardViewController` forwards straight back into `refreshSuggestions`.
    /// Each is a full run of the local tier over identical inputs, and each
    /// publishes `suggestions` again, which is a rebuild of every key on the
    /// board. Measured warm on the iOS 26.2 Simulator at `-O`, iPhone 17 Pro:
    /// 0.79 ms a call in English and **7.3 ms in Hebrew**, 6.2 ms of which is
    /// `TypoLexicon.corrections` scanning 30,000 forms. Three of those is 22 ms
    /// against a 16.7 ms frame, which is the "heavy" a Hebrew typist can feel.
    ///
    /// `SuggestionEngine.suggestions` is a pure function of its arguments and the
    /// dictionaries behind them, so a repeated question is the one case where the
    /// previous answer is not merely as good but identical. On the Hebrew path it
    /// is *better*: `.claude/rules/suggestion-bar.md` records `UITextChecker`
    /// answering the same Hebrew prefix differently in two places in one process,
    /// so re-asking is what introduces a flip, not what avoids one.
    ///
    /// `vocabularyVersion` is the one input that is not an argument. `personal`
    /// learns words as they are committed, which is the only thing that can
    /// change an answer without changing the question — the shipped personal
    /// dictionary and `UILexicon` both arrive through `supplementary`, which is
    /// compared. See `SuggestionQuery`.
    var lastSuggestionQuery: SuggestionQuery?
    var lastSuggestionResults: [Suggestion] = []

    /// Bumped whenever `personal` takes a word. See `lastSuggestionQuery`.
    var vocabularyVersion = 0

    /// The async half of the suggestion bar.
    ///
    /// Optional because most callers do not want one: `AIKeyboardCoreTests` and
    /// the app's playground both drive a real controller, and neither should be
    /// making model calls on a typing pause. `nil` means the bar is purely local,
    /// which is a complete, shipping behaviour rather than a degraded one — see
    /// `PredictiveRefiner` for what the second tier is and is not allowed to
    /// change.
    var refiner: PredictiveRefiner?

    /// Completes the bold word and/or inserts a space after a pause. Armed
    /// only from a key the user typed, so a caret tap or the keyboard coming
    /// on screen cannot spend the pause. See `noteTypedInput`.
    /// The pasteboard generation this controller has most recently noticed.
    ///
    /// **It exists to make SwiftUI look again, and nothing reads its value.**
    /// `copyclipCaptureState` is computed and reads `UIPasteboard.changeCount`
    /// live, which is right — but a computed property cannot make a `body`
    /// re-run, and a copy made in the *host app* is another process and
    /// publishes nothing here. So a panel drawn before the copy stayed drawn:
    /// no Paste button, therefore no way to keep the clip, which is
    /// indistinguishable from CopyClip refusing to remember. See
    /// `watchPasteboardWhileCopyClipIsOpen()`.
    @Published var noticedPasteboardGeneration = 0

    /// Polls `changeCount` for as long as the CopyClip panel is on screen. Nil
    /// the rest of the time, which is most of the time.
    var copyclipWatchTask: Task<Void, Never>?

    var idleTypingTask: Task<Void, Never>?
    /// The instant of the last typed character. `nil` until something is keyed
    /// in this field, and cleared when the word is no longer in progress.
    var idleTypedAt: ContinuousClock.Instant?

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
    lazy var personal: PersonalLanguageModel =
        isSystemKeyboard ? .shared : PersonalLanguageModel(url: nil)

    /// The word being typed on grouped keys, when that feature is on. Empty and
    /// inert otherwise. See `KeyboardController+Grouped.swift`.
    let grouped = GroupedInput()

    /// Whether this controller is the keyboard iOS put on screen, rather than the
    /// app's playground, the layout editor's canvas or a test.
    ///
    /// Held as well as read in `init` because two decisions need it after
    /// construction: `stepLanguage` remembers the language the user chose, and a
    /// scripted demo choosing what the real keyboard opens on tomorrow is the
    /// same defect `personal` records above, one setting over.
    let isSystemKeyboard: Bool

    /// The real extension keeps suggestion work suspended until its rebuildable
    /// caches are warm. Cache-warm completion is the sole activation boundary.
    /// App previews and tests keep their existing eager behaviour.
    var suggestionWorkIsActive: Bool

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
        self.hostLanguage = language
        self.dictation = dictation
        self.isSystemKeyboard = isSystemKeyboard
        self.injectedEngine = engine
        self.suggestionWorkIsActive = !isSystemKeyboard
        // This build ships pointing at a deployed backend
        // (`BackendTransport.bundledDefaultURL`), so the cloud half is normally
        // present and Hebrew has somewhere to run. It was nil for the life of
        // every install before 2026-08-10: the service existed in `Backend/` and
        // had never been deployed, so `configured()` answered nil, Hebrew Fix,
        // Rewrite, Tone and Reply had no engine at all, and the best-effort branch
        // could not save them either — Apple's model rejects a whole session whose
        // *instructions* are Hebrew. That is what "the AI does not work" was.
        //
        // Resolved lazily on the first AI action, then held for this controller's
        // lifetime. Construction stays off the launch path for Foundation Models
        // and backend setup; a URL changed before that first action is picked up.
        // `networkAllowed` is what turns a 401 into a sentence the user can act
        // on. **It defaults to `{ true }` and for the whole of this type's life
        // nothing passed it**, so the `needsFullAccess` guard inside
        // `CloudIntelligence` was unreachable in the one process that needs it:
        // a keyboard without Full Access has no networking at all, and instead
        // of saying so it built a request, sent it, and got a 401 back. That is
        // the extension half of the 401s in `NIT-87` — 31 of the 36 that landed
        // after a valid token existed — and the guard was not missing, it was
        // written and tested
        // (`CloudIntelligenceTests.testNoFullAccessIsReportedBeforeAnyRequest`,
        // which asserts nothing is even sent) and simply never armed.
        //
        // **This is the only call site in the project where it bites**, which is
        // why the default went unnoticed: the other two takers of a
        // `networkAllowed` are `CloudScreenReader`, built only in
        // `AIKeyboardBroadcast`, and `CloudDictation`, built only in the
        // containing app. A broadcast extension carries the App Group through
        // its own entitlement and an app always has it, so neither is ever the
        // process the permission is withheld from. The keyboard is.
        //
        // Read at the call rather than captured, because Full Access can be
        // granted while this controller is alive.
        // See `dictationAvailability`. Here rather than in `observeDictation()`
        // because a controller that has never opened an utterance still has to
        // report what the session can see, and because the sink is what makes a
        // pause visible on the two surfaces that draw one.
        dictationAvailability = dictation.availability
        dictation.$availability
            .sink { [weak self] availability in self?.dictationAvailability = availability }
            .store(in: &cancellables)
        // **Every poll, not every change of loudness.** `$level` is Equatable and
        // drops a held note, which left the strip as three bars and a pause —
        // the dashed line that did not move. `levelTick` rises on every poll
        // whether the number changed or not, which is what the waveform is made
        // of. It only ticks while a session is being watched.
        dictation.$levelTick
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.isDictating else { return }
                var levels = self.dictationLevels
                levels.append(self.dictation.level)
                if levels.count > Self.dictationLevelHistory { levels.removeFirst() }
                self.dictationLevels = levels
            }
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
        visibleRecentEmoji = recentEmoji
        emojiSkinTone = store.storedEmojiSkinTone
        let record = store.storedCopyclipRecord
        clips = record.clips
        lastChangeCount = record.lastChangeCount

        // **There is deliberately no `UIPasteboard.changedNotification`
        // subscription here any more.** It used to snapshot the board's
        // *contents*, which since iOS 16 is the call that raises "Allow Paste?",
        // and this keyboard was firing it on a notification nobody had asked
        // for. Under `CopyClipRefresh` the only thing it could still do is a
        // passive refresh, which has no user-visible effect that opening
        // CopyClip does not already do a moment later, so the subscription is
        // gone rather than reduced. See `refreshCopyClip(_:)`.
        apply(store.storedKeyboardLayout)
        // The guard inside `refreshSuggestions` keeps the real extension's
        // construction free of dictionary, model and engine work. In-app hosts
        // and tests remain eager, including their first local suggestion bar.
        refreshSuggestions(schedulingRefinement: false)
    }

    /// Starts suggestion work after the extension is visible and its rebuildable
    /// caches are warm. Cache-warm completion is the extension caller. Safe to
    /// call again.
    @discardableResult
    public func activateSuggestionWorkAfterPresentation() -> Bool {
        guard !suggestionWorkIsActive else { return false }
        retirePendingAutocorrectUndo(.acceptLearning)
        suggestionWorkIsActive = true
        if refiner == nil {
            refiner = PredictiveRefiner.standard { [weak self] words, askedAbout in
                self?.applyRefinement(words, for: askedAbout)
            }
        }
        refreshSuggestions(schedulingRefinement: false)
        return true
    }

    /// Prevents callbacks from a disappearing field from rebuilding predictions
    /// for a document the next appearance may no longer own.
    public func suspendSuggestionWork() {
        guard isSystemKeyboard else { return }
        suggestionWorkIsActive = false
        cancelRefinement()
        lastSuggestionQuery = nil
        lastSuggestionResults = []
        if !suggestions.isEmpty { suggestions = [] }
    }

    // MARK: Layout

    /// Takes a layout, repairing what only this process knows.
    ///
    /// **The globe is put back here and nowhere else, and "nowhere else" now
    /// includes the validator.** Whether the key is required is
    /// `needsInputModeSwitchKey`, a property of the *device* and unknown to the
    /// store: a layout saved on a phone with one keyboard installed is missing
    /// nothing, and becomes a trap the day a second one is added. No preset places
    /// the key, so this repair is the ordinary path rather than a rescue, and it
    /// runs *before* the check below, which is why `LayoutValidator` was never
    /// the thing standing between a user
    /// and a keyboard they could not switch away from. It carried a `missingGlobe`
    /// error anyway, and the only surface that ever saw it was the layout editor,
    /// where it blocked Done on the shipped default for anybody with two keyboards
    /// installed. That rule is deleted; this is the whole mechanism.
    ///
    /// A layout that is still unusable after the repair falls all the way back to
    /// the default, because a keyboard that cannot draw itself is not a state the
    /// user can get out of from inside the keyboard. A preview
    /// (`allowingIncomplete`) skips the globe repair so the editor canvas matches
    /// the model. The real keyboard still inserts it.
    ///
    /// **A layout that did not move is not republished, and on this property
    /// that is worth more than the comparison costs.** `customization` is
    /// `@Published`, and this is called twice on a cold launch — once from
    /// `init` and once from `reloadCustomization()` in `viewWillAppear`, both
    /// before the first frame — with the same stored bytes each time. Each
    /// assignment fires `KeyboardView`'s observation and the extension's
    /// `$customization` sink, which is `.receive(on: RunLoop.main)` and so buys
    /// a runloop hop and a second `updateKeyboardHeight()` on top. The same
    /// guard `updateKeyboardHeight()` and `applyBrandPalette()` already keep.
    ///
    /// Comparing is meaningful only because **every** id on the path is stable,
    /// and there are three of them rather than the two an earlier version of this
    /// comment audited. `SlotSpec.id` is a `Codable` `UUID`, so two decodes of one
    /// blob carry the same ids; `LayoutPreset.all` and
    /// `KeyboardCustomization.default` are both `static let`; **and the globe key
    /// this function repairs in is given `repairedGlobeID` rather than a fresh
    /// one.** The first version of this guard checked the first two and shipped
    /// with the third minting a new `UUID()` on every call, which cancelled the
    /// guard on every phone with a second keyboard installed — that is, on every
    /// real install. If any of the three becomes a computed `var`, every read
    /// mints fresh ids, this guard silently stops firing, and every appearance
    /// re-keys every `ForEach` in the keyboard.
    /// The identity the repaired globe key is given, **fixed rather than fresh,
    /// and the guard below is why.**
    ///
    /// `SlotSpec.init` defaults to `id: UUID()` and `SlotSpec`'s `Equatable` is
    /// synthesised, so `id` is part of it. Minting one here made every repaired
    /// layout unequal to every other repaired layout built from the identical
    /// stored bytes — which cancelled the guard below outright on any phone with
    /// a second keyboard installed, meaning **every real install**, since this
    /// product only exists alongside a system keyboard. It is the exact failure
    /// that guard's own doc comment warns about, arriving from two lines above it
    /// rather than from the presets it audited. Caught in review; the first
    /// version of the guard shipped without it.
    ///
    /// A fixed id is safe here where it would not be in general: the insert is
    /// guarded on `!hasGlobe`, so there is never a second globe key in the layout
    /// for this to collide with, which is the duplicate-identity hazard
    /// `SlotSpec.init` documents.
    static let repairedGlobeID = UUID(uuidString: "9E0B1E4C-3F8A-4C21-9E0D-6B5A1F2C7D34")!

    public func apply(_ layout: KeyboardCustomization, allowingIncomplete: Bool = false) {
        var repaired = layout
        let hasGlobe = (repaired.bottomRow + repaired.cursorRow).contains { $0.action == .globe }
        if showsGlobeKey, !hasGlobe, !allowingIncomplete {
            // Second from the start: beside the plane key and away from the space
            // bar.
            let index = min(1, repaired.bottomRow.count)
            repaired.bottomRow.insert(
                SlotSpec(id: Self.repairedGlobeID, action: .globe, width: .units(1.0)), at: index)
        }
        guard allowingIncomplete || LayoutValidator.isUsable(repaired) else {
            guard customization != .default else { return }
            customization = .default
            return
        }
        guard customization != repaired else { return }
        customization = repaired
    }

    /// The `keyboardType` the keys were last shaped for.
    ///
    /// Nil until a field answers. It exists so the decision below can be taken
    /// **once per field**: `refreshSuggestions` runs on every keystroke and every
    /// caret move, and re-deciding there would mean an OTP box the user had
    /// deliberately switched to letters snapping back to the digits on the next
    /// key. Comparing the reported value is also the only thing that tells a field
    /// *swap* — the host moved focus and the keyboard never went away, so
    /// `viewWillAppear` did not fire — from the same field being typed into.
    var adoptedKeyboardType: UIKeyboardType?

    /// The `autocapitalizationType` the keys were last shaped for.
    ///
    /// Same shape and same reason as `adoptedKeyboardType`: nil until a field
    /// answers, and read once per field so a keystroke cannot re-decide it.
    var adoptedAutocapitalizationType: UITextAutocapitalizationType?

    /// What this field's own trait says about capitalising what is typed into
    /// it, decided once at focus by `adoptFieldAutocapitalization` and read
    /// from every boundary event afterwards — see `armShiftAtBoundary` in
    /// `KeyboardController+Typing`. Starts at `.sentences`, which is what a
    /// controller that has never adopted a field's trait already behaves like:
    /// the same value the nil fallback resolves to.
    var autocapitalizationMode: UITextAutocapitalizationType = .sentences

    /// The language this keyboard moved to on its own, and the one it moved away
    /// from.
    ///
    /// **Reshaping a keyboard for a field is only half a decision; the other half
    /// is putting it back, and the first version of this did not have one.** A
    /// Hebrew user who touched one email box kept an English keyboard afterwards,
    /// in the chat they went back to and in every app after that, because one
    /// extension instance is reused across fields *and* across host apps (see
    /// `.claude/rules/keyboard-wiring.md`). They had to slide the space bar back
    /// by hand every time, which is worse than the Hebrew-in-an-email-field
    /// problem the switch was written to solve.
    ///
    /// Restored **only while the keyboard is still standing on the language it
    /// imposed**. A user who slid to something else inside that field has made a
    /// decision of their own and putting it back would be the keyboard arguing
    /// with them, which is the same claim-checked-rather-than-trusted shape
    /// `pendingAutocorrectUndo` and `GroupedInput.lastWritten` already use.
    private var imposedLatin: (was: KeyboardLanguage, became: KeyboardLanguage)?

    /// Field types whose answer is digits.
    ///
    /// `.numbersAndPunctuation` is here with the three genuinely numeric pads
    /// because the digits are what it is asking for; the marks it also wants are
    /// on the same plane's third and fourth rows. `.phonePad` and `.namePhonePad`
    /// are absent because iOS draws those itself and they never reach us.
    static let digitFieldTypes: Set<UIKeyboardType> = [
        .numberPad, .decimalPad, .asciiCapableNumberPad, .numbersAndPunctuation
    ]

    /// Field types that cannot hold a non-Latin script.
    ///
    /// **`.webSearch` is deliberately not here.** Apple documents it as optimised
    /// for search terms and URL entry, it accepts any script, and Apple's own
    /// Hebrew keyboard stays Hebrew on one — searching in Hebrew is an ordinary
    /// thing to do, so treating a search box as ASCII would take the keyboard
    /// away from the user for no reason. `.twitter` is absent for the same
    /// reason: a tweet can be Hebrew. An address and a URL genuinely cannot.
    static let latinFieldTypes: Set<UIKeyboardType> = [.asciiCapable, .emailAddress, .URL]

    /// Shapes the keyboard for the field it is standing over.
    ///
    /// **Nothing in this project read `keyboardType` at all**, and iOS substitutes
    /// its own keyboard only for `.phonePad` and `.namePhonePad` — so every OTP
    /// box, quantity field, price field and PIN input asking for `.numberPad`,
    /// `.decimalPad` or `.asciiCapableNumberPad` got the full letter QWERTY, which
    /// reads as a keyboard that is broken rather than one that is missing a
    /// feature. The Latin-wanting types are the other half of the same gap, and
    /// they became a defect the day `IsASCIICapable` was set to `true`: iOS now
    /// hands us the ASCII-capable, email and URL fields it used to withhold, so a
    /// user whose last keystroke was Hebrew met Hebrew letters in a field that
    /// cannot hold them, where before the flip they got Apple's ASCII keyboard.
    /// See `.claude/rules/keyboard-wiring.md`.
    ///
    /// **Decided at focus and never again for that field, in both halves.** The
    /// plane key and the space-bar slide still do exactly what they always did the
    /// moment the user reaches for them, and nothing here puts them back — a
    /// keyboard that re-imposes its guess on the next keystroke is a keyboard the
    /// user cannot argue with, and a numeric plane is one a user with a custom
    /// layout could be stranded on if they could not leave it. That escape is not
    /// an assumption: `LayoutValidator.missingPlaneSwitch` makes a layout with no
    /// `123` key an *error*, `apply(_:)` drops an unusable layout back to the
    /// default, and `CustomLayoutCompiler.resolvedCap` points that key at
    /// `.letters` from every plane that is not `.letters`. So every keyboard that
    /// reaches a user has a way back.
    ///
    /// `force` is the appearance: a fresh focus re-decides even when the trait has
    /// not moved, because the user's manual switch belonged to the session that
    /// just ended and an OTP field has to come back up on digits. Everywhere else
    /// only a *changed* trait re-decides, which cannot fire while one field is
    /// being typed into.
    ///
    /// Returns whether the language moved, so the caller can rescore the bar.
    @discardableResult
    func adoptFieldKeyboardType(force: Bool) -> Bool {
        guard let reported = target?.keyboardType ?? nil else {
            // Two different silences, and only one of them is news. On appear a
            // nil is a host that does not implement the trait, so forgetting what
            // the last field asked for is right. Mid-session it is a
            // `ProxyTextTarget` whose input view controller has gone — see
            // `TextTarget` — and treating that as a field change would re-adopt
            // the *same* type on the next callback, which is the user pressing ABC
            // and being put back on the digits a keystroke later.
            if force { adoptedKeyboardType = nil }
            return false
        }
        guard force || reported != adoptedKeyboardType else { return false }
        // Both read before the write, because every branch below is about the
        // difference between the field being left and the field being entered.
        let previous = adoptedKeyboardType
        // Before the branches, so a re-entrant refresh below sees the decision as
        // already taken.
        adoptedKeyboardType = reported

        if Self.digitFieldTypes.contains(reported) {
            plane = .numbers
            return false
        }

        // **Undo the last field's shape before imposing this one's, because a
        // keyboard that only ever reshapes accumulates.** The digits are the
        // sharp case: nothing else in this class puts the plane back except the
        // `123` key, so before this line a six-digit code box followed by a chat
        // box gave the chat box a numeric keyboard, in a different app, with no
        // key pressed in between.
        if let previous, Self.digitFieldTypes.contains(previous) { plane = .letters }

        let wantsLatin = Self.latinFieldTypes.contains(reported)
        var restored = false
        if !wantsLatin, let imposed = imposedLatin {
            // Only while the keyboard is still standing where this code put it.
            if language == imposed.became {
                language = imposed.was
                restored = true
            }
            imposedLatin = nil
        }

        // `.default` and nil keep today's behaviour exactly, and so now does
        // `.webSearch`. `.phonePad` and `.namePhonePad` never reach us: iOS draws
        // those itself.
        guard wantsLatin else { return restored }

        // The plane as well as the language: a form whose previous field was a
        // quantity box left the keyboard on the digits, and this is the one
        // moment that knows the next field wants letters.
        plane = .letters

        guard language.script != .latin,
            let latin = enabledLanguages.first(where: { $0.script == .latin })
        else { return restored }
        // Latin to Latin keeps the *original* language, so a form of five ASCII
        // fields restores what the user had when they reached the first one
        // rather than what the fourth one left behind.
        if imposedLatin == nil { imposedLatin = (was: language, became: latin) }
        language = latin
        return true
    }

    /// Reads `autocapitalizationType` the way `adoptFieldKeyboardType` reads
    /// `keyboardType`, and decides how `shift` starts and re-arms in this field.
    ///
    /// **`.none` never arms shift, `.allCharacters` locks it, and `.words` /
    /// `.sentences` arm it exactly where Return and the double-space full stop
    /// already did** — see `armShiftAtBoundary` in `KeyboardController+Typing`.
    /// This function only decides the mode a boundary event goes on to consult;
    /// it does not touch shift on an ordinary keystroke, which is what stops
    /// typing itself from fighting a shift the user just set by hand.
    ///
    /// **A host that answers nil reads as `.sentences`**, which is what this
    /// keyboard already did before it read the trait at all, so a host that
    /// never implemented `autocapitalizationType` sees no change — the same
    /// fallback `adoptFieldKeyboardType` gives `.default` and nil.
    ///
    /// **Never touches a `.locked` shift.** Caps lock only ever comes from the
    /// user's own `toggleShift()`; nothing here may cancel it, even walking
    /// into a field this decides fresh for — the concrete case is a
    /// `.sentences` field the user has locked caps in, then a boundary or a
    /// silent field swap that would otherwise re-arm `.on` over it.
    ///
    /// **Called from `prepareForNewDocument()` only, always at `force: true`.**
    /// `adoptFieldKeyboardType` also re-decides from `refreshSuggestions()` on
    /// every keystroke, which is what catches a field swapped without the
    /// keyboard being dismissed — see `.claude/rules/keyboard-wiring.md`. Doing
    /// the same here would mean every keystroke re-reading whichever value the
    /// mock or the real proxy has landed on, which is far more exposed than a
    /// rarely-changing `keyboardType`: several `TextTarget` conformers in
    /// `AIKeyboardCoreTests` answer a fixed, non-nil `autocapitalizationType`
    /// from the moment they are built rather than only after a field genuinely
    /// changes, so a per-keystroke recheck would treat their very first
    /// keystroke as a field swap and re-arm shift out from under whatever a
    /// test — or a real caller — had just set it to by hand. Catching a silent
    /// mid-session swap of this trait as well is real future work, and it
    /// needs a call from `KeyboardController+Suggestions.swift`.
    @discardableResult
    func adoptFieldAutocapitalization(force: Bool) -> Bool {
        let reported = target?.autocapitalizationType ?? nil
        guard force || reported != adoptedAutocapitalizationType else { return false }
        adoptedAutocapitalizationType = reported
        autocapitalizationMode = reported ?? .sentences
        // **While a search box owns the keys, `shift` is the query's and the
        // document's is parked, so this decision belongs to the parked value.**
        // The box is reachable from here because nothing resets `overlay` when
        // the keyboard goes away: an extension instance iOS keeps alive comes
        // back through `viewWillAppear` with the box still open, and that path
        // calls this. Writing `shift` there would put the capital straight back
        // into a query that exists precisely so prose rules do not reach it, and
        // then hand the *previous* field's shift to the field this call just
        // read. The caps-lock guard moves with it for the same reason: a lock the
        // user set inside the query is not the document saying so. See
        // `adoptSearchShift(from:)`.
        let ownedBySearch = overlay.isSearch
        let current = ownedBySearch ? (shiftBeforeSearch ?? shift) : shift
        guard current != .locked else { return true }
        let decided: ShiftState
        switch autocapitalizationMode {
        case .none: decided = .off
        case .allCharacters: decided = .locked
        case .words, .sentences: decided = store.storedAutocapitalise ? .on : .off
        @unknown default: decided = store.storedAutocapitalise ? .on : .off
        }
        if ownedBySearch {
            shiftBeforeSearch = decided
        } else {
            shift = decided
        }
        return true
    }

    /// Called when the keyboard comes up over a field.
    ///
    /// An empty companion-app preview follows the keys. A preview that already
    /// contains right-to-left text keeps that content direction even when the keys
    /// are English. The real extension's UIKit identity is separate.
    public func prepareForNewDocument() {
        // **Before anything reads the field.** A character key parks its letter
        // until the finger lifts, and a keyboard torn down mid-press gets no
        // reliable disappear callback — so a letter can survive on an instance
        // iOS reuses across fields and across host apps. Typing it here would put
        // a character from the last app into this one. See
        // `discardPendingCharacter`.
        discardPendingCharacter()
        // The undo belongs to the old field, but its captured learning does not.
        // Retire the undo before reading the new document and accept the complete
        // observation captured when the replacement landed.
        if suggestionWorkIsActive { retirePendingAutocorrectUndo(.acceptLearning) }
        // **The memo's other invalidator, and it is not the field.**
        // `KeyboardViewController.viewDidAppear` reloads the personal model before
        // suggestion work is activated. Forget lives in the app, this process
        // stays alive, and the words behind an answer can therefore be wiped
        // between two identical questions. See `lastSuggestionQuery`.
        lastSuggestionQuery = nil
        lastSuggestionResults = []
        // First, because the two answers are independent: the field trait decides
        // which keys are drawn and which UIKit input identity the extension may
        // publish. `hostLanguage` separately preserves the existing content
        // direction for companion-app previews.
        //
        // The rescore is not free — `refreshSuggestions` starts
        // `PredictiveRefiner`'s clock, which is exactly what
        // `KeyboardViewController.viewWillAppear` calls `refreshDocumentState`
        // rather than this to avoid — so it is spent only when the keys have
        // actually changed script. Leaving it out is a bar offering Hebrew
        // candidates over an English keyboard, which is the two-surfaces-disagree
        // defect this codebase keeps finding.
        if adoptFieldKeyboardType(force: true) { refreshSuggestions() }
        adoptFieldAutocapitalization(force: true)
        if documentHasText,
            let rtl = SuggestionEngine.languages(in: contextBefore + contextAfter)
                .first(where: { $0.isRightToLeft })
        {
            hostLanguage = rtl
            return
        }
        hostLanguage = language
    }

    func announceHostLanguage(_ language: KeyboardLanguage) {
        hostLanguage = language
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

    /// Everything this process is holding that it can read out of its own bundle
    /// again, given back to the system.
    ///
    /// **The word lists are the largest thing a keyboard extension here holds and
    /// they are held for the life of the process.** Three caches, all of them
    /// per-language, all of them filled the first time somebody types or presses
    /// Fix in a language and never emptied, so a bilingual session pays for each
    /// of them twice. That is the right trade while there is room, because
    /// rebuilding the typo block cost a measured 161 ms on the first English
    /// keystroke of a session, and the wrong one the moment iOS says it is
    /// short — a keyboard killed for memory is replaced by the stock
    /// one with no crash log, no signal and no callback, and the user is left
    /// holding a keyboard they did not choose. See `KeyboardMemoryPeak` and
    /// `.claude/rules/keyboard-wiring.md`.
    ///
    /// Static rather than an instance method because the caches are static: the
    /// process holds them, not this controller, and a keyboard that has been torn
    /// down and rebuilt is standing on the same ones.
    ///
    /// Safe at any moment. Every one of these is a pure function of a bundled
    /// file, so the worst a purge can do is make the next lookup slow.
    /// `EmojiCatalog` is deliberately absent: it is a `static let`, so there is
    /// nothing to release, and it is a fraction of the size of one word list.
    public static func dropRebuildableCaches() {
        GroupedLexiconResource.purge()
        TypoLexicon.purge()
        MissingSpaces.purge()
        ConversationalHebrewModel.purge()
    }

    /// Builds the same caches ahead of the first keystroke, off the main thread.
    ///
    /// **The first letter of a session used to block the main thread for a
    /// measured 230 ms in English and another 190 ms the first time the other
    /// language was typed**, and both halves of that were already written down
    /// separately — `dropRebuildableCaches()` above records 161 ms to rebuild the
    /// typo block, and `.claude/rules/suggestion-bar.md` records ~70-280 ms for
    /// Apple building a language's lexicon on the first `UITextChecker` call. What
    /// nobody had asked is whether either has to be paid *at the keystroke*.
    /// Neither does. Measured on the iOS 26.2 Simulator at `-O`, iPhone 17 Pro:
    /// `TypoLexicon` 65 ms English / 124 ms Hebrew, `UITextChecker` 162 ms English
    /// / 68 ms Hebrew, all on a background thread, after which the first
    /// main-thread `TypoLexicon` lookup measures 0.01 ms and the first
    /// `SuggestionEngine.sharedChecker` call 1.0 ms. iOS rebuilds this extension
    /// whenever it feels like it, so that stall is one a user meets several times
    /// a day rather than once.
    ///
    /// **A throwaway `UITextChecker`, deliberately not `sharedChecker`.** Apple
    /// documents no thread safety for that class and the shared one is touched
    /// from the main actor on every keystroke, so warming it directly would be a
    /// data race. The cost being paid is the *process* loading the language's
    /// dictionary, which a second instance shares — that is what the 1.0 ms
    /// figure above measures, and it is the whole reason this works.
    ///
    /// The caller passes every language the user has enabled and puts the one on
    /// screen first, because the pair this product exists for is typed within
    /// seconds of each other and the second language's stall is otherwise paid on
    /// the first space-bar slide. The memory that costs is exactly the memory a
    /// session was going to hold anyway, and `didReceiveMemoryWarning` still hands
    /// all of it back.
    @discardableResult
    public static func warmRebuildableCaches(
        for languages: [KeyboardLanguage],
        completion: @escaping @MainActor @Sendable () -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { return }
            if languages.contains(where: { $0.script == .hebrew }) {
                guard !Task.isCancelled else { return }
                ConversationalHebrewModel.warm()
            }
            for language in languages {
                guard !Task.isCancelled else { return }
                // Any lookup builds the block; the word itself is never read.
                guard !Task.isCancelled else { return }
                _ = TypoLexicon.isWord("a", in: language)
                guard !Task.isCancelled else { return }
                _ = SeedLanguageModel.knows("a", in: language)
                guard let locale = language.spellCheckerLocale else { continue }
                guard !Task.isCancelled else { return }
                // `nativeName` only has to be letters in this language's own
                // script — the answer is thrown away, and asking the question is
                // the whole of the work.
                let probe = language.nativeName
                _ = UITextChecker().completions(
                    forPartialWordRange: NSRange(
                        location: 0, length: (probe as NSString).length),
                    in: probe, language: locale)
            }
            guard !Task.isCancelled else { return }
            await completion()
        }
    }

    /// Warms caches without waiting for completion.
    @discardableResult
    public static func warmRebuildableCaches(
        for languages: [KeyboardLanguage]
    ) -> Task<Void, Never> {
        warmRebuildableCaches(for: languages, completion: {})
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
