import Foundation
import UIKit

extension SuggestionEngine {

    // MARK: Completion of the word being typed

    static let completionPoolLimit = 12

    /// One `UITextChecker` for the process. Apple's own guidance is one per
    /// document mainly so ignored/learned words stay consistent; this keyboard
    /// never calls `ignoreWord`/`learnWord`, so a single shared instance is
    /// exactly as correct and avoids re-initialising the spell-check engine on
    /// every keystroke.
    @MainActor
    static let sharedChecker = UITextChecker()

    /// The word with its last letter put into final form, when that lands on a
    /// word the seed list knows.
    ///
    /// **It asks the seed list and it must never ask `UITextChecker`, and the
    /// difference between those two is the whole history of this function.** The
    /// obvious shape is "offer it when the typed word is misspelled and the
    /// corrected one is not". That was written against the checker, and it never
    /// fired: inside the engine `isKnownWord("שלומ")` comes back *true*, while
    /// the same call on a checker that has already been used for Hebrew comes
    /// back false. A rule whose correctness depends on `UITextChecker` having
    /// warmed up is a rule that silently does nothing on the first word a user
    /// types, which is the worst possible time. So it was rewritten to ask
    /// nothing at all.
    ///
    /// **Asking nothing was worse, and it was measured over the whole
    /// vocabulary.** Five letters change shape at the end of a Hebrew word, and
    /// a *finished* word may not end in the ordinary form — but a word in
    /// progress ends in whatever letter was typed last, and 20% of the mid-word
    /// keystrokes in the 353-word seed list end in one of those five. This lands
    /// as `.orthography`, which outranks every completion source, and
    /// `commitReason` names a reason for it above the seed check, so it took
    /// the bold slot: typing `פגישה` bolded `ף` at the first letter, `מכונית`
    /// bolded `מך`, `נכון` bolded `נך`, and `לפגישה` bolded `לף` while `לפגישה`
    /// itself never reached the bar. 17 of 35 measured keystroke moments bolded
    /// a non-word. Worse than the noise, it *committed* on real input: `אפ`
    /// ("app") went to `אף` ("nose") and `קליפ` to `קליף`, because Hebrew writes
    /// its loanwords with the ordinary form at the end.
    ///
    /// The seed list settles it without reintroducing the cold-checker problem:
    /// it is a bundled JSON, folded once at load, and it answers the same on the
    /// first keystroke of a session as on the thousandth. 66 of its words end in
    /// a final form, which is the common core this slip happens in — `שלומ` →
    /// `שלום`, `צריכ` → `צריך`, `כספ` → `כסף`, `דרכ` → `דרך`. It is the same gate
    /// `SeedLanguageModel.neighbours` and `LayoutTransposition` already use, and
    /// for the same reason: a rule that rewrites what the user typed may only
    /// ever land on a word that is common enough to be worth the interruption.
    ///
    /// The table itself moved to `HebrewMorphology`, which is where the rest of
    /// the facts about how Hebrew spells a word end.
    @MainActor
    static func hebrewFinalFormCorrection(of word: String) -> String? {
        guard let corrected = HebrewMorphology.inFinalForm(word),
            SeedLanguageModel.knows(corrected, in: .hebrew)
        else { return nil }
        return corrected
    }

    /// Latin words that appear inside Hebrew sentences and that `UITextChecker`
    /// ranks badly there.
    ///
    /// **Dropped once and had to come back.** The argument for dropping it was
    /// that `en_US`'s own dictionary already knows every word in it — `sync`,
    /// `standup`, `roadmap` all come back `misspelled == false`. True, and it
    /// measures the wrong thing: a suggestion bar is asked about *prefixes*, every
    /// keystroke, and `sta` inside a Hebrew sentence offers `still`, `stay`,
    /// `start` while `standup` never appears until all seven letters are typed.
    ///
    /// Place and brand names are **not** here — they went into the seed list, so
    /// they arrive ranked alongside ordinary words instead of through a second
    /// mechanism that has no opinion about which of them is common.
    static let codeSwitchVocabulary: [String] = [
        "backlog", "brief", "call", "deadline", "demo", "deploy", "deployment", "design",
        "document", "feedback", "follow-up", "invite", "meeting", "presentation", "product",
        "review", "roadmap", "scope", "screenshot", "screenshots", "slack", "sprint",
        "standup", "sync", "template", "ticket", "update"
    ]

    /// Every candidate for the word in progress, ranked, one deeper than the bar.
    @MainActor
    static func completions(
        for prefix: String,
        previousWords: [String],
        context: String,
        typedLanguage: KeyboardLanguage,
        otherLanguage: KeyboardLanguage?,
        supplementary: [String],
        personal: PersonalLanguageModel,
        codeSwitching: Bool = false
    ) -> [Candidate] {
        rank(
            generatedCompletions(
                for: prefix, previousWords: previousWords, context: context,
                typedLanguage: typedLanguage, otherLanguage: otherLanguage,
                supplementary: supplementary, personal: personal,
                codeSwitching: codeSwitching),
            limit: barSlots + 1)
    }

    /// How often this person has committed each candidate. Hebrew sums attested
    /// clitic variants of a vouched stem; other languages stay exact. Asked once,
    /// here, so `score` can stay a pure function of the candidate.
    @MainActor
    static func stampPersonalCounts(
        _ candidates: inout [Candidate], personal: PersonalLanguageModel
    ) {
        for index in candidates.indices {
            candidates[index].personalCount = personal.rankingCount(
                of: candidates[index].text, in: candidates[index].language)
        }
    }

