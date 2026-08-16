#!/usr/bin/env python3
"""Judges a letter-by-letter sweep: what would the space bar have inserted?

    Bar/typing/sweep/judge.py corpus.json run-1.json run-2.json
    Bar/typing/sweep/judge.py corpus.json run-*.json --trace=בעבודה,להתראות

**It judges the bold slot and nothing else, because that is the only column a
user can feel.** `SuggestionEngine` echoes the typed keystrokes as candidate zero
on purpose, so "the right word is in the bar" is true of an engine that has
stopped working; the scorer for the frozen 90 was wrong about exactly this and
mislabelled 40 of 76 entries. `main.swift` writes `commits` as the text of the
slot marked default, which is what `KeyboardController.insertSpace` inserts, so
this file compares that string and nothing else.

Every moment gets one of three verdicts, and only the third is a finding:

  held      The bold slot is what was typed. The engine declined to change
            anything. Conservative, never a defect.
  ontrack   The bold slot is a prefix of the word being typed, up to and
            including the whole of it. The engine is helping.
  diverged  Neither. The space bar would insert a word this person is not
            typing.

**`diverged` is the verdict the frozen 90 structurally cannot reach, and it is
the reason this tool exists.** That corpus holds a context and one frozen prefix;
it never knows what the typist was on their way to, so it can only ask whether an
answer is on a list somebody authored. A sweep knows the whole word, which turns
"is this a plausible completion" into "is this the word", and `להתר` committing
`להתרופה` is a perfectly plausible completion of the four letters typed.

That last point is also why `diverged` is split in two rather than reported as
"not a prefix-completion of what was typed". `להתרופה` *is* a prefix-completion
of `להתר` — every key is still there — and it is still the wrong word:

  continues  Every typed letter survives; the engine guessed a different ending.
  replaces   A key the user pressed is gone. Worse, because the evidence the
             engine overruled was unambiguous.

**One run is not evidence, so several are the argument the interface makes.**
Pass every run on the command line. A moment is only reported as a finding when
it diverged in *all* of them; anything that moved between runs is printed under
its own heading instead, because `UITextChecker`'s Hebrew completion list is not
stable run to run and a finding built on one run of it is a coin toss written up
as a defect.
"""

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
# `norm` is the frozen corpus's own normaliser: NFC, lowercased, quotes stripped,
# maqaf folded onto the ASCII hyphen and the curly apostrophe onto the straight
# one. A second spelling of it here would drift, and both halves of this repo's
# apostrophe bugs came from exactly that.
sys.path.insert(0, str(HERE.parent / "harness"))
import score  # noqa: E402

HELD, ONTRACK, DIVERGED = "held", "ontrack", "diverged"


def verdict(typed, commits, target):
    """The verdict for one keystroke moment, all three strings normalised."""
    if commits == typed:
        return HELD, None
    if target.startswith(commits):
        return ONTRACK, None
    return DIVERGED, ("continues" if commits.startswith(typed) else "replaces")


def judge(corpus, outputs):
    by_id = {e["id"]: e for e in corpus["entries"]}
    rows = {}
    for record in outputs:
        entry = by_id.get(record["id"])
        if entry is None:
            continue
        typed = score.norm(entry["prefix"])
        commits = score.norm(record["commits"])
        target = score.norm(entry["intended"])
        kind, shape = verdict(typed, commits, target)
        rows[record["id"]] = {
            "id": record["id"],
            "word": entry["word"],
            "context": entry["context"],
            "typed": entry["prefix"],
            "commits": record["commits"],
            "slots": record["slots"],
            "letters": len(entry["prefix"]),
            "of": len(entry["word"]),
            "verdict": kind,
            "shape": shape,
        }
    return rows


