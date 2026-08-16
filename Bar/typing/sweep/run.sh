#!/bin/bash
# Types every word in words.json letter by letter through the real
# SuggestionEngine and reports what the space bar would have inserted at each
# keystroke.
#
#   Bar/typing/sweep/run.sh
#   Bar/typing/sweep/run.sh --runs=3
#   Bar/typing/sweep/run.sh --trace=בעבודה,מהעבודה     # print a clean word too
#   SWEEP_OUT=/tmp/sweep Bar/typing/sweep/run.sh       # keep the artefacts here
#
# Needs a booted simulator, the same one `Bar/typing/harness/run.sh` needs, and
# takes about twice as long as that script because it runs it twice.
#
# **Two runs by default, and that is the point of the script rather than a
# nicety.** This engine is deterministic given the same `UITextChecker` state and
# `UITextChecker` is not: its Hebrew completion list disagrees with itself
# between identical runs, which the frozen corpus already records on
# `he-comp-03/04/05`. `judge.py` only reports a moment as a finding when every
# run agrees on it, so a sweep run once cannot produce one at all — which is the
# correct behaviour for a tool whose whole output is a list of accusations.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
runs=2
trace=()
for argument in "$@"; do
    case "$argument" in
        --runs=*) runs="${argument#*=}" ;;
        --trace=*) trace+=("$argument") ;;
        *)
            echo "usage: $0 [--runs=N] [--trace=word,word]" >&2
            exit 2
            ;;
    esac
done

out="${SWEEP_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/typing-sweep.XXXXXX")}"
mkdir -p "$out"

python3 "$here/expand.py" "$out/corpus.json"

for index in $(seq 1 "$runs"); do
    echo "--- run $index of $runs ---" >&2
    TYPING_CORPUS="$out/corpus.json" "$here/../harness/run.sh" "$out/run-$index.json"
done

python3 "$here/judge.py" "$out/corpus.json" "$out"/run-*.json "${trace[@]+"${trace[@]}"}"

# Kept, not deleted. The runs are the evidence behind whatever the report above
# says, and the next question anybody asks is "show me the two files".
echo
echo "sweep artefacts: $out"