    /// Common words the typed keystrokes are a plausible slip of.
    ///
    /// **The class of mistake nothing in this engine could reach.**
    /// `SeedLanguageModel.neighbours` is one edit over 353 hand-authored words
    /// and `UITextChecker.guesses` is Apple's own unranked list; between them
    /// they cover a single slip in a common word, and nothing else. Two slips in
    /// one word is what a hand landing a key off does, and it is what was
    /// reported: `דוגמטןת` for `דוגמאות`, `א` typed as `ט` and `ו` as `ן`, both
    /// pairs adjacent on the Hebrew top row. `TypoLexicon` searches a
    /// frequency-ranked list under `TypoChannel`, which prices a slip by what
    /// kind of slip it is rather than counting edits — an adjacent key, a
    /// transposition, a Hebrew final form, a dropped mater lectionis — so two
    /// *explainable* mistakes stay in reach while two unrelated ones do not.
    ///
    /// **Gated on the list disowning what was typed, which is a gate the seed
    /// list could never be.** The standing rule is that a keyboard does not
    /// correct words, and `SeedLanguageModel.knows` cannot enforce it: the seed
    /// is a few hundred words, so it answers no about most of the language, and
    /// the first version of the neighbour rule turned `cat` into `car` on
    /// exactly that mistake. `cat` is rank 5,234 of these 50,000 and `bus` is
    /// 1,715, while `תדוה`, `שלמו`, `teh`, `recieve` and `seperate` are absent
    /// from all of them. `TypoLexicon.isWord` reads the whole list rather than
    /// the `depth` this source may *offer* from, because a word at rank 30,000
    /// is still a word.
    ///
    /// Two offers at most, so this can never take the whole bar: `barSlots - 1`
    /// leaves a slot for whatever else had something to say.
    @MainActor
    static func frequencyCorrections(
        of word: String, in language: KeyboardLanguage, limit: Int
    ) -> [Candidate] {
        guard !TypoLexicon.isWord(word, in: language) else { return [] }
        return
            TypoLexicon.corrections(of: word, in: language, limit: limit)
            .enumerated()
            .map {
                Candidate(
                    text: matchCase(of: word, applyingTo: $0.element.word, in: language),
                    language: language, source: .frequency, ordinal: $0.offset)
            }
    }

