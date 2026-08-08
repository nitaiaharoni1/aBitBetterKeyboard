#!/bin/bash
# Rebuilds Bar/typing/reference/ from Bar/typing/corpus.json by photographing the
# stock iOS keyboard. One command, start to finish:
#
#   Bar/typing/capture.sh          # fresh capture
#   Bar/typing/capture.sh --resume # keep what is already in reference/raw
#
# Takes about an hour. Every corpus entry that cannot be driven ends up in
# manifest.json as "uncaptured" with a reason, never as a guess.
#
# The shape of this script is dictated by one fact: tapping a key that rebuilds the
# keyboard view — the globe, or 'more' for the numbers plane — kills the XCUITest
# runner mid-tap on this simulator, and takes the rest of the run with it. So:
#
#   phase 1  types everything reachable on the letter plane, resuming after each
#            death, until no entry is left unattempted
#   phase 2  retries the code-switch entries one xcodebuild invocation at a time,
#            with the globe allowed, so a death costs one entry instead of thirteen

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
ref="$here/reference"
attempts=${ATTEMPTS:-70}
total=$(python3 -c "import json;print(len(json.load(open('$here/corpus.json'))['entries']))")

"$here/setup-simulator.sh"

# The globe cycles through every installed keyboard, so there is no reason to leave
# a third-party one in the cycle while capturing Apple's behaviour. Park this
# project's keyboard for the duration and put it back on the way out. This is
# hygiene, not a fix: the runner dies on the globe with only Apple's keyboards
# installed too. README.md, "The keyboard-switch crash", has the evidence.
backup="$(xcrun simctl spawn booted defaults read .GlobalPreferences AppleKeyboards 2>/dev/null || echo '')"
respring() {
  xcrun simctl spawn booted launchctl kickstart -k system/com.apple.SpringBoard >/dev/null 2>&1 || true
  sleep 10
}
restore_keyboards() {
  if grep -q "com.nitai.aikeyboard.keyboard" <<<"$backup"; then
    echo "restoring the AI Keyboard to the simulator's keyboard list…"
    xcrun simctl spawn booted defaults write .GlobalPreferences AppleKeyboards -array \
      "en_US@sw=QWERTY;hw=Automatic" "he_IL@sw=Hebrew;hw=Automatic" "emoji@sw=Emoji" \
      "com.nitai.aikeyboard.keyboard"
    respring
  fi
}
trap restore_keyboards EXIT

xcrun simctl spawn booted defaults write .GlobalPreferences AppleKeyboards -array \
  "en_US@sw=QWERTY;hw=Automatic" "he_IL@sw=Hebrew;hw=Automatic" "emoji@sw=Emoji"
respring

if [ "${1:-}" != "--resume" ]; then
  rm -rf "$ref/raw"
  rm -f "$ref"/*.png "$ref"/capture.log
fi
mkdir -p "$ref/raw"
touch "$ref/capture.log"

done_count() {
  local n=0
  n=$(ls -1 "$ref/raw" | wc -l | tr -d ' ') || n=0
  echo "$n"
}

# Build once. Every attempt after that is `test-without-building`, which turns a
# retry from a three-minute rebuild into a thirty-second run — and retries are the
# whole strategy here.
echo
echo "### building the test bundle"
xcodebuild build-for-testing -project "$repo/AIKeyboard.xcodeproj" -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' >"$ref/.build.log" 2>&1 || {
  echo "build-for-testing failed; see $ref/.build.log" >&2
  grep -m5 "error:" "$ref/.build.log" >&2 || true
  exit 1
}

# Extra TEST_RUNNER_* assignments come in as arguments. xcodebuild output goes to a
# scratch file first and is only then filtered, so a run that dies early still
# leaves its reason on disk instead of vanishing into a pipeline.
run_test() {
  local one
  local out="$ref/.last-run.log"
  set +e
  (
    for one in "$@"; do export "${one?}"; done
    export TEST_RUNNER_STOCK_CAPTURE=1
    export TEST_RUNNER_REF_DIR="$ref"
    export TEST_RUNNER_CORPUS_PATH="$here/corpus.json"
    xcodebuild test-without-building -project "$repo/AIKeyboard.xcodeproj" -scheme AIKeyboard \
      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
      -only-testing:AIKeyboardUITests/StockKeyboardReferenceTests/testCaptureStockSuggestionBar
  ) >"$out" 2>&1
  set -e
  cat "$out" >>"$ref/capture.log"
  grep -E "CAPTURE-(PLAN|DONE)|Test skipped|Testing failed|TEST (SUCCEEDED|FAILED)" "$out" || true
}

echo
echo "### phase 1: everything typeable on the letter plane"
for attempt in $(seq 1 "$attempts"); do
  before=$(done_count)
  echo
  echo "=== attempt $attempt ($before/$total attempted) ==="
  run_test
  after=$(done_count)
  if [ "$after" = "$total" ]; then break; fi
  if [ "$after" = "$before" ]; then respring; fi
done

echo
echo "### phase 2: code-switch entries, one run each so a crash costs one entry"
mixed=$(python3 - "$here/corpus.json" <<'PY'
import json, sys
def he(c): return '֐' <= c <= '׿'
for e in json.load(open(sys.argv[1]))["entries"]:
    if len({('he' if he(c) else 'en') for c in e["context"] + e["prefix"] if c.isalpha()}) > 1:
        print(e["id"])
PY
)
while read -r id; do
  [ -n "$id" ] || continue
  captured=$(python3 -c "
import json,pathlib,sys
p = pathlib.Path('$ref/raw/$id.json')
print(json.loads(p.read_text()).get('status') if p.is_file() else 'none')
")
  if [ "$captured" = "captured" ]; then
    echo "--- $id already captured ---"
    continue
  fi
  echo "--- $id ---"
  run_test TEST_RUNNER_ALLOW_LAYOUT_SWITCH=1 TEST_RUNNER_RETRY_FAILED=1 TEST_RUNNER_ONLY_IDS="$id"
done <<<"$mixed"

python3 "$here/make-manifest.py"
echo "see $ref/manifest.json"
