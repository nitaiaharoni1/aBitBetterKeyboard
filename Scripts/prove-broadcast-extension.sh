#!/bin/bash
#
# Proves what can be proved about the broadcast upload extension without a phone.
#
#   Scripts/prove-broadcast-extension.sh ['platform=iOS Simulator,name=iPhone 17 Pro']
#
# Six checks, each able to fail on its own:
#
#   1. The .appex is built and embedded inside the app's PlugIns.
#   2. Its Info.plist declares the broadcast upload extension point, the
#      sample-buffer process mode and a principal class, all fully expanded.
#      RPBroadcastProcessMode is the one that fails quietly: without it the
#      handler is never called and the broadcast starts and delivers nothing.
#   3. Its bundle identifier sits under the containing app's, which iOS requires
#      of an embedded extension.
#  3b. That same identifier is the one BroadcastPickerButton asks the picker for.
#      A mismatch is silent: the picker lists everything or nothing.
#   4. Its binary carries the App Group entitlement, read out of the Mach-O
#      rather than the signature.
#   5. The class named in the Info.plist exists in the shipped binary, under the
#      Objective-C name the runtime will look it up by.
#
# THIS SCRIPT CANNOT PROVE A FRAME EVER ARRIVES, and does not try to. The iOS
# Simulator runtime ships no replayd, so no broadcast session can start here and
# processSampleBuffer is never called. That verdict needs a device. See the
# closing note, and .claude/docs/replaykit-contract.md.

set -uo pipefail

cd "$(dirname "$0")/.."

DESTINATION="${1:-platform=iOS Simulator,name=iPhone 17 Pro}"
PROJECT="AIKeyboard.xcodeproj"
SCHEME="AIKeyboard"
APP_ID="com.nitai.aikeyboard"
EXT_NAME="AIKeyboardBroadcast"
GROUP_ID="group.com.nitai.aikeyboard"
LOG="$(mktemp -t broadcastext)"

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; exit 1; }

echo "==> Building for $DESTINATION"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" > "$LOG" 2>&1 \
  || { tail -30 "$LOG"; fail "build"; }

APP=$(grep -o '/[^ ]*/Debug-iphonesimulator/AIKeyboard.app' "$LOG" | head -1)
if [ -z "$APP" ]; then
  # An up-to-date build prints no product paths. Ask the build system instead.
  APP="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -destination "$DESTINATION" \
          -configuration Debug -showBuildSettings 2>/dev/null \
          | awk -F' = ' '/ TARGET_BUILD_DIR = /{print $2; exit}')/AIKeyboard.app"
fi
[ -d "$APP" ] || fail "could not find the built .app (see $LOG)"

APPEX="$APP/PlugIns/$EXT_NAME.appex"
BIN="$APPEX/$EXT_NAME"
PLIST="$APPEX/Info.plist"

# 1 -----------------------------------------------------------------------
echo "==> 1. The extension is built and embedded"
[ -d "$APPEX" ] || fail "no $EXT_NAME.appex in $APP/PlugIns"
[ -x "$BIN" ] || fail "$EXT_NAME.appex carries no executable"
pass "PlugIns/$EXT_NAME.appex, $(du -k "$BIN" | cut -f1) KB executable"

# 2 -----------------------------------------------------------------------
# Values are read out of the built bundle, so an unexpanded $(PRODUCT_...) or a
# key that never made it through the build is a failure here rather than a
# surprise on device.
echo "==> 2. Info.plist declares a sample-buffer broadcast upload extension"
[ -f "$PLIST" ] || fail "no Info.plist in the .appex"

plist_value() { plutil -extract "NSExtension.$1" raw -o - "$PLIST" 2>/dev/null; }

expect_key() {
  local key="$1" want="$2" got
  got=$(plist_value "$key")
  [ -n "$got" ] || fail "NSExtension.$key is missing"
  [ "$got" = "$want" ] || fail "NSExtension.$key is \"$got\", expected \"$want\""
  pass "$key = $want"
}

