#!/usr/bin/env python3
"""Judges a letter-by-letter sweep: what would the space bar have inserted?

    Bar/typing/sweep/judge.py corpus.json run-1.json run-2.json
    Bar/typing/sweep/judge.py corpus.json run-*.json --trace=בעבודה,להתראות

**The bold slot is the headline, because it is the only column that changes the
document.** `SuggestionEngine` echoes the typed keystrokes as candidate zero on
purpose, so "the right word is in the bar" is true of an engine that has stopped
working; the scorer for the frozen 90 was wrong about exactly this and
mislabelled 40 of 76 entries. `main.swift` writes `commits` as the text of the
slot marked default, which is what `KeyboardController.insertSpace` inserts, and
the three verdicts below compare that string and nothing else.

**The other two slots get their own report, because judging only the bold one hid
a defect for months.** The Hebrew clitic split was offering `מנכון`, `מנחמד` and
`מנפגש` — three words that do not exist, in all three drawn slots — and it never
moved a commit, so this tool and the frozen 90 both read perfectly clean while a
fifth of Hebrew keystrokes drew invented words (NIT-129). That is not a bold-slot
question and no amount of care about `commits` would have found it. Two counts
are printed under the headline, and neither is folded into it:

  non-words   An offered slot `UITextChecker` says is not a word, in that
              candidate's own language. `main.swift` asks, in a second pass after
              every entry is answered, and writes `misspelled`. Always a defect:
              a keyboard may decline to help, and may not offer gibberish.
  no-target   The word being typed is in no slot at all. **Not** a defect on its
              own — two letters into a word, half the language is still a
              plausible completion and the bar has three slots — so this is a
              trend to watch across runs rather than a list of accusations.

An older run has no `misspelled` key. Those files are reported as `n/a` rather
than as zero, because a scorer that silently reads a missing measurement as a
passing one is the failure this whole section exists to describe.

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
        offered = [s for s in record["slots"] if score.norm(s) != typed]
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
            # None rather than [] when the run predates the column, so a missing
            # measurement cannot be read as a clean one.
            "misspelled": record.get("misspelled"),
            "hasTarget": any(score.norm(s) == target for s in offered),
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
    graded = [row for row in rows.values() if row["misspelled"] is not None]
    if not graded:
        print(f"  {'':24s}      offered slots: n/a (run predates the misspelled column)")
        return
    bad = sum(1 for row in graded if row["misspelled"])
    slots = sum(len(row["misspelled"]) for row in graded)
    missing = sum(1 for row in rows.values() if not row["hasTarget"])
    print(
        f"  {'':24s}      offered slots: {bad:4d} moments hold a NON-WORD ({slots} slots)"
        f"   {missing:4d} without the target word"
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

    # Same discipline as the divergences: a slot only counts as an accusation
    # when every run agrees it was there. The intersection rather than the union,
    # so a word Apple offered in one run and not the next is not reported as a
    # defect in the engine.
    invented = []
    for rid in ids:
        seen = [rows[rid] for rows in runs if rid in rows]
        if len(seen) != len(runs) or any(row["misspelled"] is None for row in seen):
            continue
        shared = set(seen[0]["misspelled"])
        for row in seen[1:]:
            shared &= set(row["misspelled"])
        if shared:
            invented.append((seen[0], sorted(shared)))

    print(f"\n  confirmed non-words in an offered slot (every run): {len(invented)}")
    for row, words in invented:
        print(
            f"    {row['id']:12s} {row['letters']}/{row['of']} of {row['word']!r}"
            f"   typed {row['typed']!r} -> {', '.join(repr(w) for w in words)}"
            f"   slots {row['slots']}"
        )

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
