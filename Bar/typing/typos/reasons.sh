#!/bin/bash
# Which rule decided each commit, for every entry in a typing corpus.
#
#   Bar/typing/typos/reasons.sh                       # the 128 typo pairs
#   Bar/typing/typos/reasons.sh Bar/typing/corpus.json  # the frozen 90
#   Bar/typing/typos/reasons.sh corpus.json > rows.tsv
#
# Prints `id, typed, intended, winner, reason, confidence`, tab separated, and a
# summary of how often each rule is right when the corpus knows the answer.
#
# **This is where the numbers in `AutocorrectConfidence.swift` came from.** The
# judge next door grades the word; this grades the rule that chose it. Re-run it
# before moving any confidence constant, and read `reasons/main.swift` for why it
# calls `commitReason` directly instead of reading the bold slot.
#
# Needs a booted simulator, the same one `harness/run.sh` needs, and compiles the
# same engine through `harness/sources.sh`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
core="$here/../../../Packages/AIKeyboardCore/Sources/AIKeyboardCore"
shared="$here/../../../Packages/AIKeyboardCore/Sources/AIKeyboardShared"
corpus="${1:-}"

if [ -z "$corpus" ]; then
    # No corpus given: expand `typos.json` the way `run.sh` does, so the default
    # is the 128 pairs this directory is about rather than the frozen 90.
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    python3 "$here/expand.py" "$work/corpus.json" >/dev/null 2>&1
    corpus="$work/corpus.json"
fi
case "$corpus" in /*) ;; *) corpus="$PWD/$corpus" ;; esac

build="$(mktemp -d)"
trap 'rm -rf "$build" ${work:-}' EXIT

. "$here/../harness/sources.sh"
copy_engine_sources "$core" "$shared" "$build"
# `shippedPersonalDictionary` lives in the harness main, which cannot be compiled
# beside this one — two top-level files is two `main`s. Lifted rather than copied
# so the probe scores the same list the harness does.
python3 - "$here/../harness/main.swift" "$build/Shipped.swift" <<'PY'
import io, re, sys
src = io.open(sys.argv[1], encoding="utf-8").read()
match = re.search(r"let shippedPersonalDictionary[^\n]*=\s*\[(.*?)\]\n", src, re.S)
if not match:
    sys.exit("shippedPersonalDictionary is no longer a literal in harness/main.swift")
io.open(sys.argv[2], "w", encoding="utf-8").write("import Foundation\n" + match.group(0))
PY
cp "$here/reasons/main.swift" "$build/"

sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun -sdk iphonesimulator swiftc -O -DHARNESS \
    -target arm64-apple-ios17.0-simulator -sdk "$sdk" \
    "$build"/*.swift -o "$build/reasons"

rows="$build/rows.tsv"
# Absolute paths and `SIMCTL_CHILD_`, for the reason `harness/run.sh` spells out:
# a relative resource path resolves inside the simulator and the lexicon silently
# loads nothing, which reports as a clean run of an engine with its whole
# frequency source switched off. `main.swift` refuses rather than scoring, and
# that refusal is what caught this while the prices were being set.
LANGUAGE_MODEL_JSON="$core/Resources/LanguageModel.json" \
    SIMCTL_CHILD_LANGUAGE_MODEL_JSON="$core/Resources/LanguageModel.json" \
    GROUPED_LEXICON_DIR="$core/Resources" \
    SIMCTL_CHILD_GROUPED_LEXICON_DIR="$core/Resources" \
    xcrun simctl spawn "${SIMULATOR_DEVICE:-booted}" "$build/reasons" "$corpus" > "$rows"

cat "$rows"
python3 - "$rows" <<'PY'
import collections, io, re, sys

rows = []
for line in io.open(sys.argv[1], encoding="utf-8"):
    parts = line.rstrip("\n").split("\t")
    if len(parts) < 6:
        continue
    rid, typed, intended, winner, reason, confidence = parts
    rows.append(
        dict(id=rid, typed=typed, intended=intended, winner=winner, reason=reason,
             confidence=int(confidence) if confidence != "-" else None))

def verdict(row):
    if row["reason"] == "nil":
        return "held"
    if row["winner"].lower() == row["intended"].lower():
        return "right"
    if row["winner"].lower() == row["typed"].lower():
        return "held"
    return "WRONG"

# A corpus that carries no `intended` (the sweep) cannot grade anything, and a
# control row is one where the two are the same string.
graded = [r for r in rows if r["intended"] not in ("", "-") and r["intended"] != r["typed"]]
if not graded:
    sys.exit(0)

table = collections.defaultdict(collections.Counter)
for row in graded:
    name = (re.match(r"(\w+)", row["reason"]) or [None, row["reason"]])[1]
    table[(name, row["confidence"])][verdict(row)] += 1

print(f"\n=== {len(graded)} graded entries: how often each rule is right ===\n")
print(f"  {'rule':<18} {'conf':>4} {'right':>6} {'WRONG':>6}")
for key in sorted(table, key=lambda k: -(k[1] or 0)):
    counts = table[key]
    print(f"  {key[0]:<18} {str(key[1]):>4} {counts['right']:>6} {counts['WRONG']:>6}")
print("\n  A rule above the floor with a poor ratio is a price to revisit;")
print("  see AutocorrectLevel.confidenceFloor.")
PY
