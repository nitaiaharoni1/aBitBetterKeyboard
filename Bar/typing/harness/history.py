#!/usr/bin/env python3
"""Writes a synthetic personal typing history for `PERSONAL_HISTORY`.

    Bar/typing/harness/history.py /tmp/history.txt
    PERSONAL_HISTORY=/tmp/history.txt Bar/typing/harness/run.sh /tmp/out.json

The harness scores with an empty personal model by default, and no phone is in
that state: after a week of typing, thousands of words carry two or more
sightings and compete for every prefix. This file stands in for that week.

Words are drawn Zipf-weighted from the top of GroupedLexicon-{he,en}.txt, so
common words collect high counts and the long tail collects two or three, the
shape a real store has. The lexicon is written text rather than chat, so this is
a stress test of how learned words compete with the rest of the bar, not a
model of any one person's vocabulary. Seeded, so the same arguments always
write the same file.
"""

import random
import sys
from pathlib import Path

RESOURCES = Path(__file__).resolve().parents[3] / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources"
TOP = 5000
LINES = 4000
WORDS_PER_LINE = 6
HEBREW_SHARE = 0.7


def vocabulary(tag):
    words = (RESOURCES / f"GroupedLexicon-{tag}.txt").read_text(encoding="utf-8").split()
    words = words[:TOP]
    weights = [1 / (rank + 1) for rank in range(len(words))]
    return words, weights


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: history.py OUT.txt")
    rng = random.Random(20260922)
    he, en = vocabulary("he"), vocabulary("en")
    lines = []
    for _ in range(LINES):
        words, weights = he if rng.random() < HEBREW_SHARE else en
        lines.append(" ".join(rng.choices(words, weights=weights, k=WORDS_PER_LINE)))
    Path(sys.argv[1]).write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
