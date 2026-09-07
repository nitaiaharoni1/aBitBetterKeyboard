import Foundation

extension SuggestionEngine {
    /// Every candidate for the word in progress, ranked, three deep.
    ///
    /// Ranked `Candidate`s rather than `Suggestion`s, because the caller has two
    /// questions to ask of this list and only one of them is about the words: the
    /// bar draws the text, and `commitReason` asks where the winner came
    /// from. See `SuggestionEngine.rank`.
    ///
    /// - Parameters:
    ///   - prefix: the word being typed.
    ///   - previousWords: the committed words directly before it, in order, empty
    ///     at the start of a message or after a full stop. This is the sentence
    ///     half of "context aware": it is what lets `לקבוע תו` reach `תור` instead
    ///     of the four-times-commoner `תודה`, and `See you ` reach `tomorrow`
    ///     instead of the three words that merely follow `you`.
    ///   - context: everything before the current word, including earlier
    ///     sentences and lines. `previousWords` stops at a full stop; this does
    ///     not. It is how a name two sentences back is still completable.
    ///   - typedLanguage: the language the characters are written in.
    ///   - otherLanguage: the other language the user enabled, for wrong-layout
    ///     detection. Nil when they have only one.
    ///   - supplementary: the personal dictionary, then `UILexicon`.
    ///   - personal: what this user's own typing has taught the keyboard.
    ///   - codeSwitching: Latin letters inside a Hebrew sentence.
    @MainActor
    static func generatedCompletions(
        for prefix: String,
        previousWords: [String],
        context: String,
        typedLanguage: KeyboardLanguage,
        otherLanguage: KeyboardLanguage?,
        supplementary: [String],
        personal: PersonalLanguageModel,
        codeSwitching: Bool = false
    ) -> [Candidate] {
        let core = wordCore(prefix)
        let lower = core.lowercased()
        var out: [Candidate] = []
        let checkerLocale = typedLanguage.spellCheckerLocale
        let directQuery = checkerQuery(of: core, in: context)
        let directCompletions =
            checkerLocale.map {
                checkerCompletions(of: core, locale: $0, query: directQuery)
            } ?? []
        appendTypedAndLayoutCandidates(
            to: &out, prefix: prefix, typedLanguage: typedLanguage, otherLanguage: otherLanguage)
        appendOrthographicCandidates(to: &out, core: core, lower: lower, typedLanguage: typedLanguage)
        appendSupplementaryCandidates(
            to: &out, prefix: prefix, supplementary: supplementary, typedLanguage: typedLanguage)
        let fieldWords = appendPersonalDocumentAndSeedCandidates(
            to: &out, core: core, context: context, typedLanguage: typedLanguage,
            personal: personal, directCompletions: directCompletions)
        appendHebrewFormCandidates(to: &out, core: core, typedLanguage: typedLanguage, locale: checkerLocale)
        appendCodeSwitchCandidates(
            to: &out, core: core, lower: lower, typedLanguage: typedLanguage,
            codeSwitching: codeSwitching)
        appendCheckerAndFrequencyCandidates(
            to: &out, core: core, typedLanguage: typedLanguage, personal: personal,
            directCompletions: directCompletions, directQuery: directQuery, locale: checkerLocale)
        stampContext(
            on: &out, previousWords: previousWords, fieldWords: fieldWords,
            typedLanguage: typedLanguage, personal: personal)
        return out
    }

    @MainActor
    private static func appendTypedAndLayoutCandidates(
        to out: inout [Candidate], prefix: String, typedLanguage: KeyboardLanguage,
        otherLanguage: KeyboardLanguage?
    ) {
        // The literal keystrokes always stay available, so the engine can never
        // trap the user into a word they did not want.
        out.append(Candidate(text: prefix, language: typedLanguage, source: .typed))

        // This is the one source that must see the keystrokes rather than the
        // trimmed word: punctuation can itself be a key from the other layout.
        if let other = otherLanguage,
            let transposed = LayoutTransposition.correction(
                of: prefix, typedLanguage: typedLanguage, other: other,
                isKnownWord: { word, language in
                    guard let locale = language.spellCheckerLocale else { return false }
                    return isKnownWord(word, checkerLocale: locale)
                })
        {
            out.append(Candidate(text: transposed, language: other, source: .layout))
        }
    }

    @MainActor
    private static func appendOrthographicCandidates(
        to out: inout [Candidate], core: String, lower: String, typedLanguage: KeyboardLanguage
    ) {
        // A dropped apostrophe is the most common thing worth fixing. English
        // only because the table contains English contractions.
        if typedLanguage == .english, let contraction = contractions[lower] {
            out.append(
                Candidate(
                    text: matchCase(of: core, applyingTo: contraction, in: typedLanguage),
                    language: .english,
                    source: ambiguousContractions.contains(lower) ? .checker : .orthography))
        }

        // Hebrew final-form correction is restricted to Hebrew code points;
        // Arabic and Persian shape letters in the font rather than the text.
        if typedLanguage.script == .hebrew, let final = hebrewFinalFormCorrection(of: core) {
            out.append(Candidate(text: final, language: .hebrew, source: .orthography))
        }
    }

