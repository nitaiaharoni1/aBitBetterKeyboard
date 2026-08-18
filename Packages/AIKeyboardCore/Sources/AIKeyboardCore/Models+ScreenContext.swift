import Foundation

// MARK: - Screen context

/// One frame's worth of understanding, after the screen has been read and
/// before anything is shown to the user.
///
/// The frame itself is never modelled here on purpose, and the promise that
/// buys is narrower than an earlier version of this comment claimed. The screen
/// is never *stored*: one frame at a time lives in a single buffer inside the
/// capture process and is overwritten by the next, and nothing on disk, in the
/// shared container or in a backup holds a picture of it. But a frame does
/// leave the device — in the ReplayKit capture flow the reading is cloud-only,
/// so tapping Reply uploads one downscaled screenshot and what comes back is
/// this. See `CloudScreenReader` and `.claude/docs/screen-capture-design.md` §5.
public struct ScreenContext: Identifiable, Equatable, Sendable {
    public let id = UUID()
    /// The app the message was read from, for the "we are reading this" strip.
    public let appName: String
    public let appIcon: String
    public let sender: String
    public let message: String
    public let language: KeyboardLanguage

    public init(
        appName: String,
        appIcon: String,
        sender: String,
        message: String,
        language: KeyboardLanguage
    ) {
        self.appName = appName
        self.appIcon = appIcon
        self.sender = sender
        self.message = message
        self.language = language
    }

    /// What the model is shown: the message, headed by the sender only when one
    /// is known.
    ///
    /// **`From \(sender):` was interpolated at both engines and neither asked
    /// whether there was a name.** An empty sender is not hypothetical — the
    /// capture path already publishes one (`ScreenReadService` writes
    /// `reading?.sender ?? ""` whenever the read names nobody), and every
    /// clipboard context has one by construction, because a copied string does
    /// not carry its author. Sent as written, that reached the model as a line
    /// reading `From :`, immediately above a schema field asking it to infer the
    /// sender's grammatical gender *from their name*. The Hebrew instructions
    /// make that inference mandatory and forbid the slash forms that hedge it, so
    /// the model was being pressed to pick a gender from a colon.
    ///
    /// Naming nobody is the honest input. `addressee` already has a `none` answer
    /// for a language that does not inflect, and it is the same answer for a
    /// message whose author is not named.
    public var modelPrompt: String {
        sender.isEmpty ? message : "From \(sender):\n\(message)"
    }
}

/// What the capture session is doing right now.
///
/// Six cases because there are six things to tell the user, and the last two are
/// the ones a state machine with four cases gets wrong: a paused session looks
/// live and a killed one looks off. `CaptureFreshness` decides which of these a
/// real session is in; the scripted in-app demo drives the first four itself.
public enum ScreenContextState: Equatable, Sendable {
    /// The user has never started a session, or stopped the last one.
    case off
    /// The session has begun and no frame has arrived yet: Apple's picker, its
    /// three-second countdown, or the stream spinning up.
    case starting
    /// Frames are arriving and nothing has been read. This is the normal state
    /// of a live session, not a transient one, because a read only ever happens
    /// in answer to a tap on Reply.
    case watching
    /// A reading of the frame on screen right now. Only ever set from a reading
    /// the freshness gate calls offerable.
    case ready(ScreenContext)
    /// Alive but not looking, because `broadcastPaused()` said so. Not an ending
    /// — nothing has to be restarted — and not live either, so no reading may be
    /// offered. Frames merely *stopping* is not this: that is
    /// `CaptureFreshness.Verdict.idle` and it arrives here as `.watching`,
    /// because "no frame for two seconds" is an inference about a delivery rate
    /// nobody has measured and "iOS paused the broadcast" is a fact.
    case paused
    /// The session ended, so it carries the reason and the strip offers a way
    /// back. A jetsam kill arrives here as `.lost`, never as `.off`: the user
    /// switched screen context on and it stopped without being asked, which is a
    /// different sentence.
    case ended(ScreenContextEndReason)

    /// Frames are being sampled. False for `.paused` and `.ended`, so nothing
    /// downstream can offer a reply against a session that is not looking.
    public var isLive: Bool {
        switch self {
        case .off, .paused, .ended: return false
        case .starting, .watching, .ready: return true
        }
    }

    /// Whether the strip has anything to say. Wider than `isLive` on purpose:
    /// "stopped when you took a call" is exactly what the user needs to see, and
    /// a strip that hides itself instead has told them screen context is off.
    public var isVisible: Bool { self != .off }

    public var context: ScreenContext? {
        if case .ready(let context) = self { return context }
        return nil
    }
}

/// One generated answer. `intent` is shown as the card's label so three replies
/// read as three decisions rather than three phrasings.
public struct ReplyOption: Identifiable, Sendable {
    public let id = UUID()
    public let intent: String
    public let icon: String
    public let text: String

    public init(intent: String, icon: String, text: String) {
        self.intent = intent
        self.icon = icon
        self.text = text
    }
}

/// One candidate returned by the AI.
///
/// `label` carries what a Rewrite variant *decides* ("Direct no", "Counter-proposal"),
/// which is the promise the three variants make and which no `ToneStyle` can
/// express. Tone still owns the icon, and is the whole answer for the Tone action.
public struct RewriteVariant: Identifiable, Sendable {
    public let id = UUID()
    public let tone: ToneStyle
    public let label: String?
    public let text: String

    public init(tone: ToneStyle, label: String? = nil, text: String) {
        self.tone = tone
        self.label = label
        self.text = text
    }
}
