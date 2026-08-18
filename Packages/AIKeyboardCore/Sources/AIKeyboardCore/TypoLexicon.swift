import Foundation
import os

/// The frequency half of the noisy-channel typo corrector: which of the
/// commonest words in a language the keystrokes somebody just typed could
/// plausibly be a slip of, ranked by how common the word is and how cheap the
/// slip would have to be.
///
/// **Why a rank-limited list rather than the full 50,000-word
/// `GroupedLexiconResource`.** `TypoChannel.cost` is only worth paying for a
/// word common enough that a person would plausibly reach for it, and asking
/// whether every one of 50,000 forms is a plausible slip of four or five
/// keystrokes is both slower than a keyboard's keystroke budget allows and
/// answers a question nobody asked — the tail of that list is the kind of
/// thing `.claude/rules/suggestion-bar.md` measured and rejected as a ranking
/// source for exactly this reason (`.claude/rules/suggestion-bar.md`'s "the
/// Hebrew frequency data was then found, measured, and does not work"
/// entry). `depth` draws the line at a smaller, still generous, common core.
///
/// **Compact by construction, not by afterthought.** A keyboard extension is
/// memory-capped, and `depth` words held as `[[Character]]` would be
/// megabytes of nothing — a Swift `Character` is a 16-byte grapheme cluster
/// box, and 30,000 words averaging five letters each is 150,000 of them. The
/// characters live in one flat `[UInt16]` instead, sliced by an `[Int32]` of
/// offsets, so looking up a word's characters is a slice into shared storage
/// rather than an allocation. The one concession is `originals: [String]`,
/// kept because a caller putting a correction in the suggestion bar needs an
/// actual spelling to draw, and boxing 30,000 short strings is a cost this
/// file accepts rather than a cost it was built to avoid.
enum TypoLexicon {

    /// How far down the frequency list this reads. Beyond it a word is not
    /// common enough to be worth rewriting somebody's keystrokes for — the
    /// same judgement `SeedLanguageModel.neighbours` and
    /// `SeedLanguageModel.knows` already make by only ever answering about
    /// words in a bounded list, just drawn from `GroupedLexiconResource`'s
    /// much larger frequency order instead of the hand-authored seed.
    /// **30,000 because that is where the words stop, measured, and not because
    /// it is a round number.** This was 12,000, and against a corpus of 128 real
    /// misspellings that window cut off ordinary Hebrew: `משכורת` ("salary") is
    /// rank 15,017, `מסעדה` ("restaurant") 15,384, `לפגישה` ("to the meeting")
    /// 15,769, `הפתעה` ("surprise") 16,588, `מהעבודה` ("from work") 21,876 and
    /// `שהילדים` ("that the children") 27,758. None of those is a rare word, and
    /// with each one outside the window the corrector reached past it for the
    /// commonest word still inside — which is how `שהילדימ` came to be corrected
    /// to `הילדים`, deleting the `ש` rather than fixing the final mem.
    ///
    /// **The reason a Hebrew window has to be so much deeper than an English one
    /// is the language rather than the corpus.** These lists are 50,000 *word
    /// forms*, and Hebrew inflects and glues its clitics onto the front of the
    /// next word, so one English lemma's worth of vocabulary is spread over many
    /// more Hebrew rows: `עבודה`, `לעבודה`, `בעבודה`, `מהעבודה` and `העבודה` are
    /// five rows here and one word to a reader. 50,000 English forms is most of
    /// the language; 50,000 Hebrew forms is not.
    ///
    /// It is still a window and not the whole list, because everything past it is
    /// the tail this repo has already measured and rejected as a source
    /// (`.claude/rules/suggestion-bar.md`, "the Hebrew frequency data was then
    /// found, measured, and does not work"). `isWord` reads all 50,000; only what
    /// may be *offered* is bounded here.
    ///
    /// **English keeps the shallower window, and that is the same argument
    /// rather than an exception to it.** The depth a language needs is set by how
    /// far down its list the ordinary words run, and 50,000 English forms is most
    /// of the language where 50,000 Hebrew forms is not. Measured: every English
    /// target in the typo corpus is reachable at 12,000, and taking English to
    /// 30,000 bought nothing and cost a real over-correction — `yjis` committed
    /// `iiis`, which is rank 27,182 and is Wikipedia's abbreviation noise rather
    /// than a word anybody types. The tail this window exists to exclude is
    /// simply nearer the front in English.
    static func depth(for language: KeyboardLanguage) -> Int {
        language.script == .hebrew ? 30_000 : 12_000
    }

