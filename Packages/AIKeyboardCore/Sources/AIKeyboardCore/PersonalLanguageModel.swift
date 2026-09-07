import Foundation

/// One word the keyboard has seen this person type, with how often.
///
/// Personal dictionary lists these. Ranking still ignores a count below
/// `PersonalLanguageModel.boostThreshold`.
public struct LearnedWord: Identifiable, Equatable, Sendable {
    public let word: String
    public let count: Int
    public let language: KeyboardLanguage

    public var id: String { "\(language.languageTag)\u{1F}\(word)" }
}

@MainActor
public final class PersonalLanguageModel {

    /// The keyboard's instance. The app reaches the same store through
    /// `SharedStore` for the count and the clear button, and the two processes are
    /// never writing at the same time — iOS does not run the keyboard while the
    /// app is foregrounded — but `generation` covers the case where they were.
    public static let shared = PersonalLanguageModel()

    /// Seen this many times before it influences ranking.
    nonisolated static let boostThreshold = 2
    /// Seen this many times before autocorrect must leave it alone.
    nonisolated static let protectThreshold = 3

    /// Beyond this the counts are halved and the singletons dropped. Chosen so the
    /// file stays well under a megabyte: a keyboard extension is memory-capped
    /// around 50 MB and this is read into memory whole.
    private static let unigramCap = 4000
    private static let bigramCap = 12000
    /// Records between disk writes. A keyboard extension is torn down without
    /// warning constantly, so this is the number of words a kill may cost; 25 is
    /// a few sentences and writing on every word would rewrite the whole file
    /// several times a second.
    private static let flushInterval = 25

    enum LearningSource: Sendable {
        case typed
        case selectedSuggestion
        case automatic
    }

    private struct VerbatimToken: Codable {
        var kind: PersonalToken.Kind
        var text: String
        var count: Int
        var languageTag: String
    }

    private struct LegacyPhone: Decodable {
        var text: String
        var count: Int
        var languageTag: String
    }

    private struct Store: Codable {
        var unigrams: [String: [String: Int]] = [:]
        var bigrams: [String: [String: Int]] = [:]
        var selected: [String: [String: Int]] = [:]
        var automatic: [String: [String: Int]] = [:]
        var rejected: [String: [String: Int]] = [:]
        var tokens: [String: VerbatimToken] = [:]

        private enum CodingKeys: String, CodingKey {
            case unigrams, bigrams, selected, automatic, rejected, tokens
        }

        private enum LegacyCodingKeys: String, CodingKey { case phones }

        init() {}

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            unigrams = try values.decodeIfPresent([String: [String: Int]].self, forKey: .unigrams) ?? [:]
            bigrams = try values.decodeIfPresent([String: [String: Int]].self, forKey: .bigrams) ?? [:]
            selected = try values.decodeIfPresent([String: [String: Int]].self, forKey: .selected) ?? [:]
            automatic = try values.decodeIfPresent([String: [String: Int]].self, forKey: .automatic) ?? [:]
            rejected = try values.decodeIfPresent([String: [String: Int]].self, forKey: .rejected) ?? [:]
            let decodedTokens =
                try values.decodeIfPresent([String: VerbatimToken].self, forKey: .tokens) ?? [:]
            for token in decodedTokens.values.sorted(by: { $0.text < $1.text }) {
                mergeToken(
                    kind: token.kind, text: token.text, count: token.count, languageTag: token.languageTag)
            }
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let phones = try legacy.decodeIfPresent([String: LegacyPhone].self, forKey: .phones) ?? [:]
            for phone in phones.values.sorted(by: { $0.text < $1.text }) {
                mergeToken(kind: .phone, text: phone.text, count: phone.count, languageTag: phone.languageTag)
            }
            for tag in unigrams.keys.sorted() {
                for (word, count) in (unigrams[tag] ?? [:]).sorted(by: { $0.key < $1.key }) {
                    guard PersonalToken.isEmail(word) else { continue }
                    mergeToken(kind: .email, text: word, count: count, languageTag: tag)
                    unigrams[tag]?[word] = nil
                }
                if unigrams[tag]?.isEmpty == true { unigrams[tag] = nil }
            }
            for tag in bigrams.keys {
                bigrams[tag] = bigrams[tag]?.filter { pair in
                    pair.key.split(separator: "\u{1F}").allSatisfy {
                        PersonalToken.kind(of: String($0)) == nil
                    }
                }
            }
            for tag in selected.keys {
                selected[tag] = selected[tag]?.filter { PersonalToken.kind(of: $0.key) == nil }
            }
            for tag in automatic.keys {
                automatic[tag] = automatic[tag]?.filter { PersonalToken.kind(of: $0.key) == nil }
            }
            if tokens.count > 200 {
                tokens = Dictionary(
                    uniqueKeysWithValues: tokens.sorted {
                        $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
                    }.prefix(200).map { ($0.key, $0.value) })
            }
        }

