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

/// What is drawn over the key grid, and it is only ever emoji now.
///
/// **Three cases were deleted rather than taught to behave.** `.aiMenu`,
/// `.aiResult` and `.dictation` each painted over every key row to say one or two
/// sentences — and the states that reached them are the ones a user meets first: an
/// empty field, a screen-context session never started, a dictation session never
/// opened. All four of those paths are `BannerState.blocked` now, so the keys stay
/// visible and the strip does the talking. See `.claude/rules/keyboard-layout.md`.
///
/// Both emoji cases stay, because neither breaks that rule: the grid is drawn inside
/// the letter area and search hands the letters back and takes only the action row.
public enum KeyboardOverlay: Equatable, Sendable {
    case none
    case emoji
    /// The emoji grid with the search box open.
    ///
    /// A state of its own rather than a flag on `.emoji`, because the two draw
    /// opposite halves of the keyboard: the grid replaces the letters, and search
    /// needs the letters back to type into the box. Making it a case means the
    /// compiler names every place that has to decide.
    case emojiSearch

    /// Either emoji state. What the Emoji key reads to know it should say `אבג`.
    public var isEmoji: Bool { self == .emoji || self == .emojiSearch }
}

public enum ShiftState: Sendable {
    case off
    case on
    case locked

    public var isUppercase: Bool { self != .off }
}

// MARK: - The microphone key

/// What the microphone key is showing, as one value.
///
/// **The recording used to be reported by a 69pt strip and is reported by the key
/// itself now**, which means the key has three appearances instead of one and a
/// `Bool` cannot carry them. It is resolved on `KeyboardController`
/// (`dictationKeyState`) rather than derived inside `KeyView`, because two of
/// the three depend on state that lives in another process and reaches the keyboard
/// through `DictationSession` — a `KeySpec` is a value and can read none of it.
///
/// Resolving it as a value rather than as a chain of `if`s in a `ViewBuilder` is
/// the same rule `SuggestionBar.ToneTap` was written under: what a SwiftUI view
/// draws cannot be read back in a test, so the decision is taken somewhere that
/// can.
public enum DictationKeyState: Equatable, Sendable {
    /// Nothing is running. The key offers to start.
    case idle
    /// The microphone is open and what it hears is being kept. **The one state
    /// drawn in record red.**
    ///
    /// `secondsLeft` is the session's own countdown and is non-nil only inside the
    /// last minute of it. **It is on the key because the strip that used to carry
    /// it is gone**, and it is the one thing that strip said which was worth
    /// keeping: a session closes itself, so without it a recording stops
    /// mid-sentence with nothing having warned anybody. A clock that runs for the
    /// whole session is one the user is invited to watch; a clock that appears is
    /// news.
    case recording(secondsLeft: Int?)
    /// The recording is closed and the last words are still in flight. A tap here
    /// calls the insert off, which is the only moment that is possible — see
    /// `KeyboardController.toggleDictation`.
    case finishing

    /// Whether the key is the live control, whatever it is doing.
    public var isActive: Bool { self != .idle }

    /// Whether a microphone is keeping what it hears right now. The record-red
    /// cap, and the question every caller means when it asks — asked as a property
    /// rather than as `== .recording`, which stopped compiling the moment the
    /// countdown became a payload and would otherwise have to be spelled
    /// `if case`.
    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    /// **Waves rather than a microphone, and a pause bar rather than a red dot.**
    /// A microphone is a picture of the hardware; waves are a picture of what the
    /// key does with it, and they are what the recording state can then animate
    /// into. While it is running the key shows the *interruption* — a pause bar is
    /// the shape a thumb goes back to when it wants the thing to stop, and this
    /// key does stop rather than pause, which is why nothing else on the keyboard
    /// offers a pause any more.
    public var icon: String {
        switch self {
        case .idle: return "waveform"
        case .recording: return "pause.fill"
        case .finishing: return "xmark"
        }
    }

    /// What a tap does, in the width a nine-point caption has.
    public var title: String {
        switch self {
        case .idle: return "Dictate"
        case .recording(let secondsLeft):
            guard let secondsLeft else { return "Stop" }
            return "\(secondsLeft)s left"
        case .finishing: return "Cancel"
        }
    }

    /// What a tap does, spelled out for VoiceOver.
    ///
    /// **The states were drawn differently and said one thing.** The key's label
    /// comes from `KeyCap`, which knows nothing about a recording, so it read
    /// "Dictate, button" whether the microphone was idle, live or finishing — the
    /// whole distinction this type exists to draw was silent, and the one state
    /// where being wrong matters most is the one where a microphone is on. The
    /// caption above cannot serve: it is nine points of text that says `42s left`,
    /// and a countdown is not what a tap does.
    ///
    /// Longer than the caption on purpose. A caption is read beside a glyph, a red
    /// cap and four neighbouring keys; this is read alone.
    public var accessibilityLabel: String {
        switch self {
        case .idle: return "Dictate"
        case .recording: return "Stop recording"
        case .finishing: return "Cancel transcription"
        }
    }

    /// The state itself, for what a tap does not say. Empty when there is nothing
    /// to add.
    public var accessibilityValue: String {
        switch self {
        case .idle: return ""
        case .recording(let secondsLeft):
            guard let secondsLeft else { return "Recording" }
            return "Recording, \(secondsLeft) seconds left"
        case .finishing: return "Transcribing"
        }
    }
}
