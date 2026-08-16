#!/bin/bash
# Holds the shipping frame fingerprint to a *landscape* frame.
#
#   Bar/screen-context/harness/run-fingerprint-landscape.sh
#
# Nothing under `Bar/screen-context/` had ever swept a landscape frame, so
# landscape's margin against `FrameReduction.Band.maximumOwnUI` was reasoning
# where portrait's was a reading. `frame-hash-landscape.mjs` renders the same 30
# scenes on a rotated screen at each shipping phone's landscape height, with our
# *landscape* keyboard on them: no banner, a 30 pt suggestion bar carrying the
# action row's chips, and `ControlSweep` running on the Reply chip, which is what
# is on screen for the whole of a read once the banner is gone.
#
# This script asks whether the Swift that runs inside the broadcast extension
# agrees with what Chromium measured, by compiling the shipping reduction itself.
# The two harnesses do not share a resampler: this one decodes with CoreGraphics
# and reduces with the shipping integer box filter, so a result that only held
# with one of them would show up here.
#
# It scores only the three `panel` renders — the state a reading is actually
# measured in — because that is the column the landscape geometry moves. The
# `base`/`last`/`chrome` columns are `frame-hash-landscape.mjs`'s, and on a
# rotated screen they are unstable on the Mail scenes for a reason that is the
# corpus rather than the fingerprint; that file's output says so.
#
# Fails rather than skips: no node, no renders, a decode failure or a non-zero
# own-false column all exit non-zero.
set -uo pipefail

cd "$(dirname "$0")"
OUT="frame-hash-landscape-out"
SHARED=../../../Packages/AIKeyboardCore/Sources/AIKeyboardShared
HEIGHTS="${HEIGHTS:-375,390,402}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

# 1. The renders. Six per scene per height, and the three `panel` ones are what
#    this scores: our own keyboard up at two sweep phases, plus the conversation
#    switch under it.
WANT=$(( $(echo "$HEIGHTS" | tr ',' '\n' | grep -c .) * 30 * 6 ))
COUNT=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" -lt "$WANT" ]; then
  echo "==> Rendering the landscape corpus (frame-hash-landscape.mjs, KEEP=1, HEIGHTS=$HEIGHTS)"
  command -v node > /dev/null || fail "node is not installed; cannot render the corpus"
  (cd .. && KEEP=1 HEIGHTS="$HEIGHTS" node harness/frame-hash-landscape.mjs) \
    || echo "    (the mjs harness reported a failure of its own; scoring its renders anyway)"
  COUNT=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
fi
[ "$COUNT" -ge "$WANT" ] || fail "expected $WANT renders in $OUT, found $COUNT"

# 2. The shipping source, compiled as-is. `FrameReduction` and its `reduce` are
#    both needed here, where the portrait harness gets away with the fingerprint
#    alone: this one calls `bottomCrop(ownUI:)` itself, because the crop is what
#    changes between one landscape phone and the next.
echo "==> Building the shipping FrameFingerprint for macOS"
cp "$SHARED/FrameFingerprint.swift" "$SHARED/FrameReduction.swift" \
   "$SHARED/FrameReduction+Reduce.swift" "$BUILD/"
cp fingerprint-landscape.swift "$BUILD/main.swift"
xcrun -sdk macosx swiftc -O "$BUILD"/*.swift -o "$BUILD/fingerprint-landscape" 2>&1 \
  | grep -E "error" | head -20
[ -x "$BUILD/fingerprint-landscape" ] || fail "the landscape fingerprint harness did not compile"

# 3. Score.
"$BUILD/fingerprint-landscape" "$OUT"
