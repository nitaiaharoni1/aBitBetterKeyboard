#!/bin/bash
# Holds the shipping frame fingerprint to the §5.5 acceptance criteria.
#
#   Bar/screen-context/harness/run-fingerprint.sh
#
# `frame-hash.mjs` chose the band and the value: over the 30 corpus scenes, the
# old bottom-45% crop misses 23 of 29 conversation switches and a 64-bit
# perceptual hash misses 11 of 29 even at the right band, while the top-14% /
# bottom-8.5% band with a SHA-256 of the 2,048-byte reduction reaches 0 and 0.
# Those two zeros are the bar. This script asks whether the *Swift* that runs
# inside the broadcast extension clears it, by compiling
# `FrameFingerprint.swift` itself rather than a copy of it.
#
# The two harnesses are not redundant. The mjs one sweeps five bands and three
# values in a browser; this one runs one configuration through the shipping
# reduction, with CoreGraphics decoding and an integer box filter instead of
# Chromium's resampler. A design that only works with one particular resampler
# is not a design, and this is where that would show up.
#
# Fails rather than skips: no node, no renders, a decode failure or a non-zero
# miss column all exit non-zero.
set -uo pipefail

cd "$(dirname "$0")"
OUT="frame-hash-out"
SHARED=../../../Packages/AIKeyboardCore/Sources/AIKeyboardShared
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

# 1. The renders. `frame-hash.mjs` writes them with KEEP=1: 30 scenes x 4
#    variants, and the `last` variant — the newest message's glyphs substituted
#    inside its own script, same length, same wrapping, same times — is the one
#    that makes this a collision test rather than thirty different pictures.
COUNT=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" -lt 120 ]; then
  echo "==> Rendering the corpus variants (frame-hash.mjs, KEEP=1)"
  command -v node > /dev/null || fail "node is not installed; cannot render the corpus"
  (cd .. && KEEP=1 node harness/frame-hash.mjs) > /dev/null || fail "frame-hash.mjs did not render"
  COUNT=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
fi
[ "$COUNT" -ge 120 ] || fail "expected 120 renders in $OUT, found $COUNT"

# 2. The shipping source, compiled as-is. CryptoKit and Foundation are all it
#    needs, which is the same reason it can live in a target the broadcast
#    extension links.
echo "==> Building the shipping FrameFingerprint for macOS"
cp "$SHARED/FrameFingerprint.swift" "$BUILD/"
cp fingerprint.swift "$BUILD/main.swift"
xcrun -sdk macosx swiftc -O "$BUILD"/*.swift -o "$BUILD/fingerprint" 2>&1 \
  | grep -E "error" | head -20
[ -x "$BUILD/fingerprint" ] || fail "the fingerprint harness did not compile"

# 3. Score.
"$BUILD/fingerprint" "$OUT"
