import Foundation

/// What this keyboard has learned about the person typing on it.
///
/// **This is the half that makes the bar fit somebody.** `SeedLanguageModel` is
/// the same few hundred words for every install; this one knows that *this* user
/// writes `Tzachi`, `standup` and `בלי־פרופ`, and that after `אני` they nearly
/// always write `מגיע`. Every keyboard that feels like it reads your mind is
/// doing this and not much else.
///
/// **What is stored, exactly.** Two counters: how often a word was committed, and
/// how often one word was committed directly after another. Nothing else. No
/// sentences, no message text, no field contents, no host app, no timestamps
/// beyond the file's own. A word pair is the longest thing that exists in here,
/// which is the line drawn when this was designed: pairs are what next-word
/// prediction needs and are short enough that the store cannot be read back as
/// anything the user wrote.
///
/// **Where it is not written.** Nothing is recorded while the focused field is a
/// credential field — the same question `SecureField` already answers for screen
/// reads, asked again here because "may I keep this word" and "may I send this
/// screen" have the same answer for a password. Nothing is recorded when the user
/// has turned learning off. And nothing leaves the device: the file lives in the
/// App Group container, which is also why it needs Full Access, and there is no
/// code path that uploads it.
///
/// **Counts are thresholds, not truth.** A word seen once may be a typo, and a
/// keyboard that learned typos and then defended them would be worse than one
/// that learned nothing. So a word has to be seen twice before it changes any
/// ranking and three times before it is protected from autocorrect.
@MainActor
public final class PersonalLanguageModel {

    /// The keyboard's instance. The app reaches the same store through
    /// `SharedStore` for the count and the clear button, and the two processes are
    /// never writing at the same time — iOS does not run the keyboard while the
    /// app is foregrounded — but `generation` covers the case where they were.
    public static let shared = PersonalLanguageModel()

    /// Seen this many times before it influences ranking.
    static let boostThreshold = 2
    /// Seen this many times before autocorrect must leave it alone.
    static let protectThreshold = 3

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

    private struct Store: Codable {
        var unigrams: [String: [String: Int]] = [:]
        var bigrams: [String: [String: Int]] = [:]
    }

