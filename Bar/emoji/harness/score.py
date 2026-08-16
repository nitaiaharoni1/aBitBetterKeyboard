"""Grades the emoji ranker against `Bar/emoji/corpus.json`.

    python3 Bar/emoji/harness/score.py                      # score, print, write results.json
    python3 Bar/emoji/harness/score.py --out /tmp/after.json
    python3 Bar/emoji/harness/score.py before.json after.json   # diff two runs

**Position, not presence.** `Bar/typing` learned this the expensive way: a
`contains` check called it a pass while 🚗 sat at rank 17 of the answers to
`car`, and `EmojiModeTests` was rewritten around the same lesson. Every number
below is about where the right answer landed.

Three columns, kept apart on purpose:

  first   Rank 1 is a right answer. The only number a user would recognise:
          it is the leftmost cell of the results strip, which is where a thumb
          goes without reading.
  strip   A right answer inside the first five. Separates "the ranker is
          wrong" from "the candidate was never generated" — the same split
          `Bar/typing` keeps between commit and offered.
  clean   No `mustNotRank` emoji inside those five. A different concept
          appearing in the strip is a failure on its own, whatever won.

An **open** `acceptable` list (`acceptableIsClosed: false`) can pass a column
and can never fail one: the list is a sample of good answers, so an emoji
outside it may be just as good and its absence proves nothing. Those land under
`unjudged` and are printed. A **closed** list, an `intended` and an
`expectEmpty` are all judged outright.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import rank  # noqa: E402

CORPUS = HERE.parent / "corpus.json"
RESULTS = HERE.parent / "results.json"

PASS, FAIL, UNJUDGED = "pass", "fail", "unjudged"
LIMIT = 60


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


def commit() -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=HERE,
            capture_output=True,
            text=True,
            check=True,
        ).stdout.strip()
    except Exception:
        return "unknown"


def judge(entry: dict, results: list[str], window: int) -> dict:
    """One entry's verdict. `results` is the full ranked list, not a slice."""
    row = {
        "id": entry["id"],
        "script": entry["script"],
        "category": entry["category"],
        "query": entry["query"],
        "top": results[:window],
        "targetRank": None,
        "first": UNJUDGED,
        "strip": UNJUDGED,
        "judged": False,
        "violations": [],
    }
    if "knownGap" in entry:
        row["knownGap"] = True

    if entry.get("expectEmpty"):
        row["first"] = row["strip"] = PASS if not results else FAIL
        row["judged"] = True
        row["count"] = len(results)
        return row

    # The judged target, and only it. `alsoFine` is deliberately not here —
    # it is reported and never counted, so `targetRank` always means the rank
    # of the thing the columns are about.
    wanted = [entry["intended"]] if "intended" in entry else list(entry["acceptable"])
    closed = "intended" in entry or entry.get("acceptableIsClosed", False)

    ranks = [results.index(e) + 1 for e in wanted if e in results]
    if ranks:
        row["targetRank"] = min(ranks)
    also = [e for e in entry.get("alsoFine", []) if e in results[:window]]
    if also:
        row["alsoFineInStrip"] = also

    hit_first = bool(results) and results[0] in wanted
    hit_strip = any(e in results[:window] for e in wanted)

    row["judged"] = closed
    row["first"] = PASS if hit_first else (FAIL if closed else UNJUDGED)
    row["strip"] = PASS if hit_strip else (FAIL if closed else UNJUDGED)

    forbidden = [e for e in entry.get("mustNotRank", []) if e in results[:window]]
    row["violations"] = forbidden
    return row


def score(corpus: dict) -> dict:
    window = corpus["mustNotRankWindow"]
    rows = []
    for entry in corpus["entries"]:
        results = rank.results(entry["query"], entry.get("recent", []), LIMIT)
        rows.append(judge(entry, results, window))

    real = [r for r in rows if r["category"] != "negative"]
    negatives = [r for r in rows if r["category"] == "negative"]

    # **The denominator is the entries that could have failed.** An open
    # `acceptable` list cannot fail, so leaving those in would let one raise
    # the headline and never lower it — which is the shape of a number that
    # only ever goes up. They are reported on their own line instead, as the
    # floor they are.
    definite = [r for r in real if r["judged"]]
    opened = [r for r in real if not r["judged"]]
    reciprocal = [1.0 / r["targetRank"] if r["targetRank"] else 0.0 for r in definite]
    with_forbidden = [r for r, e in zip(rows, corpus["entries"]) if e.get("mustNotRank")]

    headline = {
        "entries": len(rows),
        "window": window,
        "first": {
            "pass": sum(1 for r in definite if r["first"] == PASS),
            "of": len(definite),
        },
        "strip": {
            "pass": sum(1 for r in definite if r["strip"] == PASS),
            "of": len(definite),
        },
        "mrr": round(sum(reciprocal) / len(reciprocal), 4) if reciprocal else 0.0,
        "mrrOver": len(definite),
        "open": {
            "entries": len(opened),
            "firstFromTheSample": sum(1 for r in opened if r["first"] == PASS),
            "stripFromTheSample": sum(1 for r in opened if r["strip"] == PASS),
        },
        "negative": {
            "pass": sum(1 for r in negatives if r["first"] == PASS),
            "of": len(negatives),
        },
        "clean": {
            "pass": sum(1 for r in with_forbidden if not r["violations"]),
            "of": len(with_forbidden),
        },
        "knownGaps": sum(1 for r in rows if r.get("knownGap")),
    }
    return {"headline": headline, "entries": rows}