    @MainActor
    private static func appendSupplementaryCandidates(
        to out: inout [Candidate], prefix: String, supplementary: [String],
        typedLanguage: KeyboardLanguage
    ) {
        // Compare both ends after folding punctuation, but avoid treating a
        // punctuation-only prefix as every personal word.
        let typed = comparable(prefix)
        if !typed.isEmpty {
            out +=
                supplementary
                .filter { comparable($0).hasPrefix(typed) && comparable($0) != typed }
                .prefix(completionPoolLimit)
                .enumerated()
                .map {
                    Candidate(
                        text: $0.element, language: typedLanguage, source: .personal,
                        ordinal: $0.offset)
                }
        }
    }

    @MainActor
    private static func appendPersonalDocumentAndSeedCandidates(
        to out: inout [Candidate], core: String, context: String, typedLanguage: KeyboardLanguage,
        personal: PersonalLanguageModel, directCompletions: [String]
    ) -> [String] {
        out += personal.words(startingWith: core, in: typedLanguage, limit: completionPoolLimit)
            .enumerated()
            .map {
                Candidate(
                    text: matchCaseUnlessVerbatim(of: core, applyingTo: $0.element, in: typedLanguage),
                    language: typedLanguage, source: .learned, ordinal: $0.offset)
            }

        // Tokenise the field once, then use it both for its own candidates and
        // for follower ranking later in this pass.
        let fieldWords = documentWords(in: context)
        out += documentCandidates(for: core, among: fieldWords, typedLanguage: typedLanguage)
        out += seedCandidates(
            for: core, typedLanguage: typedLanguage, personal: personal,
            spelledOut: directCompletions)
        return fieldWords
    }

    @MainActor
    private static func appendHebrewFormCandidates(
        to out: inout [Candidate], core: String, typedLanguage: KeyboardLanguage, locale: String?
    ) {
        // Irregular forms are a closed table; inflections are dictionary-checked
        // constructions, so they deliberately rank as different sources.
        if typedLanguage.script == .hebrew {
            out += hebrewIrregulars(of: core)
                .enumerated()
                .map {
                    Candidate(
                        text: $0.element, language: typedLanguage, source: .irregular,
                        ordinal: $0.offset)
                }
            if let locale {
                out += hebrewInflections(of: core, locale: locale)
                    .enumerated()
                    .map {
                        Candidate(
                            text: $0.element, language: typedLanguage, source: .inflection,
                            ordinal: $0.offset)
                    }
            }
        }
    }

    @MainActor
    private static func appendCodeSwitchCandidates(
        to out: inout [Candidate], core: String, lower: String, typedLanguage: KeyboardLanguage,
        codeSwitching: Bool
    ) {
        // Latin vocabulary gets this precedence only inside Hebrew text. An
        // empty folded word must not match every entry.
        if codeSwitching, !lower.isEmpty {
            out +=
                codeSwitchVocabulary
                .filter { $0.hasPrefix(lower) && $0 != lower }
                .prefix(completionPoolLimit)
                .enumerated()
                .map {
                    Candidate(
                        text: matchCase(of: core, applyingTo: $0.element, in: typedLanguage),
                        language: .english, source: .codeSwitch, ordinal: $0.offset)
                }
        }
    }

    @MainActor
    private static func appendCheckerAndFrequencyCandidates(
        to out: inout [Candidate], core: String, typedLanguage: KeyboardLanguage,
        personal: PersonalLanguageModel, directCompletions: [String], directQuery: CheckerQuery,
        locale: String?
    ) {
        out += checkerCandidates(
            for: core, typedLanguage: typedLanguage, personal: personal,
            completions: directCompletions, query: directQuery, locale: locale)
        out += frequencyCorrections(of: core, in: typedLanguage, limit: completionPoolLimit)
    }

    @MainActor
    private static func stampContext(
        on out: inout [Candidate], previousWords: [String], fieldWords: [String],
        typedLanguage: KeyboardLanguage, personal: PersonalLanguageModel
    ) {
        let followers = Set(
            contextFollowers(
                last: previousWords, field: fieldWords,
                language: typedLanguage, personal: personal
            ).map(SeedLanguageModel.fold))
        let immediateFollowers = Set(
            (SeedLanguageModel.followers(after: previousWords, in: typedLanguage)
                + personal.followers(
                    after: previousWords.last ?? "", in: typedLanguage, limit: completionPoolLimit)
                + documentFollowers(
                    after: previousWords.last ?? "", among: fieldWords, limit: completionPoolLimit)).map(
                    SeedLanguageModel.fold))
        for index in out.indices {
            let key = SeedLanguageModel.fold(out[index].text)
            out[index].followsImmediateContext = immediateFollowers.contains(key)
            out[index].followsContext = followers.contains(key) || out[index].followsImmediateContext
        }
        stampPersonalCounts(&out, personal: personal)
    }
}
