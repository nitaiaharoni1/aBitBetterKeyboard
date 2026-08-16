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
    /// Fresh every time a list is built, so SwiftUI can tell two slots apart.
    /// **Not part of equality.** The synthesised `==` included it, so the bar
    /// saw a new array on every keystroke even when the three words had not
    /// moved, and faded them for 180ms — a beat behind the fingers. Two
    /// suggestions are the same offer when the word, the language and the bold
    /// slot agree.
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

    public static func == (lhs: Suggestion, rhs: Suggestion) -> Bool {
        lhs.text == rhs.text && lhs.language == rhs.language && lhs.isDefault == rhs.isDefault
    }
}

// MARK: - Keyboard mode

public enum KeyboardPlane: Sendable {
    case letters
    case numbers
    case symbols
}

/// What is drawn over the letter keys. The action row stays.
///
/// **Three cases were deleted rather than taught to behave.** `.aiMenu`,
/// `.aiResult` and `.dictation` each painted over every key row to say one or two
/// sentences — and the states that reached them are the ones a user meets first: an
/// empty field, a screen-context session never started, a dictation session never
/// opened. All four of those paths are `BannerState.blocked` now, so the keys stay
/// visible and the strip does the talking. See `.claude/rules/keyboard-layout.md`.
///
/// Emoji and CopyClip stay, because neither breaks that rule: both panels sit
/// inside the letter area. Each has a search twin that needs the letters back.
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
    /// Clipboard history over the letter keys. The action row stays, the way
    /// `.emoji` does.
    case copyclip
    /// CopyClip with the search box open. Same swap as `.emojiSearch`: the
    /// panel goes, the letters come back, and the action row becomes matches.
    case copyclipSearch

    /// Either emoji state. What the Emoji key reads to know it should say `אבג`.
    public var isEmoji: Bool { self == .emoji || self == .emojiSearch }

    public var isCopyClip: Bool { self == .copyclip || self == .copyclipSearch }

    /// A box on this keyboard owns the keystrokes instead of the document.
    ///
    /// The two search states are the only places a letter goes somewhere other
    /// than the user's message, which is why they are also the only places the
    /// document's shift must not follow it. See
    /// `KeyboardController.adoptSearchShift(from:)`.
    public var isSearch: Bool { self == .emojiSearch || self == .copyclipSearch }

    /// The letter rows are on screen. Hidden, not removed, while a panel covers
    /// them so the overlay keeps the same height.
    ///
    /// **The space row is not one of them, and it used to be.** A panel covered
    /// the letters *and* the bottom row, which put `123`, space, the full stop,
    /// return — and, once Emoji moved down there, the only key that closes the
    /// grid — underneath the grid. `KeyboardView+Keys` draws the bottom row
    /// outside the panel's stack now, so this answers for the sliding rows alone.
    public var showsLetterKeys: Bool {
        self == .none || self == .emojiSearch || self == .copyclipSearch
    }

    /// The action row is on screen. Hidden during search, which spends that
    /// band on results.
    public var showsActionRow: Bool { self == .none || self == .emoji || self == .copyclip }
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
    /// The microphone is open and what it hears is being kept. Drawn in record
    /// red, together with `.finishing` — see `isRecording`.
    ///
    /// `secondsLeft` is the session's own countdown and is non-nil only inside the
    /// last minute of it. **It is on the key because the strip that used to carry
    /// it is gone**, and it is the one thing that strip said which was worth
    /// keeping: a session closes itself, so without it a recording stops
    /// mid-sentence with nothing having warned anybody. A clock that runs for the
    /// whole session is one the user is invited to watch; a clock that appears is
    /// news.
    case recording(secondsLeft: Int?)
    /// The recording is closed and the last words are still in flight.
    ///
    /// Drawn as pause, same as `.recording`: the key has two appearances, waves
    /// and pause, and an × was the third. A tap here does nothing — the insert is
    /// already on its way, and starting a second utterance on top of it is the
    /// defect this case exists to prevent. See `KeyboardController.toggleDictation`.
    case finishing

    /// Whether the key is the live control, whatever it is doing.
    public var isActive: Bool { self != .idle }

    /// Whether the key is the live microphone control, red cap included.
    ///
    /// True through `.finishing` as well as `.recording`, so the key does not
    /// flip back to orange record for the second it takes the words to land —
    /// that flash read as "tap me again" and is exactly the window a second
    /// utterance used to open in.
    public var isRecording: Bool { self != .idle }

    /// **Waves at rest, pause while the microphone is on.** Two appearances,
    /// not three: an × while the last words were in flight offered to cancel an
    /// insert that is already on its way, and nobody asked for that. The pause
    /// bar is still a stop, not a pause — the cross-process pause protocol is
    /// gone — and it stays on the key until the transcript lands so the thumb
    /// has one shape to go back to.
    public var icon: String {
        switch self {
        case .idle: return "waveform"
        case .recording, .finishing: return "pause.fill"
        }
    }

    /// What a tap does, in the width a nine-point caption has.
    public var title: String {
        switch self {
        case .idle: return "Record"
        case .recording(let secondsLeft):
            guard let secondsLeft else { return "Pause" }
            return "\(secondsLeft)s left"
        case .finishing: return "Pause"
        }
    }

    /// What a tap does, spelled out for VoiceOver.
    ///
    /// **The states were drawn differently and said one thing.** The key's label
    /// comes from `KeyCap`, which knows nothing about a recording, so it read
    /// "Record, button" whether the microphone was idle, live or finishing — the
    /// whole distinction this type exists to draw was silent, and the one state
    /// where being wrong matters most is the one where a microphone is on. The
    /// caption above cannot serve: it is nine points of text that says `42s left`,
    /// and a countdown is not what a tap does.
    ///
    /// Longer than the caption on purpose. A caption is read beside a glyph, a red
    /// cap and four neighbouring keys; this is read alone.
    public var accessibilityLabel: String {
        switch self {
        case .idle: return "Record"
        case .recording, .finishing: return "Pause recording"
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
