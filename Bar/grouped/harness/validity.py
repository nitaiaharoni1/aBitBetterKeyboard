#!/usr/bin/env python3
"""How much the sweep's numbers can carry.

`results.json` reports rates to a tenth of a percent off roughly 1,800 English
and 1,500 Hebrew words. That precision is arithmetic, not evidence. This asks
three questions the sweep cannot ask itself:

1. **How thin is the sample** — tokens, distinct words, and how many appear once.
2. **Is the test text unnaturally easy** — the Zipf distribution of what is being
   typed. Corpora written to exercise a keyboard could be all common words, which
   would flatter every commit rate in the sweep.
3. **Would a different sample have said something different** — split-half over
   twenty random halves, reporting the spread.

The decoder is deterministic, so this is entirely about sample size. The
"one corpus run is not evidence" rule in `AGENTS.md` is about a sampled judge and
a sampled model; it does not apply to the sweep, and this does not make it apply.
What does apply is that 90 frozen moments were once mistaken for a keyboard.

    python3 Bar/grouped/harness/validity.py
"""

from __future__ import annotations

import json
import random
import statistics
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import run as sweep  # noqa: E402
from decode import Decoder, Lexicon, zipf  # noqa: E402
from grouping import HEBREW_CLITICS, Layout  # noqa: E402

DATA = HERE.parent / "data"
HALVES = 20


def main() -> None:
    sweep.require_data(*sweep.EVERYTHING)
    rows = json.loads((DATA / "rows.json").read_text(encoding="utf-8"))["languages"]
    text = json.loads((DATA / "testtext.json").read_text(encoding="utf-8"))

    entries: dict[str, list[dict]] = {"en": [], "he": []}
    for entry in text["entries"]:
        entry = dict(entry)
        entry["tokens"] = sweep.tokenise(entry["text"])
        if entry["tokens"]:
            entries[entry["language"]].append(entry)

    report: dict[str, dict] = {}

    for language in ("en", "he"):
        lexicon = Lexicon.load(DATA / f"lexicon-{language}.json")
        tokens = [t for e in entries[language] for t in e["tokens"]]
        counts = Counter(tokens)
        zipfs = [zipf(lexicon.freq[t]) for t in tokens if t in lexicon.freq]

        print(f"\n=== {language.upper()} sample")
        print(f"  entries      {len(entries[language])}")
        print(f"  tokens       {len(tokens)}")
        print(f"  distinct     {len(counts)}   (type/token {len(counts)/len(tokens):.2f})")
        print(f"  seen once    {sum(1 for c in counts.values() if c == 1)}")
        print(
            f"  Zipf         mean {statistics.mean(zipfs):.2f}  "
            f"median {statistics.median(zipfs):.2f}  "
            f"p10 {statistics.quantiles(zipfs, n=10)[0]:.2f}   (7 = 'the', 3 = rare)"
        )
        report[language] = {
            "entries": len(entries[language]),
            "tokens": len(tokens),
            "distinct": len(counts),
            "seenOnce": sum(1 for c in counts.values() if c == 1),
            "meanZipf": round(statistics.mean(zipfs), 2),
            "medianZipf": round(statistics.median(zipfs), 2),
        }

    print(f"\n=== split-half stability, {HALVES} random halves, no context")
    print(f"{'':>22} {'full':>7} {'min':>7} {'max':>7} {'sd':>6}")
    stability = []
    for language, k, avoid, label in (
        ("en", 2, None, "en k=2"),
        ("en", 3, None, "en k=3 (L1)"),
        ("en", 4, None, "en k=4 (L2)"),
        ("en", 5, None, "en k=5 (L3)"),
        ("he", 2, HEBREW_CLITICS, "he k=2 separated"),
        ("he", 3, HEBREW_CLITICS, "he k=3 (L1) separated"),
        ("he", 4, None, "he k=4 (L2)"),
        ("he", 5, None, "he k=5 (L3)"),
    ):
        lexicon = Lexicon.load(DATA / f"lexicon-{language}.json")
        layout = Layout(rows[language]["rows"], k, avoid=avoid)
        decoder = Decoder(lexicon, layout)
        pool = entries[language]
        full = sweep.evaluate(pool, layout, decoder, None)["commitRate"]
        rnd = random.Random(7)
        rates = []
        for _ in range(HALVES):
            shuffled = pool[:]
            rnd.shuffle(shuffled)
            rates.append(
                sweep.evaluate(shuffled[: len(shuffled) // 2], layout, decoder, None)[
                    "commitRate"
                ]
            )
        print(
            f"{label:>22} {full:>6.1%} {min(rates):>6.1%} {max(rates):>6.1%} "
            f"{statistics.stdev(rates):>5.2%}"
        )
        stability.append(
            {
                "label": label,
                "full": round(full, 4),
                "min": round(min(rates), 4),
                "max": round(max(rates), 4),
                "sd": round(statistics.stdev(rates), 4),
            }
        )

    worst = max(s["sd"] for s in stability)
    print(
        f"\n  Widest half-to-half spread: {worst:.1%}. Read every rate in "
        f"results.json\n  as ±{worst*100:.0f} points at best, and never compare two "
        "conditions that differ\n  by less than that."
    )

    out = HERE.parent / "validity.json"
    out.write_text(
        json.dumps(
            {
                "generated_by": "Bar/grouped/harness/validity.py",
                "halves": HALVES,
                "sample": report,
                "splitHalf": stability,
                "worstSpread": worst,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"\nwrote {out}")


if __name__ == "__main__":
    main()
