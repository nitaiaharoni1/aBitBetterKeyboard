import SwiftUI

extension KeyboardController {

    // MARK: Dictation

    public func startDictation() {
        // **A dead end the user has to be walked out of by hand, said in the strip.**
        // Nothing in a keyboard extension can start a recording session or launch
        // its own app — `UIApplication` is unavailable there and the responder-chain
        // `openURL` workaround is disallowed — so this names the app, the screen and
        // the button, and offers no button of its own because there is none to
        // offer. See `.claude/rules/dictation.md`.
        //
        // **These three resets are above the guard, not below it, and that is not
        // tidiness.** They used to run unconditionally, before the availability
        // check opened the panel; putting the check first left the no-session tap
        // without them. `dictation.$failure` only ever *sets* `dictationFailure`,
        // and the only other place that clears it is `stopDictation`'s teardown —
        // which the user reaches through a Dismiss button that is gone the moment
        // the session ends, because `.dictationFailed` needs a live session to
        // render. So a refusal left behind by a session that closed itself sat in
        // the property until the next live session brought it back on screen,
        // attached to a recording that had not failed.
        dictationTranscript = ""
        dictationFailure = ""
        pendingDictationInsert = false

        // **This is what the guard below is asking, and without it the answer
        // was a value nothing had ever read.** `DictationSession.availability`
        // only tracks the shared page while its poll is running, and the poll
        // used to be started *below* the check that reads it — after the refusal
        // had already returned. So the check read the `.noSession(.notEnded)` the
        // session is initialised with, the banner said "No dictation session" over
        // a session that was live in the app, and the poll that would have
        // corrected it was never reached: every tap refused, on every device, for
        // as long as the keyboard was up. `refresh()` rather than
        // `startWatching()` because the refusal must not leave a timer running —
        // `DictationRequest.keyboardAliveAt` is a dead-man's switch and a timer
        // outliving the keyboard is the one thing that defeats it — and because
        // `stopWatching()` clears the availability this refusal is about to
        // print. The live path starts the watch below, where `refresh()` runs
        // again for nothing.
        dictation.refresh()

        guard dictation.availability.isLive else {
            refuse(
                .init(
                    action: nil,
                    title: dictationRefusalTitle,
                    detail: dictationRefusalDetail,
                    remedy: .none))
            return
        }

        dictation.startWatching()
        observeDictation()
        isDictating = dictation.beginUtterance()
        if isDictating { Feedback.modifierPress() }

        waveformTask?.cancel()
        waveformTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.waveformPhase += 0.05 + self.dictation.level * 0.5
                try? await Task.sleep(for: .milliseconds(45))
            }
        }
    }

    /// The two states that are not a recording, in the words the deleted panel used.
    private var dictationRefusalTitle: String {
        switch dictation.availability {
        case .needsFullAccess: return "Dictation needs Full Access"
        default: return "No dictation session"
        }
    }

    private var dictationRefusalDetail: String {
        switch dictation.availability {
        case .needsFullAccess:
            return
                "Recording happens in the AI Keyboard app and the words come back here, which needs Full Access. Settings › General › Keyboard › Keyboards."
        case .noSession(let reason):
            // The reason only prints when it is news. "Nobody has started one" and
            // "you stopped it" are the ordinary states, and narrating them would
            // make the sentence longer without making it more useful.
            let why = reason == .notEnded || reason == .stoppedByUser ? "" : reason.explanation + " "
            return "\(why)Open AI Keyboard, tap Start dictation, then come back."
        default:
            return ""
        }
    }

    public func stopDictation(insert: Bool) {
        waveformTask?.cancel()
        waveformTask = nil

        if insert, isDictating {
            pendingDictationInsert = true
            isDictating = false
            dictation.stopUtterance()
            return
        }

        // **The third clause used to be `overlay == .dictation` and dropping it
        // outright would have wedged the banner.** It was what let a *stopped*
        // session still be torn down — and the state that needs that is a recording
        // that failed: `dictation.$failure` clears `isDictating` and
        // `pendingDictationInsert` before setting the reason, so by the time the
        // user taps Dismiss on "Nothing to insert" the first two are both false. The
        // panel used to be open, so the old clause carried it; with no panel, this
        // guard would return early and `dictationFailure` would never be cleared,
        // leaving the sentence to reappear on the session's next tick forever.
        guard isDictating || pendingDictationInsert || !dictationFailure.isEmpty else { return }

        pendingDictationInsert = false
        isDictating = false
        dictation.cancelUtterance()
        dictation.stopWatching()
        dictationTranscript = ""
        dictationFailure = ""
    }

    static func isRightToLeft(reported: String, text: String) -> Bool {
        if let tag = reported.split(separator: ",").first,
            let language = KeyboardLanguage(languageTag: String(tag))
        {
            return language.isRightToLeft
        }
        return SuggestionEngine.languages(in: text).first?.isRightToLeft == true
    }

    func observeDictation() {
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