expect_key NSExtensionPointIdentifier com.apple.broadcast-services-upload
expect_key RPBroadcastProcessMode RPBroadcastProcessModeSampleBuffer

PRINCIPAL=$(plist_value NSExtensionPrincipalClass)
[ -n "$PRINCIPAL" ] || fail "NSExtension.NSExtensionPrincipalClass is missing"
case "$PRINCIPAL" in
  *'$('*) fail "NSExtensionPrincipalClass is unexpanded: $PRINCIPAL" ;;
esac
pass "NSExtensionPrincipalClass = $PRINCIPAL"

# 3 -----------------------------------------------------------------------
echo "==> 3. The bundle identifier sits under the app's"
EXT_ID=$(plutil -extract CFBundleIdentifier raw -o - "$PLIST" 2>/dev/null)
case "$EXT_ID" in
  "$APP_ID".*) pass "$EXT_ID" ;;
  *) fail "$EXT_ID is not under $APP_ID; iOS will refuse to load the extension" ;;
esac

# 3b ----------------------------------------------------------------------
# RPSystemBroadcastPickerView.preferredExtension is matched against the installed
# extensions by bundle identifier. A mismatch does not error: the picker simply
# lists every broadcast service on the phone, or none, and the user starts
# somebody else's or nothing at all — which on a device looks exactly like
# "the broadcast doesn't work". The two live in different files with no compiler
# relationship, so nothing but this notices when one moves.
echo "==> 3b. The picker asks for the identifier the extension actually has"
PICKER_SRC="Packages/AIKeyboardCore/Sources/AIKeyboardCore/ScreenContextStrip.swift"
[ -f "$PICKER_SRC" ] || fail "$PICKER_SRC is gone; BroadcastPickerButton has moved"
PREFERRED=$(sed -n 's/.*extensionBundleID = "\([^"]*\)".*/\1/p' "$PICKER_SRC" | head -1)
[ -n "$PREFERRED" ] || fail "no extensionBundleID literal in $PICKER_SRC"
[ "$PREFERRED" = "$EXT_ID" ] \
  && pass "preferredExtension = $PREFERRED" \
  || fail "preferredExtension is \"$PREFERRED\" but the extension is \"$EXT_ID\""

# 4 -----------------------------------------------------------------------
# `codesign -d --entitlements` prints an empty dict for a simulator build, so the
# entitlements are read from the binary's __TEXT,__entitlements section instead —
# the same technique as Scripts/prove-app-group.sh check 1.
echo "==> 4. The binary carries the App Group entitlement"
read_entitlements() {
  otool -X -s __TEXT __entitlements "$1" 2>/dev/null | python3 -c '
import re, sys
words = re.findall(r"\b[0-9a-f]{8}\b", sys.stdin.read())
data = b"".join(bytes.fromhex(w)[::-1] for w in words)
i = data.find(b"<?xml")
sys.stdout.write(data[i:].decode("utf-8", "replace") if i >= 0 else "")
'
}
read_entitlements "$BIN" | grep -q "$GROUP_ID" \
  && pass "$EXT_NAME binary declares $GROUP_ID" \
  || fail "$EXT_NAME binary does not declare $GROUP_ID"

