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

    **A band asks it once, for both its rows together**, which is what keeps the
    key count at every dial stop exactly the one this harness measured before
    banding existed: English's 19 banded letters at three per key give six keys
    where the two rows separately gave three and three.
    """
    return max(1, int(row_length / k + 0.5))


def split(items: list, n: int) -> list[list]:
    """Contiguous groups of roughly equal size, **leading groups taking the
    extra** — so ten items in three groups is 4|3|3, not 3|3|4."""
    n = max(1, n)
    base, extra = divmod(len(items), n)
    out, at = [], 0
    for index in range(n):
        size = base + (1 if index < extra else 0)
        out.append(items[at : at + size])
        at += size
    return out


def split_avoiding(items: list, n: int, weight) -> list[list] | None:
    """Same group count as `split`, but no group may hold two items that
    `weight` scores. Boundaries move; adjacency and order are preserved.

    Returns `None` when no such split exists at that key count, which is itself
    a result: it means separating those letters costs an extra key.

    Exact rather than greedy — an exhaustive walk over contiguous partitions,
    which is free on rows of ten items and avoids a greedy rule quietly
    producing a lopsided row and calling it the cost of the constraint. Ties
    break toward the most even split, measured as squared deviation from the
    ideal size.

    `weight` is a count rather than a flag because a *column* of a band can carry
    two of the letters being kept apart, in which case nothing can separate them
    and this correctly reports that.
    """
    n = max(1, n)
    ideal = len(items) / n
    best: tuple[float, list[list]] | None = None

    def walk(at: int, left: int, parts: list[list], cost: float) -> None:
        nonlocal best
        if best is not None and cost >= best[0]:
            return
        if left == 0:
            if at == len(items):
                best = (cost, [list(p) for p in parts])
            return
        # Leave at least one item for each remaining part.
        for size in range(1, len(items) - at - (left - 1) + 1):
            piece = items[at : at + size]
            if sum(weight(item) for item in piece) > 1:
                continue
            parts.append(piece)
            walk(at + size, left - 1, parts, cost + (size - ideal) ** 2)
            parts.pop()

    walk(0, n, [], 0.0)
    return best[1] if best else None


def split_row(row: str, k: int) -> list[str]:
    """One row's letters in contiguous groups of roughly k."""
    return ["".join(part) for part in split(list(row), key_count(len(row), k))]


def split_row_avoiding(row: str, k: int, avoid: set[str]) -> list[str] | None:
    """The same key count, with no group holding two letters of `avoid`."""
    parts = split_avoiding(
        list(row), key_count(len(row), k), lambda c: 1 if c in avoid else 0
    )
    return None if parts is None else ["".join(part) for part in parts]


def absorb_singletons(parts: list, letters_of, merge, avoid: set[str]) -> list:
    """Fold any one-letter group into a neighbour.

    English `p` and Hebrew `ף` sit on leftover columns with nothing above or
    below them, and the split otherwise leaves them on a key of their own.
    Two leftovers next to each other join first; otherwise the letter joins
    the neighbour that does not put two Hebrew prefixes on one key.
    """
    parts = [list(part) for part in parts]
    while True:
        singles = [i for i, part in enumerate(parts) if len(letters_of(part)) == 1]
        if not singles or len(parts) == 1:
            return parts
        i = singles[0]
        neighbors = [j for j in (i - 1, i + 1) if 0 <= j < len(parts)]

        def collides(other: int) -> bool:
            merged = letters_of(parts[i]) + letters_of(parts[other])
            return sum(1 for c in merged if c in avoid) > 1

        safe_singletons = [
            j
            for j in neighbors
            if len(letters_of(parts[j])) == 1 and not collides(j)
        ]
        if safe_singletons:
            target = safe_singletons[0]
        else:
            safe = [j for j in neighbors if not collides(j)]
            target = (safe or neighbors)[0]
        lo, hi = (target, i) if target < i else (i, target)
        parts[lo] = merge(parts[lo], parts[hi])
        del parts[hi]


