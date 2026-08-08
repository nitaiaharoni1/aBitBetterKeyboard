#!/bin/bash
#
# Proves the capture channel carries a reading between two processes.
#
#   Scripts/prove-capture-channel.sh ['platform=iOS Simulator,name=iPhone 17 Pro']
#
# A separate script from prove-app-group.sh rather than a fifth check inside it,
# for two reasons. It answers a different question — that one asks whether the
# App Group is shared at all, this one whether the mmap'd pages and the freshness
# gate work across the boundary — and it is the slower of the two, because it has
# to hold both processes live for fourteen seconds while a timeline plays out.
# Folding it in would make the cheap proof pay for the expensive one.
#
# Six checks, each able to fail on its own:
#
#   1. AIKeyboardShared is linked into the broadcast extension and AIKeyboardCore
#      is not, read out of the Mach-O. The whole point of the split is that a
#      ~50 MB process does not get SwiftUI.
#   2. The shipping fingerprint clears the §5.5 acceptance criteria: 0 misses and
#      0 false invalidations over the corpus, in both configurations — with the
#      host's keyboard on screen and with *our own*, panel open and its loading
#      shimmer at two phases. The second pair is §5.5.1 and it is not decoration:
#      over the band that keeps our keyboard, our own animation gives all 30
#      frames a new identity, which retires the answer to the tap that paid for
#      it. Skipped only if the renders are absent and node is not installed, and
#      it says so loudly.
#   3. Both processes run and the keyboard extension reports in at all.
#   4. The keyboard extension read the session identifier the *other* process
#      wrote. This is the one a unit test cannot do.
#   5. The keyboard extension saw the identity change under it, which means it is
#      reading a live mapping and not a snapshot taken when it opened.
#   6. The freshness gate ran on that cross-process data and moved from
#      `offerable` to `superseded` when the conversation changed. That transition
#      is the product behaviour this whole design exists for.
#
# WHAT THIS SCRIPT CANNOT PROVE, and does not try to: that the *broadcast
# extension* is the process on the producing end. The iOS Simulator runtime ships
# no replayd, so no broadcast session can start here, AIKeyboardBroadcast is never
# launched and processSampleBuffer is never called. The producer in check 3
# onwards is the containing app running CaptureChannelProbe, which drives the same
# CaptureChannelWriter and the same FrameFingerprint over synthetic frames. That
# makes the channel, the pages, the seqlock and the gate genuinely cross-process;
# it does not make ReplayKit's half of it tested. See
# .claude/docs/replaykit-contract.md and the closing note.

set -uo pipefail

cd "$(dirname "$0")/.."

DESTINATION="${1:-platform=iOS Simulator,name=iPhone 17 Pro}"
PROJECT="AIKeyboard.xcodeproj"
SCHEME="AIKeyboard"
APP_ID="com.nitai.aikeyboard"
EXT_NAME="AIKeyboardBroadcast"
LOG="$(mktemp -t capturechannel)"

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

echo "==> Building for $DESTINATION"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" > "$LOG" 2>&1 \
  || { tail -30 "$LOG"; fail "build"; }

APP=$(grep -o '/[^ ]*/Debug-iphonesimulator/AIKeyboard.app' "$LOG" | head -1)
if [ -z "$APP" ]; then
  APP="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
          -configuration Debug -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ TARGET_BUILD_DIR = /{print $2; exit}')/AIKeyboard.app"
fi
[ -d "$APP" ] || fail "could not find the built .app (see $LOG)"

# 1 -----------------------------------------------------------------------
# A Debug build splits the code into a stub executable and a .debug.dylib, so
# both images are examined. Release has only the one.
echo "==> 1. The broadcast extension links AIKeyboardShared and not AIKeyboardCore"
APPEX="$APP/PlugIns/$EXT_NAME.appex"
[ -d "$APPEX" ] || fail "no $EXT_NAME.appex in $APP/PlugIns"

SHARED_FOUND=""
CORE_FOUND=""
for image in "$APPEX/$EXT_NAME" "$APPEX/$EXT_NAME.debug.dylib"; do
  [ -f "$image" ] || continue
  SYMS=$(nm -a "$image" 2>/dev/null || true)
  case "$SYMS" in *"Sources/AIKeyboardShared"*) SHARED_FOUND="$image" ;; esac
  case "$SYMS" in *"Sources/AIKeyboardCore/"*) CORE_FOUND="$image" ;; esac
