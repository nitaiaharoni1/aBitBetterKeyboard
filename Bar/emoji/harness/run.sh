#!/bin/bash
# Score the emoji ranker against Bar/emoji/corpus.json.
#
#     Bar/emoji/harness/run.sh              # selftest, then score, writes results.json
#     Bar/emoji/harness/run.sh /tmp/after.json
#
# Seconds, no simulator, no network, Python 3 standard library only. That is the
# whole point of the shape: `Bar/typing` has to build for the iOS Simulator
# because `UITextChecker` is UIKit, and a ranker cannot be tuned at minutes a
# run. `Bar/grouped/harness/run.sh` is the same trade.
#
# **This scores a port.** `swift-check.sh` is what makes it a score of the
# keyboard, and it is a separate command because it needs Xcode and this does
# not. Run it whenever `EmojiSearch.swift` or `EmojiCatalog.json` moves.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"

python3 "$here/selftest.py"
echo ""
exec python3 "$here/score.py" ${1:+--out "$1"}