    /// Seed neighbours first, then words this person has actually used.
    /// Personal hits fill any remaining slots so a name you type can be
    /// offered from a one-key slip the seed list has never heard of.
    @MainActor
    static func neighbourWords(
        of word: String, in language: KeyboardLanguage, personal: PersonalLanguageModel,
        limit: Int
    ) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let seed = SeedLanguageModel.neighbours(of: word, in: language, limit: limit)
        let learned = personal.neighbours(of: word, in: language, limit: limit)
        for hit in seed + learned {
            let key = SeedLanguageModel.fold(hit)
            guard seen.insert(key).inserted else { continue }
            out.append(hit)
            if out.count == limit { break }
        }
        return out
    }

    /// Completions drawn from words already in this field.
    ///
    /// Most recent first, so a name used in the sentence being typed outranks
    /// the same prefix from a paragraph above. Hebrew clitics are stripped the
    /// same way `seedCandidates` strips them: `לקוואק` in the field is how
    /// `קוו` reaches `קוואק`. The document spelling is kept rather than
    /// recased to the prefix — `Zorblin` stays `Zorblin` even if the user has
    /// only typed `zor`.
    static func documentCandidates(
        for prefix: String, among fieldWords: [String], typedLanguage: KeyboardLanguage
    ) -> [Candidate] {
        let typed = comparable(prefix)
        guard !typed.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [Candidate] = []
        for word in fieldWords.reversed() {
            guard let offered = documentOffer(word, matching: typed, language: typedLanguage)
            else { continue }
            let key = comparable(offered)
            guard key != typed, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(
                Candidate(
                    text: offered, language: typedLanguage, source: .document,
                    ordinal: out.count))
            if out.count == completionPoolLimit { break }
        }
        return out
    }

    /// The form of a field word that continues this prefix, if any.
    private static func documentOffer(
        _ word: String, matching typed: String, language: KeyboardLanguage
    ) -> String? {
        if comparable(word).hasPrefix(typed) { return word }
        guard language.script == .hebrew else { return nil }
        for reading in HebrewMorphology.splits(of: word) where !reading.prefix.isEmpty {
            if comparable(reading.stem).hasPrefix(typed) { return reading.stem }
        }
        return nil
    }

    /// Whether the dictionary agrees that a word reached by taking Hebrew apart is
    /// a word at all.
    ///
    /// **The split is the engine's own guess, and until this gate existed nothing
    /// ever checked it against anything.** `seedCandidates` reads `מנ` as `מ` + `נ`,
    /// asks the seed list what starts with `נ`, gets `נכון` / `נחמד` / `נפגש` — the
    /// commonest words there are — glues the clitic back on and offers `מנכון`,
    /// `מנחמד`, `מנפגש`. None of those is a word. They arrive `.seed`, which scores
    /// 3000 less 500 a clitic, so they beat every completion `UITextChecker` has and
    /// take **all three drawn slots**, and the word the user is typing is not in the
    /// bar at all. Measured 2026-08-16 over 121 keystroke moments from 55 common
    /// Hebrew words: **17 moments drew a non-word (26 slots of the 363 there are),
    /// and the word being typed was missing from 30 of them.** The same shape is
    /// what put `מכסהרורי` on a real phone — that one comes through the split path's
    /// own `UITextChecker` call rather than the seed list, which is why the gate is
    /// asked of both and why that call is gone.
    ///
    /// The test is the dictionary's completion list **for the word as it was
    /// actually typed**, which is already being fetched for `checkerCandidates`. A
    /// reading may therefore *re-rank* what Apple offers and may not invent
    /// anything: `לעבו` still reaches `לעבודה` because Apple lists it third and the
    /// seed prior pulls it to first, which is exactly what the split was built for.
    ///
    /// **The premise this file was written under is no longer true and that is
    /// what makes the gate cheap.** `HebrewMorphology` says no dictionary lists the
    /// glued forms. On the iOS 26.2 Simulator `UITextChecker` lists every one of
    /// them: `לעבודה` is 3rd for `לעבו`, `בעבודה` 1st for `בעבו`, `מהעבודה` 1st for
    /// `מהעבו`, `מהעיר` 1st for `מהעי`, `מהגן` 3rd for `מהג` — all five controls the
    /// split exists to serve. What morphology still buys is the *ranking*, since
    /// Apple has no frequency model; what it was also doing was manufacturing words.
    ///
    /// **An empty list is not a contradiction.** Apple answers nothing for plenty of
    /// Hebrew prefixes (`צהרי` is one), and a gate that read silence as refusal
    /// would switch morphology off exactly where no other source can help.
    static func readingIsSpelledOut(_ word: String, among completions: [String]) -> Bool {
        guard !completions.isEmpty else { return true }
        let folded = SeedLanguageModel.fold(word)
        return completions.contains { SeedLanguageModel.fold($0) == folded }
    }

    /// The number and gender endings this rule may put on a stem.
    ///
    /// The same five `hebrewLexemeStem` takes off, used in the other direction.
    /// `יות` is deliberately absent: it is there so that ending is not read as a
    /// `ת` with two letters in front of it, which is a question about taking a
    /// word apart and not about building one.
    private static let hebrewInflectionEndings = ["ות", "ים", "ה", "ת", "י"]

    /// Hebrew plurals that are not their singular plus an ending.
    ///
    /// **A lookup, deliberately, where everything else here is a rule.** `בית` →
    /// `בתים` drops a letter and changes a vowel, `אישה` → `נשים` shares no letters
    /// with its own singular, and `יד` → `ידיים` is a dual. Those are segholate
    /// patterns and suppletive stems, real Hebrew morphology, and a three-slot
    /// suggestion bar has no business modelling them. Twenty-one rows is the whole
    /// of the problem people actually type.
    ///
    /// **Every row is here because it was measured missing, not because it looked
    /// irregular.** The ending table was run over 45 candidate pairs on the iOS
    /// 26.2 Simulator, 2026-08-16: it already reaches 22 of them — `מקום` →
    /// `מקומות`, `חלון` → `חלונות`, `דרך` → `דרכים`, `מכונית` → `מכוניות` — because
    /// `hebrewShapeFolded` puts the final letter back before the ending goes on, so
    /// a word only *looks* irregular. Those 22 are not here and must not be added:
    /// a row that duplicates the rule is a row that can disagree with it later.
    ///
    /// Two failures explain the 23 that did miss. Most are simply too short for the
    /// floors that keep the rule from inventing — `בן`, `אח`, `יד` fail
    /// `word.count >= 3`, and `בית`, `שנה`, `דלת`, `חנות` all leave a two-letter
    /// stem once their apparent ending comes off. The rest reach the dictionary and
    /// get the wrong answer: `אישה` is offered `אישות` and `אישים`, which are real
    /// words and are not the plural of "woman".
    ///
    /// **The spellings are the corpus's, not the author's.** Modern Hebrew writes
    /// several of these two ways, and `Resources/GroupedLexicon-he.txt` — 50,000
    /// word forms ranked by frequency in real text — settles which: `אמהות`
    /// (18,564) over `אימהות` (25,222), and `ידיים` / `עיניים` / `רגליים` over
    /// `ידים` / `עינים` / `רגלים`, two of which the corpus does not contain at all.
    ///
    /// **`עם` and `אם` were measured, are correct, and are left out.** Their
    /// plurals `עמים` and `אמהות` are real, but both singulars are two letters
    /// whose commoner reading is a function word — "with" and "if" — and both
    /// plurals sit past rank 6,000 where every other row here is inside 8,200. A
    /// row is worth its slot when the noun reading is the likely one.
    /// Internal rather than private so `ContextAwareSuggestionTests` can walk every
    /// row against `UITextChecker`. A hand-written table is a place a typo ships
    /// silently, and the language it is written in is not one most readers of this
    /// file can proofread.
    static let hebrewIrregularPlurals: [(singular: String, plural: String)] = [
        ("אב", "אבות"), ("אח", "אחים"), ("אחות", "אחיות"), ("איש", "אנשים"),
        ("אישה", "נשים"), ("בית", "בתים"), ("בן", "בנים"), ("בת", "בנות"),
        ("גן", "גנים"), ("דלת", "דלתות"), ("חג", "חגים"), ("חנות", "חנויות"),
        ("יד", "ידיים"), ("יום", "ימים"), ("עין", "עיניים"), ("עיר", "ערים"),
        ("עץ", "עצים"), ("רגל", "רגליים"), ("שם", "שמות"), ("שנה", "שנים"),
        ("שעה", "שעות")
    ]

    /// The table above read from either end, built once.
    ///
    /// Both directions, because the gap runs both ways and the reverse costs a
    /// line: the same measurement showed `נשים`, `בתים` and `ימים` returning
    /// nothing at all, where a regular plural already finds its own singular
    /// (`פגישות` → `פגישה`) through the `ה` ending.
    private static let hebrewIrregularForms: [String: [String]] = {
        var out: [String: [String]] = [:]
        for pair in hebrewIrregularPlurals {
            out[SeedLanguageModel.fold(pair.singular), default: []].append(pair.plural)
            out[SeedLanguageModel.fold(pair.plural), default: []].append(pair.singular)
        }
        return out
    }()

    /// The other inflections of a Hebrew word that is already finished.
    ///
    /// **English gets this for free and Hebrew cannot, and the difference is the
    /// whole reason this exists.** English inflects by *appending*, so a prefix
    /// search over a dictionary finishes a finished word without being asked:
    /// measured over 15 common English verbs, 15 of 15 drew a full bar — `walk` →
    /// `walking`, `walked`, `walks`. Hebrew *replaces* the ending, so `רוצה` →
    /// `רוצים` is not a prefix extension of anything and **no** prefix-based
    /// completion can ever reach it. That is the same asymmetry
    /// `hasDistinctHebrewLexemes` is built on, seen from the other side.
    ///
    /// Measured over 20 common finished Hebrew words: **7 drew a thin bar, and in
    /// every one `UITextChecker` itself returned nothing.** `הולך`, `רוצה`,
    /// `הודעה` and `פגישה` all come back with an empty completion list and `מכסה`
    /// comes back with exactly one — which is why the bar in the report that
    /// started NIT-129 had three slots and nothing honest to fill them with. The
    /// verbs Apple does have it has well (13 of 20 full), so this is a floor under
    /// a gap rather than a replacement for its dictionary.
    ///
    /// Four things hold it down, and each is what stops a generative rule doing
    /// harm.
    ///
    /// **It only runs on a word that is already a word.** A prefix is not an
    /// unfinished inflection of anything, and the gate also puts the result out of
    /// the space bar's reach for free: `commitReason` answers nil at
    /// `SeedLanguageModel.knows`, and failing that at `!known` in the four-letter
    /// gate, for every word this can fire on. So these can be tapped and never
    /// committed.
    ///
    /// **Every candidate has to appear in Apple's completion list for the stem**,
    /// which is `readingIsSpelledOut` applied to the one other place this engine
    /// builds a word rather than looking one up. The endings say what *shape* an
    /// inflection has; the dictionary says whether that one exists. Neither half
    /// works alone: taking Apple's completions of `רוצ` wholesale would offer
    /// `רוצפה`, and taking the endings wholesale offers `בעבודים`.
    ///
    /// **Asking `isKnownWord` per candidate instead was measured and was not
    /// enough**, which is worth keeping because it is the cheaper thing to reach
    /// for. Apple's spelling half accepts plenty it would never *offer*: over the
    /// sweep it passed `בעבודים`, `לעבודים`, `משפחים`, `מסעדים` and `בבקשים` —
    /// the masculine plural on a feminine noun — plus `מכוניה`, `כספה`, and
    /// `להתחילה` and `להזמינה`, which hang a gender ending on an infinitive.
    /// The completion list rejects all of them. It also settles the hyphenated
    /// personal-dictionary entry (`בלי-פרופ` was producing `בלי-פרופות`,
    /// `בלי-פות`, `בלי-פרות`) without a rule about hyphens, because Apple has no
    /// completions for any of those stems.
    ///
    /// **An empty list refuses here, where `readingIsSpelledOut` allows.** The
    /// difference is what happens next: there, silence means falling back to the
    /// morphology that is the only thing that can reach a glued Hebrew word, so
    /// reading it as refusal would switch the feature off where it is needed
    /// most. Here the fallback is the empty slot this rule exists to fill, and a
    /// word built out of a dictionary that has said nothing is exactly the
    /// invention NIT-129 was about.
    ///
    /// **The stem has to keep three letters**, where `hebrewLexemeStem` itself
    /// stops at two. That function is asked whether two completions of the *same
    /// keystrokes* are one word, so both sides already share a long prefix; this
    /// one invents from a stem and needs the stricter floor. `בית` is the case:
    /// its `ת` looks like a feminine construct ending, stripping it leaves `בי`,
    /// and `ביים` is a real word with nothing to do with a house.
    ///
    /// **`hebrewIrregulars` is how `בית` reaches `בתים` anyway, and it is a
    /// different function rather than a branch inside this one.** Every gate above
    /// exists to stop this rule *inventing* a word, and a closed table of
    /// twenty-one pairs invents nothing, so it should not have to pass tests
    /// written for a guess: `בן`, `אח` and `יד` are two letters, which is exactly
    /// why no rule can reach their plurals and precisely what the length floor
    /// refuses.
    ///
    /// **The last letter goes back to its ordinary shape first.** `הולך` ends in a
    /// final kaf, and `הולך` + `ות` is not a word in any sense; `הולכ` + `ות` is
    /// `הולכות`. `hebrewShapeFolded` already inverts `HebrewMorphology.finalForms`
    /// for the comparison next door.
    ///
    /// Ranked below every other source (`Source.inflection`), so it can only ever
    /// fill a slot nothing else wanted. That is deliberate and it is what makes
    /// the change safe to measure: on any moment where the bar was already full,
    /// nothing moves at all.
    @MainActor
    static func hebrewInflections(of word: String, locale: String) -> [String] {
        guard word.count >= 3,
            SeedLanguageModel.knows(word, in: .hebrew) || isKnownWord(word, checkerLocale: locale)
        else { return [] }
        let stem = hebrewShapeFolded(hebrewLexemeStem(word))
        guard stem.count >= 3 else { return [] }
        // The stem alone, with no sentence around it: it is a fragment this rule
        // made up rather than a span of the document, which is the same reason
        // `checkerQuery` keeps the isolated shape for a split Hebrew stem.
        let offered = Set(checkerCompletions(of: stem, locale: locale).map(SeedLanguageModel.fold))
        guard !offered.isEmpty else { return [] }
        let folded = SeedLanguageModel.fold(word)
        return hebrewInflectionEndings.map { stem + $0 }
            .filter {
                SeedLanguageModel.fold($0) != folded && offered.contains(SeedLanguageModel.fold($0))
            }
    }

    /// The irregular counterparts of a Hebrew word, in either direction.
    ///
    /// **A separate function from `hebrewInflections`, and separate is the whole
    /// design.** That one asks `UITextChecker` whether the word it just built
    /// exists, needs the main actor to do it, and is held down by two length
    /// floors — all of which are there because it *guesses*. This one reads a
    /// closed table and guesses nothing, so it asks nothing, runs anywhere, and is
    /// not subject to floors written for a generator. They also rank differently:
    /// see `Source.irregular` for the measurement that separated them.
    static func hebrewIrregulars(of word: String) -> [String] {
        hebrewIrregularForms[SeedLanguageModel.fold(word)] ?? []
    }

    /// Seed-list completions, including the ones only reachable by taking a Hebrew
    /// word apart.
    ///
    /// For English this is a plain prefix search. For Hebrew it runs once per
    /// reading from `HebrewMorphology.splits` — `לעבו` as itself, and as `ל` +
    /// `עבו` — and puts the clitic back on whatever the stem completed to. That
    /// second reading is what pulls `לעבודה` past the two verbs Apple ranks above
    /// it.
    ///
    /// **Every split reading is checked against the dictionary before it is
    /// offered; only the unsplit one is trusted on its own.** See
    /// `readingIsSpelledOut` for the measurement. `spelledOut` is Apple's completion
    /// list for the typed word, passed in because `completions(for:)` already has
    /// it.
    ///
    /// **What a learned word is allowed to do here, and why it is the exception.**
    /// A clitic on a word this person types is `לסאפא` — a form Apple has never
    /// heard of and never will, since the stem is not in its dictionary either. The
    /// gate above asks a dictionary whether a word exists, and for the learned tier
    /// the answer is always no and always uninformative, so asking it there would
    /// delete precisely the words the personal model exists to supply. Two sightings
    /// are still needed before `words(startingWith:)` will name one.
    @MainActor
    static func seedCandidates(
        for prefix: String, typedLanguage: KeyboardLanguage, personal: PersonalLanguageModel,
        spelledOut: [String]
    ) -> [Candidate] {
        var out: [Candidate] = []
        let readings: [(prefix: String, stem: String)] =
            typedLanguage.script == .hebrew
            ? HebrewMorphology.splits(of: prefix) : [("", prefix)]

        for reading in readings {
            let depth = reading.prefix.count
            let seedStems = SeedLanguageModel.words(
                startingWith: reading.stem, in: typedLanguage, limit: completionPoolLimit)
            let personalStems = personal.words(
                startingWith: reading.stem, in: typedLanguage, limit: completionPoolLimit)
            for (index, stem) in seedStems.enumerated() {
                let glued = matchCase(
                    of: prefix, applyingTo: reading.prefix + stem, in: typedLanguage)
                guard depth == 0 || readingIsSpelledOut(glued, among: spelledOut) else { continue }
                out.append(
                    Candidate(
                        text: glued, language: typedLanguage, source: .seed, cliticDepth: depth,
                        ordinal: index))
            }
            for (index, stem) in personalStems.enumerated() {
                out.append(
                    Candidate(
                        text: matchCaseUnlessVerbatim(
                            of: prefix, applyingTo: reading.prefix + stem, in: typedLanguage),
                        language: typedLanguage, source: .learned, cliticDepth: depth,
                        ordinal: index))
            }
            // **`UITextChecker` used to be asked about the invented stem too, and
            // that call is gone.** It existed because the seed list is a few hundred
            // words and has nothing to say about most stems, so a reading it could
            // not answer fell through to Apple's dictionary — asked about a stem
            // this engine made up. What came back was glued to the clitic and
            // offered: `מכסה` was read as `מ` + `כסה`, Apple completed `כסה` to
            // `כסהרה` and `כסהרורי`, and the bar on a real phone held `מכסהרה` and
            // `מכסהרורי` beside `מכסהו`. That is the defect this whole gate was
            // written for, arriving through the one source the gate would have had
            // to veto on every single call.
            //
            // Under `readingIsSpelledOut` the call cannot produce anything new: a
            // glued form only survives if Apple already lists it for the typed word,
            // and `checkerCandidates` offers that same list at `cliticDepth` 0,
            // which scores 500 a letter *higher*, so `rank` keeps the unsplit copy
            // and the split one was always going to be dropped as a duplicate.
            //
            // It takes a *call count* with it and not a measured saving, which is
            // worth stating precisely because the comment that used to be here
            // defended this path with a latency argument. A Hebrew keystroke now
            // makes exactly one `UITextChecker.completions` call where it could
            // make three. Wall clock did not move: median over the 90 corpus
            // entries read 2.28 and 1.62 ms across two runs before and 2.28 and
            // 1.77 ms after, and the worst entry swung between 18 and 94 ms on
            // runs of identical code. The arithmetic is real and this instrument
            // cannot see it.
        }
        return out
    }

    /// `UITextChecker`'s own answers about the word: completions first, and
    /// corrections only when the completions came back thin.
    ///
    /// Takes the word rather than the keystrokes — `completions(for:)` trims the
    /// edge marks once and hands the same string to every source, for the reason
    /// written there.
    ///
    /// **The surrounding sentence is the string Apple's API is for.** Passing
    /// only the word in progress made every completion context-free, so
    /// `completions(forPartialWordRange:in:language:)` could not see `The
    /// elephant ate. The ele` and had no way to prefer `elephant` over
    /// `election`. The current word is appended to `context` and the range
    /// points at it.
    ///
    /// **The list arrives rather than being fetched, because two callers need the
    /// same one.** `completions(for:)` asks Apple once and hands it here to be
    /// offered and to `seedCandidates` to be checked against; see
    /// `readingIsSpelledOut`. Fetching it in both places would pay for the most
    /// expensive call on the keystroke path twice to get the same answer.
    ///
    /// **Measured, disclosed gap in the correction half.** `recieve` completes to
    /// nothing, so the correction branch fires and `guesses` gives `receive`.
    /// `helo` completes to `helot`/`helots` — real words, so the branch never runs
    /// — and the much likelier `hello` sits second in `guesses`. That specific
    /// failure is now caught upstream by the seed list rather than here, because
    /// `hello` is a common word and `helot` is not; the branch below is still
    /// gated the same way, since running `guesses` on every keystroke costs more
    /// than it returns once a frequency prior exists.
    @MainActor
    static func checkerCandidates(
        for word: String, typedLanguage: KeyboardLanguage, personal: PersonalLanguageModel,
        completions: [String], query: CheckerQuery, locale: String?
    )
        -> [Candidate]
    {
        // Apple ships no spell checker for every language this keyboard draws —
        // Persian is not in `UITextChecker.availableLanguages` at all. There is
        // nothing to fall back to: another language's dictionary would offer
        // another language's words, which is worse than offering none.
        guard let locale else { return [] }
        let lower = word.lowercased()
        var out: [Candidate] = []

        out +=
            completions
            .prefix(completionPoolLimit)
            .enumerated()
            .map {
                Candidate(
                    text: matchCase(of: word, applyingTo: $0.element, in: typedLanguage),
                    language: typedLanguage, source: .checker, ordinal: $0.offset)
            }

        // A common word one keystroke away.
        //
        // **Gated on what was typed, not on how many completions came back.** Two
        // earlier placements both failed: under `rangeOfMisspelledWord` it never
        // ran for a Hebrew typo at all, because Apple's Hebrew checker does not
        // report `תדוה` as misspelled; under the "fewer than two completions" gate
        // it never ran for `שלמו`, because taking the word apart had already
        // produced two. The condition that actually matters is neither — it is
        // that the *typed* word is absent from the common core. A word that is
        // itself common needs no neighbours (`bus` must never be shown `but`), and
        // a word that is not is worth asking about however many completions it
        // happens to have.
        //
        // **Asked about `wordCore`, not the keystrokes, and a comma was the whole
        // bug.** `neighbours` refuses a candidate shorter than what was typed, so
        // a trailing mark counted as a letter and pushed every real neighbour
        // under the floor: `teh` corrected to `the` and `teh,` corrected to
        // nothing. In Hebrew there is no second path to fall back on — Apple's
        // checker calls `תדוה` and `שלמו` perfectly good words, so this rule is
        // the only one that sees them — and `תדוה,` came back holding one slot,
        // the typo, with `תודה` never generated at all. Greeting somebody or
        // ending a clause is the commonest way a word meets a mark, so this was
        // most of the ground the rule was written to cover.
        if !SeedLanguageModel.knows(word, in: typedLanguage) {
            out +=
                neighbourWords(of: word, in: typedLanguage, personal: personal, limit: completionPoolLimit)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCaseUnlessVerbatim(
                            of: word, applyingTo: $0.element, in: typedLanguage),
                        language: typedLanguage, source: .neighbour, ordinal: $0.offset,
                        keyAdjacent: KeyProximity.isAdjacentSubstitution(
                            word, $0.element, in: typedLanguage))
                }
        }

        guard out.count < 2, query.range.length > 0 else { return out }

        let misspelled = sharedChecker.rangeOfMisspelledWord(
            in: query.text, range: query.range, startingAt: query.range.location, wrap: false,
            language: locale)
        guard misspelled.location != NSNotFound else { return out }

        if let corrections = sharedChecker.guesses(
            forWordRange: query.range, in: query.text, language: locale)
        {
            out +=
                corrections
                .filter { $0.lowercased() != lower }
                .prefix(completionPoolLimit)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCase(of: word, applyingTo: $0.element, in: typedLanguage),
                        language: typedLanguage, source: .correction, ordinal: $0.offset)
                }
        }
        return out
    }

    /// The string and range `UITextChecker` is asked about.
    ///
    /// The current word is always the tail, so a second occurrence of the same
    /// letters earlier in the field cannot steal the range. An empty context
    /// keeps the isolated-word shape the split-stem path still needs.
    struct CheckerQuery {
        let text: String
        let range: NSRange
    }

    static func checkerQuery(of word: String, in context: String) -> CheckerQuery {
        let nsWord = word as NSString
        guard !context.isEmpty else {
            return CheckerQuery(text: word, range: NSRange(location: 0, length: nsWord.length))
        }
        let nsContext = context as NSString
        return CheckerQuery(
            text: nsContext.appending(word),
            range: NSRange(location: nsContext.length, length: nsWord.length))
    }

    @MainActor
    static func checkerCompletions(
        of word: String, locale: String, query: CheckerQuery? = nil
    ) -> [String] {
        let nsWord = word as NSString
        guard nsWord.length > 0 else { return [] }
        let asked = query ?? CheckerQuery(text: word, range: NSRange(location: 0, length: nsWord.length))
        let lower = word.lowercased()
        return
            (sharedChecker.completions(
                forPartialWordRange: asked.range, in: asked.text, language: locale)
            ?? [])
            .filter { $0.lowercased() != lower }
    }

    static let ambiguousContractions: Set<String> = ["its", "ill", "lets", "cant", "wont"]

    static func correctionIsAmbiguous(
        typed: String, winner: Candidate, alternatives: [Candidate]
    ) -> Bool {
        let folded = SeedLanguageModel.fold(typed)
        let chosen = SeedLanguageModel.fold(winner.text)
        guard !chosen.hasPrefix(folded),
            let budget = TypoChannel.budget(forTypedLength: typed.count),
            let chosenCost = TypoChannel.cost(
                typed: Array(typed), candidate: Array(winner.text),
                language: winner.language, budget: budget)
        else { return false }
        return alternatives.contains { other in
            let word = SeedLanguageModel.fold(other.text)
            guard other.source != .typed, other.language == winner.language,
                word != chosen, word != folded, !word.hasPrefix(folded),
                !(winner.followsImmediateContext && !other.followsImmediateContext),
                let cost = TypoChannel.cost(
                    typed: Array(typed), candidate: Array(other.text),
                    language: winner.language, budget: budget)
            else { return false }
            return cost.cost <= chosenCost.cost
        }
    }

    /// Whether the space bar may act on the reading this candidate was reached
    /// through.
    ///
    /// **Only Hebrew ever reaches the body of this, and the split is the engine's
    /// own guess about the user's word.** `HebrewMorphology.splits` returns every
    /// way the typed letters could be read as clitics plus a stem and leaves the
    /// choice to the ranking, which is why `score` charges half a tier per clitic
    /// letter — a reading stacked on a reading. Offering a distrusted reading
    /// costs a slot. *Committing* one puts a word in the field that the user never
    /// typed a stem of: `להתר`, four letters into `להתראות` ("goodbye"), was read
    /// as `ל` + `ה` + `תרופה` and the space bar inserted `להתרופה`, "to the
    /// medicine".
    ///
    /// **A reading that assumes more than it rests on.** Every clitic letter is a
    /// claim that a key the user pressed is a function word rather than part of
    /// the word being completed, so those letters are spent and not earned: `לה` +
    /// `תר` identifies a five-letter noun from two of the four letters typed.
    /// Measuring the assumption against what is left of the word, rather than
    /// against a constant, is what keeps the case every cheaper gate breaks —
    /// `בעבו` still commits `בעבודה` (one clitic, three letters of stem) and
    /// `מהעבו` still commits `מהעבודה` (two clitics, three letters of stem).
    ///
    /// **A second reading used to be distrusted here too, and it is gone because
    /// nothing produces it any more.** `seedCandidates` used to ask
    /// `UITextChecker` about a split reading when the seed list had nothing to say
    /// about it (`seedStems.isEmpty`), so a candidate could arrive `source ==
    /// .checker` at `cliticDepth > 0` — Apple's unranked Hebrew list answering a
    /// question about a stem this engine made up — and this function refused it
    /// outright. That call is deleted (see `seedCandidates`): every `.checker`
    /// candidate is built with no `cliticDepth` argument now, which defaults to
    /// zero, so the guard above already returns `true` for it before the source is
    /// ever asked. **`להתרא` reaching `להתראיין` was believed to be this case and
    /// measurement said otherwise**: read out of the engine, that winner is
    /// `.checker` at `cliticDepth` **0** — Apple completing the glued form itself
    /// — so it was never the reading this clause refused; what is actually
    /// happening there is `להתראות` and `להתראיין` sharing a prefix, which
    /// `hasDistinctHebrewLexemes` is the fix for. See
    /// `testTwoHebrewWordsSharingAPrefixDoNotTakeTheSpaceBar`.
    ///
    /// This reading is still *offered*. Only the bold slot moves, and a
    /// deliberate tap still commits it.
    static func commitTrustsReading(_ candidate: Candidate, typed: String) -> Bool {
        guard candidate.cliticDepth > 0 else { return true }
        return candidate.cliticDepth < typed.count - candidate.cliticDepth
    }

    /// Whether these completions are more than one word with a suffix stuck on.
    ///
    /// `schedule` / `scheduled` is one lexeme. `respond` / `response` is two:
    /// neither string begins with the other. Asked of the seed list's own
    /// answers, most-common first, so the head is the one the four-letter gate
    /// would have committed.
    static func hasDistinctLexemes(_ words: [String]) -> Bool {
        guard words.count >= 2 else { return false }
        let folded = words.map(SeedLanguageModel.fold)
        let head = folded[0]
        return folded.dropFirst().contains { other in
            !other.hasPrefix(head) && !head.hasPrefix(other)
        }
    }

    /// The same question in Hebrew: `hasDistinctLexemes` with the one move that
    /// language makes and English does not.
    ///
    /// **English inflects by adding letters; Hebrew replaces them.** `schedule` →
    /// `scheduled` keeps the whole word at the front, which is why the prefix test
    /// works there. `עבודה` pluralises to `עבודות`, which does *not* start with
    /// `עבודה`, so the prefix test alone reads one word as two — and that is
    /// precisely why widening `hasDistinctLexemes` to Hebrew stops the correct
    /// `בעבו` → `בעבודה`. The objection was recorded with the slots behind it in
    /// `.claude/rules/suggestion-bar.md` before this existed; the answer is not to
    /// abandon the prefix test but to add the ending swap beside it.
    ///
    /// So two completions are one word when either holds, and different words only
    /// when neither does:
    ///
    /// - one still starts with the other — `להתראות` / `להתראותם`, `להתראיין` /
    ///   `להתראיינה`, which is a possessive or a gender hung off the end and is the
    ///   same shape English has;
    /// - or the same stem is left once the ending comes off — `הודעה` / `הודעות`,
    ///   `עבודה` / `עבודות`, which is the shape only Hebrew has.
    ///
    /// `להתראות` and `להתראיין` fail both and are, correctly, two words: neither
    /// starts with the other, and `להתרא` is not `להתראיין`.
    ///
    /// **Asked only of candidates that complete the typed letters.** A correction
    /// deletes a key that was pressed rather than continuing from it — `להתראי`
    /// offers `התראי`, an imperative reached by dropping the lamed — and a word
    /// that disagrees with the keystrokes is not one of the readings they are
    /// ambiguous *between*. The caller filters; including them made this refuse
    /// four completions that were on their way to the right word.
    static func hasDistinctHebrewLexemes(_ words: [String]) -> Bool {
        guard words.count >= 2 else { return false }
        let folded = words.map { hebrewShapeFolded(SeedLanguageModel.fold($0)) }
        let head = folded[0]
        let headStem = hebrewLexemeStem(head)
        return folded.dropFirst().contains { other in
            !other.hasPrefix(head) && !head.hasPrefix(other)
                && hebrewLexemeStem(other) != headStem
        }
    }

    /// Hebrew's five final forms written as their ordinary shapes, so two
    /// spellings of one letter compare equal.
    ///
    /// **A letter changes shape when it stops being last, and that defeats a
    /// prefix test on its own.** `להתראיין` ends in a final nun; the moment
    /// anything is added the nun goes back to its ordinary shape, so
    /// `להתראיינה` does not start with `להתראיין` on the code points at all — and
    /// `hasDistinctHebrewLexemes` duly read one word as two and refused two
    /// keystrokes that were on their way to the right one. `SeedLanguageModel`
    /// folds the same way before measuring edit distance and records the same
    /// surprise about `שלמו` / `שלום`. Both invert `HebrewMorphology.finalForms`,
    /// which is where the fact itself lives, rather than each spelling out the
    /// five pairs.
    private static let hebrewOrdinaryForms: [Character: Character] =
        HebrewMorphology.finalForms.reduce(into: [:]) { $0[$1.value] = $1.key }

    private static func hebrewShapeFolded(_ word: String) -> String {
        guard word.contains(where: { hebrewOrdinaryForms[$0] != nil }) else { return word }
        return String(word.map { hebrewOrdinaryForms[$0] ?? $0 })
    }

    /// A Hebrew word with one inflectional ending taken off, or the word itself.
    ///
    /// Number and gender, and nothing beyond that: `ות` and `ים` are the two
    /// plurals, `ה` is the feminine singular, `ת` its construct form and `י` the
    /// first-person possessive, so `עבודה`, `עבודות`, `עבודת` and `עבודתי` all
    /// reduce to `עבוד`. Longest ending first, so `יות` is not read as a `ת` with
    /// two letters in front of it.
    ///
    /// **The five final forms are deliberately absent, and that is the trap.**
    /// `ם` and `ן` do end plenty of inflections, and they are also ordinary root
    /// letters at the end of a word: stripping them turns `להתראיין` into
    /// `להתראיי` and then into the same stem as `להתראות`, which is the one pair
    /// this whole rule exists to keep apart. Anything a longer ending would have
    /// caught is caught by the prefix half of `hasDistinctHebrewLexemes` instead.
    ///
    /// **Not a morphological analyser** — no roots, no binyanim, no pronoun
    /// suffixes — because the only question it is asked is whether two completions
    /// of the *same keystrokes* are the same word, and both sides already share a
    /// long prefix. A stem shorter than two letters is refused for the reason
    /// `HebrewMorphology` lets only the seed list answer a one-letter stem: below
    /// that there is not enough word left to have been inflected.
    static func hebrewLexemeStem(_ word: String) -> String {
        for ending in ["יות", "ות", "ים", "ה", "ת", "י"] where word.hasSuffix(ending) {
            let stem = String(word.dropLast(ending.count))
            if stem.count >= 2 { return stem }
        }
        return word
    }

    /// The word inside what was typed, with the marks that sit at its edges
    /// without belonging to it taken off.
    ///
    /// **Both apostrophes, spelled as an escape, because the curly one did not
    /// survive being written literally.** This read
    /// `hasSuffix("'s") || hasSuffix("'s")` — two branches that look like the two
    /// apostrophes and are the same eight bytes, so the second was dead and
    /// `Nitai’s` was never reduced to `Nitai`. That is not a hypothetical
    /// spelling: the apostrophe key's long press offers `’`
    /// (`KeyboardLayout+NumbersSymbols`), and a host field with smart quotes on —
    /// the default everywhere except this repo's own test helper — turns a typed
    /// `'` into `’` inside the document that `currentWordPrefix` reads back.
    static func wordCore(_ typed: String) -> String {
        let trimmed = typed.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.hasSuffix("'s") || trimmed.hasSuffix("\u{2019}s") else { return trimmed }
        return String(trimmed.dropLast(2)).trimmingCharacters(in: .punctuationCharacters)
    }

    /// A word reduced to the form two spellings of it have in common, for
    /// comparing what is being typed against the user's own list.
    ///
    /// **`SeedLanguageModel.fold` rather than a second spelling of it.** This
    /// carried its own copy of the same three moves, and the copy's apostrophe
    /// rule was `replacingOccurrences(of: "'", with: "'")` — ASCII on both sides,
    /// so it did nothing. The measured cost was the personal dictionary silently
    /// letting go of a word the moment it wore a curly apostrophe: `Nitai's` was
    /// protected and `Nitai’s` committed as `Nita’s`.
    static func comparable(_ word: String) -> String {
        SeedLanguageModel.fold(wordCore(word))
    }

    @MainActor
    static func isKnownWord(_ word: String, checkerLocale: String) -> Bool {
        guard !word.isEmpty else { return false }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = sharedChecker.rangeOfMisspelledWord(
            in: word, range: range, startingAt: 0, wrap: false,
            language: checkerLocale)
        return misspelled.location == NSNotFound
    }
}
