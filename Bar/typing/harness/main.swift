// Runs the real SuggestionEngine over Bar/typing/corpus.json and writes what the
// three slots would hold for each of the 90 entries.
//
// **Runs on the iOS Simulator, not on macOS, and that is not a preference.**
// `SuggestionEngine` is built on `UITextChecker`, which is UIKit and therefore
// iOS-only; macOS spells with `NSSpellChecker`, a different API with a different
// dictionary and a different ranking. Scoring the engine against a checker it
// does not ship with would measure the wrong thing. `run.sh` compiles for
// `iphonesimulator` and runs the binary with `xcrun simctl spawn`.
//
// The output is deliberately dumb — ids and strings, no verdicts. `score.py`
// decides what is good, because judging is a separate step that has to be
// re-runnable against a frozen capture.

import Foundation
import UIKit

struct CorpusEntry: Decodable {
    let id: String
    let category: String
    let language: String
    let keyboard: String
    let context: String
    let prefix: String
    /// The word this entry is aimed at, when the corpus knows one.
    ///
    /// **Two corpora spell it and they do not mean the same thing.** In the sweep
    /// it is the whole word being typed letter by letter, so it extends the
    /// prefix. In the frozen 90 it is on 24 entries and means the *correction* —
    /// `dont` → `don't`, `,usv` → `תודה` — which shares no completion relationship
    /// with the keystrokes at all. `reachable` only asks its question of the first
    /// kind and reports nil for the rest; 47 of the frozen entries carry
    /// `acceptable` instead and none at all.
    let intended: String?
}

struct CorpusFile: Decodable {
    let entries: [CorpusEntry]
}

struct SlotRecord: Encodable {
    let id: String
    let category: String
    let slots: [String]
    /// Index of the bold slot — what the space bar commits.
    let defaultIndex: Int
    /// What the space bar would commit, spelled out, because "index 1" is not
    /// something a reader can check against `mustNotCorrect` at a glance.
    let commits: String
    /// Offered slots that **no source vouches for**: not Apple's spell checker,
    /// not Apple's completion list for what was typed, not the seed list, not the
    /// shipped personal dictionary. The typed echo is excluded.
    ///
    /// **The bold slot is not the only column a user can feel, and believing it
    /// was is why a whole class of defect went unmeasured.** `judge.py` grades
    /// what the space bar inserts, which is right and is what it says it does —
    /// and the Hebrew clitic split spent months offering `מנכון`, `מנחמד`,
    /// `מנפגש` in the other two slots without ever moving a commit, so both
    /// committed instruments read clean while a fifth of Hebrew keystrokes drew
    /// words that do not exist (NIT-129).
    ///
    /// **"`UITextChecker` calls it misspelled" was the first version of this test
    /// and it was useless, which is worth keeping written down because it is the
    /// obvious thing to reach for.** It reported **38 findings on a clean build
    /// and zero real ones**: `Nitai`, `Handi`, `Wispr` and `סאפא` are the shipped
    /// personal dictionary, `Adi`, `Roni` and `stam` are seed entries, `december`
    /// and `september` fail only because the bar matched the lower case of what
    /// was typed, and `סאפיינס` and `סאבלימינל` are words Apple's *completion*
    /// list offers while its *spelling* half rejects them. An instrument that
    /// cries wolf 38 times is worse than none, because the one real finding is
    /// the line nobody reads.
    ///
    /// So the test is the engine's own sources as the whitelist, which is also
    /// what makes it mean something: a string that every list this keyboard
    /// consults has never heard of is not a word it declined to rank — it is a
    /// word it made up.
    let misspelled: [String]
    /// Whether `UITextChecker` lists the word being typed among its completions of
    /// this prefix, when the corpus says what that word is. Nil when it does not.
    ///
    /// **The ceiling on every re-ranking idea, and without it "the bar is missing
    /// the target word" is a number nobody can act on.** `judge.py` reports 311 of
    /// 664 moments without the target, which sounds enormous and mostly is not:
    /// one letter into `להתראות` nothing should offer the whole word, and no
    /// ranking can offer a word no source generated. This column separates the two
    /// — a moment where Apple's own list holds the target and the bar does not is a
    /// moment some ranking could have won, and there are **14** of those in the
    /// Hebrew sweep against 11 that nothing could reach.
    ///
    /// Read the count, not the flag: it is a property of Apple's dictionary rather
    /// than of this engine, so it moves when iOS does and never when this repo
    /// does.
    let reachable: Bool?

