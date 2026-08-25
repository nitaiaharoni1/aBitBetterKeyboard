#!/bin/bash
# Types every pair in pairs.json through the real SuggestionEngine, the same way
# Bar/typing/typos/run.sh does for typos.json. This is a probe, not an exam: its
# job is to widen the evidence behind CommitReason.frequency's (cost: 110,
# count: 2) split, not to hold a headline number. Do not register its output
# with Bar/drift.
#
#   Bar/typing/typos/probes-motor2/run.sh
#   Bar/typing/typos/probes-motor2/run.sh --runs=3
#   SIMULATOR_DEVICE=<udid> Bar/typing/typos/probes-motor2/run.sh
#
# Reuses expand.py and judge.py unchanged, via TYPOS_PAIRS, exactly as
# Bar/typing/typos/README.md says a corpus of a different shape should:
# TYPING_CORPUS is already honoured by harness/run.sh and judge.py takes a
# corpus path as an argument, so nothing here re-implements either script.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
typos="$here/.."
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

out="${PROBE_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/typing-probe-motor2.XXXXXX")}"
mkdir -p "$out"

TYPOS_PAIRS="$here/pairs.json" python3 "$typos/expand.py" "$out/corpus.json"

for index in $(seq 1 "$runs"); do
    echo "--- run $index of $runs ---" >&2
    SIMULATOR_DEVICE="${SIMULATOR_DEVICE:-booted}" \
        TYPING_CORPUS="$out/corpus.json" "$typos/../harness/run.sh" "$out/run-$index.json"
done

python3 "$typos/judge.py" "$out/corpus.json" "$out"/run-*.json "${judge_flags[@]+"${judge_flags[@]}"}"

echo
echo "probe artefacts: $out"
