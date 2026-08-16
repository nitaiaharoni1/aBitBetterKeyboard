"""The shipping emoji ranker, in Python, over the shipping catalogue.

This is a **port, not a design**. Every line below answers to
`Packages/AIKeyboardCore/Sources/AIKeyboardCore/EmojiSearch.swift` and
`EmojiCatalog.swift`, and where the Swift is odd this is odd in the same way —
the keyword rung really does measure the shortest name across *both* locales,
which is the bug the whole harness exists to make scoreable. Do not improve it
here. `swift-check.sh` compiles the real Swift and fails if these two disagree
on a single result, which is the only thing that makes a number from this file
a number about the keyboard.

Why a port at all: `EmojiSearch` is Foundation-only and so is `EmojiCatalog`,
but they live in a package that only builds against an iOS Simulator, and the
suite that exercises them takes minutes. A ranker cannot be tuned at that
price. This runs in under a second with no simulator and no Xcode.
"""

from __future__ import annotations

import json
import unicodedata
from functools import lru_cache
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent.parent
CATALOG = (
    REPO
    / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources/EmojiCatalog.json"
)

# Swift's `Int.max` on every platform this ships to. `Match.none` and the
# recents rank of an emoji that is not in recents are both spelled with it, and
# both are compared rather than special-cased, so the value has to be the same
# one.
INT_MAX = 2**63 - 1

# `Match.none`: rung `.max`, coverage 0, length `.max`. Kept as a plain tuple
# because Swift's `Match: Comparable` compares rung, then coverage, then length
# — which is exactly what tuple ordering does.
NONE = (INT_MAX, 0.0, INT_MAX)

# `EmojiSearch.recentBoost`.
RECENT_BOOST = 2


class Catalog:
    """`EmojiCatalog`, loaded the way `EmojiCatalog.load()` loads it.

    The blob is `name|name<TAB>keyword keyword`. The tab is what keeps names
    tellable from keywords, and the pipe is what keeps the two locales apart;
    getting either wrong changes which rung a query lands on rather than
    producing an error.
    """

    def __init__(self, path: Path = CATALOG):
        payload = json.loads(path.read_text(encoding="utf-8"))
        self.path = path
        self.all: list[str] = []
        self.names: dict[str, list[str]] = {}
        self.keywords: dict[str, str] = {}
        self.order: dict[str, int] = {}
        self.category: dict[str, str] = {}
        order = 0
        for category in payload["categories"]:
            for emoji in category["emoji"]:
                self.all.append(emoji)
                blob = payload["keywords"].get(emoji, "\t")
                halves = blob.split("\t", 1)
                # `split(separator: "|")` omits empty subsequences by default;
                # `split(separator: "\t", omittingEmptySubsequences: false)`
                # does not. Both spellings are load-bearing.
                self.names[emoji] = [n for n in halves[0].split("|") if n]
                self.keywords[emoji] = halves[1] if len(halves) > 1 else ""
                self.order[emoji] = order
                self.category[emoji] = category["id"]
                order += 1

    def beyond_the_length_rule(self) -> list[str]:
        """Catalogue strings `swift_count` would count wrongly.

        `swift_count` handles combining marks and nothing else, which is enough
        for this catalogue and is checked rather than assumed — see its own
        note. Anything astral, any ZWJ, any variation selector or regional
        indicator inside a *name or keyword* would need real grapheme
        segmentation. `selftest.py` fails on a non-empty answer.
        """
        offenders = []
        for emoji in self.all:
            for text in self.names[emoji] + [self.keywords[emoji]]:
                for char in text:
                    code = ord(char)
                    if (
                        code > 0xFFFF
                        or code == 0x200D
                        or 0xFE00 <= code <= 0xFE0F
                        or 0x1F1E6 <= code <= 0x1F1FF
                    ):
                        offenders.append(text)
                        break
        return offenders

    def combining_marks(self) -> list[str]:
        """Catalogue strings where a code-point count would be wrong.

        Not a problem — `swift_count` handles these — but worth being able to
        print, because `EmojiSearch`'s own doc comment says CLDR's Hebrew
        carries no niqqud and four strings in the shipped file do.
        """
        offenders = []
        for emoji in self.all:
            for text in self.names[emoji] + [self.keywords[emoji]]:
                if any(unicodedata.category(c) in ("Mn", "Me", "Mc") for c in text):
                    offenders.append(text)
        return offenders


_catalog: Catalog | None = None


def catalog() -> Catalog:
    global _catalog
    if _catalog is None:
        _catalog = Catalog()
    return _catalog


def normalise(query: str) -> str:
    """`EmojiSearch.normalise`: trimmed and lowercased, nothing else."""
    return query.strip().lower()


