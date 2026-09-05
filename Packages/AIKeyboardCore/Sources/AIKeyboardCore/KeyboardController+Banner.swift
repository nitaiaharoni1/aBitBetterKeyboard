import Foundation
import SwiftUI

extension KeyboardController {

    // MARK: Banner state

    /// What the strip above the suggestion bar is saying right now.
    ///
    /// One place rather than every view re-running `BannerState.resolve` with the
    /// same arguments — and the height the extension asks the host for
    /// reads `isPresented` off the same value the strip draws from.
    public var bannerState: BannerState {
        BannerState.resolve(
            isDictating: isDictating,
            dictationIsLive: dictationAvailability.isLive,
            isWorking: isWorking,
            runningAction: runningAction,
            error: aiError,
            block: block,
            options: bannerOptions,
            index: bannerIndex,
            screenContext: screenContext.context,
            idleHint: screenContextHint ?? BannerState.defaultHint)
    }

    /// Whether the action strip is on screen. False for the idle instruction.
    public var showsActionBanner: Bool { bannerState.isPresented }

    /// Whether a key in the action row (or an edge copy of one) should read as
    /// the thing currently happening.
    ///
    /// **Asked of the controller rather than of the strip, because the strip is
    /// no longer up for the two states this most has to answer.** It used to read
    /// `BannerState.activeActionKey`, which worked only for as long as every live
    /// state had a row of its own; a running call and a live recording now light
    /// the control itself, and a key that stopped lighting for them would leave
    /// the user with nothing at all saying which action they had tapped.
    public func isActionKeyActive(_ cap: KeyCap) -> Bool {
        if case .emoji = cap { return overlay.isEmoji }
        if case .copyclip = cap { return overlay.isCopyClip }
        if cap == .dictation {
            // A dictation refusal carries no `AIAction` — that is what `nil`
            // means in `Block.action` — so it is the microphone it belongs to.
            return isDictationActive || (block.map { $0.action == nil } ?? false)
        }
        guard let action = activeAIAction else { return false }
        switch action {
        case .reply: return cap == .aiReply
        case .fix: return cap == .aiFix
        case .rewrite, .tone: return cap == .quickTone
        }
    }

    /// Which of the three text actions the row should draw as current.
    ///
    /// The same order `BannerState.resolve` asks its questions in, and for the
    /// same reasons: a recording outranks everything because it is running in
    /// another process, a refusal is about the tap that was just made, and a call
    /// in flight outranks the previous call's leftovers.
    var activeAIAction: AIAction? {
        if isDictationActive { return nil }
        if let block { return block.action }
        if isWorking { return runningAction }
        // The half-second after the answer lands: the key stays lit while the
        // rim closes, or the arrival would draw white on a cap that has
        // already gone pale. Below work, because `beginWork` clears it and a
        // read racing that clear must answer for the call, not the leftover.
        if let arrivingAction { return arrivingAction }
        switch bannerState {
        case .options(let action, _, _), .failed(let action, _, _): return action
        default: return nil
        }
    }

    /// What the microphone key is showing.
    ///
    /// **The recording is reported by the key now, and this is where that is
    /// decided.** It used to be a 69pt strip with a waveform in it; the strip is
    /// gone for a recording, so the things it said — starting, listening,
    /// finishing — have to be appearances of one key. See `DictationKeyState`.
    ///
    /// `pendingDictationInsert` is the window in the middle: `isDictating` is
    /// already false and the transcription is still in flight. A key that went
    /// dark there would offer to start a second recording over the first one's
    /// answer.
    public var dictationKeyState: DictationKeyState {
        if isDictating {
            let remaining = dictationRemainingSeconds
            return .recording(secondsLeft: remaining.flatMap { $0 < 60 ? Int($0) : nil })
        }
        if pendingDictationInsert { return .finishing }
        return .idle
    }

    /// Whether the microphone key is the live control right now.
    public var isDictationActive: Bool { dictationKeyState.isActive }

