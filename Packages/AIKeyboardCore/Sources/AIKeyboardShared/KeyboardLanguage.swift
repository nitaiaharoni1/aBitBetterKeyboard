import Foundation

/// Which of the two keyboards this product is: the one the user types on, and
/// the one a reading of the screen says to answer in.
///
/// **In `AIKeyboardShared` because the capture process needs it.** A screen
/// reading carries the language to reply in, and the read now happens inside the
/// broadcast upload extension, which must never link `AIKeyboardCore`. Only the
/// SwiftUI half of this type stayed behind: `layoutDirection` is an extension in
/// `Models.swift`, which is the whole reason that file imports SwiftUI.
public enum KeyboardLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case english
    case hebrew

    public var id: String { rawValue }

    /// Shown on the globe key and in the language switcher.
    public var shortName: String {
        switch self {
        case .english: return "EN"
        case .hebrew: return "עב"
        }
    }

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .hebrew: return "Hebrew"
        }
    }

    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .hebrew: return "עברית"
        }
    }

    public var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .hebrew: return "🇮🇱"
        }
    }

    public var isRightToLeft: Bool { self == .hebrew }

    /// Placeholder on the space bar, the way the system keyboard names itself.
    public var spaceLabel: String {
        switch self {
        case .english: return "space"
        case .hebrew: return "רווח"
        }
    }

    public var returnLabel: String {
        switch self {
        case .english: return "return"
        case .hebrew: return "שורה"
        }
    }

    public func next() -> KeyboardLanguage {
        self == .english ? .hebrew : .english
    }
}