@lru_cache(maxsize=None)
def graphemes(text: str) -> tuple[str, ...]:
    """A Swift `String` as Swift sees it: a sequence of `Character`s.

    **Four strings in the shipped catalogue make this load-bearing, and the
    first version of this port got two answers wrong because it skipped it.**
    CLDR's Hebrew carries niqqud in four places — 🐏 is `אַיִל`, 🛷 is
    `מִזְחֶלֶת`, 👩‍🏫 is `מוֹרָה`, 🩺 has `מַסְכֵּת` among its keywords — and every
    one of Swift's string operations here works on grapheme clusters:

    - `"אַיִל".hasPrefix("א")` is **false** in Swift, because the first
      `Character` is `אַ`, alef *with* its patah. In Python, `str.startswith`
      compares code points and answers true. That one difference put 🐏 in the
      results for `א` on the Python side and not the Swift side, and shifted
      every rank below it.
    - `String.count` is 3 for `אַיִל`, where `len` is 5. `Match.length` is the
      tiebreak of last resort, so a length off by two is a different answer.
    - `==` is canonical equivalence, so NFC and NFD spellings of one word are
      one word. `unicodedata.normalize` per cluster is exactly that.

    Combining marks attach to the character before them, which is the whole
    rule. It is enough only because nothing in this catalogue's names or
    keywords is astral, ZWJ-joined, variation-selected or a regional indicator
    — `Catalog.beyond_the_length_rule` checks that and `selftest.py` enforces
    it, so this stays a small honest approximation rather than a silent one.
    """
    clusters: list[str] = []
    for char in text:
        if clusters and unicodedata.category(char) in ("Mn", "Me", "Mc"):
            clusters[-1] += char
        else:
            clusters.append(char)
    return tuple(unicodedata.normalize("NFC", c) for c in clusters)


def swift_count(text: str) -> int:
    """`String.count`."""
    return len(graphemes(text))


def swift_equal(a: str, b: str) -> bool:
    """Swift's `==` on `String`, which is canonical equivalence."""
    return graphemes(a) == graphemes(b)


def swift_has_prefix(text: str, needle: tuple[str, ...]) -> bool:
    """Swift's `hasPrefix`, over `Character`s. `needle` is already split."""
    return graphemes(text)[: len(needle)] == needle


def _coverage(needle_length: int, length: int) -> float:
    return -float(needle_length) / float(length) if length > 0 else 0.0


def _shortest(names: list[str]) -> int:
    return min((swift_count(n) for n in names), default=INT_MAX)


def score(needle: str, names: list[str], keywords: str) -> tuple[int, float, int]:
    """`EmojiSearch.score`. Smaller sorts first; `NONE` means no match.

    The four rungs, in the order the Swift asks them:

    0. the query *is* a name
    1. an exact keyword, or a whole word of a name
    2. the start of a word of a name
    3. the start of a keyword

    **Rung 1's keyword branch scores `length` as the shortest name across both
    locales**, which is why an English query can be decided by a Hebrew name.
    That is faithfully reproduced. It is the defect NIT-106 exists to measure,
    and a port that quietly fixed it would measure a keyboard nobody has.
    """
    keyword_words = [w for w in keywords.split(" ") if w]
    needle_clusters = graphemes(needle)
    needle_length = len(needle_clusters)
    best = NONE

    for name in names:
        if swift_equal(name, needle):
            return (0, -1.0, swift_count(name))

    if any(swift_equal(w, needle) for w in keyword_words):
        best = min(best, (1, -1.0, _shortest(names)))
    for name in names:
        if any(swift_equal(w, needle) for w in name.split(" ") if w):
            length = swift_count(name)
            best = min(best, (1, _coverage(needle_length, length), length))
    if best[0] <= 1:
        return best

    for name in names:
        for word in name.split(" "):
            if word and swift_has_prefix(word, needle_clusters):
                length = swift_count(name)
                best = min(best, (2, _coverage(needle_length, length), length))
    for word in keyword_words:
        if swift_has_prefix(word, needle_clusters):
            length = swift_count(word)
            best = min(best, (3, _coverage(needle_length, length), length))
    return best


def results(query: str, recent: list[str] | None = None, limit: int = 60) -> list[str]:
    """`EmojiSearch.results(for:recent:limit:)`, best first."""
    needle = normalise(query)
    if not needle:
        return []

    recent = recent or []
    recent_rank = {emoji: index for index, emoji in enumerate(recent)}

    cat = catalog()
    scored = []
    for emoji in cat.all:
        match = score(needle, cat.names[emoji], cat.keywords[emoji])
        if match == NONE:
            continue
        rank = recent_rank.get(emoji, INT_MAX)
        if rank != INT_MAX:
            match = (max(0, match[0] - RECENT_BOOST), match[1], match[2])
        scored.append((emoji, match, rank, cat.order[emoji]))

    # `EmojiSearch.results` sorts on rung, then recency, then the rest of the
    # match, then catalogue order. Rung is already the head of the match, so
    # flattening the two into one key is the same ordering and not a shortcut.
    scored.sort(key=lambda row: (row[1][0], row[2], row[1][1], row[1][2], row[3]))
    return [row[0] for row in scored[:limit]]


def explain(query: str, emoji: str, recent: list[str] | None = None) -> dict:
    """One emoji's score for one query, for reading a disagreement.

    A rank that moved says two rankers differ; this says where.
    """
    cat = catalog()
    needle = normalise(query)
    match = score(needle, cat.names[emoji], cat.keywords[emoji])
    boosted = match
    rank = (recent or []).index(emoji) if emoji in (recent or []) else INT_MAX
    if rank != INT_MAX and match != NONE:
        boosted = (max(0, match[0] - RECENT_BOOST), match[1], match[2])
    return {
        "emoji": emoji,
        "names": cat.names[emoji],
        "rung": None if match == NONE else match[0],
        "coverage": None if match == NONE else match[1],
        "length": None if match == NONE else match[2],
        "boostedRung": None if boosted == NONE else boosted[0],
        "recentRank": None if rank == INT_MAX else rank,
        "order": cat.order[emoji],
    }


if __name__ == "__main__":
    import sys

    for query in sys.argv[1:] or ["car", "heart", "לב"]:
        print(query, "->", " ".join(results(query)[:10]))