        private mutating func mergeToken(
            kind: PersonalToken.Kind, text: String, count: Int, languageTag: String
        ) {
            guard count > 0, PersonalToken.kind(of: text) == kind,
                let key = PersonalLanguageModel.tokenKey(for: text, kind: kind)
            else { return }
            let total = min(max(tokens[key]?.count ?? 0, 0), 10_000) + min(count, 10_000)
            tokens[key] = VerbatimToken(
                kind: kind, text: tokens[key]?.text ?? text, count: min(total, 10_000),
                languageTag: tokens[key]?.languageTag ?? languageTag)
        }
    }

    private var store = Store()
    /// Rebuilt from the Hebrew half of `store` on first use after a mutation.
    /// Nil means "not built", not "empty".
    private var hebrewIndex: HebrewPersonalIndex?
    var hasCachedHebrewIndex: Bool { hebrewIndex != nil }
    /// The same shape `HebrewPersonalIndex.followersByPrevious` has, for every
    /// other language, built per language tag on first use after a mutation. A
    /// tag with no entry here is "not built", not "empty".
    private var followerIndexes: [String: [String: [(String, Int)]]] = [:]
    var hasCachedFollowerIndex: Bool { !followerIndexes.isEmpty }
    private let url: URL?
    private var pendingWrites = 0
    private var loadedGeneration = 0
    /// What the file looked like when `store` was decoded from it. See
    /// `FileStamp` and `reload()`.
    private var loadedStamp: FileStamp?

    /// Enough of the file's identity to answer "is this the same bytes I already
    /// decoded" without reading them.
    ///
    /// Size as well as time, because the two are independent and cheap: a
    /// modification that keeps the length has to move the clock, and a
    /// modification inside the clock's resolution has to be the same length to
    /// slip past. Both together is a `stat`, against a read-and-decode of the
    /// whole store.
    ///
    /// **What it cannot see** is a write that lands within the modification
    /// date's resolution — around 100 ns at this end of the epoch — and produces
    /// a file of exactly the same size. `save()` is `Data.write(options:
    /// .atomic)`, a create and a rename, so two of those from two processes are
    /// milliseconds apart at their closest. It is a real limit and not a
    /// reachable one.
    private struct FileStamp: Equatable {
        let modified: Date
        let size: Int
    }

    /// - Parameter url: where to persist. Defaults to the App Group container;
    ///   `nil` keeps the model entirely in memory, which is what tests and the
    ///   corpus harness use so a scoring run cannot inherit a developer's typing.
    init(url: URL? = PersonalLanguageModel.defaultURL) {
        self.url = url
        load()
    }

    /// `nonisolated` because it is the default argument of `init`, which is
    /// evaluated at the call site before any actor hop has happened. It touches no
    /// instance state, so there is nothing to isolate.
    nonisolated static var defaultURL: URL? {
        SharedContainer.url?.appendingPathComponent("PersonalLanguageModel.json")
    }

    // MARK: Reading

    /// How often this user has committed this word. Zero for one they never have.
    public func count(of word: String, in language: KeyboardLanguage) -> Int {
        if let kind = PersonalToken.kind(of: word), let key = Self.tokenKey(for: word, kind: kind) {
            return store.tokens[key]?.count ?? 0
        }
        return store.unigrams[language.languageTag]?[SeedLanguageModel.fold(word)] ?? 0
    }

    func observationCount(
        of word: String, in language: KeyboardLanguage, source: LearningSource
    ) -> Int {
        let key = SeedLanguageModel.fold(word)
        let tag = language.languageTag
        switch source {
        case .automatic:
            return store.automatic[tag]?[key] ?? 0
        case .selectedSuggestion:
            return store.selected[tag]?[key] ?? 0
        case .typed:
            return max((store.unigrams[tag]?[key] ?? 0) - (store.selected[tag]?[key] ?? 0), 0)
        }
    }

    /// Exact count everywhere except Hebrew, where attested clitic variants of a
    /// vouched stem add their counts together. Protection, Forget, and the
    /// dictionary list still read `count(of:)`.
    public func rankingCount(of word: String, in language: KeyboardLanguage) -> Int {
        let folded = SeedLanguageModel.fold(word)
        guard !folded.isEmpty else { return 0 }
        if Self.isVerbatimToken(word) { return count(of: word, in: language) }
        let observed =
            language.script == .hebrew
            ? currentHebrewIndex().rankingCount(of: folded) : count(of: folded, in: language)
        let selected = (store.selected[language.languageTag]?[folded] ?? 0) > 0
        return selected && !Self.isVerbatimToken(folded) ? max(observed, Self.boostThreshold) : observed
    }

    public func learnedWords() -> [LearnedWord] {
        var out: [LearnedWord] = []
        for (tag, counts) in store.unigrams {
            guard let language = KeyboardLanguage(languageTag: tag) else { continue }
            for (word, count) in counts {
                out.append(LearnedWord(word: word, count: count, language: language))
            }
        }
        out += store.tokens.values.compactMap { token in
            guard let language = KeyboardLanguage(languageTag: token.languageTag) else { return nil }
            return LearnedWord(word: token.text, count: token.count, language: language)
        }
        return out.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.language.displayName != $1.language.displayName {
                return $0.language.displayName < $1.language.displayName
            }
            return $0.word < $1.word
        }
    }

    /// Re-read the App Group file. The keyboard writes it; the app's in-memory
    /// copy is from launch and goes stale the moment you type elsewhere.
    /// A previously loaded file that disappears means empty: Forget deletes
    /// the file, and a keyboard that is still alive must drop the old counts.
    ///
    /// **A file that has not moved is not read again**, which is what takes the
    /// second full decode off the keyboard's cold launch path:
    /// `KeyboardController.init` constructs `.shared`, whose `init` decodes the
    /// store, and `KeyboardViewController.viewWillAppear` then calls this — two
    /// reads and two decodes of the same bytes before the first frame.
    ///
    /// **The file decides, never a clock, and that is the point.** The obvious
    /// version of this saving is "skip the reload when this is the instance's
    /// first appearance, since nothing can change in between", and that
    /// reasoning is unsound: iOS may build a keyboard extension's controller and
    /// present it much later, and the user genuinely can go and press Forget in
    /// the app inside that window. A stamp cannot be fooled by the length of the
    /// gap — if the app rewrote the file, the stamp moved, and this reads it.
    public func reload() {
        adoptClearIfNeeded()
        guard let url else { return }
        let stamp = Self.stamp(of: url)
        if let stamp, stamp == loadedStamp { return }
        if stamp == nil, loadedStamp == nil { return }
        guard let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Store.self, from: data)
        else {
            replaceStore(with: Store())
            pendingWrites = 0
            loadedStamp = nil
            return
        }
        replaceStore(with: decoded)
        loadedStamp = stamp
    }

    /// Whether the word is this user's own, firmly enough that autocorrect must
    /// not replace it.
    ///
    /// The threshold is what separates this from the personal dictionary, which is
    /// absolute because the user typed it into Settings by hand. This one is
    /// inferred, so it takes repetition before it earns the same protection.
    func isProtected(_ word: String, in language: KeyboardLanguage) -> Bool {
        if Self.isVerbatimToken(word) { return count(of: word, in: language) > 0 }
        return count(of: word, in: language) >= Self.protectThreshold
            || (store.selected[language.languageTag]?[SeedLanguageModel.fold(word)] ?? 0) > 0
    }

    func allWords(in language: KeyboardLanguage) -> [String] {
        guard let counts = store.unigrams[language.languageTag] else { return [] }
        return counts.filter { isReadable($0.key, count: $0.value, in: language) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
    }

    func words(startingWith prefix: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        let folded = SeedLanguageModel.fold(prefix)
        guard !folded.isEmpty, limit > 0 else { return [] }
        var matches: [(String, Int)] = (store.unigrams[language.languageTag] ?? [:]).filter {
            $0.key.hasPrefix(folded) && $0.key != folded && isReadable($0.key, count: $0.value, in: language)
        }.map { ($0.key, $0.value) }
        matches += verbatimTokens(startingWith: prefix, kind: .email, limit: limit).map {
            ($0, count(of: $0, in: language))
        }
        return Self.mostFrequent(matches, limit: limit)
    }

    /// Count first, then the word itself.
    ///
    /// The second half is not decoration: `sorted(by:)` is not stable and a
    /// dictionary has no order to inherit, so without a total tie-break two runs
    /// over one store can disagree about which word is slot 1 — the bar would
    /// shuffle under the user with nothing having changed.
    private static func mostFrequent(_ matches: [(String, Int)], limit: Int) -> [String] {
        matches
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func neighbours(of word: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        let folded = SeedLanguageModel.fold(word)
        guard folded.count >= 3, let counts = store.unigrams[language.languageTag] else {
            return []
        }
        let matches: [(String, Int)] = counts.compactMap { key, count in
            guard isReadable(key, count: count, in: language) else { return nil }
            guard SeedLanguageModel.isOneEditAway(key, of: folded) else { return nil }
            return (key, count)
        }
        return Self.mostFrequent(matches, limit: limit)
    }

    /// Words this user tends to write after this one, most often first.
    ///
    /// **Indexed rather than scanned, in every language, because this is asked
    /// once per word of the field on every keystroke.**
    /// `SuggestionEngine.contextFollowers` hands `followers(mentionedIn:)` every
    /// word in the document, so a linear `filter` over the stored bigrams — up to
    /// `bigramCap`, 12,000 pairs — was paid once per field word per letter typed.
    /// Hebrew has been reading `HebrewPersonalIndex.followersByPrevious`, a
    /// dictionary keyed by the previous word, since it was written; this gives the
    /// other languages the identical shape rather than a second mechanism.
    func followers(after word: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        let key = SeedLanguageModel.fold(word)
        guard !key.isEmpty else { return [] }
        if language.script == .hebrew {
            return currentHebrewIndex().followers(
                after: key, limit: limit, minimumCount: Self.boostThreshold)
        }
        let matches = currentFollowerIndex(for: language)[key] ?? []
        return matches.prefix(limit).map(\.0)
    }

    /// What this person writes after any of these words, later tokens first.
    ///
    /// The single-word lookup is what the last token uses. Walking the rest of
    /// the field is how `אני מגיע` still teaches `מגיע` when two more words
    /// have landed since `אני`.
    func followers(
        mentionedIn words: [String], in language: KeyboardLanguage, limit: Int
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for word in words.reversed() {
            for next in followers(after: word, in: language, limit: limit) {
                let key = SeedLanguageModel.fold(next)
                guard seen.insert(key).inserted else { continue }
                out.append(next)
                if out.count == limit { return out }
            }
        }
        return out
    }

    /// Joins the two halves of a pair key. A unit separator rather than a space,
    /// because `record` accepts a hyphen inside a word and a space would make
    /// `בלי־פרופ` ambiguous with a pair the moment the maqaf folded.
    private static let pairSeparator = "\u{1F}"

    private func currentHebrewIndex() -> HebrewPersonalIndex {
        if let hebrewIndex { return hebrewIndex }
        let tag = KeyboardLanguage.hebrew.languageTag
        let built = HebrewPersonalIndex(
            unigrams: store.unigrams[tag] ?? [:],
            bigrams: store.bigrams[tag] ?? [:],
            pairSeparator: Character(Self.pairSeparator))
        hebrewIndex = built
        return built
    }

    /// One language's bigrams as a lookup from the previous word to what follows
    /// it, already in `mostFrequent`'s order — count descending, then the word
    /// itself, because `sorted(by:)` is not stable and a dictionary has no order
    /// to inherit. The `boostThreshold` floor is applied while building, since it
    /// is a constant and every reader asks with it.
    private func currentFollowerIndex(for language: KeyboardLanguage) -> [String: [(String, Int)]] {
        let tag = language.languageTag
        if let cached = followerIndexes[tag] { return cached }
        let separator = Character(Self.pairSeparator)
        var built: [String: [(String, Int)]] = [:]
        for (pair, count) in store.bigrams[tag] ?? [:] where count >= Self.boostThreshold {
            let halves = pair.split(
                separator: separator, maxSplits: 1, omittingEmptySubsequences: false)
            guard halves.count == 2 else { continue }
            built[String(halves[0]), default: []].append((String(halves[1]), count))
        }
        for previous in built.keys {
            built[previous]?.sort { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
        }
        followerIndexes[tag] = built
        return built
    }

    private func invalidateHebrewIndex() {
        hebrewIndex = nil
    }

    /// Every language's, unconditionally, at each seam the Hebrew index is
    /// retired at. Which tags a write touched is knowable — `prune` alone can
    /// halve any of them — but keeping a second, finer answer to that question
    /// beside the Hebrew one is how two invalidation rules drift apart, and the
    /// whole cost of being wrong here is one rebuild.
    private func invalidateFollowerIndexes() {
        followerIndexes.removeAll()
    }

    private func replaceStore(with replacement: Store) {
        let tag = KeyboardLanguage.hebrew.languageTag
        let hebrewChanged =
            store.unigrams[tag] != replacement.unigrams[tag]
            || store.bigrams[tag] != replacement.bigrams[tag]
        store = replacement
        if hebrewChanged { invalidateHebrewIndex() }
        invalidateFollowerIndexes()
    }

    // MARK: Shape

    /// Marks that live inside a word rather than ending it: Hebrew's geresh and
    /// gershayim, the Catalan interpunct and Persian's zero-width non-joiner.
    /// `KeyboardController.staysInsideWord` answers the identical question of a
    /// single typed character; this asks it of a whole folded word instead, so
    /// the marks are held here as `Character`s rather than re-derived.
    private static let wordInternalMarks: Set<Character> = ["\u{05F3}", "\u{05F4}", "\u{00B7}", "\u{200C}"]

    /// A folded string made only of letters, apostrophe, hyphen or a mark that
    /// stays inside a word. What both halves of an ordinary unigram — the word
    /// itself and the one committed before it — have to satisfy before either
    /// is kept.
    private static func isLearnableOrdinaryWord(_ folded: String) -> Bool {
        folded.contains(where: \.isLetter)
            && folded.allSatisfy { $0.isLetter || $0 == "'" || $0 == "-" || wordInternalMarks.contains($0) }
    }

    nonisolated static func isVerbatimToken(_ text: String) -> Bool {
        PersonalToken.kind(of: text) != nil
    }

    private func isReadable(_ word: String, count: Int, in language: KeyboardLanguage) -> Bool {
        count >= Self.boostThreshold || (store.selected[language.languageTag]?[word] ?? 0) > 0
    }

    // MARK: Writing

    /// Remember a committed word, and the pair it makes with the one before it.
    ///
    /// - Parameters:
    ///   - word: the word as committed. Ordinary words are folded; structured
    ///     personal tokens retain their original text.
    ///   - previous: the word committed immediately before, if any.
    ///   - language: which language's counters this belongs in.
    ///   - permitted: whether recording is allowed at all right now. The caller
    ///     passes the answer rather than this asking, because the two things it
    ///     depends on — the user's setting and the focused field — both live in
    ///     `KeyboardController` and neither belongs in a store.
    /// - Returns: whether a count was actually written. Callers that debounce
    ///   repeats must not treat a refused write as a successful one.
    @discardableResult
    func record(
        word: String, previous: String?, language: KeyboardLanguage, permitted: Bool,
        source: LearningSource = .typed
    ) -> Bool {
        guard permitted, word.unicodeScalars.count <= 1024 else { return false }
        adoptClearIfNeeded()
        let folded = SeedLanguageModel.fold(word)

        if Self.isVerbatimToken(word) {
            return recordVerbatimToken(word, language: language, permitted: permitted, source: source)
        }
        guard (2...128).contains(folded.count), Self.isLearnableOrdinaryWord(folded)
        else { return false }
        let tag = language.languageTag
        switch source {
        case .automatic:
            store.automatic[tag, default: [:]][folded] = Self.incremented(store.automatic[tag]?[folded])
            if store.automatic[tag, default: [:]].count > Self.unigramCap {
                store.automatic[tag] = halved(store.automatic[tag] ?? [:], limit: Self.unigramCap)
            }
            pendingWrites += 1
            if pendingWrites >= Self.flushInterval { save() }
            return true
        case .selectedSuggestion:
            store.selected[tag, default: [:]][folded] = Self.incremented(store.selected[tag]?[folded])
        case .typed:
            break
        }

        store.unigrams[tag, default: [:]][folded] = Self.incremented(store.unigrams[tag]?[folded])
        if let previous {
            let before = SeedLanguageModel.fold(previous)
            if (2...128).contains(before.count), Self.isLearnableOrdinaryWord(before) {
                let key = before + Self.pairSeparator + folded
                store.bigrams[tag, default: [:]][key] = Self.incremented(store.bigrams[tag]?[key])
            }
        }

        let prunedHebrew = prune()
        if language.script == .hebrew || prunedHebrew { invalidateHebrewIndex() }
        invalidateFollowerIndexes()
        pendingWrites += 1
        if pendingWrites >= Self.flushInterval { save() }
        return true
    }

    @discardableResult
    func recordVerbatimToken(
        _ text: String, language: KeyboardLanguage, permitted: Bool,
        source: LearningSource = .typed
    ) -> Bool {
        guard permitted, source != .automatic, text.unicodeScalars.count <= 1024,
            let kind = PersonalToken.kind(of: text), let key = Self.tokenKey(for: text, kind: kind)
        else { return false }
        adoptClearIfNeeded()
        let display = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = VerbatimToken(
            kind: kind, text: display, count: Self.incremented(store.tokens[key]?.count),
            languageTag: language.languageTag)
        store.tokens[key] = token
        if store.tokens.count > 200 {
            let keep = store.tokens.filter { $0.key != key }.sorted {
                $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
            }.prefix(199)
            store.tokens = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            store.tokens[key] = token
        }
        save()
        return true
    }

    func verbatimTokens(startingWith prefix: String, kind: PersonalToken.Kind, limit: Int) -> [String] {
        adoptClearIfNeeded()
        guard limit > 0, let key = PersonalToken.completionKey(for: prefix, kind: kind)
        else { return [] }
        return store.tokens.values.filter { token in
            guard token.kind == kind, token.count > 0,
                let candidate = PersonalToken.key(for: token.text, kind: kind)
            else { return false }
            return candidate.hasPrefix(key) && candidate != key
        }.sorted {
            $0.count == $1.count ? $0.text < $1.text : $0.count > $1.count
        }.prefix(limit).map(\.text)
    }

    @discardableResult
    func recordPhoneNumber(
        _ text: String, language: KeyboardLanguage, permitted: Bool,
        source: LearningSource = .typed
    ) -> Bool {
        guard PersonalToken.kind(of: text) == .phone else { return false }
        return recordVerbatimToken(text, language: language, permitted: permitted, source: source)
    }

    func phoneNumbers(startingWith prefix: String, limit: Int) -> [String] {
        verbatimTokens(startingWith: prefix, kind: .phone, limit: limit)
    }

    nonisolated private static func tokenKey(for text: String, kind: PersonalToken.Kind) -> String? {
        guard let key = PersonalToken.key(for: text, kind: kind) else { return nil }
        return kind.rawValue + "\u{1F}" + key
    }

    func recordRejectedCorrection(
        original: String, replacement: String, language: KeyboardLanguage, permitted: Bool
    ) {
        guard permitted else { return }
        let original = SeedLanguageModel.fold(original)
        let replacement = SeedLanguageModel.fold(replacement)
        guard original != replacement, (2...128).contains(original.count),
            (2...128).contains(replacement.count),
            Self.isLearnableOrdinaryWord(original), Self.isLearnableOrdinaryWord(replacement)
        else { return }
        adoptClearIfNeeded()
        let tag = language.languageTag
        let key = original + Self.pairSeparator + replacement
        store.rejected[tag, default: [:]][key] = Self.incremented(store.rejected[tag]?[key], maximum: 100)
        if let pairs = store.rejected[tag], pairs.count > 512 {
            store.rejected[tag] = Dictionary(
                uniqueKeysWithValues: pairs.sorted {
                    $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
                }.prefix(512).map { ($0.key, $0.value) })
        }
        save()
    }

    func isRejectedCorrection(
        original: String, replacement: String, language: KeyboardLanguage
    ) -> Bool {
        adoptClearIfNeeded()
        let key = SeedLanguageModel.fold(original) + Self.pairSeparator + SeedLanguageModel.fold(replacement)
        return (store.rejected[language.languageTag]?[key] ?? 0) > 0
    }

    nonisolated static func normalizedPhonePrefix(_ text: String) -> String? {
        PhoneNumberToken.normalizedPrefix(text)
    }

    nonisolated static func isPhoneNumber(_ text: String) -> Bool {
        PhoneNumberToken.isComplete(text)
    }

    nonisolated static func phoneNumberSuffix(in context: String) -> String? {
        PhoneNumberToken.suffix(in: context)
    }

    /// Halve everything and drop what is left at one.
    ///
    /// Decay rather than eviction, so the store forgets gradually instead of
    /// falling off a cliff: a word the user typed constantly last year and never
    /// since fades out over a few prunes, and one they type every day survives
    /// every prune. Dropping the singletons is what actually reclaims the room —
    /// they are the long tail of typos and one-off names.
    private func prune() -> Bool {
        let hebrewTag = KeyboardLanguage.hebrew.languageTag
        var hebrewChanged = false
        for (tag, counts) in store.unigrams where counts.count > Self.unigramCap {
            store.unigrams[tag] = halved(counts, limit: Self.unigramCap)
            if tag == hebrewTag { hebrewChanged = true }
        }
        for (tag, counts) in store.selected where counts.count > Self.unigramCap {
            store.selected[tag] = halved(counts, limit: Self.unigramCap)
        }
        for (tag, counts) in store.bigrams where counts.count > Self.bigramCap {
            store.bigrams[tag] = halved(counts, limit: Self.bigramCap)
            if tag == hebrewTag { hebrewChanged = true }
        }
        return hebrewChanged
    }

    private static func incremented(_ count: Int?, maximum: Int = 10_000) -> Int {
        min(max(count ?? 0, 0), maximum - 1) + 1
    }

    private func halved(_ counts: [String: Int], limit: Int) -> [String: Int] {
        let decayed: [String: Int] = counts.reduce(into: [:]) { out, pair in
            let count = pair.value / 2
            if count >= 1 { out[pair.key] = count }
        }
        guard decayed.count > limit else { return decayed }
        return Dictionary(
            uniqueKeysWithValues: decayed.sorted {
                $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
            }.prefix(limit).map { ($0.key, $0.value) })
    }

    // MARK: Persistence

    /// The file's size and modification date, or nil if it is not there.
    ///
    /// **`FileManager.attributesOfItem` and never `URL.resourceValues`, and that
    /// was measured rather than reasoned about.** `URL` caches resource values on
    /// the `NSURL` behind it, and `url` here is a *stored* property read on every
    /// reload — so the first version of this returned the same stamp forever.
    /// Measured on macOS 2026-08-22: a rewrite that changed the file's length,
    /// read back through the same stored `URL`, produced a byte-identical stamp.
    /// That is a keyboard that never re-reads the file at all: Forget in the app
    /// would not reach a live keyboard, and a word learned in one process would
    /// never reach the other — the exact two defects `reload()` exists to
    /// prevent, reintroduced by the change meant to make it cheaper.
    ///
    /// `attributesOfItem(atPath:)` is a fresh `stat` on every call with no cache
    /// to go stale. Building a new `URL` per call was measured and works too;
    /// this is the one that does not require knowing why.
    private static func stamp(of url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let modified = attributes[.modificationDate] as? Date,
            let size = attributes[.size] as? Int
        else { return nil }
        return FileStamp(modified: modified, size: size)
    }

    private func load() {
        loadedGeneration = Self.generation
        guard let url, let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Store.self, from: data)
        else { return }
        replaceStore(with: decoded)
        loadedStamp = Self.stamp(of: url)
    }

    /// Write now. Called on every 25th word and by `KeyboardViewController` as the
    /// keyboard goes away, which is the only moment it is certain there is one.
    ///
    /// Re-stamps, because the bytes on disk are now the bytes in memory: without
    /// this every save would cost the next `reload()` a decode of what this
    /// process had just written.
    public func save() {
        pendingWrites = 0
        guard let url, let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(
            to: url,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        loadedStamp = Self.stamp(of: url)
    }

    /// Drop one word and the pairs it sat in. Saved now so a keyboard that
    /// reloads on appear does not put it back.
    public func forget(_ word: String, in language: KeyboardLanguage) {
        let folded = SeedLanguageModel.fold(word)
        guard !folded.isEmpty else { return }
        if let kind = PersonalToken.kind(of: word), let key = Self.tokenKey(for: word, kind: kind) {
            store.tokens[key] = nil
        }
        let tag = language.languageTag
        store.selected[tag]?[folded] = nil
        store.automatic[tag]?[folded] = nil
        store.rejected[tag] = store.rejected[tag]?.filter {
            !$0.key.hasPrefix(folded + Self.pairSeparator)
                && !$0.key.hasSuffix(Self.pairSeparator + folded)
        }
        let oldHebrewUnigrams =
            language.script == .hebrew ? store.unigrams[tag] : nil
        let oldHebrewBigrams =
            language.script == .hebrew ? store.bigrams[tag] : nil
        store.unigrams[tag]?[folded] = nil
        if store.unigrams[tag]?.isEmpty == true {
            store.unigrams[tag] = nil
        }
        if var pairs = store.bigrams[tag] {
            let head = folded + Self.pairSeparator
            let tail = Self.pairSeparator + folded
            pairs = pairs.filter { !$0.key.hasPrefix(head) && !$0.key.hasSuffix(tail) }
            store.bigrams[tag] = pairs.isEmpty ? nil : pairs
        }
        if language.script == .hebrew,
            oldHebrewUnigrams != store.unigrams[tag]
                || oldHebrewBigrams != store.bigrams[tag]
        {
            invalidateHebrewIndex()
        }
        // Unconditional, unlike the Hebrew index above: a follower list for any
        // language may have named this word, and a rebuild is cheaper than the
        // comparison that would decide whether one did.
        invalidateFollowerIndexes()
        save()
    }

    /// Forget everything. Personal dictionary's Forget.
    public func clear() {
        replaceStore(with: Store())
        pendingWrites = 0
        if let url { try? FileManager.default.removeItem(at: url) }
        // The file this stamp described is gone. Leaving it behind would let a
        // later `save()` and `reload()` pair agree that nothing had changed.
        loadedStamp = nil
        Self.generation += 1
        loadedGeneration = Self.generation
    }

    /// How many distinct words are remembered, for the line under the setting. A
    /// number the user can watch go up is the only honest way to show that a
    /// store they cannot read is doing something.
    public var learnedWordCount: Int {
        store.unigrams.values.reduce(0) { $0 + $1.count } + store.tokens.count
    }

    // MARK: Cross-process clearing

    /// Bumped by whichever process called `clear()`.
    ///
    /// The app and the keyboard hold separate instances of this class in separate
    /// processes, so "the user pressed Clear in Settings" has to reach a keyboard
    /// that may already be loaded. Same shape as `storedPersonalDictionary`: the
    /// value goes through the shared defaults and is read at the moment it
    /// matters, because the copy in memory was filled once and cannot know.
    private static var generation: Int {
        get { SharedContainer.userDefaults.integer(forKey: "personalModelGeneration") }
        set { SharedContainer.userDefaults.set(newValue, forKey: "personalModelGeneration") }
    }

    private func adoptClearIfNeeded() {
        let current = Self.generation
        guard current != loadedGeneration else { return }
        replaceStore(with: Store())
        pendingWrites = 0
        loadedGeneration = current
    }
}
