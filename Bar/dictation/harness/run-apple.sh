#!/bin/bash
# Runs Apple's own dictation model over Bar/dictation/audio/ and writes
# apple_live_outputs.json next to the corpus.
#
#   Bar/dictation/harness/run-apple.sh              # writes Bar/dictation/apple_live_outputs.json
#   Bar/dictation/harness/run-apple.sh /tmp/out.json
#   Bar/dictation/harness/score.py apple_live_outputs.json
#
# This measures the **live** half of dictation — the words the keyboard shows
# while somebody is speaking — not the transcript of record, which is
# `CloudDictation` and is what `run.sh` measures. See `LiveTranscriber`.
#
# Compiles for the iOS Simulator and runs there, because `DictationTranscriber`
# is an iOS API with no macOS equivalent, so a macOS run would not be measuring
# the shipping path. Same reason `Bar/typing/harness/run.sh` does it.
#
# Needs a booted simulator on iOS 26 or newer.
# `xcrun simctl boot 'iPhone 17 Pro'` if there is none. The Hebrew and English
# models are downloaded on the first run, which takes a minute and needs network.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bar="$(cd "$here/.." && pwd)"
out="${1:-$bar/apple_live_outputs.json}"
# Absolute, always. `simctl spawn` runs the binary with the *device's* data
# directory as its working directory, so a relative path is written somewhere
# inside the simulator and the run looks like it wrote nothing.
case "$out" in
    /*) ;;
    *) out="$(pwd)/$out" ;;
esac

booted=$(xcrun simctl list devices booted | grep -o '[0-9A-F-]\{36\}' | head -1)
[ -n "$booted" ] || { echo "no booted simulator: xcrun simctl boot 'iPhone 17 Pro'" >&2; exit 1; }

build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

xcrun --sdk iphonesimulator swiftc \
    -target arm64-apple-ios26.0-simulator \
    -o "$build/apple-live" "$here/apple-live.swift"

xcrun simctl spawn "$booted" "$build/apple-live" "$bar" "$out"
echo "wrote $out"
