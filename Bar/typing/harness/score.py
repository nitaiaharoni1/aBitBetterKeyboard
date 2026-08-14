#!/usr/bin/env python3
"""Scores engine_outputs.json against corpus.json.

Answers the corpus README's question 1 — "is it good?" — which needs no capture
and works on all 90 entries. Question 2, "is it better than free?", needs
reference/manifest.json, and at the time of writing that has 1 captured row out
of 90, so it is reported separately and never folded into the headline.

    Bar/typing/harness/score.py                       # scores engine_outputs.json
    Bar/typing/harness/score.py before.json after.json  # diffs two runs
    TYPING_CORPUS=Bar/typing/async/corpus.json score.py  # grades a different exam

Three things are counted, and they are not the same question:

  commit   The bold slot is what the space bar inserts. For an `intended` entry
           this is the only score that matters to a user: offering the right word
           in slot 2 while committing the wrong one in slot 1 is still a keyboard
           that types the wrong word. Asked of every entry with a word in
           progress, `acceptable` ones included — for a year this column was the
           `offered` column relabelled for those, and it hid an entry that
           committed a Hebrew non-word while counting as a pass. Where the corpus
           entry types nothing the column is blank rather than zero, because
           `insertSpace` commits nothing when no word is in progress.
  offered  The right word appears in any of the three slots. A weaker pass, worth
           counting separately because it separates "the ranker is wrong" from
           "the candidate was never generated" — two different bugs.
  intact   For `mustNotCorrect`, the bold slot still holds exactly what was typed.
           Any change is the failure; this is the `I` -> `idea` regression guard.

`acceptable` lists with `acceptableIsClosed: false` are a sample of good answers,
never a whitelist, so a miss there is reported but is NOT counted as a failure.
The corpus README is explicit about this and a scorer that ignored it would
punish good suggestions for not being on a list that never claimed to be closed.
"""

import json
import os
import pathlib
import sys
import unicodedata

BAR = pathlib.Path(__file__).resolve().parent.parent


def corpus_path():
    if override := os.environ.get("TYPING_CORPUS"):
        return pathlib.Path(override)
    return BAR / "corpus.json"


def strip_marks(text):
    """Slot text with the decoration a bar puts around it taken off.

    The stock keyboard quotes its literal slot ("minu" comes back as “minu”), and
    a comparison that keeps the quotes reports every literal slot as a miss.
    """
    return text.strip().strip("“”‘’\"'")


def norm(text):
    """Two spellings of one word reduced to the form they share.

    NFC first, because Hebrew typed on a keyboard and Hebrew written in a JSON
    file can decompose differently and compare unequal while looking identical.
    The maqaf fold matches `SuggestionEngine.comparable`; without it a corpus
    entry spelled with Hebrew's own hyphen never matches a slot spelled with the
    ASCII one, which is the only hyphen a Hebrew layout can type.
    """
    text = unicodedata.normalize("NFC", strip_marks(text)).lower()
    return text.replace("־", "-").replace("’", "'")


def load(path):
    return json.loads(pathlib.Path(path).read_text())


def score(outputs, corpus):
    by_id = {e["id"]: e for e in corpus["entries"]}
    rows = []
    for record in outputs:
        entry = by_id.get(record["id"])
        if entry is None:
            continue
        slots = [norm(s) for s in record["slots"]]
        commits = norm(record["commits"])
        typed = norm(entry["prefix"])

        row = {
            "id": record["id"],
            "category": record["category"],
            "slots": record["slots"],
            "commits": record["commits"],
            "kind": None,
            "pass": None,
            "offered": None,
            "commit": None,
        }

        if entry.get("mustNotCorrect"):
            row["kind"] = "mustNotCorrect"
            row["commit"] = commits == typed
            row["pass"] = row["commit"]
        elif entry.get("intended"):
            row["kind"] = "intended"
            want = norm(entry["intended"])
            row["commit"] = commits == want
            row["pass"] = row["commit"]
            row["offered"] = want in slots
        elif entry.get("acceptable"):
            closed = entry.get("acceptableIsClosed", False)
            want = {norm(w) for w in entry["acceptable"]}
            hit = bool(want & set(slots))
            row["kind"] = "acceptable-closed" if closed else "acceptable-open"
            row["offered"] = hit
            # **The commit column used to be the offered column relabelled here,
            # and that is 40 of the 76 judged entries reporting a number nobody
            # measured.** `row["pass"]` was set from `hit` and printed under
            # `commit`, so an entry that offered the right word in slot 2 while
            # bolding a non-word in slot 1 counted as a pass — which is what
            # `he-comp-07` did, committing `מון` for `מונ` with `מונית` sitting
            # beside it. This file's own docstring says why that is the wrong
            # answer: the bold slot is what the space bar inserts.
            #
            # Leaving the typed word alone is not a failure — declining to
            # complete is the conservative half of the trade this engine is built
            # on — so the test is that the bold slot is either what was typed or
            # one of the good answers. With an empty prefix there is nothing to
            # ask: `KeyboardController.insertSpace` commits nothing when no word
            # is in progress, so the bold slot there is a tap target.
            row["commit"] = None if not typed else (commits == typed or commits in want)
            # An open list is a sample, not a whitelist: a miss is not a failure,
            # so it is recorded as unknown rather than as False. Its *commit* is
            # judged anyway, because "the space bar inserted a word that is on
            # neither list" needs no closed list to be wrong.
            row["pass"] = (hit and row["commit"] is not False) if closed else None
        else:
            row["kind"] = "unjudged"
        rows.append(row)
    return rows


