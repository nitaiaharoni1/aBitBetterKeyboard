#!/usr/bin/env python3
"""What happens when the thumb misses.

The main sweep in `run.py` assumes every tap hits the intended key. That is
the decoder's ceiling, and it cannot see the reason grouped keys exist: a
bigger target. This script adds Gaussian noise, in ungrouped-key widths, and
asks which *drawn* key contains the noisy point.

    python3 Bar/grouped/harness/miss.py

Writes `Bar/grouped/miss.json`. Needs the same data files as `run.py`.
"""

from __future__ import annotations

import json
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import run  # noqa: E402
from decode import Decoder, Lexicon  # noqa: E402
from grouping import HEBREW_CLITICS, Layout  # noqa: E402

DATA = HERE.parent / "data"
OUT = HERE.parent / "miss.json"
SHIPPED = (
    HERE.parent.parent.parent
    / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources"
)

# Noise in ungrouped-key widths. 0.35 is a fat thumb on a ~35pt key; 0.2 is
# careful; 0.5 is walking. The same sigma is applied to every layout, so a
# two-by-two grouped key is four times the area and the miss rate should drop.
SIGMAS = (0.20, 0.35, 0.50)
SAMPLES = 1  # one noisy realisation per letter; the seed makes it repeatable
SEED = 20260813


def letter_centers(rows: list[str]) -> dict[str, tuple[float, float]]:
    cells = {}
    for row_index, row in enumerate(rows):
        for col, letter in enumerate(row):
            cells[letter] = (col + 0.5, row_index + 0.5)
    return cells


def key_boxes(layout: Layout, centers: dict[str, tuple[float, float]]):
    """Axis-aligned boxes in ungrouped-key units.

    A band key is always two rows tall, even when a leftover column only
    has letters on one of them (`ךף` sits on the lower half with empty
    glass above). Measuring only the letters would shrink the target the
    keyboard actually draws.
    """
    boxes = []
    for row_index, row in enumerate(layout.groups_by_row):
        band = layout.k > 1 and row_index == 0 and len(layout.rows) >= 3
        for group in row:
            pts = [centers[letter] for letter in group if letter in centers]
            xs = [p[0] for p in pts]
            x0, x1 = min(xs) - 0.5, max(xs) + 0.5
            if band:
                y0, y1 = 0.0, 2.0
            else:
                ys = [p[1] for p in pts]
                y0, y1 = min(ys) - 0.5, max(ys) + 0.5
            boxes.append((x0, y0, x1, y1))
    return boxes


def hit(x: float, y: float, boxes) -> int:
    for index, (x0, y0, x1, y1) in enumerate(boxes):
        if x0 <= x < x1 and y0 <= y < y1:
            return index
    best, best_d = 0, 1e9
    for index, (x0, y0, x1, y1) in enumerate(boxes):
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        d = (x - cx) ** 2 + (y - cy) ** 2
        if d < best_d:
            best, best_d = index, d
    return best


def noisy_code(word: str, layout: Layout, centers, boxes, rng: random.Random, sigma: float):
    """Key sequence after each letter's tap is nudged. None if untypeable."""
    true = layout.code(word)
    if true is None:
        return None, 0, 0
    folded = layout.fold(word) if layout.fold else word
    out = []
    hits = misses = 0
    for character, intended in zip(folded, true):
        if character not in centers:
            out.append(intended)
            continue
        cx, cy = centers[character]
        landed = hit(cx + rng.gauss(0, sigma), cy + rng.gauss(0, sigma), boxes)
        out.append(landed)
        if landed == intended:
            hits += 1
        else:
            misses += 1
    return tuple(out), hits, misses


