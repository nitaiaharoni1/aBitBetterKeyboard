# The engine sources a loose `swiftc` needs, and nothing else.
#
# **Sourced by two scripts, which is the whole reason it is a file.**
# `harness/run.sh` scores the bar and `typos/reasons.sh` reports which rule
# decided each commit; both compile the same engine, and a list kept twice drifts.
# The ai-text harness keeps its own and drifts every time a file is added.
#
# `SuggestionEngine*.swift` is globbed so a new `SuggestionEngine+*.swift` needs
# no edit here. Everything else is named, and `AutocorrectConfidence.swift` is
# named because it does not carry that prefix — leaving it out is a compile error
# rather than a silent wrong number, since `CommitReason` is what the commit
# decision returns.
copy_engine_sources() {
    local core="$1" shared="$2" build="$3" source
    cp "$core"/SuggestionEngine*.swift "$build/"
    for source in Models.swift LanguageDetector.swift SeedLanguageModel.swift \
        HebrewMorphology.swift LayoutTransposition.swift PersonalLanguageModel.swift \
        KeyProximity.swift TypoChannel.swift TypoLexicon.swift GroupedLexiconResource.swift \
        AutocorrectConfidence.swift; do
        cp "$core/$source" "$build/"
    done
    # Both targets have a `LanguageDetector.swift`, one half each, and they land in
    # the same directory here. Same rename the ai-text harness does.
    cp "$shared/LanguageDetector.swift" "$build/SharedLanguageDetector.swift"
    for source in KeyboardLanguage.swift KeyboardLanguage+Named.swift LanguageCatalogue.swift \
        LanguageCatalogueExtended.swift SharedContainer.swift; do
        cp "$shared/$source" "$build/"
    done
}
