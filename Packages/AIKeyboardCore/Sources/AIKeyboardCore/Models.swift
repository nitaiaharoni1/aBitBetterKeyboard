import SwiftUI

// MARK: - Languages

/// The one thing `KeyboardLanguage` cannot say from `AIKeyboardShared`, because
/// saying it needs SwiftUI and the capture process must not link SwiftUI. The
/// enum itself lives in `AIKeyboardShared/KeyboardLanguage.swift`; this is the
/// only line of it that stayed behind.
extension KeyboardLanguage {
    public var layoutDirection: LayoutDirection {
        isRightToLeft ? .rightToLeft : .leftToRight
    }
}

// MARK: - AI actions

public enum AIAction: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Answers the message on screen. Only useful while a screen context session
    /// is running, so it leads the menu and explains itself when it cannot run.
    case reply
    case fix
    case rewrite
    case tone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .reply: return "Reply"
        case .fix: return "Fix"
        case .rewrite: return "Rewrite"
        case .tone: return "Tone"
        }
    }

    public var subtitle: String {
        switch self {
        case .reply: return "Answer what's on screen"
        case .fix: return "Grammar & spelling"
        case .rewrite: return "Three ways to say it"
        case .tone: return "Pick a register"
        }
    }

    public var icon: String {
        switch self {
        case .reply: return "arrowshape.turn.up.left"
        case .fix: return "checkmark.circle"
        case .rewrite: return "arrow.triangle.2.circlepath"
        case .tone: return "slider.horizontal.3"
        }
    }

    /// Reply reads the screen; everything else only reads the text field.
    public var needsScreenContext: Bool { self == .reply }
}

// MARK: - Tone

public enum ToneStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case clearer
    case shorter
    case professional
    case casual
    case confident
    case friendly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .clearer: return "Clearer"
        case .shorter: return "Shorter"
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .confident: return "Confident"
        case .friendly: return "Friendly"
        }
    }

    /// **No tone may wear a sparkle, and Clearer did.** SF `sparkle` and SF
    /// `sparkles` are the same drawing at different counts. These six are drawn in
    /// the tone picker and on a result variant, both inside a panel whose header
    /// carries `SparkleMark`, so a sparkle here still puts two of them on one
    /// screen meaning two different things.
    ///
    /// It used to be worse and closer: the one-tap button in `SuggestionBar` wore
    /// this symbol directly beside that bar's own `SparkleMark`, so the shipped
    /// default tone put two sparkles side by side, one running a rewrite and one
    /// opening a panel, and every instruction that named "✨" pointed at both. That
    /// button now wears `SuggestionBar.toneButtonSymbol` and names the tone in
    /// words underneath — see its doc comment for why. `ToneIconTests` holds both
    /// halves of the rule.
    public var icon: String {
        switch self {
        case .clearer: return "eyeglasses"
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .professional: return "briefcase"
        case .casual: return "figure.wave"
        case .confident: return "bolt"
        case .friendly: return "hand.wave"
        }
    }
}

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

// MARK: - Suggestions

/// A word offered in the suggestion bar.
public struct Suggestion: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let text: String
    /// Which language the candidate came from, which is not always the layout on
    /// screen: `SuggestionEngine.languages(in:)` reads the sentence and offers
    /// Hebrew words mid-English and back. Provenance only — the bar used to draw
    /// a `LanguageTag` from it and no longer does, because the word is already
    /// written in its own script and the badge only cost it room.
    public let language: KeyboardLanguage
    /// The middle slot is what a space press will commit, the way iOS marks it.
    public let isDefault: Bool

    public init(text: String, language: KeyboardLanguage, isDefault: Bool = false) {
        self.text = text
        self.language = language
        self.isDefault = isDefault
    }
}

// MARK: - Keyboard mode

public enum KeyboardPlane: Sendable {
    case letters
    case numbers
    case symbols
}

public enum KeyboardOverlay: Equatable, Sendable {
    case none
    case emoji
    case aiMenu
    case aiResult(AIActionResultKind)
    case dictation
}

public enum AIActionResultKind: Equatable, Sendable {
    case fix
    case variants(ToneStyle?)
    case replies
    /// Reply was tapped with no live session, so explain instead of failing.
    case needsScreenContext
}

public enum ShiftState: Sendable {
    case off
    case on
    case locked

    public var isUppercase: Bool { self != .off }
}
