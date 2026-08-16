#!/usr/bin/env python3
"""Grades a frequency word list against a sweep: would ranking by it have helped?

    Bar/typing/sweep/frequency.py corpus.json run-1.json wordlist.txt
    Bar/typing/sweep/frequency.py corpus.json run-1.json wordlist.txt --language=he
    Bar/typing/sweep/frequency.py corpus.json run-1.json wordlist.txt --from=1

The list is one word per line, commonest first, which is the shape
`Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources/GroupedLexicon-he.txt`
already ships in.

**It answers the question before the work rather than after it, and the answer so
far has been no.** "The bar should prefer the commoner word" is the most natural
idea anybody has about this engine and it costs days to implement properly:
loading tens of thousands of words on the keystroke path of a memory-capped
extension, choosing a curve, then two runs a side on both instruments. This
script costs a second and needs no simulator, because every input it needs is
already on disk: the sweep knows the word each keystroke was reaching for, the
run knows which slots were drawn, and the list knows which word is commoner.

Two numbers come out, and the second is the one that kills proposals.

  gain      Moments where the bar is missing the word being typed, Apple's own
            completion list holds it (`SlotRecord.reachable`), and this list
            ranks it above every slot that *was* drawn. The most a perfect
            frequency ranker could win.
  exposure  Moments where the bar **does** hold the target and this list ranks
            some other drawn slot above it. Every one is a moment a
            frequency-forward ranking could take away, so it is the ceiling on
            the damage rather than a prediction of it.

Neither is a simulation of any particular design: a real change keeps the source
tiers, and a term bounded below 1000 cannot cross one. They bracket it. A list
whose exposure dwarfs its gain cannot be rescued by a smaller budget — the same
comparisons are being made either way, just more weakly.

**`--from` defaults to 3 because one and two letters is where a frequency list
looks best and means least.** At `--from=1` the Leipzig list scores 13 gains, and
five of them are moments like `ד` → `דרך` and `ב` → `בית`: with one letter typed
it is naming the commonest word in the language that starts with it, and it is
"right" only because this sweep's word list is made of common words. That is the
tool flattering the idea it exists to test. Three letters is where a completion
engine has something to work with, and the same list scores 3 there.

**Measured 2026-08-16 against the two lists this repo already bundles** (Leipzig,
Wikipedia, 50,000 words each, CC BY 4.0), two runs a side, identical both times:
Hebrew **gain 4, exposure 48**; English **gain 0, exposure 70**. So it is not a
Hebrew problem and it is not a right-to-left one. It is a domain problem: the
list is an encyclopedia's and the keyboard is a chat field's, and the misses are
not marginal — `סליחה` is rank 37,467, `כשאני` 39,651, `מונית` 21,885, and `תודה`
sits at 8,904 behind `עוד` at 118, because nobody writes "sorry" or "thanks" in
an encyclopedia. `SeedLanguageModel`'s 353 hand-authored words are ranked
"against the kind of text this keyboard is typed into", and that property, not
the length of the list, is what makes them work. See NIT-132.
"""

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "harness"))
import score  # noqa: E402

ABSENT = float("inf")


def ranks(path):
    """Word to position, commonest first, normalised the way the corpus is."""
    out = {}
    with open(path, encoding="utf-8") as handle:
        for position, line in enumerate(handle):
            word = score.norm(line.strip())
            if word and word not in out:
                out[word] = position
    return out


def grade(corpus, outputs, table, language, floor):
    by_id = {e["id"]: e for e in corpus["entries"]}
    gain, exposure, unreadable = [], [], 0
    for record in outputs:
        entry = by_id.get(record["id"])
        if entry is None or (language and entry["language"] != language):
            continue
        if len(entry["prefix"]) < floor:
            continue
        if not entry.get("intended"):
            continue
        typed = score.norm(entry["prefix"])
        target = score.norm(entry["intended"])
        # **Only where the target continues what was typed**, which is the same
        # guard `SlotRecord.reachable` applies and for the same reason. This
        # grades a *completion* ranking. 24 of the frozen 90 spell `intended` as a
        # correction — `dont` → `don't` — and a frequency list has no business
        # being asked which of those two is commoner.
        if target == typed or not target.startswith(typed):
            continue
        drawn = [s for s in record["slots"] if score.norm(s) != typed]
        mine = table.get(target, ABSENT)
        better = [s for s in drawn if table.get(score.norm(s), ABSENT) < mine]
        if any(score.norm(s) == target for s in drawn):
            if better:
                exposure.append((entry, record, mine, better))
            continue
        # Only a moment some ranking could have won. `reachable` is written by
        # the harness in its second pass; an older run does not have it and is
        # counted as unreadable rather than as a loss.
        if record.get("reachable") is None:
            unreadable += 1
        elif record["reachable"] and not better:
            gain.append((entry, record, mine, better))
    return gain, exposure, unreadable


def show(label, rows, table):
    print(f"\n  {label} ({len(rows)}):")
    for entry, record, mine, better in rows:
        drawn = " ".join(
            f"{s}({place(table.get(score.norm(s), ABSENT))})"
            for s in record["slots"]
            if score.norm(s) != score.norm(entry["prefix"])
        )
        print(
            f"    {entry['id']:10s} {entry['prefix']} -> "
            f"{entry['intended']}({place(mine)})   drawn {drawn}"
        )


def place(rank):
    return "absent" if rank == ABSENT else str(rank)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    language = next(
        (a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--language=")), None
    )
    if len(args) != 3:
        print(__doc__.strip().splitlines()[2].strip(), file=sys.stderr)
        return 2
    floor = int(
        next((a.split("=", 1)[1] for a in sys.argv[1:] if a.startswith("--from=")), 3)
    )
    corpus = json.load(open(args[0], encoding="utf-8"))
    outputs = json.load(open(args[1], encoding="utf-8"))
    table = ranks(args[2])
    gain, exposure, unreadable = grade(corpus, outputs, table, language, floor)

    print(f"\n=== {pathlib.Path(args[2]).name}: {len(table)} words, {floor}+ letters typed ===")
    print(f"  gain     {len(gain):4d}  missing, winnable, and this list ranks it first")
    print(f"  exposure {len(exposure):4d}  offered today, and this list prefers another slot")
    if unreadable:
        print(f"  {unreadable} moments n/a — the run predates the reachable column")
    show("the gains", gain, table)
    show("the exposure", exposure, table)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