def headline(rows, label):
    counts = {HELD: 0, ONTRACK: 0, DIVERGED: 0}
    for row in rows.values():
        counts[row["verdict"]] += 1
    total = len(rows)
    print(
        f"  {label:24s} {total:4d} moments   "
        f"{counts[HELD]:4d} held  {counts[ONTRACK]:4d} on track  "
        f"{counts[DIVERGED]:4d} DIVERGED"
    )


def trail(runs, word, ids):
    """Every keystroke of one word, with what each run would have committed."""
    print(f"\n  {word}")
    for rid in ids:
        cells = []
        for rows in runs:
            row = rows.get(rid)
            if row is None:
                continue
            mark = {HELD: " ", ONTRACK: "+", DIVERGED: "!"}[row["verdict"]]
            cells.append(f"{mark} {row['commits']}")
        first = next(rows[rid] for rows in runs if rid in rows)
        same = len(set(cells)) == 1
        shown = cells[0] if same else "   ||   ".join(cells)
        print(f"    {first['typed']:<14s} -> {shown}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    traced = set()
    for flag in (a for a in sys.argv[1:] if a.startswith("--trace")):
        _, _, value = flag.partition("=")
        traced.update(w for w in value.replace(",", " ").split() if w)
    if len(args) < 2:
        print(__doc__.splitlines()[2].strip(), file=sys.stderr)
        return 2

    corpus = json.loads(pathlib.Path(args[0]).read_text())
    runs = [judge(corpus, json.loads(pathlib.Path(p).read_text())) for p in args[1:]]

    print(f"\n=== letter-by-letter sweep: {len(runs)} run(s) ===")
    for path, rows in zip(args[1:], runs):
        headline(rows, pathlib.Path(path).name)

    ids = [e["id"] for e in corpus["entries"]]
    ordered_words = []
    per_word = {}
    for entry in corpus["entries"]:
        key = (entry["word"], entry["context"])
        if key not in per_word:
            per_word[key] = []
            ordered_words.append(key)
        per_word[key].append(entry["id"])

    # A finding has to survive every run. Anything that moved is instability in
    # `UITextChecker`, not a defect, and gets its own heading.
    confirmed, unstable = [], []
    for rid in ids:
        seen = [rows[rid] for rows in runs if rid in rows]
        if len(seen) != len(runs):
            continue
        verdicts = {row["verdict"] for row in seen}
        commits = {row["commits"] for row in seen}
        if len(verdicts) > 1 or len(commits) > 1:
            unstable.append((rid, seen))
        if verdicts == {DIVERGED}:
            confirmed.append(seen[0])

    print(f"\n  confirmed divergences (every run): {len(confirmed)}")
    if confirmed:
        # Worst first: a moment that threw away a key the user pressed leads one
        # that merely guessed an ending, and within each, the further into the
        # word it happened the less excuse the engine had.
        confirmed.sort(key=lambda r: (r["shape"] != "replaces", -r["letters"] / r["of"]))
        print()
        for row in confirmed:
            print(
                f"    {row['id']:12s} {row['shape']:9s} "
                f"{row['letters']}/{row['of']} of {row['word']!r}"
                + (f" after {row['context']!r}" if row["context"] else "")
            )
            print(f"      typed {row['typed']!r} -> commits {row['commits']!r}   slots {row['slots']}")

        print("\n  the words those moments are on the way to, keystroke by keystroke:")
        hit = {(row["word"], row["context"]) for row in confirmed}
        for key in ordered_words:
            if key in hit:
                trail(runs, key[0] + (f"  (after {key[1]!r})" if key[1] else ""), per_word[key])

    if traced:
        print("\n  traced words:")
        for key in ordered_words:
            if key[0] in traced:
                trail(runs, key[0] + (f"  (after {key[1]!r})" if key[1] else ""), per_word[key])

    print(f"\n  moments that moved between runs: {len(unstable)}")
    for rid, seen in unstable:
        first = seen[0]
        answers = " | ".join(f"{row['verdict']}:{row['commits']!r}" for row in seen)
        print(f"    {rid:12s} typed {first['typed']!r}  {answers}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