done
[ -n "$SHARED_FOUND" ] || fail "$EXT_NAME contains no AIKeyboardShared code; it cannot write the channel"
pass "AIKeyboardShared compiled into ${SHARED_FOUND##*/}"

[ -z "$CORE_FOUND" ] || fail "$EXT_NAME contains AIKeyboardCore code, which drags SwiftUI into a ~50 MB process"
pass "no AIKeyboardCore code in the extension"

LINKED=$(for image in "$APPEX/$EXT_NAME" "$APPEX/$EXT_NAME.debug.dylib"; do
  [ -f "$image" ] && otool -L "$image" 2>/dev/null
done)
case "$LINKED" in
  *SwiftUI*) fail "$EXT_NAME links SwiftUI" ;;
esac
pass "no SwiftUI in the extension's load commands"
printf '  note %s KB extension binary, %s KB debug dylib\n' \
  "$(du -k "$APPEX/$EXT_NAME" | cut -f1)" \
  "$([ -f "$APPEX/$EXT_NAME.debug.dylib" ] && du -k "$APPEX/$EXT_NAME.debug.dylib" | cut -f1 || echo 0)"

# 2 -----------------------------------------------------------------------
# The fingerprint is the only thing standing between the user and a reply about
# the wrong conversation (§6 condition 4 is an exact-equality test and the only
# content condition in the gate), so its two zeros are checked here rather than
# taken on trust from the design document.
echo "==> 2. The shipping fingerprint clears the acceptance criteria"
if [ ! -d Bar/screen-context/harness/frame-hash-out ] && ! command -v node > /dev/null; then
  fail "no rendered corpus and no node to render it with; the fingerprint is unchecked"
fi
FINGERPRINT=$(Bar/screen-context/harness/run-fingerprint.sh 2>&1)
RC=$?
echo "$FINGERPRINT" | grep -E "^(identity|settleHash)" | sed 's/^/  /'
[ $RC -eq 0 ] || { echo "$FINGERPRINT" | tail -10; fail "the fingerprint missed a conversation switch, moved on chrome, or moved on our own shimmer"; }
pass "0 misses, 0 false invalidations over the 30-scene corpus, host keyboard and ours"
echo "$FINGERPRINT" | grep -F "the panel variant can still see" | sed 's/^ *PASS/  witness/'

# 3 -----------------------------------------------------------------------
echo "==> 3. Both processes run"
BOOTED=$(xcrun simctl list devices booted -j 2>/dev/null | DEST="$DESTINATION" python3 -c '
import json, os, sys
dest = os.environ["DEST"]
want = dict(p.split("=", 1) for p in dest.split(",") if "=" in p)
devices = [d for rt in json.load(sys.stdin)["devices"].values() for d in rt]
for d in devices:
    if d["udid"] == want.get("id") or d["name"] == want.get("name"):
        print(d["udid"]); raise SystemExit
' 2>/dev/null)
[ -n "$BOOTED" ] || fail "the destination simulator is not booted; boot it first"

SINCE=$(date '+%Y-%m-%d %H:%M:%S')
xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  -only-testing:AIKeyboardUITests/CaptureChannelCrossProcessTests > "$LOG" 2>&1
TEST_RC=$?
if grep -q "Test skipped" "$LOG"; then
  grep -m1 "Test skipped" "$LOG"
  fail "the extension never ran, so nothing was proved either way"
fi

logs() {
  xcrun simctl spawn "$BOOTED" log show --start "$SINCE" \
    --predicate "subsystem == \"com.nitai.aikeyboard\" AND process == \"$1\"" \
    --style compact 2>/dev/null
}

# The producing side, for cross-checking only. Nothing here is evidence on its
# own: a process always sees its own writes.
PROBE=$(logs AIKeyboard | grep -o 'channel-probe .*')
# The consuming side. This is the evidence.
WATCH=$(logs AIKeyboardExtension | grep -o 'channel-watch .*')

[ -n "$PROBE" ] || fail "the app process never wrote to the channel (see $LOG)"
[ -n "$WATCH" ] || fail "the keyboard extension process never reported reading the channel"
pass "$(echo "$PROBE" | wc -l | tr -d ' ') producer lines, $(echo "$WATCH" | wc -l | tr -d ' ') consumer lines"
echo "  extension said: $(echo "$WATCH" | head -1)"
echo "                  $(echo "$WATCH" | tail -1)"

case "$WATCH" in
  *storage=processLocal*) fail "the extension could not reach the App Group container" ;;