# 5 -----------------------------------------------------------------------
# The plist names the class as "Module.Class"; the runtime finds it under the
# mangled Objective-C name, because the handler subclasses an Objective-C class.
# Deriving that name from the plist string and demanding the symbol is what makes
# this a check on the two agreeing rather than on either one alone.
echo "==> 5. The principal class exists in the binary"
MANGLED=$(PRINCIPAL="$PRINCIPAL" python3 -c '
import os, sys
value = os.environ["PRINCIPAL"]
parts = value.split(".")
if len(parts) != 2 or not all(parts):
    sys.exit(1)
module, cls = parts
print(f"_TtC{len(module)}{module}{len(cls)}{cls}")
') || fail "NSExtensionPrincipalClass \"$PRINCIPAL\" is not a Module.Class name"

# In a Debug build Xcode splits the code into a .debug.dylib next to the stub
# executable, so the class is in one of the two. A Release build has only the one.
# `nm -a` rather than `nm -g`, because Release keeps the class symbol local and
# `nm -g` reports nothing for a binary that plainly contains the class.
# Symbols are read once into a variable rather than piped into `grep -q`.
# `grep -q` exits the moment it matches, which SIGPIPEs `nm`, and under
# `set -o pipefail` the pipeline then reports 141 no matter what grep found.
# That bit this script: the check below failed on a binary that plainly
# contained the symbol. Any short-output check that appeared to work was
# winning a race, not passing.
SYMBOL="_OBJC_CLASS_\$_$MANGLED"
FOUND=""
SYMS=""
for image in "$BIN" "$BIN.debug.dylib"; do
  [ -f "$image" ] || continue
  candidate=$(nm -a "$image" 2>/dev/null || true)
  case "$candidate" in
    *"$SYMBOL"*) FOUND="$image"; SYMS="$candidate"; break ;;
  esac
done
[ -n "$FOUND" ] \
  || fail "no $SYMBOL in $EXT_NAME or its debug dylib; the Info.plist names a class that is not there"
pass "$MANGLED defined in ${FOUND##*/}"

# A class by that name is not enough, and this is not hypothetical: a
# `final class SampleHandler: NSObject {}` with no ReplayKit import at all
# passed every check above and printed "Proved". ReplayKit only calls a class
# that actually subclasses RPBroadcastSampleHandler and actually overrides the
# delivery callback, and the compiler catches neither — Swift compiles a
# SampleHandler that is not one, and an override whose signature drifted
# compiles as a brand new method. With no replayd on this destination there is
# no runtime backstop, so it is caught statically or not at all.

UNDEF=$(nm -mu "$FOUND" 2>/dev/null || true)
case "$UNDEF" in
  *'_OBJC_CLASS_$_RPBroadcastSampleHandler'*) ;;
  *) fail "$EXT_NAME does not reference RPBroadcastSampleHandler; its principal class is not a broadcast handler" ;;
esac
pass "subclasses RPBroadcastSampleHandler (undefined external from ReplayKit)"

# The ObjC thunk for processSampleBuffer(_:with:), present only when the class
# overrides it with the signature ReplayKit dispatches to. An override whose
# signature drifted mangles differently and this goes red.
case "$SYMS" in
  *processC6Buffer_4withySo08CMSampleF3Refa_So08RPSampleF4TypeVtFTo*) ;;
  *) fail "$EXT_NAME has no ObjC entry point for processSampleBuffer(_:with:); frames would never be delivered" ;;
esac
pass "overrides processSampleBuffer(_:with:) with the signature ReplayKit calls"

# -------------------------------------------------------------------------
echo
echo "Proved: the extension builds, embeds, declares the three keys ReplayKit"
echo "requires, is entitled to $GROUP_ID, and that the class its Info.plist"
echo "names is a real RPBroadcastSampleHandler subclass overriding the frame"
echo "delivery callback with the signature ReplayKit dispatches to."
echo
echo "Check 4 is simulator-only by construction: a device Release .appex carries"
echo "no __TEXT,__entitlements section at all, because entitlements live in the"
echo "code signature there. Pointed at a device build this script would fail"
echo "spuriously rather than tell you something true."
echo
echo "NOT proved, and not provable here: that a frame ever arrives. The iOS"
echo "Simulator runtime ships no replayd, so no broadcast session can start on"
echo "this destination and processSampleBuffer is never called. Whether frames"
echo "are delivered, at what size and pixel format, and what the extension's"
echo "memory baseline is against the ~50 MB cap are all device measurements, and"
echo "none of them has been taken."
