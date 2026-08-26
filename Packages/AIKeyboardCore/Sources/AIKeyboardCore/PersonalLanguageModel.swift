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
/// anything the user wrote. **One shape is kept verbatim rather than as a run of
/// letters: an email address** (`PersonalLanguageModel.isVerbatimToken`), because
/// a keyboard that cannot learn the one string its owner retypes every day is not
/// doing this file's job. It earns no pair — the bigram half is skipped outright
/// for it, since an address commonly follows a sentence with nothing in common
/// with what usually follows it — and it earns no ranking at all short of
/// `protectThreshold` sightings, not `boostThreshold`: a pasted address seen once
/// or twice must stay out of the bar. Ordinary words also carry a short, fixed
/// list of marks that sit *inside* a word rather than ending it — Hebrew's geresh
/// and gershayim, the Catalan interpunct, Persian's zero-width non-joiner — the
/// same marks `KeyboardController.staysInsideWord` already answers for a typed
/// character, so a word reached through the accents popup (`צ׳יפס`, `col·legi`)
/// is one this store can keep too, on both sides of a pair.
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
/// ranking and three times before it is protected from autocorrect. A verbatim
/// token skips the first floor: it needs the three-sighting one from the start,
/// because there is no ranking use for an address that has been typed once.
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

    private struct Store: Codable {
        var unigrams: [String: [String: Int]] = [:]
        var bigrams: [String: [String: Int]] = [:]
    }

    private var store = Store()
    /// Rebuilt from the Hebrew half of `store` on first use after a mutation.
    /// Nil means "not built", not "empty".
    private var hebrewIndex: HebrewPersonalIndex?
    var hasCachedHebrewIndex: Bool { hebrewIndex != nil }
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
        store.unigrams[language.languageTag]?[SeedLanguageModel.fold(word)] ?? 0
    }

    /// Exact count everywhere except Hebrew, where attested clitic variants of a
    /// vouched stem add their counts together. Protection, Forget, and the
    /// dictionary list still read `count(of:)`.
    public func rankingCount(of word: String, in language: KeyboardLanguage) -> Int {
        let folded = SeedLanguageModel.fold(word)
        guard !folded.isEmpty else { return 0 }
        guard language.script == .hebrew else { return count(of: folded, in: language) }
        return currentHebrewIndex().rankingCount(of: folded)
    }

    /// Every stored word, including those seen once. Personal dictionary shows
    /// these so the user can see what the store holds before Forget. Ranking
    /// still ignores count below `boostThreshold` — `protectThreshold` for a
    /// verbatim token such as an email — and every other read surface stays
    /// gated the same way.
    public func learnedWords() -> [LearnedWord] {
        var out: [LearnedWord] = []
        for (tag, counts) in store.unigrams {
            guard let language = KeyboardLanguage(languageTag: tag) else { continue }
            for (word, count) in counts {
                out.append(LearnedWord(word: word, count: count, language: language))
            }
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
    /// A missing file is empty, not "keep what we had": Forget deletes the
    /// file, and a keyboard that is still alive must drop the old counts.
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
    ///
    /// An absent file is deliberately **not** an early return. Its stamp is nil,
    /// the `if let` below fails, and the reset runs — which is the Forget case
    /// the paragraph above is about.
    public func reload() {
        loadedGeneration = Self.generation
        guard let url else { return }
        let stamp = Self.stamp(of: url)
        if let stamp, stamp == loadedStamp { return }
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
        count(of: word, in: language) >= Self.protectThreshold
    }

    /// Every word this person has typed often enough to count, most typed first.
    ///
    /// Exists for `GroupedDecoder`, which has to *enumerate* a vocabulary rather
    /// than ask about one word or one prefix: a grouped keystroke is a set of
    /// possible prefixes, so the decoder indexes the whole list up front. Gated on
    /// `readThreshold` for the same reason `words(startingWith:)` is — one
    /// accidental typing of a non-word should not put it in the dictionary that
    /// decides what other keystrokes mean, and a paste seen once or twice should
    /// not either.
    func allWords(in language: KeyboardLanguage) -> [String] {
        guard let counts = store.unigrams[language.languageTag] else { return [] }
        return counts.filter { $0.value >= Self.readThreshold(for: $0.key) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map(\.key)
    }

    /// Learned words starting with this prefix, most typed first.
    ///
    /// Gated on `boostThreshold`, except a verbatim token — today only an email
    /// — which needs `protectThreshold` sightings before it is handed back: a
    /// paste read once or twice must not reach the bar. See `readThreshold`.
    func words(startingWith prefix: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        let folded = SeedLanguageModel.fold(prefix)
        guard !folded.isEmpty, let counts = store.unigrams[language.languageTag] else { return [] }
        let matches: [(String, Int)] = counts.filter {
            $0.key.hasPrefix(folded) && $0.key != folded && $0.value >= Self.readThreshold(for: $0.key)
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

    /// Learned words one edit from this typo, most typed first.
    ///
    /// The seed neighbour list cannot see a name this person writes. Same
    /// distance and "never shorter" rules as `SeedLanguageModel.neighbours`,
    /// and the same floor `words(startingWith:)` reads by — two sightings for
    /// an ordinary word, three for a verbatim one — so one slip does not become
    /// a dictionary and a pasted address does not become a "did you mean".
    func neighbours(of word: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        let folded = SeedLanguageModel.fold(word)
        guard folded.count >= 3, let counts = store.unigrams[language.languageTag] else {
            return []
        }
        let matches: [(String, Int)] = counts.compactMap { key, count in
            guard count >= Self.readThreshold(for: key) else { return nil }
            guard SeedLanguageModel.isOneEditAway(key, of: folded) else { return nil }
            return (key, count)
        }
        return Self.mostFrequent(matches, limit: limit)
    }

    /// Words this user tends to write after this one, most often first.
    func followers(after word: String, in language: KeyboardLanguage, limit: Int) -> [String] {
        let key = SeedLanguageModel.fold(word)
        guard !key.isEmpty else { return [] }
        if language.script == .hebrew {
            return currentHebrewIndex().followers(
                after: key, limit: limit, minimumCount: Self.boostThreshold)
        }
        guard let counts = store.bigrams[language.languageTag] else { return [] }
        let head = key + Self.pairSeparator
        let matches: [(String, Int)] = counts.filter {
            $0.key.hasPrefix(head) && $0.value >= Self.boostThreshold
        }
        .map { (String($0.key.dropFirst(head.count)), $0.value) }
        return Self.mostFrequent(matches, limit: limit)
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

    private func invalidateHebrewIndex() {
        hebrewIndex = nil
    }

    private func replaceStore(with replacement: Store) {
        let tag = KeyboardLanguage.hebrew.languageTag
        let hebrewChanged =
            store.unigrams[tag] != replacement.unigrams[tag]
            || store.bigrams[tag] != replacement.bigrams[tag]
        store = replacement
        if hebrewChanged { invalidateHebrewIndex() }
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
        folded.allSatisfy { $0.isLetter || $0 == "'" || $0 == "-" || wordInternalMarks.contains($0) }
    }

    /// Whether a folded token has the shape of an email address — the one
    /// string this store learns verbatim rather than as a run of letters.
    ///
    /// Exactly one `@`; a non-empty local part of letters, digits, `.`, `_`,
    /// `%`, `+` or `-`; a domain of one or more dot-separated labels of letters,
    /// digits or `-`, the last of which is at least two letters. That last
    /// clause is what keeps a half-typed `nitai@gmail` out — there is no dot yet
    /// for a domain to end on — and it is what a pure digit string, a price and
    /// a URL carrying a `/` all fail on their own terms, before this is even
    /// asked: none of them has an `@` in it at all.
    ///
    /// **Two things this shape allows on purpose, named so a later reader does
    /// not mistake them for gaps.** The local part is a character-class test
    /// with no adjacency rule, so `nitai..name@gmail.com` passes — this is the
    /// stated set, not RFC 5321's stricter grammar, because the only job here
    /// is telling an address apart from a price or a code, not validating one
    /// a mail server would accept. And a domain or TLD letter is anything
    /// `Character.isLetter` calls a letter, so `café.fr` and a Hebrew domain
    /// both pass — an IDN reading rather than the ASCII-only, punycode-encoded
    /// domains DNS actually carries, chosen because folding non-Latin scripts
    /// out of a shape test would refuse an address this keyboard's own Hebrew
    /// typists are exactly the ones who might have.
    ///
    /// `nonisolated` because it touches no instance state and
    /// `SuggestionEngine.matchCaseUnlessVerbatim` needs to ask it from outside
    /// this actor's isolation, the same reason `defaultURL` above is.
    nonisolated static func isVerbatimToken(_ folded: String) -> Bool {
        let halves = folded.split(separator: "@", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return false }
        let local = halves[0]
        let localMarks: Set<Character> = [".", "_", "%", "+", "-"]
        guard !local.isEmpty,
            local.allSatisfy({ $0.isLetter || $0.isNumber || localMarks.contains($0) })
        else { return false }

        let labels = halves[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
            labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) }),
            let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter)
        else { return false }
        return true
    }

    /// The sighting floor a stored word needs before a read surface may hand it
    /// back. An ordinary word crosses at `boostThreshold`; a verbatim token
    /// needs `protectThreshold` — the same floor autocorrect already asks of it
    /// — so a paste seen once or twice stays out of every reader alike.
    private static func readThreshold(for folded: String) -> Int {
        isVerbatimToken(folded) ? protectThreshold : boostThreshold
    }

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
    /// - Returns: whether a count was actually written. Callers that debounce
    ///   repeats must not treat a refused write as a successful one.
    @discardableResult
    func record(
        word: String, previous: String?, language: KeyboardLanguage, permitted: Bool
    ) -> Bool {
        guard permitted else { return false }
        adoptClearIfNeeded()
        let folded = SeedLanguageModel.fold(word)

        // **The one verbatim shape this store keeps, and the only one.** An
        // email address is not a word by the character-class rule below — it
        // carries a digit-bearing domain and an `@` no ordinary word has — so it
        // takes a shape check instead, and it is stored on its own terms: no
        // ranking floor below `protectThreshold`, and no bigram half at all. A
        // word pair exists to teach next-word prediction, and an address
        // commonly follows a sentence with nothing in particular in common with
        // what usually follows it, so writing that pair would buy nothing and
        // would be one more fragment of what the user typed sitting in the file.
        if Self.isVerbatimToken(folded) {
            store.unigrams[language.languageTag, default: [:]][folded, default: 0] += 1
            let prunedHebrew = prune()
            if language.script == .hebrew || prunedHebrew { invalidateHebrewIndex() }
            pendingWrites += 1
            if pendingWrites >= Self.flushInterval { save() }
            return true
        }

        // Two letters is the floor. Single characters carry no signal and every
        // stray keystroke would land in the store. Letters, apostrophe and
        // hyphen, plus the marks a word can carry *inside* it without ending —
        // Hebrew's geresh and gershayim (`צ׳יפס`, `צה״ל`), the Catalan interpunct
        // (`col·legi`) and Persian's zero-width non-joiner — the same marks
        // `KeyboardController.staysInsideWord` already answers for, because a
        // word reached through the accents popup is still a word. Anything else
        // — a digit outside the email shape above, a slash, most other symbols —
        // is a code, a price or a URL, and is exactly the kind of thing this
        // must not keep.
        guard folded.count >= 2, Self.isLearnableOrdinaryWord(folded)
        else { return false }

        store.unigrams[language.languageTag, default: [:]][folded, default: 0] += 1
        if let previous {
            let before = SeedLanguageModel.fold(previous)
            if !before.isEmpty, Self.isLearnableOrdinaryWord(before) {
                let key = before + Self.pairSeparator + folded
                store.bigrams[language.languageTag, default: [:]][key, default: 0] += 1
            }
        }

        let prunedHebrew = prune()
        if language.script == .hebrew || prunedHebrew { invalidateHebrewIndex() }
        pendingWrites += 1
        if pendingWrites >= Self.flushInterval { save() }
        return true
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
            store.unigrams[tag] = halved(counts)
            if tag == hebrewTag { hebrewChanged = true }
        }
        for (tag, counts) in store.bigrams where counts.count > Self.bigramCap {
            store.bigrams[tag] = halved(counts)
            if tag == hebrewTag { hebrewChanged = true }
        }
        return hebrewChanged
    }

    private func halved(_ counts: [String: Int]) -> [String: Int] {
        counts.reduce(into: [:]) { out, pair in
            let decayed = pair.value / 2
            if decayed >= 1 { out[pair.key] = decayed }
        }
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
        try? data.write(to: url, options: .atomic)
        loadedStamp = Self.stamp(of: url)
    }

    /// Drop one word and the pairs it sat in. Saved now so a keyboard that
    /// reloads on appear does not put it back.
    public func forget(_ word: String, in language: KeyboardLanguage) {
        let folded = SeedLanguageModel.fold(word)
        guard !folded.isEmpty else { return }
        let tag = language.languageTag
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
        replaceStore(with: Store())
        pendingWrites = 0
        loadedGeneration = current
    }
}