esac
pass "the extension reports storage=appGroup"

# 4 -----------------------------------------------------------------------
echo "==> 4. The extension read a value the other process wrote"
# The last session on each side, not the first: the test launches the app twice
# (iOS will not offer a keyboard whose containing app has never run), so the
# producer begins a session per launch and only the last one is live.
PROBE_SESSION=$(echo "$PROBE" | grep -o 'session=[0-9A-F-]*' | tail -1 | cut -d= -f2)
WATCH_SESSION=$(echo "$WATCH" | grep -o 'session=[0-9A-F-]*' | tail -1 | cut -d= -f2)
[ -n "$PROBE_SESSION" ] || fail "the producer logged no session identifier"
[ "$WATCH_SESSION" = "$PROBE_SESSION" ] \
  || fail "the extension ended on session $WATCH_SESSION, the producer on $PROBE_SESSION"
pass "session $PROBE_SESSION, written by AIKeyboard, read by AIKeyboardExtension"

# 5 -----------------------------------------------------------------------
# Two distinct identities in the consumer's own log is what separates a live
# mapping from a snapshot: a reader that opened the file once and cached its
# contents would report one identity forever.
echo "==> 5. The extension saw the page change under it"
IDENTITIES=$(echo "$WATCH" | grep -o 'identity=[0-9a-f]*' | sort -u | grep -cv 'identity=none')
[ "$IDENTITIES" -ge 2 ] \
  || fail "the extension saw $IDENTITIES distinct frame identities; a live mapping shows at least 2"
pass "$IDENTITIES distinct frame identities observed by the reading process"

# 6 -----------------------------------------------------------------------
# The product behaviour, end to end and across the boundary: a reading of the
# screen that is on show is offerable, and the moment the screen changes it is
# not. Condition 4 of the freshness gate is the only thing that catches the
# second case and it is being exercised here on data the reader did not write.
echo "==> 6. The freshness gate retired the reading when the conversation changed"
echo "$WATCH" | grep -q 'verdict=offerable reading=Maya' \
  || fail "the extension never found the reading offerable; the gate refused a fresh reading"
pass "verdict=offerable while the reading matched the frame on screen"

# Scoped to the offerable lines that carry a reading. A trailing
# `offerable reading=none` is an ordinary state — the gate is happy and there is
# simply nothing published yet — and matching it here made the ordering check
# pass or fail on which state the timeline happened to end in.
OFFERABLE_LINE=$(echo "$WATCH" | grep -n 'verdict=offerable reading=[^n]' | tail -1 | cut -d: -f1)
SUPERSEDED_LINE=$(echo "$WATCH" | grep -n 'verdict=superseded' | tail -1 | cut -d: -f1)
[ -n "$SUPERSEDED_LINE" ] \
  || fail "the extension never retired the reading; a stale reply would have been offered"
[ "$SUPERSEDED_LINE" -gt "$OFFERABLE_LINE" ] \
  || fail "superseded came before offerable; the timeline did not play out"
pass "verdict=superseded once the producer changed the frame identity"

[ $TEST_RC -eq 0 ] \
  && pass "the UI driver also finished cleanly" \
  || echo "  note: the UI driver did not finish cleanly (rc=$TEST_RC); the extension's own
        report above is what proves the read. Full log: $LOG"

# -------------------------------------------------------------------------
echo
echo "Proved: two processes on this machine share the capture channel. The"
echo "keyboard extension read a session identifier, a live sequence of frame"
echo "identities and a ScreenReadingRecord written by a different process, and"
echo "its freshness gate moved from offerable to superseded when the frame"
echo "identity changed underneath it. Only text and hashes crossed: the pages"
echo "hold timestamps, counters and a SHA-256, and reading.json has no image"
echo "field to put pixels in."
echo
echo "NOT proved, and not provable here: that the producing process is the"
echo "broadcast extension. The iOS Simulator runtime ships no replayd, so no"
echo "broadcast session starts on this destination, AIKeyboardBroadcast is never"
echo "launched, and processSampleBuffer is never called. The producer above is"
echo "the containing app driving the same CaptureChannelWriter and the same"
echo "FrameFingerprint over synthetic frames. Whether ReplayKit delivers frames,"
echo "in what pixel format, and what the extension's memory baseline is against"
echo "the ~50 MB cap are all device measurements, and none has been taken."
