"""Candidate ranker changes, scored against the same corpus.

    python3 Bar/emoji/harness/variants.py            # every variant, headline each
    python3 Bar/emoji/harness/variants.py --out DIR  # also write a results file each

**Nothing here ships and nothing here is a proposal on its own.** It is the
lever the corpus was built to have: a place to put a candidate scoring rule and
find out what it costs, in seconds, before anybody edits `EmojiSearch.swift`.
Two of the variants below are repairs that were already tried and rejected on an
ad-hoc 60-query run; they are here so that judgement is reproducible against a
frozen corpus instead of remembered.

A variant is a replacement for `rank.score`. Everything else — the catalogue,
the sort, the recents boost — stays exactly as it ships, so a delta is
attributable to the one rule that moved.

`shipping` always means *today's* shipping engine, so it moves when the Swift
moves. The rule it replaced is kept beside it as `keyword-covers-everything`,
which is what rung 1 was before NIT-112, or the row that decided the change
would stop being reproducible the moment the change landed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import rank  # noqa: E402
import score as scorer  # noqa: E402

HEBREW = range(0x0590, 0x0600)

# Captured at import, because a variant is installed by rebinding `rank.score`
# and `shipping` has to be able to call the real one without calling itself.
SHIPPING = rank.score


def _is_hebrew(text: str) -> bool:
    return any(ord(c) in HEBREW for c in text)


def _shortest_in_script(names: list[str], hebrew: bool) -> int:
    same = [n for n in names if _is_hebrew(n) == hebrew]
    return min((rank.swift_count(n) for n in same), default=rank.INT_MAX)


def shipping(needle, names, keywords):
    return SHIPPING(needle, names, keywords)


def keyword_own_length(needle, names, keywords):
    """Repair 1: an exact keyword's `length` is the keyword, not a name.

    The obvious reading of `Match.length`'s own doc comment. An exact keyword
    covers all of itself, so every exact-keyword match ties at the needle's
    length and catalogue order breaks it.

    Scored against the pre-NIT-112 rung 1, which is the rule it was a repair
    for, so the −4 it was rejected on stays the number it was rejected on.
    """
    return _score(needle, names, keywords, keyword_length="needle", keyword_coverage=-1.0)


def keyword_same_script(needle, names, keywords):
    """Repair 2: an exact keyword's `length` is the shortest name in the
    query's own script, so an English query is never decided by a Hebrew name.

    Also scored against the pre-NIT-112 rung 1, for the same reason.
    """
    return _score(needle, names, keywords, keyword_length="script", keyword_coverage=-1.0)


def keyword_covers_everything(needle, names, keywords):
    """Rung 1 as it was before NIT-112: an exact keyword's coverage is −1.

    No name word can ever reach −1, so an exact keyword always beat a name that
    merely contains the word. That is what put 🏠 second for `heart`: `heart` is
    among 🏠's CLDR keywords, and no rearrangement of `length` could help,
    because the keyword branch had already won on coverage.
    """
    return _score(needle, names, keywords, keyword_coverage=-1.0)


def name_word_outranks_keyword(needle, names, keywords):
    """The plain rung split: a name word at rung 1, an exact keyword at rung 2.

    **Measured, and rejected.** +4 on `first`, +0.033 MRR, +2 on `clean`, and it
    fixes `heart` outright — while `ירח` falls from rank 1 to 13 and `car` from
    6 to 12, because "ירח מלא" and "police car" carry the word in a name where
    🌙 and 🚗 only ever had it as a keyword. A twelve-place regression on a
    common Hebrew word does not get paid for by a headline, in a keyboard whose
    reason to exist is Hebrew.
    """
    return _score(needle, names, keywords, split_rung_one=True, keyword_coverage=-1.0)


def keyword_worth_a_third(needle, names, keywords):
    """The split, softened: an exact keyword is worth a third of a name.

    The best headline of anything tried for NIT-112 — +4 `first`, +0.036 MRR,
    +2 `clean` — and it still moves 21 entries, `ירח` and `moon` from rank 1 to
    4 and `קשת` from 1 to 2. It also takes `flower` and `פרח` out of the strip
    entirely, which **no column can see**: both carry an open `acceptable` list,
    and an open list cannot fail. Kept here as the reminder that a rising
    headline and a worse keyboard are not exclusive.
    """
    return _score(needle, names, keywords, keyword_coverage=-1.0 / 3.0)


def keyword_just_under_half(needle, names, keywords):
    """Half, less a hair: 0.48 rather than the 0.5 that shipped.

    The whole difference between this and shipping is whether a name word
    filling *exactly* half its name outranks an exact keyword. Saying yes is
    worth one more on `first` and one more on `clean` — `flower`, `angry`,
    `טלפון` and `כסף` improve — and costs `moon` its rank 1 to 🌑 "new moon",
    4 of 8. Rejected because the constant is then fitted rather than stated:
    there is no sentence for 0.48 that is not "the number that let `new moon`
    through". Everything in [0.5, 0.555] scores identically to shipping.
    """
    return _score(needle, names, keywords, keyword_coverage=-0.48)


def _score(
    needle,
    names,
    keywords,
    keyword_length="shortest",
    split_rung_one=False,
    keyword_coverage=None,
):
    keyword_words = [w for w in keywords.split(" ") if w]
    needle_clusters = rank.graphemes(needle)
    needle_length = len(needle_clusters)
    hebrew = _is_hebrew(needle)
    if keyword_coverage is None:
        keyword_coverage = rank.EXACT_KEYWORD_COVERAGE
    best = rank.NONE

    def coverage(length):
        return -float(needle_length) / float(length) if length > 0 else 0.0

    for name in names:
        if rank.swift_equal(name, needle):
            return (0, -1.0, rank.swift_count(name))

    exact_keyword = 2 if split_rung_one else 1
    name_word = 1
    prefix_name = 3 if split_rung_one else 2
    prefix_keyword = 4 if split_rung_one else 3

    if any(rank.swift_equal(w, needle) for w in keyword_words):
        if keyword_length == "needle":
            length = needle_length
        elif keyword_length == "script":
            length = _shortest_in_script(names, hebrew)
        else:
            length = min(
                (rank.swift_count(n) for n in names), default=rank.INT_MAX
            )
        best = min(best, (exact_keyword, keyword_coverage, length))
    for name in names:
        if any(rank.swift_equal(w, needle) for w in name.split(" ") if w):
            length = rank.swift_count(name)
            best = min(best, (name_word, coverage(length), length))
    if best[0] <= max(exact_keyword, name_word):
        return best

    for name in names:
        for word in name.split(" "):
            if word and rank.swift_has_prefix(word, needle_clusters):
                length = rank.swift_count(name)
                best = min(best, (prefix_name, coverage(length), length))
    for word in keyword_words:
        if rank.swift_has_prefix(word, needle_clusters):
            length = rank.swift_count(word)
            best = min(best, (prefix_keyword, coverage(length), length))
    return best


VARIANTS = {
    "shipping": shipping,
    "keyword-covers-everything": keyword_covers_everything,
    "keyword-own-length": keyword_own_length,
    "keyword-same-script": keyword_same_script,
    "name-word-outranks-keyword": name_word_outranks_keyword,
    "keyword-worth-a-third": keyword_worth_a_third,
    "keyword-just-under-half": keyword_just_under_half,
}

# A data change rather than a ranker change, kept next to them because the
# corpus is what tells the two apart. Giving 🫀 a Hebrew name of its own was
# tried once and reverted because 💏 won instead — see
# `.claude/docs/test-suite-state.md`. With `name-word-outranks-keyword` in
# place, 💏 cannot win: it carries `לב` as a keyword and not as a name.
DATA_PATCH = {"🫀": ["anatomical heart", "לב אנטומי"]}


def run(name: str, patch_names: bool) -> dict:
    corpus = json.loads((HERE.parent / "corpus.json").read_text(encoding="utf-8"))
    original_score = SHIPPING
    catalogue = rank.catalog()
    original_names = {e: list(catalogue.names[e]) for e in DATA_PATCH}
    try:
        rank.score = VARIANTS[name]
        if patch_names:
            for emoji, names in DATA_PATCH.items():
                catalogue.names[emoji] = names
        return scorer.score(corpus)
    finally:
        rank.score = original_score
        for emoji, names in original_names.items():
            catalogue.names[emoji] = names


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", help="directory to write a results file per variant")
    args = parser.parse_args()

    conditions = [(name, False) for name in VARIANTS]
    conditions.append(("name-word-outranks-keyword", True))

    print(f"{'variant':<34} {'first':>8} {'strip':>8} {'MRR':>6} {'clean':>7}")
    print("-" * 66)
    baseline = None
    for name, patch in conditions:
        scored = run(name, patch)
        head = scored["headline"]
        label = name + (" + 🫀 data fix" if patch else "")
        first = f"{head['first']['pass']}/{head['first']['of']}"
        strip = f"{head['strip']['pass']}/{head['strip']['of']}"
        clean = f"{head['clean']['pass']}/{head['clean']['of']}"
        delta = ""
        if baseline is None:
            baseline = head
        else:
            delta = f"   {head['first']['pass'] - baseline['first']['pass']:+d}"
        print(f"{label:<34} {first:>8} {strip:>8} {head['mrr']:>6.3f} {clean:>7}{delta}")

        if args.out:
            path = Path(args.out) / f"{name}{'-datafix' if patch else ''}.json"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                json.dumps(scored, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

    print("")
    print("The five argued-about queries under each variant:")
    for name, patch in conditions:
        original = SHIPPING
        catalogue = rank.catalog()
        saved = {e: list(catalogue.names[e]) for e in DATA_PATCH}
        rank.score = VARIANTS[name]
        if patch:
            for emoji, names in DATA_PATCH.items():
                catalogue.names[emoji] = names
        answers = "  ".join(
            f"{q}: {''.join(rank.results(q, [], 3))}"
            for q in ("car", "heart", "לב", "ירח", "moon")
        )
        rank.score = original
        for emoji, names in saved.items():
            catalogue.names[emoji] = names
        print(f"  {name + (' + data fix' if patch else ''):<34} {answers}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
