#!/bin/bash
#
# Builds, installs and relaunches the app on a simulator.
#
#   Scripts/run-sim.sh                     # once
#   Scripts/run-sim.sh --watch             # ... and again on every save
#   Scripts/run-sim.sh --host com.apple.MobileSMS
#   Scripts/run-sim.sh --device 'iPhone 17 Pro Max'
#
# There is no "refresh" on iOS: an edit reaches the simulator only by
# rebuilding, reinstalling and relaunching. This is that cycle, and the
# incremental build is why it is seconds rather than a minute — it keeps its own
# derived data under build/, so it never fights Xcode's.
#
# --watch polls the source tree rather than using fswatch/entr/watchexec, none of
# which are installed and none of which this needs: a checksum of every Swift
# file's modification time, once a second, costs nothing next to a build.
#
# **What this cannot do is reload the keyboard inside another app.** iOS hosts
# the extension in the process of whatever app is using it, and reinstalling does
# not evict one that is already running: edit a key, reinstall, open Messages and
# you are looking at the *previous* build. --host names an app to kill for that
# reason. Pass it whichever app you are testing the keyboard in.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="AIKeyboard"
APP_ID="com.nitai.aikeyboard"
DERIVED="$ROOT/build"
APP_PATH="$DERIVED/Build/Products/Debug-iphonesimulator/AIKeyboard.app"
LOG="$DERIVED/run-sim.log"

DEVICE_NAME="iPhone 17 Pro"
WATCH=0
HOSTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --watch) WATCH=1; shift ;;
        --device) DEVICE_NAME="$2"; shift 2 ;;
        --host) HOSTS+=("$2"); shift 2 ;;
        -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# The booted simulator wins over the named one. Booting a second device while one
# is already up gives you two, and installs land on whichever simctl picks.
resolve_device() {
    local booted
    booted="$(xcrun simctl list devices booted -j \
        | /usr/bin/python3 -c 'import json,sys
devices = json.load(sys.stdin)["devices"]
for runtime in devices.values():
    for device in runtime:
        print(device["udid"]); raise SystemExit')"
    if [[ -n "$booted" ]]; then
        echo "$booted"
        return
    fi

    local udid
    udid="$(xcrun simctl list devices available \
        | grep -m1 "^ *${DEVICE_NAME} (" \
        | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
    if [[ -z "$udid" ]]; then
        echo "no simulator named '$DEVICE_NAME'" >&2
        exit 1
    fi
    xcrun simctl boot "$udid"
    xcrun simctl bootstatus "$udid" -b >/dev/null
    open -a Simulator
    echo "$udid"
}

cycle() {
    local udid="$1"
    printf '· building… '

    # Redirected to a file rather than piped: a pipe closed early SIGPIPEs
    # xcodebuild mid-build and leaves its children behind.
    if ! xcodebuild build \
        -project "$ROOT/AIKeyboard.xcodeproj" \
        -scheme "$SCHEME" \
        -destination "platform=iOS Simulator,id=$udid" \
        -derivedDataPath "$DERIVED" \
        >"$LOG" 2>&1; then
        printf 'failed\n'
        grep -E "error:" "$LOG" | sort -u | head -20
        echo "  full log: $LOG"
        return 1
    fi

    # Kill before install. Installing over a running app leaves the old
    # process serving the old binary until something kills it.
    xcrun simctl terminate "$udid" "$APP_ID" >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$APP_PATH"
    # Reinstall drops the extension from Apple's enabled list. The UI tests
    # already document this. Write it back so the next tap on a field still
    # has a keyboard to open.
    restore_enabled_keyboards "$udid"
    if ! launch_app "$udid"; then
        printf 'launch failed\n'
        return 1
    fi

    for host in "${HOSTS[@]:-}"; do
        [[ -n "$host" ]] || continue
        # The point of --host: this is what evicts the stale keyboard extension.
        xcrun simctl terminate "$udid" "$host" >/dev/null 2>&1 || true
    done

    printf 'installed and launched\n'
}

restore_enabled_keyboards() {
    local udid="$1"
    xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleKeyboards -array \
        "en_US@sw=QWERTY;hw=Automatic" \
        "he_IL@sw=Hebrew;hw=Automatic" \
        "emoji@sw=Emoji" \
        "com.nitai.aikeyboard.keyboard" >/dev/null
}

# SpringBoard denies a launch that arrives while it is still tearing down the
# previous process (`SBMainWorkspace` / `FBSOpenApplicationServiceErrorDomain`).
# One atomic handoff, then two retries, beats terminate-and-immediately-launch.
launch_app() {
    local udid="$1"
    local err
    err="$(mktemp)"
    local attempt
    for attempt in 1 2 3; do
        if xcrun simctl launch --terminate-running-process "$udid" "$APP_ID" \
            >/dev/null 2>"$err"; then
            rm -f "$err"
            return 0
        fi
        sleep 0.6
    done
    cat "$err" >&2
    rm -f "$err"
    return 1
}

# Every Swift file's mtime, plus the project file, as one number. Cheap enough to
# ask once a second and it notices a deletion, which a "newest mtime" check does
# not.
signature() {
    find "$ROOT/AIKeyboard" "$ROOT/AIKeyboardExtension" "$ROOT/AIKeyboardBroadcast" \
        "$ROOT/Packages" -name '*.swift' -exec stat -f '%m %N' {} + 2>/dev/null \
        | sort \
        | cat - "$ROOT/AIKeyboard.xcodeproj/project.pbxproj" \
        | cksum
}

mkdir -p "$DERIVED"
UDID="$(resolve_device)"
echo "· simulator $UDID"

# `cycle || …` would disable `set -e` inside the function, so a failed
# launch still printed "installed and launched".
if ! cycle "$UDID"; then
    [[ $WATCH -eq 1 ]] || exit 1
fi

if [[ $WATCH -eq 0 ]]; then
    exit 0
fi

echo "· watching for changes — ctrl-c to stop"
LAST="$(signature)"
while true; do
    sleep 1
    NOW="$(signature)"
    [[ "$NOW" == "$LAST" ]] && continue

    # Settle: a save from an editor can touch several files a few hundred
    # milliseconds apart, and each one would otherwise start its own build.
    while true; do
        sleep 0.4
        SETTLED="$(signature)"
        [[ "$SETTLED" == "$NOW" ]] && break
        NOW="$SETTLED"
    done

    LAST="$NOW"
    printf '\n· change detected %s\n' "$(date '+%H:%M:%S')"
    if ! cycle "$UDID"; then
        :
    fi
done
