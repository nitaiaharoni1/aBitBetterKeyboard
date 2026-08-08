#!/bin/bash
#
# Reads the nine device-only unknowns off a real iPhone.
#
# Everything else in this repo has been measured against a simulator, a macOS
# build, or a frozen corpus. None of those can answer the questions below,
# because the simulator runtime ships no `replayd`: `processSampleBuffer` has
# never executed anywhere, so every number about *frames* is a prediction.
#
#   R1   Do frames arrive at all, and at what size, pixel format, orientation
#        and rate? The whole design assumes ~4 Hz of BGRA at device resolution.
#   R2   What is the real jetsam ceiling for a broadcast upload extension, and
#        how close does a read come to it?
#   R2c  What does the extension cost before it has seen a single frame?
#   R3   What does a Vision pass cost inside that budget, on device?
#   R7   What does the TLS handshake and upload add on top?
#   R8/9 Can the broadcast picker be presented from a keyboard extension?
#   R11  Does the broadcast survive the screen locking?
#   R14  Does any host app actually populate `isSecureTextEntry` through the
#        document proxy, or do they all answer nil?
#   R16  Are the fingerprint band fractions right on real pixels?
#   R17  Does a rotation break the fingerprint? Nothing rotates the buffer, and
#        the crop band assumes row 0 is the physical top of the screen. If it is
#        not, the band that should exclude our own keyboard excludes something
#        else, and our shimmer starts moving the frame identity again. Step (f)
#        below is what exercises it.
#
# The extension already logs every fact these need. This script installs it,
# captures the log while you drive the phone, and reads the answers back out.
# It measures; it does not judge. A run that answers six of nine is a good run.
#
# Usage:  Scripts/measure-on-device.sh [seconds]      (default 180)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION="${1:-180}"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/Bar/device/$STAMP"
LOG="$OUT/device.log"
SUBSYSTEM="com.nitai.aikeyboard"

mkdir -p "$OUT"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()  { printf '  \033[32mok\033[0m    %s\n' "$*"; }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; }
huh() { printf '  \033[33m?\033[0m     %s\n' "$*"; }

# ---------------------------------------------------------------- 1. the phone

say "1. Finding a connected device"

DEVICES_JSON="$OUT/devices.json"
xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1 || true

UDID="$(python3 - "$DEVICES_JSON" <<'PY'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    sys.exit(0)
for d in devices:
    props = d.get("deviceProperties", {})
    conn = d.get("connectionProperties", {})
    if conn.get("tunnelState") in ("connected", "available") or props.get("developerModeStatus") == "enabled":
        if conn.get("pairingState") == "paired":
            print(d["identifier"])
            break
PY
)"

if [ -z "$UDID" ]; then
    bad "no device is reachable"
    cat <<'EOF'

  On the iPhone:
    1. Plug it in with a cable, and unlock it.
    2. Tap "Trust" if it asks.
    3. Settings > Privacy & Security > Developer Mode > on, then reboot.

  On this Mac, once Xcode has been opened at least once:
    4. Xcode > Settings > Accounts: make sure an Apple ID is signed in.
       Only "Apple Distribution" certificates exist right now, and those
       cannot install a debug build. Xcode creates the development one
       the first time it signs for a device.

  Then run this script again.
EOF
    exit 1
fi
ok "device $UDID"

if ! grep -q 'DEVELOPMENT_TEAM' "$ROOT/AIKeyboard.xcodeproj/project.pbxproj"; then
    bad "the project sets no DEVELOPMENT_TEAM, so a device build cannot sign"
    echo "      open AIKeyboard.xcodeproj, pick the team on every target, and re-run"
    exit 1
fi
ok "project carries a development team"

# ------------------------------------------------------------------- 2. build