def evaluate(entries, layout, decoder, centers, boxes, sigma: float, seed: int) -> dict:
    rng = random.Random(seed)
    typed = unmappable = oov = commit = offered = hits = misses = 0
    for entry in entries:
        for word in entry["tokens"]:
            typed += 1
            code, h, m = noisy_code(word, layout, centers, boxes, rng, sigma)
            hits += h
            misses += m
            if code is None:
                unmappable += 1
                continue
            if word not in decoder.lexicon.freq:
                oov += 1
                continue
            ranked = decoder.candidates(code)
            if word not in ranked:
                continue
            position = ranked.index(word)
            if position == 0:
                commit += 1
            elif position < 3:
                offered += 1
    in_scope = typed - unmappable
    known = in_scope - oov
    aimed = hits + misses
    return {
        "typed": typed,
        "unmappable": unmappable,
        "inScope": in_scope,
        "oov": oov,
        "known": known,
        "commit": commit,
        "offeredOnly": offered,
        "commitRate": commit / known if known else 0,
        "offeredRate": (commit + offered) / known if known else 0,
        "keyHits": hits,
        "keyMisses": misses,
        "keyHitRate": hits / aimed if aimed else 0,
        "sigma": sigma,
    }


def load_lexicon(language: str) -> Lexicon:
    """Measurement JSON if present, else the lists the keyboard ships."""
    measured = DATA / f"lexicon-{language}.json"
    if measured.exists():
        return Lexicon.load(measured)
    shipped = SHIPPED / f"GroupedLexicon-{language}.txt"
    if shipped.exists():
        return Lexicon.from_ranked_lines(language, shipped)
    sys.exit(
        f"missing lexicon for {language}\n"
        "  python3 Scripts/generate-grouped-lexicon.py\n"
        "  # or Bar/grouped/.venv/bin/python Bar/grouped/make-lexicon.py"
    )


def main() -> None:
    run.require_data("rows.json", "testtext.json")
    rows = json.loads((DATA / "rows.json").read_text(encoding="utf-8"))
    text = json.loads((DATA / "testtext.json").read_text(encoding="utf-8"))
    lex = {language: load_lexicon(language) for language in ("en", "he")}
    entries = {"en": [], "he": []}
    for entry in text["entries"]:
        entry["tokens"] = run.tokenise(entry["text"])
        if entry["tokens"]:
            entries[entry["language"]].append(entry)

    conditions = [
        ("en", 1, None, "en ungrouped"),
        ("en", 3, None, "en L1"),
        ("he", 1, HEBREW_CLITICS, "he ungrouped"),
        ("he", 3, HEBREW_CLITICS, "he L1 separated"),
    ]

    results = []
    print(f"{'layout':<22} {'σ':>5} {'hit key':>8} {'commit':>8} {'offered':>8}")
    for language, k, avoid, label in conditions:
        source_rows = rows["languages"][language]["rows"]
        layout = Layout(source_rows, k, avoid=avoid)
        decoder = Decoder(lex[language], layout)
        centers = letter_centers(source_rows)
        boxes = key_boxes(layout, centers)
        for sigma in SIGMAS:
            stats = evaluate(
                entries[language], layout, decoder, centers, boxes, sigma, SEED
            )
            stats["label"] = label
            stats["language"] = language
            stats["k"] = k
            stats["keys"] = layout.keys
            results.append(stats)
            print(
                f"{label:<22} {sigma:5.2f} {100 * stats['keyHitRate']:7.1f}% "
                f"{100 * stats['commitRate']:7.1f}% {100 * stats['offeredRate']:7.1f}%"
            )

    OUT.write_text(
        json.dumps(
            {
                "generated_by": "Bar/grouped/harness/miss.py",
                "warning": (
                    "Gaussian tap noise in ungrouped-key widths. The same sigma "
                    "hits a grouped key less often because the target is larger. "
                    "Not a user study."
                ),
                "seed": SEED,
                "sigmas": list(SIGMAS),
                "lexicon": {language: lex[language].source for language in lex},
                "results": results,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"\n-> {OUT}")


if __name__ == "__main__":
    main()
