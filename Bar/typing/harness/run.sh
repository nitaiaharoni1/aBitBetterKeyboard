#!/bin/bash
# Runs the real SuggestionEngine over Bar/typing/corpus.json and writes
# engine_outputs.json next to the corpus.
#
#   Bar/typing/harness/run.sh              # writes Bar/typing/engine_outputs.json
#   Bar/typing/harness/run.sh /tmp/out.json
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
# Absolute, always. `simctl spawn` runs the binary with the *device's* data
# directory as its working directory, so a relative path given on the command
# line is written somewhere inside the simulator and the run looks like it wrote
# nothing. The default above is already absolute; this is for the argument.
case "$out" in
    /*) ;;
    *) out="$PWD/$out" ;;
esac

build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

# The engine and everything it reaches. Globbed rather than listed so a new
# `SuggestionEngine+*.swift` is picked up without editing this script — the
# ai-text harness lists its files and drifts every time one is added.
cp "$core"/SuggestionEngine*.swift "$build/"
for source in Models.swift LanguageDetector.swift SeedLanguageModel.swift \
    HebrewMorphology.swift LayoutTransposition.swift PersonalLanguageModel.swift; do
    cp "$core/$source" "$build/"
done
# Both targets have a `LanguageDetector.swift`, one half each, and they land in
# the same directory here. Same rename the ai-text harness does.
cp "$shared/LanguageDetector.swift" "$build/SharedLanguageDetector.swift"
for source in KeyboardLanguage.swift KeyboardLanguage+Named.swift LanguageCatalogue.swift \
    LanguageCatalogueExtended.swift SharedContainer.swift; do
    cp "$shared/$source" "$build/"
done
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
LANGUAGE_MODEL_JSON="$core/Resources/LanguageModel.json" \
    SIMCTL_CHILD_LANGUAGE_MODEL_JSON="$core/Resources/LanguageModel.json" \
    xcrun simctl spawn "$device" "$build/harness" "$here/../corpus.json" "$out"

echo "engine outputs: $out"