say "2. Building for the device"
# `-allowProvisioningUpdates` because no profiles exist for these four bundle IDs
# yet and only Xcode can make them. If this fails with "Revoke certificate", that
# is not something a script should decide: the account holds an Apple Development
# certificate whose private key is not in this keychain, and the only automatic
# way forward revokes it, which breaks it for every other machine using it.
# Either restore the key from a .p12 backup or revoke it deliberately in Xcode >
# Settings > Accounts > Manage Certificates.
xcodebuild build -project "$ROOT/AIKeyboard.xcodeproj" -scheme AIKeyboard \
    -destination "id=$UDID" -allowProvisioningUpdates -derivedDataPath "$OUT/dd" \
    > "$OUT/build.log" 2>&1 || { bad "build failed, see $OUT/build.log"; tail -30 "$OUT/build.log"; exit 1; }
ok "built"

APP="$(find "$OUT/dd/Build/Products" -maxdepth 2 -name 'AIKeyboard.app' -type d | head -1)"
[ -n "$APP" ] || { bad "no .app produced"; exit 1; }

# The one fact worth checking before the phone ever runs it: the capture process
# must not have linked the UIKit/SwiftUI half of the package. Same check as
# Scripts/prove-broadcast-extension.sh, re-run here against the *device* slice,
# because that is the binary whose 50 MB budget is at stake.
APPEX="$APP/PlugIns/AIKeyboardBroadcast.appex/AIKeyboardBroadcast"
if [ -f "$APPEX" ]; then
    SIZE=$(stat -f%z "$APPEX")
    LINKED="$(otool -L "$APPEX" 2>/dev/null || true)"
    if grep -q 'SwiftUI\|UIKitCore' <<<"$LINKED"; then
        bad "the broadcast extension links SwiftUI or UIKit — it must not"
    else
        ok "broadcast extension links neither SwiftUI nor UIKit ($SIZE bytes, arm64)"
    fi
fi

say "3. Installing"
xcrun devicectl device install app --device "$UDID" "$APP" > "$OUT/install.log" 2>&1 \
    || { bad "install failed, see $OUT/install.log"; tail -20 "$OUT/install.log"; exit 1; }
ok "installed"

# -------------------------------------------------------------- 4. the capture

cat <<EOF

