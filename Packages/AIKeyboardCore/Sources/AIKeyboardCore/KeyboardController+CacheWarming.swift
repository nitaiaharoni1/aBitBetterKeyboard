import UIKit

private enum CacheWarmResult: Equatable, Sendable {
    case ready
    case memoryPressure
    case cancelled
}

extension KeyboardController {
    /// Builds the same caches ahead of the first keystroke, off the main thread.
    ///
    /// **The first letter of a session used to block the main thread for a
    /// measured 230 ms in English and another 190 ms the first time the other
    /// language was typed**, and both halves of that were already written down
    /// separately — `dropRebuildableCaches()` records 161 ms to rebuild the typo
    /// block, and `.claude/rules/suggestion-bar.md` records ~70-280 ms for Apple
    /// building a language's lexicon on the first `UITextChecker` call. What
    /// nobody had asked is whether either has to be paid *at the keystroke*.
    /// Neither does. Measured on the iOS 26.2 Simulator at `-O`, iPhone 17 Pro:
    /// `TypoLexicon` 65 ms English / 124 ms Hebrew, `UITextChecker` 162 ms English
    /// / 68 ms Hebrew, all on a background thread, after which the first
    /// main-thread `TypoLexicon` lookup measures 0.01 ms and the first
    /// `SuggestionEngine.sharedChecker` call 1.0 ms. iOS rebuilds this extension
    /// whenever it feels like it, so that stall is one a user meets several times
    /// a day rather than once.
    ///
    /// **A throwaway `UITextChecker`, deliberately not `sharedChecker`.** Apple
    /// documents no thread safety for that class and the shared one is touched
    /// from the main actor on every keystroke, so warming it directly would be a
    /// data race. The cost being paid is the *process* loading the language's
    /// dictionary, which a second instance shares — that is what the 1.0 ms
    /// figure above measures, and it is the whole reason this works.
    ///
    /// The caller passes every language the user has enabled and puts the one on
    /// screen first, because the pair this product exists for is typed within
    /// seconds of each other and the second language's stall is otherwise paid on
    /// the first space-bar slide. The memory that costs is exactly the memory a
    /// session was going to hold anyway, and `didReceiveMemoryWarning` still hands
    /// all of it back.
    @discardableResult
    public static func warmRebuildableCaches(
        for languages: [KeyboardLanguage],
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) {
            if languages.contains(where: { $0.script == .hebrew }) {
                guard await Self.continueCacheWarming(
                    Self.warmCache { ConversationalHebrewModel.warm() }, completion: completion)
                else { return }
            }
            for language in languages {
                guard await Self.continueCacheWarming(Self.warmCaches(for: language), completion: completion)
                else { return }
            }
            guard !Task.isCancelled else { return }
            await completion(Self.hasSuggestionMemoryHeadroom(reservingMB: Self.suggestionWorkReserveMB))
        }
    }

    /// Warms caches without waiting for completion.
    @discardableResult
    public static func warmRebuildableCaches(for languages: [KeyboardLanguage]) -> Task<Void, Never> {
        warmRebuildableCaches(for: languages, completion: { _ in })
    }

    private nonisolated static func warmCaches(for language: KeyboardLanguage) -> CacheWarmResult {
        let typoResult = warmCache { _ = TypoLexicon.isWord("a", in: language) }
        guard typoResult == .ready else {
            return typoResult
        }
        let seedResult = warmCache { _ = SeedLanguageModel.knows("a", in: language) }
        guard seedResult == .ready else {
            return seedResult
        }
        guard let locale = language.spellCheckerLocale else { return .ready }
        let probe = language.nativeName
        return warmCache {
            _ = UITextChecker().completions(
                forPartialWordRange: NSRange(location: 0, length: (probe as NSString).length),
                in: probe,
                language: locale)
        }
    }

    private nonisolated static func warmCache(_ work: () -> Void) -> CacheWarmResult {
        guard !Task.isCancelled else { return .cancelled }
        guard hasSuggestionMemoryHeadroom(reservingMB: suggestionWarmReserveMB) else {
            return .memoryPressure
        }
        autoreleasepool(invoking: work)
        return Task.isCancelled ? .cancelled : .ready
    }

    private nonisolated static func continueCacheWarming(
        _ result: CacheWarmResult,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) async -> Bool {
        guard result != .memoryPressure else {
            await completion(false)
            return false
        }
        return result == .ready
    }
}