    enum CodingKeys: String, CodingKey {
        case id, category, slots, defaultIndex = "default", commits, misspelled, reachable
    }
}

/// The corpus names a keyboard layout per entry; the engine wants the enabled
/// list with that layout first, exactly as `KeyboardController.refreshSuggestions`
/// builds it. Every corpus entry is a Hebrew/English user, which is the product's
/// own case, so the tail is the other one of the pair.
func languages(forKeyboard keyboard: String) -> [KeyboardLanguage] {
    let front: KeyboardLanguage = keyboard.hasPrefix("he") ? .hebrew : .english
    let back: KeyboardLanguage = front == .hebrew ? .english : .hebrew
    return [front, back]
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: harness <corpus.json> <out.json>\n".utf8))
    exit(2)
}

let corpusURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2])

/// Which `AutocorrectLevel` the bold slot is decided at.
///
/// **Defaults to what ships, not to what the engine defaults to.** This file
/// claims to measure the shipping keyboard, so an unset variable has to mean the
/// setting a fresh install gets — `AutocorrectLevel.shippedDefault` — and not
/// `SuggestionEngine.suggestions`'s own `.full`, which means "ask every rule".
/// That is also what makes `Bar/drift/` track the product rather than the
/// cascade: it runs this with no variable set.
///
/// **An unknown name exits rather than falling back**, for the reason the
/// lexicon check below exits: a typo in the variable would score the default
/// under a filename that says `confident`, and a wrong number that looks right is
/// the one failure mode this harness exists to prevent.
let autocorrectLevel: AutocorrectLevel = {
    guard let name = ProcessInfo.processInfo.environment["AUTOCORRECT_LEVEL"], !name.isEmpty
    else { return .shippedDefault }
    switch name {
    case "off": return .off
    case "confident": return .confident
    case "full": return .full
    default:
        FileHandle.standardError.write(
            Data("AUTOCORRECT_LEVEL must be off, confident or full — got \(name)\n".utf8))
        exit(2)
    }
}()

let corpus = try JSONDecoder().decode(CorpusFile.self, from: Data(contentsOf: corpusURL))

/// **Refuses to score an engine that is missing a source, rather than scoring
/// it.** `TypoLexicon` reads `GroupedLexicon-{en,he}.txt`, and under `-DHARNESS`
/// it finds them through `GROUPED_LEXICON_DIR` because `Bundle.module` does not
/// exist in a loose compile. A missing or misspelled variable does not fail: the
/// lexicon simply loads nothing, `frequencyCorrections` returns nothing, and the
/// run produces a full set of plausible numbers for an engine with its whole
/// frequency-correction source switched off. That is the failure mode this repo
/// keeps writing down — a control that answers nothing cannot be told from one
/// that works — so the check is a hard exit and not a warning.
MainActor.assumeIsolated {
    for (language, control) in [(KeyboardLanguage.english, "the"), (.hebrew, "של")]
    where !TypoLexicon.isWord(control, in: language) {
        FileHandle.standardError.write(
            Data(
                """
                GroupedLexicon-\(language.languageTag).txt did not load: \
                TypoLexicon does not know '\(control)'. Set GROUPED_LEXICON_DIR \
                (and SIMCTL_CHILD_GROUPED_LEXICON_DIR) to the Resources directory.

                """.utf8))
        exit(3)
    }
}