def summarise(rows):
    buckets = {}
    for row in rows:
        bucket = buckets.setdefault(
            row["kind"],
            {"n": 0, "pass": 0, "offered": 0, "judged": 0, "commit": 0, "commitJudged": 0},
        )
        bucket["n"] += 1
        if row["pass"] is not None:
            bucket["judged"] += 1
            bucket["pass"] += int(row["pass"])
        if row["commit"] is not None:
            bucket["commitJudged"] += 1
            bucket["commit"] += int(row["commit"])
        if row["offered"]:
            bucket["offered"] += 1
    return buckets


def report(rows, label):
    buckets = summarise(rows)
    print(f"\n=== {label} ===")
    order = ["mustNotCorrect", "intended", "acceptable-closed", "acceptable-open", "unjudged"]
    total_pass = total_judged = 0
    for kind in order:
        bucket = buckets.get(kind)
        if not bucket:
            continue
        # `offered` is not a question that can be asked of `mustNotCorrect`: there
        # is no word to have offered, only a word to have left alone. It printed
        # `0/12` there, which reads as twelve failures.
        offered = (
            f"   {bucket['offered']:3d}/{bucket['n']:<3d} offered"
            if kind != "mustNotCorrect"
            else "   (n/a)"
        )
        # Counted from the rows that were asked, never from `pass`. Every entry
        # with an empty prefix is absent from the denominator, because nothing is
        # committed where no word is in progress.
        commit = (
            f"{bucket['commit']:3d}/{bucket['commitJudged']:<3d} commit"
            if bucket["commitJudged"]
            else f"{'':11s}"
        )
        if bucket["judged"]:
            total_pass += bucket["pass"]
            total_judged += bucket["judged"]
        print(f"  {kind:20s} {commit}{offered}")
    print(f"  {'TOTAL (judged)':20s} {total_pass:3d}/{total_judged:<3d}")
    return total_pass, total_judged


def failures(rows):
    return {r["id"]: r for r in rows if r["pass"] is False}


def main():
    corpus = load(corpus_path())
    args = sys.argv[1:]
    if len(args) == 2:
        before = score(load(args[0]), corpus)
        after = score(load(args[1]), corpus)
        report(before, f"before: {args[0]}")
        report(after, f"after: {args[1]}")
        fb, fa = failures(before), failures(after)
        fixed = sorted(set(fb) - set(fa))
        broke = sorted(set(fa) - set(fb))
        print(f"\n  fixed:  {len(fixed)}  {', '.join(fixed) or '-'}")
        print(f"  broke:  {len(broke)}  {', '.join(broke) or '-'}")
        for rid in broke:
            print(f"    ! {rid}  commits {fa[rid]['commits']!r}  slots {fa[rid]['slots']}")
        return

    path = args[0] if args else BAR / "engine_outputs.json"
    rows = score(load(path), corpus)
    report(rows, str(path))
    print("\n  failing:")
    for row in rows:
        if row["pass"] is False:
            print(f"    {row['id']:12s} {row['kind']:18s} commits {row['commits']!r}  slots {row['slots']}")
    # An open list cannot say a *miss* is wrong, but it can say a commit is: the
    # space bar inserted a word that is neither what the user typed nor one of the
    # answers anybody thought was good. `cs-11` lived here, committing `לף`.
    committed_elsewhere = [
        row for row in rows if row["kind"] == "acceptable-open" and row["commit"] is False
    ]
    if committed_elsewhere:
        print("\n  open-list entries that still commit something off the list:")
        for row in committed_elsewhere:
            print(f"    {row['id']:12s} commits {row['commits']!r}  slots {row['slots']}")
    print("\n  open-list misses (NOT failures, the list is a sample):")
    for row in rows:
        if row["kind"] == "acceptable-open" and not row["offered"]:
            print(f"    {row['id']:12s} slots {row['slots']}")


if __name__ == "__main__":
    main()
