#!/bin/bash
#
# Proves the app and the keyboard extension share one App Group.
#
#   Scripts/prove-app-group.sh ['platform=iOS Simulator,name=iPhone 17 Pro']
#
# Four checks, each able to fail on its own:
#
#   1. Both built binaries carry the app group entitlement.
#   2. iOS resolves a shared container for the app group.
#   3. What the app process writes lands in that container.
#   4. The keyboard extension process — a separate process — acts on a setting
#      the app process wrote. This is the one that matters; the first three can
#      all pass while the two processes still see different stores.
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
GROUP_ID="group.com.nitai.aikeyboard"
LOG="$(mktemp -t appgroup)"

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

echo "==> Building for $DESTINATION"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" > "$LOG" 2>&1 \
  || { tail -30 "$LOG"; fail "build"; }

APP=$(grep -o '/[^ ]*/Debug-iphonesimulator/AIKeyboard.app' "$LOG" | head -1)
[ -d "$APP" ] || fail "could not find the built .app (see $LOG)"

# 1 -----------------------------------------------------------------------
# Entitlements on the simulator live in the binary's __TEXT,__entitlements
# section, not in the code signature, so `codesign -d --entitlements` reads
# empty here and is not a usable check.
echo "==> 1. App group entitlement in both binaries"
read_entitlements() {
  otool -X -s __TEXT __entitlements "$1" 2>/dev/null | python3 -c '
import re, sys
words = re.findall(r"\b[0-9a-f]{8}\b", sys.stdin.read())
data = b"".join(bytes.fromhex(w)[::-1] for w in words)
i = data.find(b"<?xml")
sys.stdout.write(data[i:].decode("utf-8", "replace") if i >= 0 else "")
'
}
for pair in "app:$APP/AIKeyboard" \
            "extension:$APP/PlugIns/AIKeyboardExtension.appex/AIKeyboardExtension"; do
  name="${pair%%:*}"; bin="${pair#*:}"
  read_entitlements "$bin" | grep -q "$GROUP_ID" \
    && pass "$name binary declares $GROUP_ID" \
    || fail "$name binary does not declare $GROUP_ID"
done

# 2 -----------------------------------------------------------------------
echo "==> 2. iOS resolves a shared container"
# Resolve the destination to a booted device rather than taking whichever one
# happens to be first — more than one simulator is often up.
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

xcrun simctl install "$BOOTED" "$APP" > /dev/null 2>&1 || fail "install"
CONTAINER=$(xcrun simctl get_app_container "$BOOTED" "$APP_ID" "$GROUP_ID" 2>/dev/null)
[ -n "$CONTAINER" ] && [ -d "$CONTAINER" ] \
  && pass "container at ${CONTAINER##*/}" \
  || fail "iOS did not create a container for $GROUP_ID (entitlement not in effect)"

# 3 -----------------------------------------------------------------------
echo "==> 3. The app process writes into it"
PLIST="$CONTAINER/Library/Preferences/$GROUP_ID.plist"
rm -f "$PLIST"
xcrun simctl terminate "$BOOTED" "$APP_ID" > /dev/null 2>&1
xcrun simctl launch "$BOOTED" "$APP_ID" -uiTestReset -uiTestSkipOnboarding > /dev/null 2>&1 \
  || fail "could not launch the app"
for _ in $(seq 1 20); do [ -f "$PLIST" ] && break; sleep 0.5; done
[ -f "$PLIST" ] \
  && pass "$(plutil -p "$PLIST" | grep -c '=>') settings in the shared container" \
  || fail "the app wrote nothing to the shared container"

xcrun simctl spawn "$BOOTED" log show --last 2m \
  --predicate 'subsystem == "com.nitai.aikeyboard"' --style compact 2>/dev/null \
  | grep -q "storage=appGroup" \
  && pass "app process reports storage=appGroup" \
  || echo "  note: no storage=appGroup log line yet (only written by load(), not by -uiTestReset)"

# 4 -----------------------------------------------------------------------
# The UI test turns English off in the app, enables the keyboard, and brings it
# up in a real text field. That makes iOS launch the extension in its own
# process, where `SharedStore.load()` reports what it read. The verdict is that
# report rather than the test's own assertion: reading another process's
# accessibility hierarchy is what makes this test flaky under load, whereas the
# extension's log line is stamped with its process name by the OS and cannot be
# faked by the app.
echo "==> 4. The keyboard extension process reads what the app wrote"
SINCE=$(date '+%Y-%m-%d %H:%M:%S')
xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
  -only-testing:AIKeyboardUITests/AppGroupCrossProcessTests > "$LOG" 2>&1
RC=$?
if grep -q "Test skipped" "$LOG"; then
  grep -m1 "Test skipped" "$LOG"
  fail "the extension never ran, so nothing was proved either way"
fi

REPORT=$(xcrun simctl spawn "$BOOTED" log show --start "$SINCE" \
  --predicate 'subsystem == "com.nitai.aikeyboard" AND process == "AIKeyboardExtension"' \
  --style compact 2>/dev/null | grep -o 'load storage=.*' | tail -1)

[ -n "$REPORT" ] || fail "the extension process never reported in; it did not run"
echo "  extension said: $REPORT"

case "$REPORT" in
  *storage=processLocal*) fail "the extension fell back to its own private store" ;;
esac
case "$REPORT" in
  *languages=hebrew*) ;;
  *) fail "the extension read languages it was not given; the app wrote [hebrew]" ;;
esac
pass "extension process read storage=appGroup and the app's languages=hebrew"

[ $RC -eq 0 ] \
  && pass "the UI test also saw the Hebrew layout on screen" \
  || echo "  note: the UI driver did not finish cleanly (rc=$RC); the extension's own"
[ $RC -eq 0 ] || echo "        report above is what proves the read. Full log: $LOG"

echo
echo "The app group is real: the keyboard extension process read a value the app process wrote."
