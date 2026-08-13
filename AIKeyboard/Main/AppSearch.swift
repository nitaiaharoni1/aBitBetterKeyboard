import AIKeyboardCore
import SwiftUI

/// App-wide jump search: a field under each tab's title that opens the matching
/// screen or lands on the matching settings row.
///
/// Lives on `RootView` rather than `MainTabView` because a palette change
/// rebuilds the tab tree (`.id(store.brandPalette)`), and the query should not
/// vanish because the user picked a different orange.
@MainActor
final class AppSearch: ObservableObject {
    @Published var query = ""
    @Published var showsPlayground = false
    @Published var homePush: AppSearchHomePush?
    @Published var settingsPush: AppSearchSettingsPush?
    @Published var highlightedRow: AppSearchRow?
    @Published var highlightedLanguage: KeyboardLanguage?
    /// Bumped on every jump so a screen already sitting on a `NavigationLink`
    /// destination is torn down before the search-chosen one is pushed. Mixing
    /// the two kinds of push on one stack is how you end up on Dictionary
    /// behind Layout.
    @Published var stackEpoch = 0

    /// Consumed by `MainTabView`. A `Binding` in the environment defaults to
    /// `.constant(.home)` and silently eats taps if the key is missing.
    @Published var pendingTab: MainTab?

    var results: [AppSearchItem] { AppSearchItem.matches(for: query) }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func dismiss() {
        query = ""
    }

    func open(_ item: AppSearchItem) {
        query = ""
        highlightedRow = nil
        highlightedLanguage = nil
        homePush = nil
        settingsPush = nil
        showsPlayground = false
        pendingTab = nil
        stackEpoch += 1
        highlightClear?.cancel()

        switch item.destination {
        case .tab(let tab):
            pendingTab = tab
        case .dictation:
            pendingTab = .home
            homePush = .dictation
        case .screenContext:
            pendingTab = .home
            homePush = .screenContext
        case .playground:
            pendingTab = .home
            showsPlayground = true
        case .subscription:
            pendingTab = .settings
            settingsPush = .subscription
        case .dictionary:
            pendingTab = .settings
            settingsPush = .dictionary
        case .layout:
            pendingTab = .settings
            settingsPush = .layout
        case .cloudModel:
            pendingTab = .settings
            settingsPush = .cloudModel
        case .language(let language):
            pendingTab = .languages
            highlightedLanguage = language
        case .row(let row):
            pendingTab = row == .mixing ? .languages : .settings
            highlightedRow = row
        }

        scheduleHighlightClear()
    }

    private var highlightClear: Task<Void, Never>?

    /// The wash is how you find the row. Leaving it on forever makes the next
    /// visit look like a search landing.
    private func scheduleHighlightClear() {
        guard highlightedRow != nil || highlightedLanguage != nil else { return }
        highlightClear = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            highlightedRow = nil
            highlightedLanguage = nil
        }
    }
}

// MARK: - Destinations

enum AppSearchHomePush: String, Identifiable {
    case dictation
    case screenContext
    var id: String { rawValue }
}

enum AppSearchSettingsPush: String, Identifiable {
    case dictionary
    case layout
    case subscription
    case cloudModel
    var id: String { rawValue }
}

/// A settings (or Languages) row that has no screen of its own. Search scrolls
/// to it rather than pushing.
enum AppSearchRow: String, Hashable {
    case autocorrect
    case completeOnPause
    case spaceOnPause
    case pauseLength
    case autocapitalise
    case predictions
    case learnAsYouType
    case groupedKeys
    case numberRow
    case defaultTone
    case palette
    case haptics
    case keySounds
    case replayOnboarding
    case mixing
}

enum AppSearchDestination: Hashable {
    case tab(MainTab)
    case dictation
    case screenContext
    case playground
    case subscription
    case dictionary
    case layout
    case cloudModel
    case language(KeyboardLanguage)
    case row(AppSearchRow)
}

// MARK: - Catalog

