#!/bin/bash
# Types every misspelling in typos.json through the real SuggestionEngine and
# reports whether the bar offered the word the person meant and whether the space
# bar would have taken it.
#
#   Bar/typing/typos/run.sh
#   Bar/typing/typos/run.sh --runs=3
#   Bar/typing/typos/run.sh --verbose                  # print every stable row
#   TYPOS_OUT=/tmp/typos Bar/typing/typos/run.sh       # keep the artefacts here
#   SIMULATOR_DEVICE=<udid> Bar/typing/typos/run.sh    # a device that is not `booted`
#
# Needs a booted simulator, the same one `Bar/typing/harness/run.sh` needs, and
# takes about twice as long as that script because it runs it twice.
#
# **Two runs by default, and that is the point of the script rather than a
# nicety.** This engine is deterministic given the same `UITextChecker` state and
# `UITextChecker` is not: its Hebrew completion list disagrees with itself between
# identical runs, which the frozen corpus already records on `he-comp-03/04/05`.
# `judge.py` counts a row only when every run agreed about it, so a single run
# produces a table with holes in it rather than a confident wrong answer.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
runs=2
judge_flags=()
for argument in "$@"; do
    case "$argument" in
        --runs=*) runs="${argument#*=}" ;;
        --verbose) judge_flags+=("$argument") ;;
        *)
            echo "usage: $0 [--runs=N] [--verbose]" >&2
            exit 2
            ;;
    esac
done

out="${TYPOS_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/typing-typos.XXXXXX")}"
mkdir -p "$out"

# Expands *and* validates: a row whose `class` does not match the shape of the two
# strings fails here, before a simulator is touched. See expand.py.
python3 "$here/expand.py" "$out/corpus.json"

for index in $(seq 1 "$runs"); do
    echo "--- run $index of $runs ---" >&2
    SIMULATOR_DEVICE="${SIMULATOR_DEVICE:-booted}" \
        TYPING_CORPUS="$out/corpus.json" "$here/../harness/run.sh" "$out/run-$index.json"
done

python3 "$here/judge.py" "$out/corpus.json" "$out"/run-*.json "${judge_flags[@]+"${judge_flags[@]}"}"

# Kept, not deleted. The runs are the evidence behind whatever the report above
# says, and the next question anybody asks is "show me the two files".
echo
echo "typo artefacts: $out"
