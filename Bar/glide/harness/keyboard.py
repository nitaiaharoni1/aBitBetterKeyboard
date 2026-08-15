"""Key geometry for the glide-typing spike: where each letter's key centre
sits, and the same `.code(word)` interface `Bar/grouped/harness/decode.py`'s
`Decoder` already expects.

Physical layout only — one letter, one key, no grouping. Reuses the row
strings `Bar/grouped/make-rows.py` already extracted from `LetterLayouts.swift`
rather than re-deriving them, so a row edited in Swift moves this harness too.
"""

from __future__ import annotations

import json
from pathlib import Path

GROUPED_DATA = Path(__file__).resolve().parent.parent.parent / "grouped" / "data"


def load_rows(language: str) -> list[str]:
    payload = json.loads((GROUPED_DATA / "rows.json").read_text(encoding="utf-8"))
    return payload["languages"][language]["rows"]


def letter_centers(rows: list[str]) -> dict[str, tuple[float, float]]:
    """One key centre per letter, in key-width units.

    Rows are already left-to-right screen order — `rows.json` says so, and
    Hebrew is not mirrored there either — so column position is read straight
    off the row string with no direction handling needed.

    Each row is centred under the widest row, the way the keyboard actually
    draws `asdfghjkl` and `zxcvbnm` narrower than `qwertyuiop` rather than
    flush left. Skipping this moves every key's x by up to half a key width,
    which is not a small error next to the sigmas this sweep uses.
    """
    width = max(len(row) for row in rows)
    centers: dict[str, tuple[float, float]] = {}
    for row_index, row in enumerate(rows):
        offset = (width - len(row)) / 2.0
        for col, letter in enumerate(row):
            centers[letter] = (offset + col + 0.5, row_index + 0.5)
    return centers


def nearest_letter(x: float, y: float, centers: dict[str, tuple[float, float]]) -> str:
    """The letter whose key centre is closest to (x, y)."""
    best_letter, best_d = None, float("inf")
    for letter, (cx, cy) in centers.items():
        d = (x - cx) ** 2 + (y - cy) ** 2
        if d < best_d:
            best_letter, best_d = letter, d
    return best_letter


class GlideLayout:
    """One language's physical keyboard, letter-per-key, exposed as the same
    `.code(word)` interface `Bar/grouped/harness/decode.Decoder` already
    expects — reused unmodified below, not reimplemented, which is the answer
    to "can that decoder be reused for glide typing" written in code rather
    than in prose.

    The code a word maps to is its own spelling with consecutive duplicate
    letters collapsed: the shape a perfectly executed swipe produces, since a
    path does not stop and restart at a repeated letter. It is also the reason
    `later` and `latter` cannot be told apart by geometry alone — both collapse
    to the same code, exactly the ambiguity `GroupedDecoder` already ranks
    homographs under, just arrived at by a different route.

    Any non-letter character — punctuation, digits, another script — returns
    `None` for the whole word. A grouped key can still show a symbol on the
    same plane it draws letters on; a glide gesture cannot cross from the
    letter plane to the numbers plane mid-swipe, so a word that needs one is
    unmappable here in a way it is not for `Bar/grouped`.
    """

    def __init__(self, rows: list[str]):
        self.rows = rows
        self.centers = letter_centers(rows)

    def code(self, word: str) -> tuple[str, ...] | None:
        out: list[str] = []
        for letter in word:
            if letter not in self.centers:
                return None
            if not out or out[-1] != letter:
                out.append(letter)
        return tuple(out) if out else None