/// What a stock install actually has in its personal dictionary.
///
/// Copied from `SharedStore.shippedPersonalDictionary` rather than read from it:
/// `SharedStore` pulls in Combine and most of the app's settings surface, and the
/// corpus is a question about the engine. `SuggestionEngineTests` asserts the two
/// stay equal, so this cannot drift silently.
///
/// It has to be here at all because scoring with an *empty* list measures a
/// keyboard nobody has: `nc-05` types `Nitai`, and with no dictionary the space
/// bar commits `Nit` — a real defect, but one this file would be inventing.
let shippedPersonalDictionary = ["Nitai", "Handi", "Wispr", "KeyboardKit", "סאפא", "בלי־פרופ"]

/// How long each call took, so the local tier's latency is measured rather than
/// claimed.
///
/// **It is a budget, not a curiosity.** The whole two-tier design rests on tier
/// one being fast enough to run on every keystroke, and the number people notice
/// a keyboard missing is about 20 ms for the *entire* key press — drawing
/// included. Printed as a median and a worst case, because a mean would hide the
/// one entry that scans the whole seed list.
var elapsed: [Double] = []

/// Whether a string in a slot is one no list this keyboard consults has ever
/// heard of. See `SlotRecord.misspelled` for the four sources and for what
/// happened when this asked the spell checker alone.
@MainActor
func invented(_ text: String, in language: KeyboardLanguage, typed: String) -> Bool {
    guard let locale = language.spellCheckerLocale else { return false }
    if SuggestionEngine.isKnownWord(text, checkerLocale: locale) { return false }
    // Apple wants a proper noun capitalised and `matchCase` gives the candidate
    // the case of what was typed, so `de` offering `december` is Apple's own word
    // in the user's own case rather than an invention.
    let capitalised = text.prefix(1).uppercased() + text.dropFirst()
    if capitalised != text, SuggestionEngine.isKnownWord(capitalised, checkerLocale: locale) {
        return false
    }
    // Apple's two halves disagree: `סאפיינס` is in the completion list for `סא`
    // and is reported misspelled by the same object. A word it offered is a word
    // it vouches for, whichever half answered.
    let nsTyped = typed as NSString
    if nsTyped.length > 0,
        let offered = SuggestionEngine.sharedChecker.completions(
            forPartialWordRange: NSRange(location: 0, length: nsTyped.length), in: typed,
            language: locale),
        offered.contains(text)
    {
        return false
    }
    if SeedLanguageModel.knows(text, in: language) { return false }
    let folded = SeedLanguageModel.fold(text)
    return !shippedPersonalDictionary.contains { SeedLanguageModel.fold($0) == folded }
}

/// Whether Apple's completion list for this prefix holds the word being typed.
/// See `SlotRecord.reachable`.
///
/// Asked with the sentence around it, exactly as `SuggestionEngine` asks: the API
/// reads the context to rank, so asking the isolated word would measure a
/// different list from the one the engine saw.
@MainActor
func reachable(_ entry: CorpusEntry, in language: KeyboardLanguage) -> Bool? {
    guard let intended = entry.intended, intended != entry.prefix,
        let locale = language.spellCheckerLocale
    else { return nil }
    // **Only where the target continues what was typed.** A completion list is
    // asked what a prefix grows into, so asking it about a *correction* measures
    // nothing: `dont` → `don't` and `,usv` → `תודה` both come back false, and both
    // are answered correctly elsewhere, by `guesses` and by `LayoutTransposition`.
    // Reported as nil rather than false, or 24 frozen entries would read as
    // "no ranking could win this" when no ranking was ever the question.
    guard
        SeedLanguageModel.fold(intended).hasPrefix(SeedLanguageModel.fold(entry.prefix))
    else { return nil }
    let text = entry.context + entry.prefix
    let range = NSRange(
        location: (entry.context as NSString).length, length: (entry.prefix as NSString).length)
    guard range.length > 0 else { return nil }
    let offered =
        SuggestionEngine.sharedChecker.completions(
            forPartialWordRange: range, in: text, language: locale) ?? []
    return offered.contains { SeedLanguageModel.fold($0) == SeedLanguageModel.fold(intended) }
}

