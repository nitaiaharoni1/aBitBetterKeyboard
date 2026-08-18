import Foundation

// MARK: - Where Reply gets the message it is answering

/// The three places a message Reply can answer comes from, and the order they
/// are preferred in.
///
/// **This type exists because Reply had exactly one source and that source has
/// never run.** Until `FeatureFlags.screenCaptureReply` there was no choice to
/// make: a reading came off a ReplayKit capture session or Reply refused. That
/// path is complete and, in its reading half, measured against
/// `Bar/screen-context/` — and no line of the capture half has executed
/// anywhere, because the iOS Simulator ships no `replayd`. Shipping it meant
/// asking for a screen recording, on top of Full Access, to get a text reply.
///
/// **The pasteboard answers the same question and costs nothing.** The message
/// the user copied is a message somebody sent them, which is exactly what Reply
/// is for, and reaching it needs no entitlement, no broadcast and no permission
/// dialog. What it costs instead is spelled out in `clipboardGap`: this keyboard
/// cannot read the pasteboard's *contents* without either the iOS paste alert or
/// a tap on `UIPasteControl`, so the message has to be in the CopyClip ledger
/// before Reply can see it.
public enum ReplySource: Equatable, Sendable {

    /// The scripted in-app sample, which photographs nothing.
    /// `ScreenContextSession.contextForReply` short-circuits to it, which is why
    /// no context is carried here.
    ///
    /// **It is currently reachable from nowhere at all, which is stronger than
    /// "gated".** This comment used to say it was reachable from the containing
    /// app's playground behind `SharedStore.screenContextAllowed`; checked on
    /// 2026-08-18, `ScreenContextSession.start()` has no call site outside
    /// `AIKeyboardCoreTests`, and nothing in the app writes
    /// `screenContextAllowed`, so it is false on every install. The sample is a
    /// test fixture today.
    ///
    /// Kept ahead of `.clipboard` in the preference order anyway: if the sample
    /// is ever given a button again, a demo the user deliberately started should
    /// outrank whatever happens to be on their pasteboard.
    case scripted

    /// A ReplayKit capture session that is live right now.
    ///
    /// **Unreachable while `FeatureFlags.screenCaptureReply` is false**, which is
    /// every build until NIT-6 passes on a real device. The case is kept rather
    /// than deleted for the reason the whole capture path is: this is a hold, not
    /// a teardown, and the day the flag flips this is where the screen goes back
    /// to outranking the clipboard.
    case capture

    /// The newest clip in the CopyClip ledger, already turned into a context.
    ///
    /// Carried rather than fetched again at use, because the decision "this clip
    /// is the newest thing the user copied" is made at the moment of the tap and
    /// must not be re-made against a pasteboard that moved in between.
    case clipboard(ScreenContext)

    // MARK: - Building a context out of a clip

    /// One clip, as the thing Reply answers.
    ///
    /// **Three of `ScreenContext`'s five fields are left empty, and that is the
    /// honest answer rather than a shortcut.** A clip is a string; it does not
    /// know which app it was copied from, what that app's icon is, or who wrote
    /// it. `appName` and `appIcon` are already empty on the real capture path
    /// (`ScreenContextChannel.reading`) and nothing renders them. `sender` is the
    /// one worth stating out loud: inventing a plausible name would put a
    /// stranger's name into the model's prompt and, in Hebrew, into the
    /// grammatical gender every reply is written in. `ScreenContext.modelPrompt`
    /// is what keeps an empty sender from reaching the model as `From :`.
    ///
    /// **`Prompts.reply(for:)` reads `message` and `language` and nothing else** —
    /// checked, not assumed: it branches on `context.language.script`,
    /// `context.language.displayName` and `isHebrew(context.message)`. So the
    /// two fields a clip *can* fill are the two the instructions are built from,
    /// and only `CloudIntelligence.replies`' user prompt ever wanted the sender.
    public static func context(for clip: Clip) -> ScreenContext {
        let message = clip.text.value
        return ScreenContext(
            appName: "",
            appIcon: "",
            sender: "",
            message: message,
            language: language(of: message))
    }

    /// The language a reply to this text has to be written in.
    ///
    /// `LanguageDetector.dominantLanguageTag` rather than a count of letters:
    /// `KeyboardLanguage(languageTag:)` is the same route dictation takes to turn
    /// a reported language into one of ours, and the counting alternative gets
    /// the sentence this product exists for backwards — `בוא נעשה sync על
    /// ה-roadmap` is ten Hebrew letters against eleven Latin ones.
    ///
    /// **English is the fallback and it is not a guess about the message.** A
    /// string too short for `NLLanguageRecognizer`, or written in a language with
    /// no keyboard in this catalogue, lands here — and `Prompts.reply(for:)`
    /// answers `.english` by appending `scriptDirective(for:)`, which names the
    /// script it actually finds in the text. Hebrew is caught one branch earlier
    /// still, by `isHebrew(context.message)`. So the fallback costs the *named*
    /// language ("The message is in French"), never the script.
    static func language(of text: String) -> KeyboardLanguage {
        guard let tag = LanguageDetector.dominantLanguageTag(in: text),
            let language = KeyboardLanguage(languageTag: tag)
        else { return .english }
        return language
    }

    // MARK: - What the clipboard can offer right now

    /// The clipboard's answer to "is there a message to reply to", or nil when
    /// there is not.
    ///
    /// **A pending pasteboard generation refuses rather than falling back to the
    /// clip behind it.** `CopyClipCaptureState.control` means the user has copied
    /// something the keyboard has not been allowed to read, so the newest clip is
    /// no longer the newest copy — and answering the previous one would be a
    /// reply in the user's own name about somebody else's message, which is the
    /// failure the whole freshness gate exists to prevent one process away.
    ///
    /// `.neither` is a copied image or file, which can never become a clip;
    /// `refreshCopyClip(.userAsked)` has already advanced the cursor past it by
    /// the time this is asked, so the ledger's newest clip is still the newest
    /// *message* and is offered.
    public static func fromClipboard(
        newest: Clip?, capture: CopyClipCaptureState
    )
        -> ReplySource?
    {
        guard capture != .control, let newest else { return nil }
        return .clipboard(context(for: newest))
    }

    /// Which sentence to print when `fromClipboard(newest:capture:)` answered nil.
    public static func clipboardGap(
        newest: Clip?, capture: CopyClipCaptureState
    )
        -> ClipboardReplyGap
    {
        capture == .control ? .copyNotRead : .nothingCopied
    }
}

/// Why the clipboard has no message for Reply, in the two shapes the user can do
/// something different about.
///
/// **Two cases rather than one sentence, because the work is different.** One is
/// "copy something"; the other is "the thing you copied is one tap away and this
/// keyboard is not allowed to take it without you". Collapsing them would tell a
/// user who has just copied the exact message they want answered to go and copy
/// it.
public enum ClipboardReplyGap: Equatable, Sendable {
    /// The ledger is empty and the pasteboard has not moved since it last caught
    /// up. Nothing has been copied that this keyboard has ever been shown.
    case nothingCopied
    /// Something has been copied since the ledger last caught up, and reading it
    /// is not this keyboard's to do. See `PasteboardReader`: the accessor that
    /// returns a new item's *text* is the one that raises iOS's "Allow Paste?"
    /// alert, so `UIPasteControl` in the CopyClip panel is the only route in, and
    /// the user's own tap on it is the consent.
    case copyNotRead
}
