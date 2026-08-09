#!/bin/bash
# Rebuilds Bar/layouts/stock-rendered-rows.json by photographing Apple's own
# keyboard and measuring where it puts each key on screen.
#
#   Bar/layouts/capture-rendered.sh              # en_US he_IL ar
#   Bar/layouts/capture-rendered.sh he_IL        # just one
#
# apple-layouts.json is *physical* key order, which is not screen order for a
# right-to-left script — that difference is what shipped every RTL keyboard
# mirrored. This file is the screen order, and RenderedRowOrderTests compares
# this keyboard's own rendering against it.
#
# The wanted layout is made the simulator's *first* keyboard and the device is
# resprung, so the test never presses the globe: the globe kills the XCUITest
# runner on this simulator even with only Apple's keyboards installed
# (Bar/typing/README.md, "The keyboard-switch crash").

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
out="$here/stock-rendered-rows.json"
work="$here/.capture"
layouts=("$@")
[ ${#layouts[@]} -gt 0 ] || layouts=(en_US he_IL ar)

"$repo/Bar/typing/setup-simulator.sh"

backup="$(xcrun simctl spawn booted defaults read .GlobalPreferences AppleKeyboards 2>/dev/null || echo '')"
respring() {
  xcrun simctl spawn booted launchctl kickstart -k system/com.apple.SpringBoard >/dev/null 2>&1 || true
  sleep 10
}
restore_keyboards() {
  echo "restoring the simulator's keyboard list…"
  xcrun simctl spawn booted defaults write .GlobalPreferences AppleKeyboards -array \
    "en_US@sw=QWERTY;hw=Automatic" "he_IL@sw=Hebrew;hw=Automatic" "emoji@sw=Emoji" \
    $(grep -q "com.nitai.aikeyboard.keyboard" <<<"$backup" && echo "com.nitai.aikeyboard.keyboard")
  respring
}
trap restore_keyboards EXIT

mkdir -p "$work/raw"

echo
echo "### building the test bundle"
xcodebuild build-for-testing -project "$repo/AIKeyboard.xcodeproj" -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' >"$work/.build.log" 2>&1 || {
  echo "build-for-testing failed; see $work/.build.log" >&2
  grep -m5 "error:" "$work/.build.log" >&2 || true
  exit 1
}

for layout in "${layouts[@]}"; do
  echo
  echo "=== $layout ==="
  case "$layout" in
    en_US) first="en_US@sw=QWERTY;hw=Automatic" ;;
    he_IL) first="he_IL@sw=Hebrew;hw=Automatic" ;;
    # The input mode is bare `ar`, not `ar_XX`. A tag iOS does not recognise is
    # dropped silently and the device comes up on English, which is why the test
    # reads the layout off the keys rather than trusting this list.
    ar) first="ar@sw=Arabic;hw=Automatic" ;;
    *) echo "unknown layout $layout" >&2; exit 1 ;;
  esac
  # Only the wanted layout and emoji, so nothing can restore a different one.
  xcrun simctl spawn booted defaults write .GlobalPreferences AppleKeyboards -array \
    "$first" "emoji@sw=Emoji"
  respring

  set +e
  (
    export TEST_RUNNER_STOCK_LAYOUT="$layout"
    export TEST_RUNNER_REF_DIR="$work"
    xcodebuild test-without-building -project "$repo/AIKeyboard.xcodeproj" -scheme AIKeyboard \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -only-testing:AIKeyboardUITests/StockKeyboardReferenceTests/testCaptureStockLetterRows
  ) >"$work/$layout.log" 2>&1
  set -e
  # STOCK-ROWS and nothing else: a skip means the device came up on a different
  # layout, and a run that quietly recorded nothing must not look like a success.
  grep -E "STOCK-ROWS" "$work/$layout.log" || {
    echo "no rows captured for $layout:" >&2
    grep -E "Test skipped|error:|Testing failed" "$work/$layout.log" >&2 || true
    echo "see $work/$layout.log" >&2
    exit 1
  }
done

# The photographs go beside the numbers. `KeyboardLayout` cites them for Hebrew's
# delete key, and a citation nobody can look at is a claim.
mkdir -p "$here/stock"
for layout in "${layouts[@]}"; do
  cp "$work/stock-$layout.png" "$here/stock/$layout.png"
done

python3 - "$work/raw" "$out" <<'PY'
import json, pathlib, sys, datetime

raw, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
existing = json.loads(out.read_text())["layouts"] if out.is_file() else {}
for f in sorted(raw.glob("stock-*.json")):
    entry = json.loads(f.read_text())
    existing[entry["layout"]] = {"rows": entry["rows"]}
out.write_text(json.dumps({
    "generated": datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat(),
    "note": "Where the stock iOS keyboard puts each key on screen: rows top to "
            "bottom, keys left to right by their measured frames. Written by "
            "Bar/layouts/capture-rendered.sh.",
    "layouts": existing,
}, ensure_ascii=False, indent=1) + "\n")
print("==>", out)
PY
