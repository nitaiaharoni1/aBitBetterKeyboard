#!/bin/bash
# Measures what Vision costs a process, on both deployments this machine can reach.
#
#   Bar/screen-context/harness/run-memory.sh [simulator-name]
#
# Two columns, and the difference between them is the finding, not noise:
# macOS maps the Apple Neural Engine frameworks and the iOS Simulator does not.
# A physical iPhone is an ANE configuration, so the macOS column is the closer
# analogue of the device and the simulator column is the optimistic one. Neither
# is a device number. Nothing here can produce a device number.
#
# Fails rather than skips, in the manner of Scripts/prove-app-group.sh: no
# booted simulator, a build error, a missing image or a task_info that will not
# answer all exit non-zero. A probe that cannot measure must print no number.
set -uo pipefail

cd "$(dirname "$0")"
IMAGES="$(cd ../images && pwd)"
SIM_NAME="${1:-iPhone 17 Pro}"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

CONFIGS="${CONFIGS:-decode jpeg rects fast accurate accurate-en}"
SCALES="${SCALES:-1.0}"

[ -d "$IMAGES" ] || fail "no images directory at $IMAGES"
COUNT=$(ls "$IMAGES"/*.png 2>/dev/null | wc -l | tr -d ' ')
[ "$COUNT" -ge 30 ] || fail "expected 30 bar images, found $COUNT"

echo "==> Building both deployments"
xcrun -sdk macosx swiftc -O memory.swift -o "$BUILD/memory-macos" 2>&1 | grep -E "error:" && fail "macOS build"
[ -x "$BUILD/memory-macos" ] || fail "macOS build produced no binary"
pass "macOS binary"

SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun -sdk iphonesimulator swiftc -O -target arm64-apple-ios26.0-simulator -sdk "$SIM_SDK" \
  memory.swift -o "$BUILD/memory-ios" 2>&1 | grep -E "error:" && fail "simulator build"
[ -x "$BUILD/memory-ios" ] || fail "simulator build produced no binary"
pass "iOS Simulator binary"

UDID=$(xcrun simctl list devices booted -j 2>/dev/null | SIM="$SIM_NAME" python3 -c '
import json, os, sys
want = os.environ["SIM"]
for rt in json.load(sys.stdin)["devices"].values():
    for d in rt:
        if d["name"] == want:
            print(d["udid"]); raise SystemExit
' 2>/dev/null)
[ -n "$UDID" ] || fail "no booted simulator named '$SIM_NAME'; boot it, do not skip"
pass "simulator $SIM_NAME booted"

# The ANE control. If these two ever agree, the columns below stop meaning what
# the design doc says they mean and the doc has to be re-argued.
MAC_ANE=$("$BUILD/memory-macos" "$IMAGES" decode 1.0 | awk '/^ane-mapped/ {$1=""; print}')
SIM_ANE=$(xcrun simctl spawn "$UDID" "$BUILD/memory-ios" "$IMAGES" decode 1.0 | awk '/^ane-mapped/ {$1=""; print}')
echo "  macOS  ANE frameworks:$MAC_ANE"
echo "  sim    ANE frameworks:$SIM_ANE"
case "$MAC_ANE" in *AppleNeuralEngine*) pass "macOS is an ANE deployment" ;;
  *) fail "macOS mapped no ANE framework; the control this doc rests on is gone" ;; esac
case "$SIM_ANE" in *AppleNeuralEngine*) fail "the simulator mapped an ANE framework; it is no longer the non-ANE control" ;;
  *) pass "the iOS Simulator is not an ANE deployment" ;; esac

printf '\n%-14s %-6s %14s %14s\n' config scale "macOS peak MB" "sim peak MB"
for scale in $SCALES; do
  for config in $CONFIGS; do
    MAC=$("$BUILD/memory-macos" "$IMAGES" "$config" "$scale") || fail "macOS $config $scale"
    SIM=$(xcrun simctl spawn "$UDID" "$BUILD/memory-ios" "$IMAGES" "$config" "$scale") || fail "sim $config $scale"
    MP=$(echo "$MAC" | awk '/^peak/ {print $2}')
    SP=$(echo "$SIM" | awk '/^peak/ {print $2}')
    [ -n "$MP" ] && [ -n "$SP" ] || fail "$config $scale produced no peak on one side"
    printf '%-14s %-6s %14s %14s\n' "$config" "$scale" "$MP" "$SP"
  done
done

echo
echo "Peak is the number that decides the design: jetsam reads phys_footprint, and"
echo "an extension dies at its ceiling rather than degrading. Neither column is a"
echo "device measurement. Run this on a device before believing any of it fits."
