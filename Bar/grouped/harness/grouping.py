"""Turning a keyboard row into grouped keys, and a word into the keys it presses.

Every grouping here is derived from the shipped rows in `data/rows.json`, which
`make-rows.py` extracts from `LetterLayouts.swift`. Nothing is hand-written, so a
row edited in Swift moves the whole harness with it.
"""

from __future__ import annotations

import unicodedata

# The seven single letters Hebrew glues to the front of a word: ה the, ב in,
# ל to, מ from, ו and, ש that, כ as. `HebrewMorphology` strips one before asking
# the dictionary and puts it back afterwards.
HEBREW_CLITICS = set("הבלמושכ")

# Positionally determined: a Hebrew word may only end in the final form and may
# only not end in the ordinary one. `SeedLanguageModel.shapeFolded` folds these
# already, for measuring edit distance.
FINAL_TO_ORDINARY = {"ך": "כ", "ם": "מ", "ן": "נ", "ף": "פ", "ץ": "צ"}


# --- splitting a row ---------------------------------------------------------


def key_count(row_length: int, k: int) -> int:
    """How many keys a row of this length becomes at k letters per key.

    **Rounding is half-up, not Python's `round`.** `round(10/4)` is 2 under
    banker's rounding and 3 under half-up, which is the difference between a row
    of ten letters becoming two keys or three. Minimum one, so a row can never
    vanish.
    """
    return max(1, int(row_length / k + 0.5))


def split_row(row: str, k: int) -> list[str]:
    """Contiguous groups of roughly k letters, **leading groups taking the
    extra** — so `qwertyuiop` at k=3 is `qwer|tyu|iop`, not `qwe|rty|uiop`."""
    n = key_count(len(row), k)
    base, extra = divmod(len(row), n)
    out, at = [], 0
    for index in range(n):
        size = base + (1 if index < extra else 0)
        out.append(row[at : at + size])
        at += size
    return out


def split_row_avoiding(row: str, k: int, avoid: set[str]) -> list[str] | None:
    """Same key count as `split_row`, but no group may hold two letters of
    `avoid`. Boundaries move; adjacency and order are preserved.

    Returns `None` when no such split exists at that key count, which is itself
    a result: it means separating those letters costs an extra key.

    Exact rather than greedy — an exhaustive walk over contiguous partitions,
    which is free on rows of ten letters and avoids a greedy rule quietly
    producing a lopsided row and calling it the cost of the constraint. Ties
    break toward the most even split, measured as squared deviation from the
    ideal size.
    """
    n = key_count(len(row), k)
    ideal = len(row) / n
    best: tuple[float, list[str]] | None = None

    def walk(at: int, left: int, parts: list[str], cost: float) -> None:
        nonlocal best
        if best is not None and cost >= best[0]:
            return
        if left == 0:
            if at == len(row):
                best = (cost, list(parts))
            return
        # Leave at least one letter for each remaining part.
        for size in range(1, len(row) - at - (left - 1) + 1):
            piece = row[at : at + size]
            if sum(1 for c in piece if c in avoid) > 1:
                continue
            parts.append(piece)
            walk(at + size, left - 1, parts, cost + (size - ideal) ** 2)
            parts.pop()

    walk(0, n, [], 0.0)
    return best[1] if best else None


# --- a whole layout ----------------------------------------------------------


class Layout:
    """One language's rows at one grouping level, and the map from letter to key."""

    def __init__(
        self,
        rows: list[str],
        k: int,
        avoid: set[str] | None = None,
        fold=None,
    ):
        self.k = k
        self.rows = rows
        # Applied to every word before it is coded, on both sides of the
        # comparison. Used by the 22-letter Hebrew variant, where the five final
        # forms are off the keyboard and the decoder restores them from position.
        self.fold = fold
        self.groups_by_row: list[list[str]] = []
        self.infeasible = False

        for row in rows:
            if avoid:
                split = split_row_avoiding(row, k, avoid)
                if split is None:
                    self.infeasible = True
                    split = split_row(row, k)
            else:
                split = split_row(row, k)
            self.groups_by_row.append(split)

        self.groups = [g for row in self.groups_by_row for g in row]
        self.letter_to_key = {
            letter: index for index, group in enumerate(self.groups) for letter in group
        }

    @property
    def keys(self) -> int:
        return len(self.groups)

    def collisions(self, among: set[str]) -> list[str]:
        """Groups holding two or more of `among`."""
        return [g for g in self.groups if sum(1 for c in g if c in among) > 1]

    def code(self, word: str) -> tuple | None:
        """The key sequence this word presses, or `None` if it cannot be typed
        on this layout.

        Letters must be on the layout. Anything that is not a letter — an
        apostrophe, a digit, a hyphen — passes through **as itself**, because it
        lives on the numbers plane where nothing is grouped and so is never
        ambiguous. `don't` therefore keeps its apostrophe as a distinct symbol
        and stays in the measurement, rather than being thrown out as
        untypeable.
        """
        out = []
        for character in self.fold(word) if self.fold else word:
            key = self.letter_to_key.get(character)
            if key is not None:
                out.append(key)
            elif character.isalpha():
                return None  # a letter from another script; the user would switch layouts
            else:
                out.append(character)
        return tuple(out)

    def describe(self) -> str:
        return "  ".join("[" + g + "]" for row in self.groups_by_row for g in row)


# --- Hebrew variants ---------------------------------------------------------


def rows_without_final_forms(rows: list[str]) -> list[str]:
    """Hebrew's 27 glyphs reduced to 22 by taking the five final forms off the
    keyboard entirely. The decoder puts the right form back from position, which
    it can do because position is what determines it."""
    return ["".join(c for c in row if c not in FINAL_TO_ORDINARY) for row in rows]


def fold_final_forms(word: str) -> str:
    return "".join(FINAL_TO_ORDINARY.get(c, c) for c in word)


def clitic_forms(stem: str) -> list[str]:
    """The glued readings one stem serves, the way `HebrewMorphology.splits`
    reaches `לעבודה`, `בעבודה` and `מהעבודה` from a single entry for `עבודה`.

    One clitic, and `ה` after another, which covers `מהעבודה`. Deeper stacking is
    deliberately absent: `SuggestionEngine.score` charges half a tier per letter
    stripped precisely because two is a guess stacked on a guess.
    """
    out = [c + stem for c in HEBREW_CLITICS]
    out += [c + "ה" + stem for c in "בלמו"]
    return out


# --- normalising -------------------------------------------------------------

_EDGE = "\"'`.,!?;:()[]{}<>«»—–-…׳״‘’“”"


def normalise(word: str) -> str:
    """Lower case and NFC, matching `SeedLanguageModel.fold`."""
    return unicodedata.normalize("NFC", word).lower()


def word_core(word: str) -> str:
    """Trim punctuation from both ends, the way `SuggestionEngine.wordCore` does.

    Both ends rather than the trailing one: a leading bracket used to hide a word
    from every lookup but one, and `Hi Nitai,` reaching the engine as `Nitai,`
    is how the personal dictionary stopped protecting a name the instant a comma
    touched it.
    """
    return word.strip(_EDGE)