    struct Correction {
        let word: String
        /// Position in the frequency list, 0 commonest.
        let rank: Int
        /// `TypoChannel.cost` for this word against the keystrokes asked about.
        let cost: Int
    }

    /// Rank among the commonest `depth` forms; `nil` for anything rarer or
    /// absent from the bundled list.
    static func rank(of word: String, in language: KeyboardLanguage) -> Int? {
        block(for: language).ranks[SeedLanguageModel.fold(word)]
    }

    /// Whether this word appears anywhere in the bundled list, all 50,000
    /// forms — a different question from `rank`, and the one that has to be
    /// asked before a word is ever rewritten.
    ///
    /// **`rank` only looks at the commonest `depth` words, the ones worth
    /// rewriting keystrokes *into*; this looks at the whole list, because the
    /// question of whether a word must never be rewritten *out of* cannot be
    /// bounded the same way.** A word can be perfectly ordinary and still
    /// rank outside `depth` — `truancy` sits at rank 37,999 in the bundled
    /// English list, well past `depth`'s 30,000, and is no less a real word
    /// for it. `rank(of:)` alone answers `nil` for it and says nothing about
    /// whether it is safe to rewrite.
    ///
    /// **This is the second dictionary `.claude/rules/suggestion-bar.md`'s
    /// "two dictionaries have to disown a word before it is replaced" rule
    /// has never actually had.** The seed list is 353 hand-authored words, so
    /// `SeedLanguageModel.knows` answers no about most of the language —
    /// `cat` is not one of the 353, `car` is, and `SeedLanguageModel
    /// .neighbours`'s own doc comment names exactly this gap: absence from a
    /// few hundred words proves nothing, and the first version of that
    /// neighbour rule, trusting only the seed list, quietly turned a typed
    /// `cat` into a committed `car`. `cat` is a real, ordinary English word —
    /// rank 5,234 in the bundled list, comfortably inside `depth` too, so
    /// this case would have been caught even by a membership check bounded
    /// to `depth`. What forces reading the *whole* list is `truancy` above:
    /// a word past `depth` still has to be recognised as a word, or
    /// `isWord` would be exactly as blind as `rank(of:) != nil` and not worth
    /// having as a second function at all.
    ///
    /// **A `Set<String>`, not a `Set<UInt64>` of hashes.** Hashing would
    /// roughly halve the memory this costs, but a collision would silently
    /// declare a typo to be a real word with nothing anywhere to catch it —
    /// this set exists to *stop* a rewrite, and a false "yes" here is a
    /// keyboard that quietly stops correcting a typo for a reason nobody
    /// could diagnose. Most Hebrew and English entries are short enough to
    /// live inside Swift's small-string inline buffer (15 bytes, no heap
    /// allocation), so the whole set is roughly a megabyte rather than
    /// 50,000 separate heap boxes. Built lazily, once per language, in the
    /// same shape `block(for:)` below already uses — a monolingual install
    /// only ever pays for the one language it types in.
    static func isWord(_ word: String, in language: KeyboardLanguage) -> Bool {
        block(for: language).allForms.contains(SeedLanguageModel.fold(word))
    }