$(printf '\033[1m4. Now drive the phone. %ss of log is being captured.\033[0m' "$DURATION")

  a. Open AI Keyboard once, and finish onboarding (this grants Full Access,
     without which the keyboard has neither network nor the App Group).
  b. Open WhatsApp or Messages and put the cursor in the compose field so
     the AI keyboard is showing.
  c. Tap the screen-context / Reply control. Accept the broadcast picker.
       -> this is R8/R9: if the picker never appears, say so.
  d. Wait for a reply to come back. Tap Reply a second time.
  e. Lock the screen for ~10 seconds, unlock, tap Reply once more.
       -> this is R11.
  f. Rotate to landscape and tap Reply once.
  g. Open a login screen somewhere (any app's password field) and note
     whether this keyboard stays on screen or iOS swaps it.
       -> this is R14.

EOF

xcrun devicectl device console --device "$UDID" > "$LOG" 2>/dev/null &
CONSOLE=$!
trap 'kill "$CONSOLE" 2>/dev/null || true' EXIT

for ((i = DURATION; i > 0; i--)); do
    printf '\r  capturing... %3ds left ' "$i"
    sleep 1
done
printf '\r  capture complete.            \n'

kill "$CONSOLE" 2>/dev/null || true
wait "$CONSOLE" 2>/dev/null || true
trap - EXIT

# --------------------------------------------------------------- 5. the answers

grep -F "$SUBSYSTEM" "$LOG" > "$OUT/ours.log" 2>/dev/null || true
LINES=$(wc -l < "$OUT/ours.log" | tr -d ' ')

say "5. What the log answers"
echo "  $LINES lines from $SUBSYSTEM, kept at $OUT/ours.log"
echo

python3 - "$OUT/ours.log" <<'PY'
import re, sys, pathlib

text = pathlib.Path(sys.argv[1]).read_text(errors="replace")

def first(pattern):
    m = re.search(pattern, text)
    return m.groups() if m else None

def every(pattern):
    return re.findall(pattern, text)

GREEN, RED, YELLOW, BOLD, OFF = "\033[32m", "\033[31m", "\033[33m", "\033[1m", "\033[0m"

def verdict(risk, question, answer):
    mark = f"{GREEN}ANSWERED{OFF}" if answer else f"{YELLOW}unanswered{OFF}"
    print(f"  {BOLD}{risk:5}{OFF} {mark}  {question}")
    if answer:
        print(f"          {answer}")
    print()

# R1 — frames at all, and in what shape
fmt = first(r"video first-frame (\d+)x(\d+) format=(\w+)")
verdict("R1", "do frames arrive, and in what size and pixel format?",
        f"{fmt[0]}x{fmt[1]}, format {fmt[2]}" if fmt else None)

orientations = every(r"video orientation=(\w+)")
verdict("R1b", "what orientations were delivered?",
        ", ".join(dict.fromkeys(orientations)) if orientations else None)

progress = every(r"video progress delivered=(\d+) sampled=(\d+) fingerprinted=(\w+)")
if progress:
    d, s, f = progress[-1]
    finger = sum(1 for p in progress if p[2] == "true")
    rate = f"{int(d)} delivered, {int(s)} sampled ({int(d)/max(int(s),1):.1f} delivered per sample)"
    rate += f"; fingerprinted on {finger}/{len(progress)} progress reports"
else:
    rate = None
verdict("R1c", "delivery rate, and does the fingerprint ever fail?", rate)

# R2c — the baseline before any frame
base = first(r"broadcast started .*baselineMB=([\d.]+|unmeasurable)")
verdict("R2c", "what does the extension cost before its first frame?",
        f"{base[0]} MB baseline" if base else None)

# R2 / R3 / R7 — the real ceiling
foot = [float(v) for v in every(r"footprintMB=([\d.]+)")]
if foot:
    peak = max(foot)
    headroom = 50 - peak
    note = f"peak footprint {peak:.1f} MB across {len(foot)} observations (low {min(foot):.1f})"
    note += f"; {headroom:.1f} MB under the nominal 50 MB cap"
    if headroom < 5:
        note += f"  {RED}<- thin{OFF}"
else:
    note = None
verdict("R2/R3/R7", "how close does a read come to the memory ceiling?", note)

degraded = every(r"memory degraded=(\w+)")
verdict("R2b", "did the governor ever refuse a read for memory?",
        f"degraded flipped to: {', '.join(dict.fromkeys(degraded))}" if degraded else None)

# R8/R9 — a session starting at all is the picker working
starts = every(r"broadcast started .*session=([0-9A-Fa-f-]+)")
verdict("R8/R9", "can the broadcast be started from the keyboard?",
        f"{len(starts)} broadcast session(s) started" if starts else None)

# R11 — pause/resume around a lock
pauses, resumes = every(r"broadcast paused"), every(r"broadcast resumed")
verdict("R11", "does the broadcast survive the screen locking?",
        f"{len(pauses)} pause / {len(resumes)} resume, and "
        f"{'it kept going' if resumes else 'it did not come back'}" if pauses else None)

# R16 — the crop band, and the read itself
reads = every(r"read (?:published|finished|refused|gave up)[^\n]*")
verdict("R16", "did a reading actually reach the keyboard?",
        f"{len(reads)} read outcome(s):\n          " + "\n          ".join(reads[:6]) if reads else None)

fin = first(r"broadcast finished delivered=(\d+) sampled=(\d+)")
verdict("--", "session totals",
        f"{fin[0]} frames delivered, {fin[1]} sampled" if fin else None)

print(f"  {BOLD}R14 is not in this log.{OFF} It is the one question only your eyes answer:")
print("  when you tapped into a password field, did this keyboard stay on")
print("  screen, or did iOS replace it with the system keyboard?")
print()
PY

say "Kept in $OUT"
echo "  device.log   everything the phone emitted"
echo "  ours.log     only this app's subsystem"
echo "  build.log    the device build"
