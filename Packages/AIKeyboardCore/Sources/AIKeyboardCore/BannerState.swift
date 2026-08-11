import Foundation

// MARK: - One thing the banner can offer

/// A generated answer the user can accept with one tap.
///
/// The three AI actions produce three differently-shaped results — one corrected
/// sentence, three rewrites labelled by the decision each takes, three replies
/// labelled by intent — and the banner shows one thing at a time. Flattening them
/// here rather than teaching the view about `RewriteVariant` and `ReplyOption`
/// separately is what keeps the paging, the Use button and the accessibility
/// wording written once.
public struct BannerOption: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The short uppercase tag over the text: an intent, a decision, a register.
    /// Empty for Fix, which has exactly one answer and nothing to distinguish it
    /// from.
    public let label: String
    public let text: String
    /// Which way to lay the text out. A reply to a Hebrew message is Hebrew
    /// whatever the keyboard is currently set to, so this comes from the answer
    /// rather than from `KeyboardController.language`.
    public let language: KeyboardLanguage

    public init(id: UUID = UUID(), label: String, text: String, language: KeyboardLanguage) {
        self.id = id
        self.label = label
        self.text = text
        self.language = language
    }
}

// MARK: - What the banner is saying

/// Everything the strip above the suggestion bar can be showing, as one value.
///
/// **One enum rather than a view that reads six published properties, because the
/// six disagree.** `isWorking`, `aiError`, `variants`, `replies`, `aiResultText`
/// and `isDictating` are set and cleared by different code paths, and a view
/// branching on them in sequence renders whichever it tested first: a failed call
/// that left `variants` populated from the previous action showed the old answer
/// under the new action's name. Resolving once, in one ordered place, is what
/// makes "which of these wins" a decision with a test on it rather than the order
/// somebody happened to write the `if`s in.
public enum BannerState: Equatable {

    /// Nothing has been asked for. Carries what to say about that, which is the
    /// message on screen when there is one and an instruction when there is not.
    case hint(String)

    /// A live screen-context reading. This is the idle state that earns the
    /// banner's height: it is what `ScreenContextStrip` used to occupy a separate
    /// 30pt row to say.
    case context(sender: String, message: String, language: KeyboardLanguage)

    /// A model call is in flight.
    case working(AIAction)

    /// Answers came back. `index` is which one is showing.
    case options(action: AIAction, options: [BannerOption], index: Int)

    /// The call failed for a reason the user can read. `AIEngineError` already
    /// separates title from message; only the title fits on one line, and the
    /// message is what the accessibility label carries.
    case failed(action: AIAction, title: String, detail: String)

    /// A recording is open in the containing app. The keyboard cannot start one —
    /// see `DictationSession` — so this state is only ever reached from one that
    /// could.
    case dictating(transcript: String, isListening: Bool)

    /// An action the user tapped that could not run, and what they can do about it.
    ///
    /// **One case for four refusals, because each of them used to be a panel.** Fix
    /// and Rewrite on an empty field, Reply with no screen-context session, and
    /// Dictate with no session in the containing app all covered every key row to say
    /// one or two sentences — so the states a user meets first were exactly the ones
    /// that hid the keyboard, and Fix drew nothing at all. They differ only in the
    /// words and in whether there is anything to tap, so they differ only in this
    /// payload.
    case blocked(Block)

    /// A recording finished and produced nothing to insert.
    ///
    /// **Its own case because the alternative was silence.** The panel this
    /// replaced stayed on screen after a failed recording precisely so it could
    /// say why — `DictationKeyboardTests` pins that a recording with no speech in
    /// it "inserts nothing and says why". Routing a live session to the banner
    /// took the panel away, and without this the user tapped Stop, watched the
    /// waveform vanish and got no text and no reason.
    case dictationFailed(String)

    /// Why an action refused to start, in the words the strip prints.
    ///
    /// A value rather than four `BannerState` cases, because the four differ in
    /// nothing a view branches on: each is a title, a sentence, and at most one
    /// button. Keeping them one case is what stops the strip growing a fifth
    /// almost-identical arm the next time something can refuse.
    public struct Block: Equatable, Sendable {

        /// What the user can do about it from inside the keyboard.
        public enum Remedy: Equatable, Sendable {
            /// Nothing here can fix it. Dismiss is the only button.
            case none
            /// The trailing chip *is* `RPSystemBroadcastPickerView`, the one system
            /// affordance a keyboard extension can host. See `BroadcastPickerButton`
            /// for the disassembly that establishes that, and for what it does not
            /// establish.
            case broadcastPicker
            /// A button that asks the extension host to open the containing app at
            /// the given URL. The host tries `extensionContext?.open(_:)` first and
            /// falls back to the responder-chain workaround if that fails. The URL
            /// is carried here so the view does not need to know it separately.
            case openApp(URL)
        }

