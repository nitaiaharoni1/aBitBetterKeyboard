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
///
/// **Two of the states it used to carry are no longer sentences.** A model call in
/// flight is an orbit on the key that started it, and a live recording is a
/// waveform on the microphone — both say what they were saying without spending
/// a 69pt row that appears and leaves. They are still *resolved* here, because
/// the order these questions are asked in is the whole value of this type; they
/// simply resolve to the idle state, which draws nothing.
public enum BannerState: Equatable {

    /// Nothing has been asked for. Carries what to say about that, which is the
    /// message on screen when there is one and an instruction when there is not.
    case hint(String)

    /// A live screen-context reading. This is the idle state that earns the
    /// banner's height: it is what `ScreenContextStrip` used to occupy a separate
    /// 30pt row to say.
    case context(sender: String, message: String, language: KeyboardLanguage)

    /// Answers came back and nothing applied them.
    ///
    /// **The one path that still reaches this is an answer to a field that moved
    /// on.** Fix, Rewrite and Reply write straight into the field the moment the
    /// model answers, so an ordinary call clears this strip rather than filling it.
    /// `applyDirectly` refuses when the field is no longer the one the model was
    /// asked about — somebody typed through the call — and leaves the answer here,
    /// behind a Use button, for a user who can see both. `index` is which one is
    /// showing.
    case options(action: AIAction, options: [BannerOption], index: Int)

    /// The call failed for a reason the user can read. `AIEngineError` already
    /// separates title from message; only the title fits on one line, and the
    /// message is what the accessibility label carries.
    case failed(action: AIAction, title: String, detail: String)

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
            /// The banner message *is* `RPSystemBroadcastPickerView`: a tap on the
            /// sentence asks Control Center to present its broadcast picker. Trailing
            /// is dismiss. See `BroadcastPickerButton` for the disassembly that
            /// establishes that a SwiftUI tap cannot start a session itself, and for
            /// what hosting the picker still does not establish.
            case broadcastPicker
            /// A button that opens the CopyClip panel.
            ///
            /// **The only remedy that is answered inside this keyboard**, and it
            /// exists because the sentence it belongs to cannot name a key.
            /// Reply from the clipboard needs the copied message to be in the
            /// ledger, the one alert-free route in is the `UIPasteControl` the
            /// CopyClip panel draws, and the CopyClip key is a configurable slot
            /// the user may have moved off the bar entirely — which is the rule
            /// `SuggestionBar.aiButtonName` was written under. So the refusal
            /// carries the way in rather than describing where to look for it.
            case copyclip
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

        /// The sentence hosts the system picker; trailing is ×. False for a
        /// refusal that must not start a recording (no Full Access, no cloud).
        var startsBroadcastFromMessage: Bool {
            remedy == .broadcastPicker
        }

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
    /// running in another process. A failure outranks options because a failed
    /// call can leave the previous action's answers in place. Work outranks both
    /// results and failure because `beginWork` clears `aiError` and sets
    /// `isWorking` in the same breath, and a retry must not flash the previous
    /// failure. Everything else is idle.
    ///
    /// **Two of those branches now resolve to idle rather than to a strip**, and
    /// they keep their place in the order for exactly the reason the order exists:
    /// a recording and a running call must still take precedence over the previous
    /// action's leftover answers, or stopping one would flash a Use button over
    /// three replies from a minute ago.
    public static func resolve(
        isDictating: Bool,
        dictationIsLive: Bool,
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
        // **A recording draws no strip and still outranks everything below it.**
        // The microphone key is red for the length of it and the words arrive in
        // the field as they are spoken, so there is nothing left for a row above
        // the candidates to say — including a silent take. "Nothing to insert"
        // was a 69pt strip for a second tap, and the key is already orange
        // record again. A recording started after a Fix must not leave that
        // Fix's leftover answer on screen behind a Use button, which is what
        // falling through to the branches below would do.
        if isDictating || dictationIsLive { return idle(screenContext, idleHint) }
        // Above every idle branch and above the work branches, because this is a
        // sentence about the tap the user just made. Below dictation for the reason
        // dictation is first: that is a recording running in another process.
        if let block { return .blocked(block) }

        // **A call in flight is an orbit on the key, and it is asked here for the
        // same reason the recording above is.** `beginWork` clears `aiError` and
        // sets `isWorking` in the same breath, so a retry tested below this line
        // would flash the failure it is retrying.
        if isWorking { return idle(screenContext, idleHint) }

        // A running action is what names every branch below, so an action-shaped
        // state without one is not renderable. It cannot happen — `beginWork` sets
        // it — and falling through to the hint rather than force-unwrapping is
        // what keeps that a cosmetic bug rather than a crash in a keyboard.
        guard let runningAction else { return idle(screenContext, idleHint) }

        if let error {
            // An engine that cannot run is not a sentence the user can act on.
            // The orbit on the key ending is the signal, same as a Fix that
            // named no mistakes. "Still downloading" was the lie this rejects:
            // the simulator never has the on-device model, the cloud 401'd, and
            // the strip reported the first of those.
            if error.isAvailabilityMiss { return idle(screenContext, idleHint) }
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
        // below" — the user taps Fix, waits through the orbit, and the keyboard
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
    /// action row already says by existing. What is left all does — a live
    /// reading, a refusal, a content failure, an answer nothing could apply.
    /// An engine that cannot run resolves to idle above, so it never reaches
    /// this list.
    ///
    /// **A model call and a recording used to be on this list and are the reason
    /// it is worth stating.** Both are constant, frequent states, and both were
    /// spending 69 points of a 368-point keyboard on a word: the row appeared, the
    /// keys moved down, and it left again a second later. They report on the
    /// control that started them now, where nothing has to move.
    public var isPresented: Bool {
        switch self {
        case .hint: return false
        case .context, .options, .failed, .blocked:
            return true
        }
    }
}
