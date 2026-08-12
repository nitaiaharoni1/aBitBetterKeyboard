#!/usr/bin/env python3
"""How big does the bundled word list have to be?

A keyboard extension is memory-capped, and `LanguageModel.json` is 24 KB today.
A 200,000-word lexicon is fine for measuring and is not obviously shippable, so
this asks what the curve looks like: at what size does trimming the list start
costing commits, and where does it stop buying any.

Two effects pull against each other and the sum is not monotonic in the obvious
direction. A **bigger** list covers more words, so out-of-vocabulary falls. A
bigger list also puts more words inside every group, so collisions rise and the
ranker has more chances to pick the wrong one. Somewhere those cross.

    python3 Bar/grouped/harness/lexsize.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import run as sweep  # noqa: E402
from decode import Decoder, Lexicon  # noqa: E402
from grouping import HEBREW_CLITICS, Layout  # noqa: E402

DATA = HERE.parent / "data"
SIZES = [2_000, 5_000, 10_000, 20_000, 50_000, 100_000, 200_000]

# Roughly, as UTF-8 JSON of [word, freq] pairs. Hebrew words are 2 bytes a letter.
BYTES_PER_WORD = {"en": 22, "he": 26}


def truncated(path: Path, limit: int) -> Lexicon:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return Lexicon(payload["language"], payload["words"][:limit], payload["source"])


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

    out = []
    for language, k, avoid, label in (
        ("en", 2, None, "en k=2 (14 keys)"),
        ("en", 3, None, "en k=3 / L1 (8 keys)"),
        ("he", 2, HEBREW_CLITICS, "he k=2 separated (14 keys)"),
        ("he", 3, HEBREW_CLITICS, "he k=3 / L1 separated (9 keys)"),
    ):
        print(f"\n=== {label}")
        print(f"{'words':>8} {'~KB':>6} {'commit':>7} {'offered':>8} {'oov':>6} {'coll':>7}")
        layout = Layout(rows[language]["rows"], k, avoid=avoid)
        for size in SIZES:
            lexicon = truncated(DATA / f"lexicon-{language}.json", size)
            decoder = Decoder(lexicon, layout)
            s = sweep.evaluate(entries[language], layout, decoder, None)
            kb = size * BYTES_PER_WORD[language] / 1024
            print(
                f"{size:>8} {kb:>6.0f} {s['commitRate']:>6.1%} {s['offeredRate']:>7.1%} "
                f"{s['oovRate']:>5.1%} {s['meanCollision']:>7.1f}"
            )
            out.append(
                {
                    "label": label,
                    "language": language,
                    "k": k,
                    "words": size,
                    "approxKB": round(kb),
                    "commitRate": round(s["commitRate"], 4),
                    "offeredRate": round(s["offeredRate"], 4),
                    "oovRate": round(s["oovRate"], 4),
                    "meanCollision": round(s["meanCollision"], 2),
                }
            )

    path = HERE.parent / "lexsize.json"
    path.write_text(
        json.dumps(
            {
                "generated_by": "Bar/grouped/harness/lexsize.py",
                "note": (
                    "Sizes are the top N of the wordfreq list by frequency. "
                    "approxKB is a rough uncompressed estimate, not a measured "
                    "bundle cost."
                ),
                "results": out,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"\nwrote {path}")


if __name__ == "__main__":
    main()