    /// Common words the typed keystrokes could plausibly be a slip of, best
    /// first. Empty when the word is too short for `TypoChannel.budget` to
    /// allow a correction, when the language has no bundled list, or when
    /// nothing in the list is within reach.
    static func corrections(of word: String, in language: KeyboardLanguage, limit: Int) -> [Correction] {
        guard let budget = TypoChannel.budget(forTypedLength: word.count) else { return [] }
        let block = block(for: language)
        guard !block.originals.isEmpty else { return [] }

        // The same bound `TypoChannel.cost` bands its own search by: an
        // insertion or a deletion is the only kind of edit that changes how
        // many letters a word has, and the cheapest either one can ever cost
        // is `TypoChannel.minimumIndelCost`. A budget that could not afford
        // even one such edit at the length difference on offer cannot afford
        // the rest of the correction either, so there is no reason to ask
        // `TypoChannel.cost` about it.
        let maxEdits = budget / TypoChannel.minimumIndelCost

        let typedFolded = Array(SeedLanguageModel.fold(word))
        let typedChars = Array(word)
        let typedMask = mask(of: typedFolded, using: block.letterBits)

        var survivors: [(index: Int, cost: Int)] = []
        survivors.reserveCapacity(limit)
        for index in block.originals.indices {
            let start = Int(block.offsets[index])
            let end = Int(block.offsets[index + 1])
            let lengthDiff = (end - start) - typedFolded.count

            // Never propose a correction more than one letter shorter than
            // what was typed. Copied from `SeedLanguageModel.neighbours`:
            // every prefix is a word in progress, so a much shorter
            // "correction" is a proposal to delete keys the user just
            // deliberately pressed. One shorter is still allowed, because
            // that is exactly the shape of dropping a doubled letter or a
            // mater lectionis — the cases `TypoChannel`'s deletion table
            // exists for.
            guard lengthDiff >= -1, abs(lengthDiff) <= maxEdits else { continue }

            // Every edit can move at most two bits of the letter bitmask —
            // the letter it removes, the letter it adds — so a popcount
            // above `2 * maxEdits` proves the word is out of reach without
            // ever running the DP in `TypoChannel.cost`. One XOR and one
            // `nonzeroBitCount` is what makes scanning `depth` words on a
            // keystroke affordable.
            let differingBits = (typedMask ^ block.masks[index]).nonzeroBitCount
            guard differingBits <= 2 * maxEdits else { continue }

            let candidateChars = characters(at: index, in: block)
            guard
                let cost = TypoChannel.cost(
                    typed: typedChars, candidate: candidateChars, language: language, budget: budget)
            else { continue }
            survivors.append((index, cost))
        }

        // Lower wins, and the two terms are the two halves of a noisy channel:
        // ranking by which word the person most likely meant is minimising
        // `-log P(typed | intended) - log P(intended)`. `cost` is the first
        // term already. The second is a prior over words, and word frequencies
        // are Zipfian — `P` falls off roughly as `1 / rank` — so it is
        // proportional to **log(rank)**, never to rank itself.
        //
        // **It was linear, `min(120, rank / 100)`, and both halves of that were
        // wrong in ways the typo corpus could see.** It saturated: every word
        // past rank 12,000 paid the identical maximum, so across most of a
        // 30,000-word window frequency stopped discriminating at all. And
        // inside the window it was far too steep — a rank gap of 12,000 bought
        // 120 points against `cost` quanta that differ by as little as 5, so
        // the prior routinely overruled the channel. `הפטעה` was corrected to
        // `הפרעה`, a whole substitution more expensive than `הפתעה`, purely on
        // rank.
        //
        // `7 * log2(1 + rank)` fixes the shape and sets the scale by one
        // question: what should being the commonest word in the language rather
        // than the rarest one in the window be worth? One ordinary edit, and no
        // more — `log2(30000)` is about 14.9, and `7 * 14.9` is about 104,
        // just over `TypoChannel.plainEdit`. So frequency can settle a tie
        // between two equally plausible slips and can never buy a wilder one.
        // No cap is needed, because a logarithm is already the shape a cap was
        // being used to fake.
        survivors.sort {
            let leftScore = $0.cost + frequencyPenalty(rank: $0.index)
            let rightScore = $1.cost + frequencyPenalty(rank: $1.index)
            return leftScore == rightScore
                ? block.originals[$0.index] < block.originals[$1.index]
                : leftScore < rightScore
        }

        return survivors.prefix(limit).map {
            Correction(word: block.originals[$0.index], rank: $0.index, cost: $0.cost)
        }
    }

    /// `-log P(word)` for a Zipfian prior, in the same units `TypoChannel`
    /// prices edits in. See the sort in `corrections(of:in:limit:)` for the
    /// derivation and for what the 7 is set by.
    private static func frequencyPenalty(rank: Int) -> Int {
        Int((7 * log2(1 + Double(rank))).rounded())
    }

