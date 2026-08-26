#!/bin/bash
# Runs the real SuggestionEngine over Bar/typing/corpus.json and writes
# engine_outputs.json next to the corpus.
#
#   Bar/typing/harness/run.sh              # writes Bar/typing/engine_outputs.json
#   Bar/typing/harness/run.sh /tmp/out.json
#   TYPING_CORPUS=sweep/corpus.json Bar/typing/harness/run.sh /tmp/out.json
#   AUTOCORRECT_LEVEL=confident Bar/typing/harness/run.sh /tmp/out.json
#
# `AUTOCORRECT_LEVEL` is `off`, `confident` or `full`. Unset means whatever a
# fresh install gets (`AutocorrectLevel.shippedDefault`), so a bare run measures
# the shipping keyboard and `Bar/drift/` tracks the product. Pass `full` to score
# the cascade with every rule asked, which is what every number recorded before
# this setting existed was read at. The two sides have to be compared entry by
# entry rather than on the headline: `confident` trades corrections for held words
# on purpose, so a lower `committed` total is the setting working, and the column
# to read is `WRONG`.
#
# `TYPING_CORPUS` is the same variable `score.py` reads, so a corpus that is not
# the frozen 90 is named once and both halves of the run agree about it. The
# README has claimed since the first sweep that this script "takes any corpus
# with the same shape"; it did not — the corpus path was hardcoded here and only
# the *output* path was an argument, so every ad-hoc sweep had to edit this file
# or copy it. `sweep/` is the caller that needed it.
#
# Compiles for the iOS Simulator and runs there, because `UITextChecker` is
# UIKit. macOS would spell-check with `NSSpellChecker`, a different dictionary
# and a different ranking, so a macOS score would not be a score of the shipping
# engine. See main.swift.
#
# Needs a booted simulator. `xcrun simctl boot 'iPhone 17 Pro'` if there is none.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../../../Packages/AIKeyboardCore/Sources/AIKeyboardCore"
shared="$here/../../../Packages/AIKeyboardCore/Sources/AIKeyboardShared"
out="${1:-$here/../engine_outputs.json}"
corpus="${TYPING_CORPUS:-$here/../corpus.json}"
# Empty means "unset": main.swift falls back to `AutocorrectLevel.shippedDefault`,
# so what ships is written down once, in Swift, and this script cannot drift from it.
level="${AUTOCORRECT_LEVEL:-}"
# Absolute, always. `simctl spawn` runs the binary with the *device's* data
# directory as its working directory, so a relative path given on the command
# line is read or written somewhere inside the simulator and the run looks like
# it did nothing. The defaults above are already absolute; this is for the two
# paths that can arrive relative.
for name in out corpus; do
    case "${!name}" in
        /*) ;;
        *) printf -v "$name" '%s' "$PWD/${!name}" ;;
    esac
done

build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# The engine and everything it reaches, in one place because two scripts compile
# it: this one and `Bar/typing/typos/reasons.sh`. A list that lived in both would
# drift, and a missing file here is a silent wrong number rather than an error.
. "$here/sources.sh"
copy_engine_sources "$core" "$shared" "$build"
cp "$here/main.swift" "$build/"

sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
# -DHARNESS switches `SeedLanguageModel` off `Bundle.module`, which SwiftPM
# synthesises and a loose compile like this one does not have. The path comes in
# through the environment instead.
xcrun -sdk iphonesimulator swiftc -O -DHARNESS \
    -target arm64-apple-ios17.0-simulator -sdk "$sdk" \
    "$build"/*.swift -o "$build/harness"

device="${SIMULATOR_DEVICE:-booted}"
# The corpus and the output path have to be readable from inside the simulator's
# sandbox; simctl spawn shares the host filesystem, so absolute paths work.
# Two resources reach the loose compile through the environment rather than
# through `Bundle.module`, which SwiftPM synthesises and this does not have:
# `LanguageModel.json` for `SeedLanguageModel` and the directory holding
# `GroupedLexicon-{en,he}.txt` for `TypoLexicon`. Scoring without the second one
# would silently measure an engine with its whole frequency-correction source
# switched off, which looks like a clean run rather than like a broken one.
LANGUAGE_MODEL_JSON="$core/Resources/LanguageModel.json" \
    SIMCTL_CHILD_LANGUAGE_MODEL_JSON="$core/Resources/LanguageModel.json" \
    CONVERSATIONAL_HEBREW_MODEL="$core/Resources/ConversationalHebrew.akn1" \
    SIMCTL_CHILD_CONVERSATIONAL_HEBREW_MODEL="$core/Resources/ConversationalHebrew.akn1" \
    DISABLE_CONVERSATIONAL_HEBREW="${DISABLE_CONVERSATIONAL_HEBREW:-}" \
    SIMCTL_CHILD_DISABLE_CONVERSATIONAL_HEBREW="${DISABLE_CONVERSATIONAL_HEBREW:-}" \
    GROUPED_LEXICON_DIR="$core/Resources" \
    SIMCTL_CHILD_GROUPED_LEXICON_DIR="$core/Resources" \
    AUTOCORRECT_LEVEL="$level" \
    SIMCTL_CHILD_AUTOCORRECT_LEVEL="$level" \
    xcrun simctl spawn "$device" "$build/harness" "$corpus" "$out"

echo "engine outputs: $out"
