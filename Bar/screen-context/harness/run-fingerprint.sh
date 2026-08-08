#!/bin/bash
# Holds the shipping frame fingerprint to the §5.5 acceptance criteria.
#
#   Bar/screen-context/harness/run-fingerprint.sh
#
# `frame-hash.mjs` chose the band and the value: over the 30 corpus scenes, the
# old bottom-45% crop misses 23 of 29 conversation switches and a 64-bit
# perceptual hash misses 10 of 29 even at the right band, while the top-14% /
# bottom-8.5% band with a SHA-256 of the 2,048-byte reduction reaches 0 and 0.
# It also found the failure that band still had: with *our own* keyboard on
# screen — which is the only state a reading is ever measured in, because the
# user tapped Reply on it — the result panel's loading shimmer moves the identity
# on 30 of 30 frames. So there are two configurations and four zeros, and this
# script asks whether the *Swift* that runs inside the broadcast extension clears
# all of them, by compiling `FrameFingerprint.swift` itself rather than a copy.
#
# The two harnesses are not redundant. The mjs one sweeps seven bands and three
# values in a browser; this one runs the two shipping configurations through the
# shipping reduction, with CoreGraphics decoding and an integer box filter
# instead of Chromium's resampler. A design that only works with one particular
# resampler is not a design, and this is where that would show up — it already
# has once, in the other direction: Chromium builds its downscale mip chain from
# the whole image, so pixels outside the crop bled into every cell until
# `frame-hash.mjs` was made to crop into its own bitmap first.
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

# 1. The renders. `frame-hash.mjs` writes them with KEEP=1: 30 scenes x 7
#    variants. The `last` variant — the newest message's glyphs substituted
#    inside its own script, same length, same wrapping, same times — is what
#    makes this a collision test rather than thirty different pictures. The three
#    `panel` variants put *our* keyboard on screen with the AI result panel
#    loading, at two shimmer phases, which is the state every real reading is
#    measured in and the one the harness used to have no render of at all.
COUNT=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$COUNT" -lt 210 ]; then
  echo "==> Rendering the corpus variants (frame-hash.mjs, KEEP=1)"
  command -v node > /dev/null || fail "node is not installed; cannot render the corpus"
  (cd .. && KEEP=1 node harness/frame-hash.mjs) > /dev/null || fail "frame-hash.mjs did not render"
  COUNT=$(ls "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
fi
[ "$COUNT" -ge 210 ] || fail "expected 210 renders in $OUT, found $COUNT"

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