def band(top: str, bottom: str, k: int, avoid: set[str]) -> tuple[list[str], bool]:
    """Two rows merged into one row of double-height keys.

    A key is a **column slice** of the two rows: `qw` over `as` is one key,
    because those four letters are what a thumb aiming at that patch of glass can
    hit. The shorter row is left-aligned under the longer one, which keeps
    today's pairs — `qw` over `as`, `op` over `l`.

    Returns the groups (letters in reading order, top row first) and whether the
    `avoid` constraint had to be given up.
    """
    width = max(len(top), len(bottom))
    columns = [
        (top[i] if i < len(top) else "", bottom[i] if i < len(bottom) else "")
        for i in range(width)
    ]
    # Never more keys than columns: at two letters per key a band of 19 letters
    # wants ten keys and has exactly ten columns to put them in.
    n = min(width, key_count(len(top) + len(bottom), k))

    parts = None
    infeasible = False
    if avoid:
        parts = split_avoiding(
            columns, n, lambda col: sum(1 for c in col if c and c in avoid)
        )
        infeasible = parts is None
    if parts is None:
        parts = split(columns, n)
    parts = absorb_singletons(
        parts,
        letters_of=lambda part: [c for col in part for c in col if c],
        merge=lambda left, right: left + right,
        avoid=avoid,
    )
    groups = [
        "".join(c for c, _ in part) + "".join(c for _, c in part) for part in parts
    ]
    return groups, infeasible


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

        # **The top two rows band and the last one does not**, because the last
        # one is where shift and delete stand on the keyboard. `groups_by_row` is
        # therefore rows *as drawn*, which is two of them and not three.
        drawn: list[str] = []
        if len(rows) >= 3 and k > 1:
            groups, infeasible = band(rows[0], rows[1], k, avoid or set())
            self.groups_by_row.append(groups)
            self.infeasible = self.infeasible or infeasible
            drawn = rows[2:]
        else:
            drawn = rows

        for row in drawn:
            if avoid:
                parts = split_row_avoiding(row, k, avoid)
                if parts is None:
                    self.infeasible = True
                    parts = split_row(row, k)
            else:
                parts = split_row(row, k)
            letter_parts = [list(part) for part in parts]
            # k=1 is one letter per key on purpose. Absorbing those would glue
            # the ungrouped control into a handful of keys and score a keyboard
            # nobody ships.
            if k > 1:
                letter_parts = absorb_singletons(
                    letter_parts,
                    letters_of=lambda part: part,
                    merge=lambda left, right: left + right,
                    avoid=avoid or set(),
                )
            self.groups_by_row.append(["".join(part) for part in letter_parts])

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


def letter_at(x: float, y: float, lines: list[list[str]], dead_band: float = 0.18) -> str | None:
    """Which letter a tap on this key meant, or None when it is too close to
    the middle to call. x and y are 0..1 in the key, origin top-left.

    Matches `GroupedKeys.letter(atX:y:in:)`. Empty lines occupy their slice and
    yield nothing, so a tap on the blank top of `ךף` is not a letter.
    """
    if not lines:
        return None
    x = min(1.0, max(0.0, x))
    y = min(1.0, max(0.0, y))
    row_count = len(lines)
    row_frac = y * row_count
    row = min(row_count - 1, int(row_frac))
    line = lines[row]
    if not line:
        return None
    col_count = len(line)
    col_frac = x * col_count
    col = min(col_count - 1, int(col_frac))
    fy = row_frac - row
    fx = col_frac - col
    if row_count > 1:
        if row > 0 and fy < dead_band:
            return None
        if row < row_count - 1 and fy > 1 - dead_band:
            return None
    if col_count > 1:
        if col > 0 and fx < dead_band:
            return None
        if col < col_count - 1 and fx > 1 - dead_band:
            return None
    return line[col]
