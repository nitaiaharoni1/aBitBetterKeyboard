"""Things that must be true before a score means anything.

`Bar/typing/async/validate.py` exists because `score.py` silently bucketed a
malformed entry as `unjudged` and it never counted again — a corpus entry that
cannot fail is worse than no entry, because the total goes up. Same idea here,
plus the two facts the port rests on.

    python3 Bar/emoji/harness/selftest.py

Exits non-zero on the first category of problem, and prints all of them.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import rank

HERE = Path(__file__).resolve().parent
CORPUS = HERE.parent / "corpus.json"

JUDGEMENTS = ("intended", "acceptable", "expectEmpty")


def main() -> int:
    problems: list[str] = []
    corpus = json.loads(CORPUS.read_text(encoding="utf-8"))
    entries = corpus["entries"]
    cat = rank.catalog()
    known = set(cat.all)

    # 1. The port's one arithmetic assumption. Swift counts grapheme clusters
    # and `Match.length` is a tiebreak, so a length off by one is a different
    # answer. `rank.swift_count` drops combining marks and does nothing else,
    # which is exact for this catalogue and only for this catalogue.
    beyond = cat.beyond_the_length_rule()
    if beyond:
        problems.append(
            f"{len(beyond)} catalogue strings are beyond rank.swift_count's rule "
            f"(astral, ZWJ, variation selector or regional indicator): {beyond[:3]}. "
            "rank.py needs real grapheme segmentation."
        )

    # 2. Every entry is judgeable, exactly one way.
    ids: set[str] = set()
    queries: dict[str, str] = {}
    for entry in entries:
        eid = entry["id"]
        if eid in ids:
            problems.append(f"{eid}: duplicate id")
        ids.add(eid)

        kinds = [k for k in JUDGEMENTS if k in entry]
        if not kinds:
            problems.append(
                f"{eid}: carries none of {JUDGEMENTS}, so it can never fail"
            )
        if "expectEmpty" in entry and len(kinds) > 1:
            problems.append(f"{eid}: expectEmpty alongside {kinds}")

        if "acceptable" in entry:
            if "acceptableIsClosed" not in entry:
                problems.append(f"{eid}: acceptable without acceptableIsClosed")
            if "acceptableSource" not in entry:
                problems.append(f"{eid}: acceptable without acceptableSource")
            if not entry["acceptable"]:
                problems.append(f"{eid}: empty acceptable list")
            if "intended" in entry:
                problems.append(
                    f"{eid}: intended and acceptable together — near answers to an "
                    "`intended` go in `alsoFine`, which is never counted"
                )
        if "alsoFine" in entry and "intended" not in entry:
            problems.append(f"{eid}: alsoFine without an intended to be near")

        # 3. Every emoji named anywhere must be in the shipping catalogue. A
        # judgement naming an emoji the grid does not have is unreachable by
        # construction and reads as a ranker failure forever.
        named = list(entry.get("acceptable", [])) + list(entry.get("mustNotRank", []))
        named += list(entry.get("recent", [])) + list(entry.get("alsoFine", []))
        if "intended" in entry:
            named.append(entry["intended"])
        for emoji in named:
            if emoji not in known:
                problems.append(f"{eid}: {emoji!r} is not in EmojiCatalog.json")

        # 4. `mustNotRank` is for a different concept, so it may never name an
        # emoji the same entry calls a good answer.
        good = set(entry.get("acceptable", [])) | set(entry.get("alsoFine", []))
        if "intended" in entry:
            good.add(entry["intended"])
        overlap = good & set(entry.get("mustNotRank", []))
        if overlap:
            problems.append(f"{eid}: {overlap} is both wanted and forbidden")

        # 5. Two entries with the same query and the same recents are one
        # entry counted twice.
        key = json.dumps([entry["query"], entry.get("recent", [])], ensure_ascii=False)
        if key in queries:
            problems.append(f"{eid}: same query and recents as {queries[key]}")
        queries[key] = eid

    if "mustNotRankWindow" not in corpus:
        problems.append("corpus has no mustNotRankWindow")

    print(f"{len(entries)} entries, {len(cat.all)} emoji in the catalogue")
    if problems:
        for problem in problems:
            print(f"  FAIL {problem}")
        return 1
    print("selftest ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