    /// Whether a key in the action row has nothing it could do, and should be
    /// drawn as such.
    ///
    /// **Only the two keys that edit what is already there.** Fix and Rewrite need
    /// a message; Reply is about the message on *screen* and is deliberately live
    /// on an empty field, which is the whole point of it, and dictation fills the
    /// field rather than reading it.
    ///
    /// This overrules the rule `SuggestionBar.ToneTap` was written under — that a
    /// control which looks unavailable and swallows the tap teaches nothing — and
    /// it is worth saying why, because that rule was learned from a real defect.
    /// It was about a button that *looked* live: a fully saturated brand icon over
    /// a faded gradient, which read as enabled, did nothing, and said nothing. A
    /// key that is visibly dimmed makes the same statement the refusal made, in the
    /// place the user is already looking, without spending a strip and a Dismiss
    /// tap on a sentence they can work out from an empty field. The words survive
    /// for anyone who cannot see it: `KeyView` reads `actionKeyDisabledReason` as
    /// the key's accessibility hint — one of three sentences now, since a recording
    /// in progress and a call already running disable these keys as well as an
    /// empty field — and
    /// `refuseForEmptyField` is still there behind every route that is not a key.
    /// **A recording disables all three, including the one that needs no text.**
    /// The field is being written into a couple of words at a time while somebody
    /// speaks, so every one of these actions would be editing a sentence that is
    /// still arriving: Fix is handed a half-finished message and replaces the whole
    /// field with a correction of it, `streamedDictation` then points at text that
    /// is no longer there, and the transcript that lands a second later cannot find
    /// its draft and inserts a second copy beside it. Reply is included because it
    /// inserts at the caret, which is exactly where the next reading is about to go.
    public func isActionKeyDisabled(_ cap: KeyCap) -> Bool {
        if isDictationActive {
            return cap == .aiFix || cap == .quickTone || cap == .aiReply
        }
        // A call in flight owns one key. The others must look off, or the bar's
        // Rewrite chip goes dim (it already ignores every `isWorking`) while the
        // Rewrite key stays lit — D8 on the two copies of one control.
        if isWorking, KeyActivity.hostsWorkingOrbit(cap), !isActionKeyActive(cap) {
            return true
        }
        switch cap {
        case .aiFix, .quickTone: return !documentHasText
        default: return false
        }
    }

    /// Why a key in the action row is drawn off, in the words the accessibility
    /// hint prints. Empty when it is not off.
    ///
    /// **A dimmed cap says "not now" to somebody who can see it and nothing at all
    /// to somebody who cannot**, so the reason has to survive in words — and there
    /// are three reasons now. "Type something first" was the only one for as long as
    /// an empty field was the only thing that could disable these keys, and reading
    /// it out over a live recording or another call would be telling the user to
    /// do the one thing they are already doing.
    public func actionKeyDisabledReason(_ cap: KeyCap) -> String {
        guard isActionKeyDisabled(cap) else { return "" }
        if isDictationActive { return "Not while you're dictating" }
        if isWorking { return "Not while a call is running" }
        return "Type something first"
    }

    /// Clears every published field the banner reads for an AI answer.
    func clearBannerState() {
        aiRequestPosition = nil
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
        block = nil
        aiResultText = ""
    }

    /// Refuses an action the user tapped, and says why in the strip.
    ///
    /// **Clears the banner first, and that is not tidiness.** `clearBannerState`
    /// empties `variants`, `replies` and `aiResultText`; without it a Reply refused
    /// for want of a session would draw its sentence over the three rewrites the
    /// previous action left behind, with the pager still offering to page through
    /// them.
    /// **Fires no haptic of its own.** Three of the four callers are reached from
    /// `press(_:)`, which has already fired `Feedback.actionPress()` for the key —
    /// so buzzing here made a refused tap buzz twice, where the panels this replaces
    /// buzzed once. The two callers that are *not* reached through a key press fire
    /// it themselves.
    public func refuse(_ block: BannerState.Block) {
        withAnimation(Theme.Motion.content) {
            clearBannerState()
            self.block = block
        }
    }

    /// The refusal Fix and Rewrite share: nothing in the field to work on.
    ///
    /// **One function rather than three call sites writing the sentence.** The key,
    /// the suggestion bar's one-tap button and `run(_:)` all reach it, and a bar and
    /// a panel disagreeing about what an empty field means is D8, which this repo
    /// has already shipped once.
    public func refuseForEmptyField(_ action: AIAction) {
        refuse(
            .init(
                action: action,
                title: "Nothing to \(action.title.lowercased())",
                detail: "Type something, then tap \(action.title).",
                remedy: .none))
    }

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
    /// **Nothing narrows this any more.** It used to return empty while a result
    /// panel was open, because `AIMenuPanel`'s Tone row ran a rewrite into
    /// `AIResultPanel` and the answer must not be drawn twice. Both panels are
    /// deleted and the strip is the only place an answer can go.
    public var bannerOptions: [BannerOption] {
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
}
