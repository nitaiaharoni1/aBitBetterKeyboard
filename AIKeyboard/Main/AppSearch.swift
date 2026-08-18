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
    @Published var languagesPush: AppSearchLanguagesPush?
    @Published var keysPush: AppSearchKeysPush?
    @Published var settingsPush: AppSearchSettingsPush?
    @Published var highlightedRow: AppSearchRow?
    @Published var highlightedLanguage: KeyboardLanguage?
    /// Bumped on every jump so a screen already sitting on a `NavigationLink`
    /// destination is torn down before the search-chosen one is pushed. Mixing
    /// the two kinds of push on one stack is how you end up on Dictionary
    /// behind Layout.
    @Published var stackEpoch = 0
    @Published var resignFocus = 0

    /// Consumed by `MainTabView`. Search jumps set this instead of writing the
    /// tab binding from a nested view, which is how a missing environment key
    /// used to swallow the tap.
    @Published var pendingTab: MainTab?

    var results: [AppSearchItem] { AppSearchItem.matches(for: query) }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func dismiss() {
        guard isSearching else { return }
        query = ""
        resignFocus += 1
    }

    func open(_ item: AppSearchItem) {
        query = ""
        highlightedRow = nil
        highlightedLanguage = nil
        languagesPush = nil
        keysPush = nil
        settingsPush = nil
        showsPlayground = false
        pendingTab = nil
        highlightClear?.cancel()
        stackEpoch += 1

        var nextLanguages: AppSearchLanguagesPush?
        var nextKeys: AppSearchKeysPush?
        var nextSettings: AppSearchSettingsPush?
        var nextRow: AppSearchRow?
        var nextLanguage: KeyboardLanguage?
        var nextPlayground = false

        switch item.destination {
        case .tab(_):
            break
        case .playground:
            nextPlayground = true
        case .subscription:
            nextSettings = .subscription
        case .dictionary:
            nextLanguages = .dictionary
        case .layout:
            nextKeys = .layout
        case .language(let language):
            nextLanguage = language
        case .row(let row):
            nextRow = row
        }

        pendingTab = item.destination.tab
        highlightedRow = nextRow
        highlightedLanguage = nextLanguage
        showsPlayground = nextPlayground

        // The stacks are rebuilt by `stackEpoch`. Setting the push in the same
        // turn is a binding that never *changes* on the new stack, so
        // `navigationDestination(item:)` does not fire. Next turn it does.
        if nextLanguages != nil || nextKeys != nil || nextSettings != nil {
            DispatchQueue.main.async {
                self.languagesPush = nextLanguages
                self.keysPush = nextKeys
                self.settingsPush = nextSettings
            }
        }

        scheduleHighlightClear()
    }

    /// Deep link landing. Home hosts the broadcast picker, so this only
    /// switches tab and washes the Screen Context row.
    func openScreenContext() {
        landOnHomeRow(.screenContext)
    }

    /// Deep link landing. Home hosts the start/stop control, so this only
    /// switches tab and washes the Dictation row.
    func openDictation() {
        landOnHomeRow(.dictation)
    }

    private func landOnHomeRow(_ row: AppSearchRow) {
        query = ""
        highlightedLanguage = nil
        languagesPush = nil
        keysPush = nil
        settingsPush = nil
        showsPlayground = false
        highlightClear?.cancel()
        stackEpoch += 1

        pendingTab = .home
        highlightedRow = row
        scheduleHighlightClear()
    }

    private var highlightClear: Task<Void, Never>?

    /// The wash is how you find the row. Leaving it on forever makes the next
    /// visit look like a search landing.
    private func scheduleHighlightClear() {
        guard highlightedRow != nil || highlightedLanguage != nil else { return }
        highlightClear = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            guard !Task.isCancelled else { return }
            highlightedRow = nil
            highlightedLanguage = nil
        }
    }
}

// MARK: - Destinations

enum AppSearchLanguagesPush: String, Identifiable {
    case dictionary
    var id: String { rawValue }
}

enum AppSearchKeysPush: String, Identifiable {
    case layout
    var id: String { rawValue }
}

enum AppSearchSettingsPush: String, Identifiable {
    case subscription
    var id: String { rawValue }
}

/// A Home, Languages, Keys, or Settings row that has no screen of its own.
/// Search scrolls to it rather than pushing.
enum AppSearchRow: String, Hashable {
    case screenContext
    case reply
    case dictation
    case autocorrect
    case completeOnPause
    case spaceOnPause
    case pauseLength
    case autocapitalise
    case predictions
    case numberRow
    case defaultTone
    case palette
    case haptics
    case keySounds
    case replayOnboarding
    case privacy
    case mixing

    var tab: MainTab {
        switch self {
        case .screenContext, .reply, .dictation:
            return .home
        case .mixing:
            return .languages
        case .numberRow, .palette, .haptics, .keySounds:
            return .keys
        case .autocorrect, .completeOnPause, .spaceOnPause, .pauseLength,
            .autocapitalise, .predictions,
            .defaultTone, .replayOnboarding, .privacy:
            return .settings
        }
    }
}

