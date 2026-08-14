#!/bin/bash
#
# Proves the keyboard extension dictates through a session held by another
# process.
#
#   Scripts/prove-dictation.sh ['platform=iOS Simulator,name=iPhone 17 Pro']
#
# Five checks, each able to fail on its own:
#
#   0. The extension does not set `hasDictationKey = true`. Face ID phones
#      may draw Apple's dictation mic in the system dock; that is wanted.
#      A build that puts the assignment back is the broken one.
#   1. The keyboard extension does NOT link AVFoundation. It cannot open the
#      microphone — Apple's guidance says so and the runtime answers 561145187 —
#      so a build in which it tries is a build that has misunderstood the design.
#   2. The app declares the `audio` background mode. Without it the recording
#      session dies the moment the user switches to the app they are writing in,
#      which is the entire use case.
#   3. Both processes run and the keyboard reports what it can see.
#   4. The keyboard extension process — a separate process — receives a
#      partial published by the app process. This is the one that matters:
#      the first three can all pass while the two processes see different pages.
#      A stop after that partial keeps those words; it does not wait for a
#      later cloud sentence.
#
# WHAT THIS DOES NOT PROVE, and nothing in this repo does yet:
#
#   * that `AVAudioEngine` records anything. `DictationChannelProbe` replaces the
#     microphone with a fixed sentence, because a UI test cannot speak.
#   * that a recording session survives backgrounding under jetsam, or that an
#     interruption is handled. Those are device behaviours; a simulator cannot
#     settle them.
#   * that transcription is any good. That is `Bar/dictation/`, scored against
#     36 clips and 29 more languages, and it is measured separately.
#
# Check 4 drives real UI and needs an uncontended simulator. If another test run
# is already using the destination it will be killed mid-run and report as a
# crash rather than a failure.

set -uo pipefail

cd "$(dirname "$0")/.."

DESTINATION="${1:-platform=iOS Simulator,name=iPhone 17 Pro}"
PROJECT="AIKeyboard.xcodeproj"
SCHEME="AIKeyboard"
APP_ID="com.nitai.aikeyboard"
# The reading the recorder publishes half a second in. A prefix of
# `DictationChannelProbe.sentence`, and the keyboard truncates what it logs
# to 24 characters — see `DictationSession.report()`.
PARTIAL="בוא נעשה"
LOG="$(mktemp -t dictation)"

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

# 0 -----------------------------------------------------------------------
# Setting hasDictationKey hides Apple's dock microphone. We want that mic.
# Match an assignment line only, in any Swift file: a comment that names the
# property must not trip this, and moving the line out of the view controller
# must not hide it.
echo "==> 0. The extension does not suppress Apple's dock microphone"
if grep -R --include='*.swift' -nE \
    '^[[:space:]]*(self\.)?hasDictationKey[[:space:]]*=[[:space:]]*true' \
    AIKeyboardExtension Packages AIKeyboard
then
  fail "a Swift file sets hasDictationKey; that hides Apple's dock microphone"
else
  pass "no Swift file sets hasDictationKey"
fi

echo "==> Building for $DESTINATION"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" > "$LOG" 2>&1 \
  || { tail -30 "$LOG"; fail "build"; }

APP=$(grep -o '/[^ ]*/Debug-iphonesimulator/AIKeyboard.app' "$LOG" | head -1)
[ -d "$APP" ] || fail "could not find the built .app (see $LOG)"

# 1 -----------------------------------------------------------------------
# The design's load-bearing negative. If this ever fails, somebody has tried to
# record in the keyboard, and the failure it produces on a device is silent:
# `setActive` throws 561145187 and the panel spins forever.
echo "==> 1. The keyboard extension does not link AVFoundation"
EXT="$APP/PlugIns/AIKeyboardExtension.appex/AIKeyboardExtension"
[ -f "$EXT" ] || fail "the keyboard extension binary is missing"
if otool -L "$EXT" 2>/dev/null | grep -qE "AVFAudio|AVFoundation"; then
  otool -L "$EXT" | grep -E "AVFAudio|AVFoundation"
  fail "the keyboard extension links AVFoundation; it cannot open the microphone"
fi
pass "no AVFoundation in the keyboard extension"

# 2 -----------------------------------------------------------------------
echo "==> 2. The app can hold a recording session in the background"
MODES=$(plutil -extract UIBackgroundModes json -o - "$APP/Info.plist" 2>/dev/null)
case "$MODES" in
  *audio*) pass "app declares UIBackgroundModes = $MODES" ;;
  *) fail "the app does not declare the audio background mode; sessions would die on app switch" ;;
esac
plutil -extract NSMicrophoneUsageDescription raw -o - "$APP/Info.plist" > /dev/null 2>&1 \
  && pass "app declares NSMicrophoneUsageDescription" \
  || fail "the app has no microphone usage description; the permission prompt would crash"

# 3, 4 --------------------------------------------------------------------
echo "==> 3. Both processes run, and 4. the keyboard reads what the app published"
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
  -only-testing:AIKeyboardUITests/DictationCrossProcessTests > "$LOG" 2>&1
RC=$?
if grep -q "Test skipped" "$LOG"; then
  grep -m1 "Test skipped" "$LOG"
  fail "the extension never ran, so nothing was proved either way"
fi

logs() {
  xcrun simctl spawn "$BOOTED" log show --start "$SINCE" \
    --predicate "subsystem == \"com.nitai.aikeyboard\" AND process == \"$1\"" \
    --style compact 2>/dev/null
}

APP_LINES=$(logs AIKeyboard | grep -c "dictation-probe")
[ "$APP_LINES" -gt 0 ] \
  && pass "the app process ran a session ($APP_LINES probe lines)" \
  || fail "the app process never started a dictation session"

WATCH=$(logs AIKeyboardExtension | grep -o 'dictation-watch .*')
[ -n "$WATCH" ] || fail "the keyboard extension process never reported in; it did not run"
echo "$WATCH" | sed 's/^/  extension said: /' | tail -6

case "$WATCH" in
  *storage=processLocal*) fail "the extension fell back to its own private store" ;;
esac
echo "$WATCH" | grep -q "availability=noSession" && echo "  (it started from noSession, as it should)"

echo "$WATCH" | grep -q "availability=listening" \
  && pass "the extension saw the other process's session and opened an utterance" \
  || fail "the extension never saw a live session"

# **Streaming is the product now.** The recorder publishes a reading of the
# utterance so far and the keyboard puts it in the field. A second tap keeps
# those words and cancels the utterance, so a later cloud sentence is not
# asked for and must not be required here. A build where the partial never
# crosses leaves the field empty on stop, which is the defect this check
# exists to catch.
echo "$WATCH" | grep -q "partial=$PARTIAL" \
  && pass "the extension received a partial transcript while the utterance was open" \
  || fail "no partial crossed the App Group, so dictation does not stream"

[ $RC -eq 0 ] \
  && pass "the UI driver also finished cleanly" \
  || echo "  note: the UI driver did not finish cleanly (rc=$RC); the extension's own"
[ $RC -eq 0 ] || echo "        report above is what proves the read. Full log: $LOG"

echo
echo "Dictation crosses the process boundary: the keyboard extension received words"
echo "produced by a session it cannot itself hold."
echo
echo "Still unproved anywhere: that a microphone was ever opened. See the header."
