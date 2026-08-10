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