    /// Whether any word in the list continues these keystrokes.
    ///
    /// **The question that separates a Hebrew word spelled wrong from one that
    /// is merely half typed**, which is a distinction `shouldAutocorrect` has to
    /// draw before it may replace a same-length Hebrew substitution. `מכונ`
    /// continues to `מכונה`, `מכוניות` and `מכונות`, so it is on its way
    /// somewhere and the space bar must leave it alone — that is the measured
    /// `מכונ` → `נכון` case the exclusion was written for. `בסגר`, `עכדיו`,
    /// `פכישה`, `כתובץ`, `משםחה` and `טלפום` continue to nothing at all, so they
    /// are finished words with a key slipped in them.
    ///
    /// **Asked of this list rather than of the seed**, and that is the whole
    /// reason it can be asked at all: `SeedLanguageModel.words(startingWith:)`
    /// is 353 words, so it answers "nothing continues this" about most of the
    /// language and the test would refuse nothing.
    ///
    /// A linear scan over the compact buffer, no second index. It runs at most
    /// once per keystroke and only on the Hebrew same-length case, which is a
    /// small fraction of them; building a trie to serve that would cost memory
    /// on every keystroke to save time on a few.
    static func hasContinuation(of prefix: String, in language: KeyboardLanguage) -> Bool {
        let folded = Array(SeedLanguageModel.fold(prefix).utf16)
        guard !folded.isEmpty else { return false }
        let block = block(for: language)
        for index in block.originals.indices {
            let start = Int(block.offsets[index])
            let end = Int(block.offsets[index + 1])
            // Strictly longer, so a word does not count as continuing itself.
            guard end - start > folded.count else { continue }
            var matches = true
            for offset in folded.indices where block.charBuffer[start + offset] != folded[offset] {
                matches = false
                break
            }
            if matches { return true }
        }
        return false
    }

    // MARK: Loading

    /// **Decoded as UTF-16 text rather than one scalar per unit, and the
    /// difference is a crash.** Mapping `UnicodeScalar(UInt32(_))!` over the
    /// buffer force-unwraps, and that initialiser answers nil for a surrogate
    /// half — so a single astral character anywhere in a bundled list would take
    /// the keyboard extension down on the keystroke that reached it. `load`
    /// keeps such words out of the buffer entirely, so this cannot happen; it is
    /// written safely anyway, because the two guarantees live in different
    /// functions and a data file is not a thing this code controls.
    private static func characters(at index: Int, in block: Block) -> [Character] {
        let start = Int(block.offsets[index])
        let end = Int(block.offsets[index + 1])
        return Array(String(decoding: block.charBuffer[start..<end], as: UTF16.self))
    }

    private static func mask(of foldedChars: [Character], using letterBits: [Character: Int]) -> UInt32 {
        var mask: UInt32 = 0
        for character in foldedChars {
            guard let bit = letterBits[character] else { continue }
            mask |= 1 << UInt32(bit)
        }
        return mask
    }

    /// One language's compact list, built once at load.
    private struct Block {
        /// Display spellings, index-aligned with every other array here.
        let originals: [String]
        /// Folded word -> rank, for `rank(of:)`.
        let ranks: [String: Int]
        /// Folded characters of every word, back to back.
        let charBuffer: [UInt16]
        /// `depth + 1` entries; word `i` spans `offsets[i]..<offsets[i+1]`.
        let offsets: [Int32]
        /// One bit per distinct letter this language's list actually uses,
        /// index-aligned with `originals`.
        let masks: [UInt32]
        /// Folded character -> bit index, built once so `corrections(of:)`
        /// can compute the typed word's mask in the same bit space as the
        /// stored ones. Capped at 32 bits; a language whose loaded words use
        /// more than 32 distinct letters simply leaves the rest unmasked,
        /// which only weakens the pre-filter — a letter with no bit never
        /// contributes to a false rejection, only to a candidate reaching
        /// `TypoChannel.cost` that a perfect mask would have skipped.
        let letterBits: [Character: Int]
        /// Every folded form in the list, all 50,000 of them, for `isWord`.
        ///
        /// **In the `Block` rather than in a cache of its own, because the two
        /// are always built together and were being read out of the file
        /// twice.** The first version kept this separately, on the argument that
        /// a caller might never ask `isWord` and should not pay to build it.
        /// That argument was true when it was written and stopped being true the
        /// moment `SuggestionEngine.frequencyCorrections` made `isWord` the
        /// *first* question asked on every keystroke: the set was always built,
        /// and building it through `GroupedLexiconResource.words(for:)` parsed
        /// the same file a second time and left all 50,000 boxed strings cached
        /// for the life of the process on top of that. Measured on the frozen
        /// 90, the first English keystroke of a session: **166 ms before this
        /// source existed, 306 ms with the two loads, 161 ms with one** — so
        /// reading once costs nothing this instrument can see, and reading twice
        /// nearly doubled the one latency a user actually waits on.
        let allForms: Set<String>

