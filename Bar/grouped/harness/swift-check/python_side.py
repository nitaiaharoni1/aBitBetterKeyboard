#!/usr/bin/env python3
"""Ask the Python harness the same questions `main.swift` asks the keyboard, and
compare the answers structurally.

Structurally rather than as text: both sides emit JSON, but Swift's
`JSONSerialization` and Python's `json` disagree about key order, escaping and
whitespace, and a `diff` over that reports formatting as a defect. What matters
is whether the two implementations *group and decode the same*, so this parses
both and walks them.

    python3 python_side.py <swift-output.json>

Exits non-zero on any disagreement, printing each one.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from decode import Decoder, Lexicon  # noqa: E402
from grouping import HEBREW_CLITICS, Layout  # noqa: E402

LEVELS = [2, 3, 4, 5]

VOCABULARY = {
    "en": ["the", "to", "and", "of", "a", "in", "is", "it", "that", "for", "cat", "car", "cab", "bat"],
    "he": ["את", "של", "לא", "על", "זה", "הוא", "אני", "כל", "שלום", "תודה", "מה", "בסדר"],
}


def clitics(tag: str) -> set:
    return HEBREW_CLITICS if tag == "he" else set()


def prefix_candidates(decoder, lexicon, code, limit=3):
    """Words whose keystrokes BEGIN with this code, commonest first.

    **The sweep and the keyboard ask different questions, and comparing them
    without this would compare nothing.** `Decoder.candidates` matches a code
    *exactly*, which is right for `run.py`: it measures a finished word against
    the words that press the same keys. The keyboard is asked mid-word, so it
    matches a *prefix* — `t|h|e` has to offer `that` after two keys. Implemented
    here rather than in `decode.py` so the measured harness is untouched by the
    port check.
    """
    out = []
    for candidate_code, words in decoder.index.items():
        if candidate_code[: len(code)] == code:
            out.extend(words)
    out.sort(key=lambda word: -lexicon.freq[word])
    return out[:limit]


def build(rows_path: Path) -> dict:
    rows_payload = json.loads(rows_path.read_text(encoding="utf-8"))["languages"]

    grouping = {}
    decoding = {}
    for tag, block in rows_payload.items():
        rows = block["rows"]
        per_level_groups = []
        per_level_decode = []
        for k in LEVELS:
            layout = Layout(rows, k, avoid=clitics(tag))
            adjacent = Layout(rows, k)
            per_level_groups.append(
                {
                    "k": k,
                    "keys": layout.keys,
                    "groups": layout.groups,
                    "adjacentGroups": adjacent.groups,
                    "cliticCollisions": layout.collisions(clitics(tag)),
                }
            )

            words = VOCABULARY[tag]
            # Descending frequency in list order, so both sides rank identically.
            lexicon = Lexicon(tag, [(w, 1.0 / (i + 1)) for i, w in enumerate(words)], "check")
            decoder = Decoder(lexicon, layout)
            codes = {}
            candidates = {}
            for word in words:
                code = layout.code(word)
                if code is None:
                    continue
                codes[word] = list(code)
                for length in range(1, len(code) + 1):
                    candidates[f"{word}|{length}"] = prefix_candidates(
                        decoder, lexicon, code[:length]
                    )
            per_level_decode.append({"k": k, "codes": codes, "candidates": candidates})
        grouping[tag] = per_level_groups
        decoding[tag] = per_level_decode
    return {"grouping": grouping, "decoding": decoding}


def compare(path: list, python_side, swift_side, problems: list) -> None:
    where = ".".join(str(p) for p in path)
    if isinstance(python_side, dict) and isinstance(swift_side, dict):
        for key in sorted(set(python_side) | set(swift_side)):
            if key not in python_side:
                problems.append(f"{where}.{key}: only Swift has it -> {swift_side[key]!r}")
            elif key not in swift_side:
                problems.append(f"{where}.{key}: only Python has it -> {python_side[key]!r}")
            else:
                compare(path + [key], python_side[key], swift_side[key], problems)
    elif isinstance(python_side, list) and isinstance(swift_side, list):
        if len(python_side) != len(swift_side):
            problems.append(f"{where}: length {len(python_side)} (py) vs {len(swift_side)} (swift)")
            return
        for index, (left, right) in enumerate(zip(python_side, swift_side)):
            compare(path + [index], left, right, problems)
    elif python_side != swift_side:
        problems.append(f"{where}: {python_side!r} (py) != {swift_side!r} (swift)")


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("usage: python_side.py <swift-output.json>")
    swift = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    python_side = build(HERE.parent.parent / "data" / "rows.json")

    problems: list = []
    compare([], python_side, swift, problems)
    if problems:
        print(f"{len(problems)} disagreement(s):", file=sys.stderr)
        for problem in problems[:40]:
            print(f"  {problem}", file=sys.stderr)
        sys.exit(1)

    groups = sum(len(v) for v in python_side["grouping"].values())
    answers = sum(
        len(level["candidates"]) for block in python_side["decoding"].values() for level in block
    )
    print(
        f"swift-check: identical — {groups} grouping conditions and "
        f"{answers} decode answers agree exactly"
    )


if __name__ == "__main__":
    main()