def report(scored: dict, corpus: dict) -> None:
    head = scored["headline"]
    rows = scored["entries"]

    order = [
        "single-concept",
        "name-vs-keyword",
        "ambiguous",
        "prefix",
        "multiword",
        "normalisation",
        "morphology",
        "recents",
        "negative",
    ]
    mark = {PASS: " ", FAIL: "X", UNJUDGED: "?"}

    for category in order:
        here = [r for r in rows if r["category"] == category]
        if not here:
            continue
        print(f"\n{category}  ({len(here)})")
        for r in here:
            gap = " (known gap)" if r.get("knownGap") else ""
            bad = (" forbidden: " + "".join(r["violations"])) if r["violations"] else ""
            place = r["targetRank"] if r["targetRank"] else "-"
            print(
                f"  {mark[r['first']]}{mark[r['strip']]} "
                f"{r['id']:<18} {r['query']!r:<14} @{str(place):<4} "
                f"{''.join(r['top'])}{bad}{gap}"
            )

    print("\n" + "=" * 64)
    print(f"first   {head['first']['pass']}/{head['first']['of']}   rank 1 is a right answer")
    print(f"strip   {head['strip']['pass']}/{head['strip']['of']}   a right answer inside {head['window']}")
    print(f"MRR     {head['mrr']:.3f}  over {head['mrrOver']} entries with a definite target")
    print(f"clean   {head['clean']['pass']}/{head['clean']['of']}   entries with no forbidden emoji in {head['window']}")
    print(f"empty   {head['negative']['pass']}/{head['negative']['of']}   queries that must return nothing")
    print(
        f"open    {head['open']['entries']} entries carry an open list and are outside "
        f"every count above; {head['open']['firstFromTheSample']} answered from the "
        f"sample at rank 1, {head['open']['stripFromTheSample']} inside {head['window']}"
    )
    print(f"gaps    {head['knownGaps']} entries are red on purpose; see corpus.json knownGap")
    print("=" * 64)


def diff(before_path: Path, after_path: Path) -> int:
    before = json.loads(before_path.read_text(encoding="utf-8"))
    after = json.loads(after_path.read_text(encoding="utf-8"))
    by_id = {r["id"]: r for r in before["entries"]}

    moved = 0
    for row in after["entries"]:
        old = by_id.get(row["id"])
        if old is None:
            print(f"  NEW  {row['id']}")
            continue
        if (
            old["first"] == row["first"]
            and old["strip"] == row["strip"]
            and old["targetRank"] == row["targetRank"]
            and old["violations"] == row["violations"]
        ):
            continue
        moved += 1
        print(f"  {row['id']:<18} {row['query']!r}")
        print(f"      before  {old['first']}/{old['strip']} @{old['targetRank']}  {''.join(old['top'])}")
        print(f"      after   {row['first']}/{row['strip']} @{row['targetRank']}  {''.join(row['top'])}")

    print("")
    for key in ("first", "strip", "clean", "negative"):
        a, b = before["headline"][key], after["headline"][key]
        arrow = "" if a["pass"] == b["pass"] else f"   {b['pass'] - a['pass']:+d}"
        print(f"{key:<8} {a['pass']}/{a['of']}  ->  {b['pass']}/{b['of']}{arrow}")
    print(
        f"{'MRR':<8} {before['headline']['mrr']:.3f}  ->  {after['headline']['mrr']:.3f}"
        f"   {after['headline']['mrr'] - before['headline']['mrr']:+.3f}"
    )
    print(f"\n{moved} entries moved")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True, description=__doc__)
    parser.add_argument("paths", nargs="*", help="two results files to diff")
    parser.add_argument("--out", default=str(RESULTS), help="where to write results")
    parser.add_argument("--quiet", action="store_true", help="headline only")
    args = parser.parse_args()

    if len(args.paths) == 2:
        return diff(Path(args.paths[0]), Path(args.paths[1]))
    if args.paths:
        parser.error("give two results files to diff, or none to score")

    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    scored = score(corpus)
    if not args.quiet:
        report(scored, corpus)

    out = {
        "schema": 1,
        "generated": date.today().isoformat(),
        "commit": commit(),
        "engine": "rank.py, checked against the shipping Swift by swift-check.sh",
        "corpus": sha256(CORPUS),
        "catalogue": sha256(rank.catalog().path),
        "limit": LIMIT,
        **scored,
    }
    Path(args.out).write_text(
        json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