        static let empty = Block(
            originals: [], ranks: [:], charBuffer: [], offsets: [0], masks: [], letterBits: [:],
            allForms: [])
    }

    /// Drops the built blocks. See `KeyboardController.dropRebuildableCaches()`,
    /// which is the only caller and carries the reasoning.
    static func purge() {
        cache.withLock { $0.removeAll() }
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [String: Block]())

    private static func block(for language: KeyboardLanguage) -> Block {
        cache.withLock { store in
            if let known = store[language.languageTag] { return known }
            let built = load(language)
            store[language.languageTag] = built
            return built
        }
    }

    /// One read of the file, both structures out of it.
    ///
    /// `GroupedLexiconResource.uncachedWords` rather than `words(for:)`, because
    /// that one caches all 50,000 boxed strings for the life of the process to
    /// serve `GroupedDecoder`, which indexes them on every grouped keystroke.
    /// This needs each string exactly twice — once folded into `allForms`, once
    /// into the compact arrays if it is inside `depth` — and then never again,
    /// so borrowing that cache would keep several megabytes alive on behalf of a
    /// feature that has finished with them.
    private static func load(_ language: KeyboardLanguage) -> Block {
        let all = GroupedLexiconResource.uncachedWords(for: language)
        guard !all.isEmpty else { return .empty }
        let allForms = Set(all.map(SeedLanguageModel.fold))
        let head = Array(all.prefix(depth(for: language)))

        // Folded, and deliberately not shape-folded onto ordinary Hebrew
        // letter forms: `TypoChannel` charges 20 for a final-form
        // substitution, and shape-folding it away here would make every
        // final-form pair in this list indistinguishable before the channel
        // ever gets a chance to price the difference.
        //
        // **The one-code-unit-per-character invariant is enforced here rather
        // than assumed, because two other things silently depend on it.**
        // `offsets` counts UTF-16 units while `corrections(of:)` compares those
        // offsets against a count of `Character`s, so an astral character would
        // make one entry's length quietly wrong; and `characters(at:)` decodes
        // the same buffer back. Every Hebrew consonant and every ASCII letter is
        // one unit, and `Scripts/generate-grouped-lexicon.py` filters both lists
        // to letters this keyboard can type, so this drops nothing today — it is
        // here so that a regenerated list cannot make it untrue without also
        // making it visible.
        // Stated as the invariant itself rather than as a proxy for it: a word
        // qualifies when its folded form has exactly as many UTF-16 units as it
        // has `Character`s. Testing for the Basic Multilingual Plane would not
        // be the same claim, because a grapheme built from several scalars is
        // one `Character` and more than one unit even when every scalar is BMP.
        let kept = head.map { ($0, SeedLanguageModel.fold($0)) }
            .filter { $0.1.count == $0.1.utf16.count }
        let originals = kept.map(\.0)
        let folded = kept.map(\.1)

        var ranks: [String: Int] = [:]
        ranks.reserveCapacity(folded.count)
        for (index, word) in folded.enumerated() where ranks[word] == nil {
            ranks[word] = index
        }

        var letterBits: [Character: Int] = [:]
        for word in folded {
            for character in word where letterBits[character] == nil && letterBits.count < 32 {
                letterBits[character] = letterBits.count
            }
        }

        var charBuffer: [UInt16] = []
        charBuffer.reserveCapacity(folded.reduce(0) { $0 + $1.count })
        var offsets: [Int32] = [0]
        offsets.reserveCapacity(folded.count + 1)
        var masks: [UInt32] = []
        masks.reserveCapacity(folded.count)
        for word in folded {
            var wordMask: UInt32 = 0
            for character in word {
                // Every folded Hebrew consonant and every ASCII letter is one
                // UTF-16 code unit, which is what keeps `offsets` — counted
                // in characters — in step with `charBuffer` — appended in
                // UTF-16 units. Nothing in either bundled list needs more
                // than that.
                charBuffer.append(contentsOf: String(character).utf16)
                if let bit = letterBits[character] { wordMask |= 1 << UInt32(bit) }
            }
            offsets.append(Int32(charBuffer.count))
            masks.append(wordMask)
        }

        return Block(
            originals: originals, ranks: ranks, charBuffer: charBuffer, offsets: offsets, masks: masks,
            letterBits: letterBits, allForms: allForms)
    }
}