enum AppSearchDestination: Hashable {
    case tab(MainTab)
    case playground
    case subscription
    case dictionary
    case layout
    case language(KeyboardLanguage)
    case row(AppSearchRow)

    /// `MainTab` owns which tab a destination lives on. Search jumps read this
    /// instead of picking a tab with leftover special cases.
    var tab: MainTab {
        switch self {
        case .tab(let tab): return tab
        case .playground: return .home
        case .subscription: return .settings
        case .language, .dictionary: return .languages
        case .layout: return .keys
        case .row(let row): return row.tab
        }
    }
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

    /// **Search is the back door every gate on a screen has to cover too.** A row
    /// taken off Home or Settings is still reachable while the catalogue points
    /// at it, and it lands worse from here: the jump switches tab, scrolls, and
    /// washes a row that is not on the screen. Two entries are gated rather than
    /// deleted, so each comes back with its flag —
    /// `FeatureFlags.screenCaptureReply` (NIT-6) for Screen Context, and
    /// `AppFeatureFlags.subscriptionPaywall` (NIT-20) for the Pro screen.
    private static var screens: [AppSearchItem] {
        let items: [AppSearchItem] = [
            item(
                // The subtitle lists what the Home card actually holds, so it
                // loses Screen Context with the card rather than promising a
                // second feature to anyone who searches for "home".
                "Home",
                FeatureFlags.screenCaptureReply
                    ? "Setup, Screen Context, Dictation" : "Setup, Reply and Dictation",
                icon: "house.fill",
                keywords: ["setup", "full access", "add keyboard"],
                .tab(.home)),
            item(
                "Dictation", "Start a session to dictate from the keyboard", icon: "mic.fill",
                keywords: ["microphone", "speech", "voice"],
                .row(.dictation)),
            // **"reply" used to match only the Screen Context entry**, which the
            // gate above withholds, so searching the app for the feature by name
            // found nothing at all. This is the same kind of entry as Dictation:
            // a Home row with no screen of its own. `paste` and `clipboard` are
            // keywords because the middle step is the one people will come
            // looking for, and `copyclip` because that is what it is called on
            // the keyboard.
            item(
                "Reply", "Answer the message you copied", icon: "arrowshape.turn.up.left",
                keywords: ["answer", "copy", "copyclip", "clipboard", "paste", "message"],
                .row(.reply)),
            item(
                "Languages", "Which layouts the globe key cycles", icon: "globe",
                keywords: ["languages", "globe"],
                .tab(.languages)),
            item(
                "Keys", "Layout, colour, and how keys feel", icon: "keyboard.fill",
                keywords: ["layout", "look", "feel", "palette", "haptics"],
                .tab(.keys)),
            item(
                "Settings", "Typing, AI, and account", icon: "gearshape.fill",
                .tab(.settings)),
            item(
                "Screen Context", "Reply to what's on screen", icon: "eye",
                keywords: ["capture", "broadcast", "reply"],
                .row(.screenContext)),
            item(
                "Try the keyboard", "Type here without leaving the app", icon: "keyboard",
                keywords: ["playground"],
                .playground),
            item(
                "Personal dictionary", "Names you add, plus words from typing",
                icon: "character.book.closed",
                keywords: [
                    "words", "names", "your words", "learned", "remembered",
                    "frequency", "counts", "remember"
                ],
                .dictionary),
            item(
                "Keyboard layout", "Presets, key size, and what each key does",
                icon: "square.grid.3x2",
                keywords: ["keys", "custom", "preset"],
                .layout),
            item(
                "aBitBetterKeyboard Pro", "Subscription", icon: "sparkles",
                keywords: ["upgrade", "paywall", "pro"],
                .subscription)
        ]
        return items.filter { item in
            switch item.destination {
            case .row(.screenContext): return FeatureFlags.screenCaptureReply
            case .subscription: return AppFeatureFlags.subscriptionPaywall
            default: return true
            }
        }
    }

    private static var rows: [AppSearchItem] {
        [
            item(
                "Autocorrect", "Off, high confidence, or full", icon: "text.badge.checkmark",
                keywords: ["confidence", "correction", "spelling"],
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
                "Haptics", "Tap feedback on keys, and how hard it hits", icon: "hand.tap",
                keywords: ["strength", "intensity", "vibration", "buzz"],
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
            // Findable by the words somebody worried about a keyboard would
            // actually type, which are mostly not the words on the row: nobody
            // searches "what we count", they search "privacy", "data" or
            // "tracking". "Reset" and "anonymous" reach the row underneath it.
            item(
                "What we count", "What the app counts, and everything it never does",
                icon: "hand.raised",
                keywords: [
                    "privacy", "analytics", "data", "tracking", "telemetry", "collect",
                    "reset", "anonymous", "identifier"
                ],
                .row(.privacy)),
            item(
                "Forget what it learned", "On Personal dictionary. Names you added stay.",
                icon: "trash",
                keywords: ["forget", "clear", "learned", "reset"],
                .dictionary),
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
            .animation(Theme.Motion.quick, value: search.highlightedRow)
    }
}
