import Foundation
import SwiftUI

extension KeyboardController {

    // MARK: Banner state

    /// Clears every published field the banner reads for an AI answer.
    func clearBannerState() {
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
    }

    /// Refuses an action the user tapped, and says why in the strip.
    ///
    /// **Clears the banner first, and that is not tidiness.** `clearBannerState`
    /// empties `variants`, `replies` and `aiResultText`; without it a Reply refused
    /// for want of a session would draw its sentence over the three rewrites the
    /// previous action left behind, with the pager still offering to page through
    /// them.
    public func refuse(_ block: BannerState.Block) {
        Feedback.modifierPress()
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
                title: "Nothing to \(action.title.lowercased()) yet",
                detail: "Type something first, then tap \(action.title).",
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
