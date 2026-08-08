#!/usr/bin/env python3
"""Scores a raw-OCR pass against the screen-context bar.

The question is narrow on purpose: did the recogniser put the expected message
text on the page at all? Structure comes later; unreadable pixels cannot be
parsed into structure by anything downstream.

Recall is character-level over the expected message with whitespace collapsed,
using difflib's matching blocks so word order and line breaks do not punish a
correct read.
"""

import json
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path

HERE = Path(__file__).resolve().parent
BAR = HERE.parent


def normalise(text):
    # Collapse whitespace and drop the bidi control marks a renderer may inject.
    text = re.sub(r"[‎‏‪-‮⁦-⁩]", "", text or "")
    return re.sub(r"\s+", " ", text).strip()


def recall(expected, actual):
    """Fraction of expected characters that appear, in order, inside actual."""
    expected, actual = normalise(expected), normalise(actual)
    if not expected:
        return None
    matcher = SequenceMatcher(None, expected, actual, autojunk=False)
    matched = sum(block.size for block in matcher.get_matching_blocks())
    return matched / len(expected)


def main():
    truth = json.loads((BAR / "ground-truth.json").read_text())
    outputs = json.loads((BAR / sys.argv[1]).read_text())

    by_id = {entry["id"]: entry for entry in truth["images"]}
    configs = sorted({row["config"] for row in outputs})

    print(f"{'config':8} {'language':9} {'n':>3} {'msg recall':>11} {'sender recall':>14}")
    print("-" * 50)

    detail = []
    for config in configs:
        buckets = {}
        for row in outputs:
            if row["config"] != config:
                continue
            entry = by_id[row["id"]]
            expected = entry.get("expected")
            if not expected:
                continue  # the deliberate no-repliable-text image
            msg = recall(expected.get("message"), row["text"])
            sender = recall(expected.get("sender"), row["text"])
            buckets.setdefault(entry["language"], []).append((msg, sender))
            detail.append((config, row["id"], entry["language"], msg, sender))

        for language in ("english", "mixed", "hebrew"):
            rows = buckets.get(language, [])
            if not rows:
                continue
            msgs = [m for m, _ in rows if m is not None]
            senders = [s for _, s in rows if s is not None]
            print(
                f"{config:8} {language:9} {len(rows):>3} "
                f"{sum(msgs)/len(msgs):>10.0%} {sum(senders)/len(senders):>13.0%}"
            )
        allrows = [v for rows in buckets.values() for v in rows]
        msgs = [m for m, _ in allrows if m is not None]
        print(f"{config:8} {'ALL':9} {len(allrows):>3} {sum(msgs)/len(msgs):>10.0%}")
        print("-" * 50)

    if "-v" in sys.argv:
        print("\nper image (msg recall):")
        for config, ident, language, msg, sender in detail:
            if config != configs[0]:
                continue
            print(f"  {ident:8} {language:9} {msg:>6.0%}")


if __name__ == "__main__":
    main()