let records: [SlotRecord] = MainActor.assumeIsolated {
    // In-memory and empty. A scoring run must not inherit whatever the machine it
    // runs on has been typing, or two runs on two laptops disagree and neither is
    // the engine's fault.
    let personal = PersonalLanguageModel(url: nil)
    // **A warm-up per language, and the cost it absorbs is measured rather than
    // waved away.** The first call in a language pays for reading and folding
    // `LanguageModel.json` and for `UITextChecker` building that language's
    // lexicon. Measured on the iOS 26.2 Simulator: **~67 ms for the first Hebrew
    // word and ~3 ms for the first English one**, against ~0.9 ms for every word
    // after. That is a real cost a real user pays once per keyboard session on
    // their first Hebrew keystroke, and it is worth knowing; charging it to
    // whichever corpus entry happens to be first is what makes a per-keystroke
    // number wrong.
    for (label, keyboard, prefix, context) in [
        ("english", "en_US", "hel", "See you "), ("hebrew", "he_IL", "של", "אני ")
    ] {
        let started = DispatchTime.now().uptimeNanoseconds
        _ = SuggestionEngine.suggestions(
            prefix: prefix, context: context, languages: languages(forKeyboard: keyboard),
            supplementary: shippedPersonalDictionary, personal: personal,
            autocorrect: autocorrectLevel)
        let cold = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        FileHandle.standardError.write(
            Data("first \(label) call: \(String(format: "%.1f", cold)) ms\n".utf8))
    }
    let answered = corpus.entries.map { entry -> (CorpusEntry, [Suggestion]) in
        let started = DispatchTime.now().uptimeNanoseconds
        let results = SuggestionEngine.suggestions(
            prefix: entry.prefix,
            context: entry.context,
            languages: languages(forKeyboard: entry.keyboard),
            supplementary: shippedPersonalDictionary,
            personal: personal,
            autocorrect: autocorrectLevel)
        elapsed.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        return (entry, results)
    }

    // **Spelling and reachability are asked in a second pass, after every entry has
    // been answered, and the order is load-bearing rather than tidy.** `UITextChecker`'s Hebrew
    // answers depend on what that process has already asked it — the frozen
    // corpus records the instability on `he-comp-03/04/05` and the sweep found
    // one prefix answering differently in two places in a single run. Asking it
    // about a slot in the middle of the measurement would put new calls into that
    // sequence and change the thing being measured. This way the completion calls
    // happen in exactly the order they did before this column existed.
    return answered.map { entry, results in
        let defaultIndex = results.firstIndex(where: \.isDefault) ?? 0
        return SlotRecord(
            id: entry.id,
            category: entry.category,
            slots: results.map(\.text),
            defaultIndex: results.isEmpty ? -1 : defaultIndex,
            commits: results.isEmpty ? entry.prefix : results[defaultIndex].text,
            // The echo is matched by text rather than by index, because a
            // next-word entry has an empty prefix and no echo at all, and
            // dropping index 0 there would hide a real offer.
            misspelled: results.filter { $0.text != entry.prefix }
                .filter { invented($0.text, in: $0.language, typed: entry.prefix) }
                .map(\.text),
            reachable: reachable(entry, in: languages(forKeyboard: entry.keyboard)[0]))
    }
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
try encoder.encode(records).write(to: outURL)

let sorted = elapsed.sorted()
let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
let slowest = zip(corpus.entries.map(\.id), elapsed)
    .sorted { $0.1 > $1.1 }
    .prefix(5)
    .map { "\($0.0) \(String(format: "%.1f", $0.1))ms" }
    .joined(separator: ", ")
FileHandle.standardError.write(
    Data(
        """
        wrote \(records.count) records to \(outURL.path)
        local tier: median \(String(format: "%.2f", median)) ms over \(elapsed.count) entries
        slowest: \(slowest)

        """.utf8))