struct AppSearchItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    var flag: String?
    let keywords: [String]
    let destination: AppSearchDestination

    func matches(_ needle: String) -> Bool {
        ([title, subtitle] + keywords).contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    static func matches(for query: String) -> [AppSearchItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return catalog.filter { $0.matches(needle) }
    }

    private static var catalog: [AppSearchItem] {
        screens + rows + languages
    }

    private static var screens: [AppSearchItem] {
        var items: [AppSearchItem] = [
            item(
                "Home", "Setup, Screen Context, Dictation", icon: "house.fill",
                keywords: ["setup", "full access", "add keyboard"],
                .tab(.home)),
            item(
                "Languages", "Which layouts the globe key cycles", icon: "globe",
                .tab(.languages)),
            item(
                "Settings", "Typing, AI, look, and feel", icon: "gearshape.fill",
                .tab(.settings)),
            item(
                "Screen Context", "Reply to what's on screen", icon: "eye",
                keywords: ["capture", "broadcast", "reply"],
                .screenContext),
            item(
                "Dictation", "Start a session to dictate from the keyboard", icon: "mic",
                keywords: ["microphone", "speech", "voice"],
                .dictation),
            item(
                "Try the keyboard", "Type here without leaving the app", icon: "keyboard",
                keywords: ["playground"],
                .playground),
            item(
                "Personal dictionary", "Names and words we should never correct",
                icon: "character.book.closed",
                keywords: ["words", "names"],
                .dictionary),
            item(
                "Keyboard layout", "Presets, key size, and what each key does",
                icon: "square.grid.3x2",
                keywords: ["keys", "custom", "preset"],
                .layout),
            item(
                "AI Keyboard Pro", "Subscription", icon: "sparkles",
                keywords: ["upgrade", "paywall", "pro"],
                .subscription)
        ]
        #if DEBUG
        items.append(
            item(
                "Cloud model", "Where Fix, Rewrite, Tone and Reply send work",
                icon: "cloud",
                keywords: ["backend", "server", "ai"],
                .cloudModel))
        #endif
        return items
    }

    private static var rows: [AppSearchItem] {
        [
            item(
                "Autocorrect", "Space inserts the bold word", icon: "text.badge.checkmark",
                .row(.autocorrect)),
            item(
                "Complete on pause", "Finishes the word after you stop typing",
                icon: "text.cursor",
                keywords: ["idle"],
                .row(.completeOnPause)),
            item(
                "Space on pause", "Adds a space after you stop typing", icon: "space",
                .row(.spaceOnPause)),
            item(
                "Pause length", "How long to wait after you stop typing", icon: "timer",
                keywords: ["idle", "delay", "ms"],
                .row(.pauseLength)),
            item(
                "Auto-capitalise", "Capitalise the first letter", icon: "textformat",
                keywords: ["capitalize", "caps"],
                .row(.autocapitalise)),
            item(
                "Predictions", "Show the suggestion bar above the keys", icon: "lightbulb",
                keywords: ["suggestions"],
                .row(.predictions)),
            item(
                "Learn as you type", "Remembers words and word pairs on this device",
                icon: "brain",
                keywords: ["personal", "model"],
                .row(.learnAsYouType)),
            item(
                "Grouped keys", "Bigger keys holding several letters",
                icon: "rectangle.grid.1x2",
                .row(.groupedKeys)),
            item(
                "Number row", "Digits above the letters", icon: "textformat.123",
                .row(.numberRow)),
            item(
                "Default tone", "How Rewrite and Tone should sound",
                icon: "slider.horizontal.3",
                keywords: ["formal", "casual", "custom"],
                .row(.defaultTone)),
            item(
                "Look", "The accent colour", icon: "paintpalette",
                keywords: ["palette", "colour", "color", "theme", "orange", "pink", "blue"],
                .row(.palette)),
            item(
                "Haptics", "Tap feedback on keys", icon: "hand.tap",
                .row(.haptics)),
            item(
                "Key sounds", "Clicks as you type. Needs Full Access.",
                icon: "speaker.wave.2",
                keywords: ["clicks", "audio"],
                .row(.keySounds)),
            item(
                "Replay onboarding", "Walk through setup again",
                icon: "arrow.counterclockwise",
                .row(.replayOnboarding)),
            item(
                "Mixing languages", "Code switching is always on",
                icon: "arrow.left.arrow.right",
                keywords: ["code switching"],
                .row(.mixing))
        ]
    }

    private static var languages: [AppSearchItem] {
        KeyboardLanguage.allCases.map { language in
            AppSearchItem(
                id: "language-\(language.id)",
                title: language.nativeName,
                subtitle: language.displayName,
                icon: "globe",
                flag: language.flag,
                keywords: [
                    language.languageTag, language.shortName, language.script.displayName
                ],
                destination: .language(language)
            )
        }
    }

    private static func item(
        _ title: String,
        _ subtitle: String,
        icon: String,
        keywords: [String] = [],
        _ destination: AppSearchDestination
    ) -> AppSearchItem {
        AppSearchItem(
            id: title, title: title, subtitle: subtitle, icon: icon, keywords: keywords,
            destination: destination)
    }
}

// MARK: - Row highlight

extension View {
    /// Marks a settings row as a search landing spot: scroll target and a brief
    /// brand wash so the match is the thing the eye hits, not just the thing
    /// that happens to be on screen.
    func searchTarget(_ row: AppSearchRow) -> some View {
        modifier(SearchTargetModifier(row: row))
    }
}

private struct SearchTargetModifier: ViewModifier {
    @EnvironmentObject private var search: AppSearch
    let row: AppSearchRow

    func body(content: Content) -> some View {
        content
            .id(row)
            .background {
                if search.highlightedRow == row {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Brand.solid.opacity(0.12))
                }
            }
    }
}