    private var store = Store()
    private let url: URL?
    private var pendingWrites = 0
    private var loadedGeneration = 0

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
        store.unigrams[language.languageTag]?[SeedLanguageModel.fold(word)] ?? 0
    }

    /// Whether the word is this user's own, firmly enough that autocorrect must
    /// not replace it.
    ///
    /// The threshold is what separates this from the personal dictionary, which is
    /// absolute because the user typed it into Settings by hand. This one is
    /// inferred, so it takes repetition before it earns the same protection.
    func isProtected(_ word: String, in language: KeyboardLanguage) -> Bool {
        count(of: word, in: language) >= Self.protectThreshold
    }

    /// Every word this person has typed often enough to count, most typed first.
    ///
    /// Exists for `GroupedDecoder`, which has to *enumerate* a vocabulary rather
    /// than ask about one word or one prefix: a grouped keystroke is a set of
    /// possible prefixes, so the decoder indexes the whole list up front. Gated on
    /// `boostThreshold` for the same reason `words(startingWith:)` is — one
    /// accidental typing of a non-word should not put it in the dictionary that
    /// decides what other keystrokes mean.
    func allWords(in language: KeyboardLanguage) -> [String] {
        guard let counts = store.unigrams[language.languageTag] else { return [] }
        return counts.filter { $0.value >= Self.boostThreshold }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
    }

    /// Learned words starting with this prefix, most typed first.
    func words(startingWith prefix: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        let folded = SeedLanguageModel.fold(prefix)
        guard !folded.isEmpty, let counts = store.unigrams[language.languageTag] else { return [] }
        let matches: [(String, Int)] = counts.filter {
            $0.key.hasPrefix(folded) && $0.key != folded && $0.value >= Self.boostThreshold
        }
        .map { ($0.key, $0.value) }
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

    /// Words this user tends to write after this one, most often first.
    func followers(after word: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        let key = SeedLanguageModel.fold(word)
        guard !key.isEmpty, let counts = store.bigrams[language.languageTag] else { return [] }
        let head = key + Self.pairSeparator
        let matches: [(String, Int)] = counts.filter {
            $0.key.hasPrefix(head) && $0.value >= Self.boostThreshold
        }
        .map { (String($0.key.dropFirst(head.count)), $0.value) }
        return Self.mostFrequent(matches, limit: limit)
    }

    /// Joins the two halves of a pair key. A unit separator rather than a space,
    /// because `record` accepts a hyphen inside a word and a space would make
    /// `בלי־פרופ` ambiguous with a pair the moment the maqaf folded.
    private static let pairSeparator = "\u{1F}"

    // MARK: Writing

    /// Remember a committed word, and the pair it makes with the one before it.
    ///
    /// - Parameters:
    ///   - word: the word as committed. Folded before storage, so the store never
    ///     holds the user's capitalisation.
    ///   - previous: the word committed immediately before, if any.
    ///   - language: which language's counters this belongs in.
    ///   - permitted: whether recording is allowed at all right now. The caller
    ///     passes the answer rather than this asking, because the two things it
    ///     depends on — the user's setting and the focused field — both live in
    ///     `KeyboardController` and neither belongs in a store.
    func record(
        word: String, previous: String?, language: KeyboardLanguage, permitted: Bool
    ) {
        guard permitted else { return }
        adoptClearIfNeeded()
        let folded = SeedLanguageModel.fold(word)
        // Two letters is the floor. Single characters carry no signal and every
        // stray keystroke would land in the store; anything with a digit or a
        // symbol in it is a code, a price or an address and is exactly the kind of
        // thing this must not keep.
        guard folded.count >= 2, folded.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" })
        else { return }

        store.unigrams[language.languageTag, default: [:]][folded, default: 0] += 1
        if let previous {
            let before = SeedLanguageModel.fold(previous)
            if !before.isEmpty, before.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }) {
                let key = before + Self.pairSeparator + folded
                store.bigrams[language.languageTag, default: [:]][key, default: 0] += 1
            }
        }

        prune()
        pendingWrites += 1
        if pendingWrites >= Self.flushInterval { save() }
    }

    /// Halve everything and drop what is left at one.
    ///
    /// Decay rather than eviction, so the store forgets gradually instead of
    /// falling off a cliff: a word the user typed constantly last year and never
    /// since fades out over a few prunes, and one they type every day survives
    /// every prune. Dropping the singletons is what actually reclaims the room —
    /// they are the long tail of typos and one-off names.
    private func prune() {
        for (tag, counts) in store.unigrams where counts.count > Self.unigramCap {
            store.unigrams[tag] = halved(counts)
        }
        for (tag, counts) in store.bigrams where counts.count > Self.bigramCap {
            store.bigrams[tag] = halved(counts)
        }
    }

    private func halved(_ counts: [String: Int]) -> [String: Int] {
        counts.reduce(into: [:]) { out, pair in
            let decayed = pair.value / 2
            if decayed >= 1 { out[pair.key] = decayed }
        }
    }

    // MARK: Persistence

    private func load() {
        loadedGeneration = Self.generation
        guard let url, let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode(Store.self, from: data)
        else { return }
        store = decoded
    }

    /// Write now. Called on every 25th word and by `KeyboardViewController` as the
    /// keyboard goes away, which is the only moment it is certain there is one.
    public func save() {
        pendingWrites = 0
        guard let url, let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Forget everything. The Settings screen's "Clear what it learned".
    public func clear() {
        store = Store()
        pendingWrites = 0
        if let url { try? FileManager.default.removeItem(at: url) }
        Self.generation += 1
        loadedGeneration = Self.generation
    }

    /// How many distinct words are remembered, for the line under the setting. A
    /// number the user can watch go up is the only honest way to show that a
    /// store they cannot read is doing something.
    public var learnedWordCount: Int {
        store.unigrams.values.reduce(0) { $0 + $1.count }
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
        store = Store()
        pendingWrites = 0
        loadedGeneration = current
    }
}