        /// Which action was refused, so the strip labels it with the same glyph and
        /// word the key wears. `nil` is dictation, which is not an `AIAction`.
        public let action: AIAction?
        public let title: String
        public let detail: String
        public let remedy: Remedy

        public init(action: AIAction?, title: String, detail: String, remedy: Remedy) {
            self.action = action
            self.title = title
            self.detail = detail
            self.remedy = remedy
        }
    }

    /// Resolves the state from everything that could be true at once.
    ///
    /// **The order of these branches is the whole point and it is not
    /// alphabetical.** Dictation outranks a model call because a recording is
    /// running in another process and stopping it is time-critical. A failure
    /// outranks options because a failed call can leave the previous action's
    /// answers in place. Work outranks both results and failure because
    /// `beginWork` clears `aiError` and sets `isWorking` in the same breath, and a
    /// retry must not flash the previous failure. Everything else is idle.
    public static func resolve(
        isDictating: Bool,
        dictationIsLive: Bool,
        dictationTranscript: String,
        dictationFailure: String,
        isWorking: Bool,
        runningAction: AIAction?,
        error: AIEngineError?,
        /// An action the user tapped that refused to start. Set by the tap and
        /// cleared by `beginWork`, so it cannot describe the same tap as
        /// `isWorking` — which makes the ordering below decided rather than
        /// incidental, and is why there is a test for it.
        block: Block?,
        options: [BannerOption],
        index: Int,
        screenContext: ScreenContext?,
        idleHint: String
    ) -> BannerState {
        // Ahead of the live check, not inside it: `stopDictation` clears
        // `isDictating` before the reason lands, so a failure tested second is a
        // failure never shown.
        if !dictationFailure.isEmpty, dictationTranscript.isEmpty, dictationIsLive || isDictating {
            return .dictationFailed(dictationFailure)
        }
        if isDictating || dictationIsLive {
            return .dictating(transcript: dictationTranscript, isListening: isDictating)
        }
        // Above every idle branch and above the work branches, because this is a
        // sentence about the tap the user just made. Below dictation for the reason
        // dictation is first: that is a recording running in another process.
        if let block { return .blocked(block) }

        // A running action is what names every branch below, so an action-shaped
        // state without one is not renderable. It cannot happen — `beginWork` sets
        // it — and falling through to the hint rather than force-unwrapping is
        // what keeps that a cosmetic bug rather than a crash in a keyboard.
        guard let runningAction else { return idle(screenContext, idleHint) }

        if isWorking { return .working(runningAction) }
        if let error {
            return .failed(action: runningAction, title: error.title, detail: error.message)
        }
        if !options.isEmpty {
            return .options(
                action: runningAction,
                options: options,
                index: min(max(0, index), options.count - 1))
        }
        // **An action that finished, raised no error and produced nothing.** The
        // banner used to fall through to the idle hint here, so a model answering
        // with an empty string left the strip reading "Type, or pick an action
        // below" — the user taps Fix, waits through the shimmer, and the keyboard
        // ends up looking exactly as it did before they touched it. An empty result
        // is the one outcome a user cannot act on or explain, which is the whole
        // reason `aiError` exists; this is the gap it does not cover, because
        // nothing threw.
        return .failed(
            action: runningAction,
            title: "Nothing came back",
            detail: "Try again, or edit it yourself.")
    }

    private static func idle(_ context: ScreenContext?, _ hint: String) -> BannerState {
        guard let context else { return .hint(hint) }
        return .context(
            sender: context.sender, message: context.message, language: context.language)
    }

    /// What the strip says when it has nothing of its own to say.
    ///
    /// Names the row rather than a glyph, for the reason `SuggestionBar
    /// .aiButtonName` exists: the controls it points at are configurable, so it
    /// must not claim a particular one is in a particular place.
    public static let defaultHint = "Type, or pick an action below"

    /// Whether the strip earns its row on screen.
    ///
    /// The idle instruction does not: "Type, or pick an action below" is what the
    /// action row already says by existing. Everything else does — a live reading,
    /// a model call, a refusal, a recording.
    public var isPresented: Bool {
        switch self {
        case .hint: return false
        case .context, .working, .options, .failed, .dictating, .blocked, .dictationFailed:
            return true
        }
    }

    /// Which action-row key should read as current, if any.
    ///
    /// A live screen-context reading is not an action the user started, so it
    /// lights nothing. Dictation is not an `AIAction`, so it is named separately.
    public var activeActionKey: ActionKey? {
        switch self {
        case .working(let action), .options(action: let action, _, _),
            .failed(action: let action, _, _):
            return .ai(action)
        case .blocked(let block):
            return block.action.map { .ai($0) } ?? .dictation
        case .dictating, .dictationFailed:
            return .dictation
        case .hint, .context:
            return nil
        }
    }

    /// A key in the action row that the banner can mark as current.
    public enum ActionKey: Equatable, Sendable {
        case ai(AIAction)
        case dictation
    }
}
