#!/bin/bash
# Runs the async-tier corpus through PredictiveRefiner and scores the slots.
#
#   ASYNC_TYPING_OUT=/tmp/async.json Bar/typing/async/run.sh
#   Bar/typing/async/run.sh /tmp/async.json
#
# Needs a booted simulator. Does not drive it. The test writes JSON; this
# script only compiles, runs that one XCTest, and scores.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
corpus="$here/corpus.json"
out="${ASYNC_TYPING_OUT:-${1:-}}"

if [[ -z "$out" ]]; then
  echo "usage: ASYNC_TYPING_OUT=/path/to/out.json $0" >&2
  echo "   or: $0 /path/to/out.json" >&2
  exit 2
fi

case "$out" in
  /*) ;;
  *) out="$PWD/$out" ;;
esac

device="${SIMULATOR_DEVICE:-0966F3D6-2589-4E88-BE84-4A69CD64FEE8}"

# Cheap first: catches a malformed entry before xcodebuild spends minutes
# building and booting to reach it.
python3 "$here/validate.py"

export ASYNC_TYPING_CORPUS="$corpus"
export ASYNC_TYPING_OUT="$out"
export TEST_RUNNER_ASYNC_TYPING_CORPUS="$corpus"
export TEST_RUNNER_ASYNC_TYPING_OUT="$out"

xcodebuild test -project "$repo/AIKeyboard.xcodeproj" -scheme AIKeyboard \
  -destination "platform=iOS Simulator,id=$device" \
  -only-testing:AIKeyboardCoreTests/AsyncTypingCorpusTests

TYPING_CORPUS="$corpus" python3 "$here/../harness/score.py" "$out"
