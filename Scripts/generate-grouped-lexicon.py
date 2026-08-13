#!/usr/bin/env python3
"""Builds the two word lists `GroupedLexiconResource` loads for grouped keys.

    python3 Scripts/generate-grouped-lexicon.py [--count N]

Writes `Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources/GroupedLexicon-en.txt`
and `-he.txt`: plain UTF-8, **one word per line, descending frequency**, no
header and no counts. The line index *is* the rank.

Source: Leipzig Corpora Collection word lists (CC BY 4.0). Wikipedia 300K
sentence dumps, English 2016 and Hebrew 2021. Attribution is in
`GroupedLexicon-NOTICE.txt` next to the lists.

Caches the downloaded archives under `Bar/grouped/.cache/leipzig/` (gitignored).
"""

from __future__ import annotations

import argparse
import io
import pathlib
import sys
import tarfile
import urllib.request

RESOURCES = (
    pathlib.Path(__file__).resolve().parent.parent
    / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources"
)
CACHE = (
    pathlib.Path(__file__).resolve().parent.parent / "Bar/grouped/.cache/leipzig"
)

DEFAULT_COUNT = 50_000

# 300K-sentence Wikipedia dumps: large enough for 50k alphabetic types, small
# enough to fetch. CC BY 4.0, https://wortschatz.uni-leipzig.de/en/usage
CORPORA = {
    "en": "https://downloads.wortschatz-leipzig.de/corpora/eng_wikipedia_2016_300K.tar.gz",
    "he": "https://downloads.wortschatz-leipzig.de/corpora/heb_wikipedia_2021_300K.tar.gz",
}

ALPHABETS = {
    "en": set("abcdefghijklmnopqrstuvwxyz"),
    "he": {chr(c) for c in range(0x05D0, 0x05EA + 1)},
}
SINGLES_KEPT = {"en": {"a", "i"}, "he": ALPHABETS["he"]}
SENTINELS = {
    "en": ["the", "you", "thanks", "okay", "tomorrow", "meeting"],
    "he": ["שלום", "תודה", "אני", "בסדר", "מה", "לא", "כן"],
}

NOTICE = """Grouped key word lists
=======================

English: Leipzig Corpora Collection, eng_wikipedia_2016_300K
Hebrew:  Leipzig Corpora Collection, heb_wikipedia_2021_300K

Source: https://wortschatz.uni-leipzig.de/
Licence: Creative Commons Attribution 4.0 (CC BY 4.0)
         https://creativecommons.org/licenses/by/4.0/

These files are frequency-ranked word forms extracted from the corpora's
*_words.txt lists, filtered to letters this keyboard can type. They are not
the original Leipzig archives.
"""


def fetch(url: str) -> pathlib.Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / url.rsplit("/", 1)[-1]
    if dest.exists() and dest.stat().st_size > 1_000_000:
        print(f"  cached {dest.name} ({dest.stat().st_size / 1e6:.1f} MB)")
        return dest
    print(f"  downloading {url}")
    tmp = dest.with_suffix(dest.suffix + ".part")
    urllib.request.urlretrieve(url, tmp)
    tmp.replace(dest)
    print(f"  saved {dest.name} ({dest.stat().st_size / 1e6:.1f} MB)")
    return dest


def words_from_archive(archive: pathlib.Path) -> list[tuple[str, int]]:
    """(word, frequency) pairs, already descending, from *_words.txt."""
    with tarfile.open(archive, "r:gz") as tar:
        member = next(m for m in tar.getmembers() if m.name.endswith("-words.txt"))
        raw = tar.extractfile(member)
        assert raw is not None
        text = io.TextIOWrapper(raw, encoding="utf-8")
        out: list[tuple[str, int]] = []
        for line in text:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            word, freq = parts[1], int(parts[2])
            out.append((word, freq))
        return out


def build(lang: str, count: int, ranked: list[tuple[str, int]]) -> tuple[list[str], dict[str, int]]:
    alphabet = ALPHABETS[lang]
    singles = SINGLES_KEPT[lang]
    kept: list[str] = []
    seen: set[str] = set()
    dropped = {"off-script": 0, "single character": 0, "duplicate": 0}
    for token, _freq in ranked:
        word = token.lower() if lang == "en" else token
        if not word or not set(word) <= alphabet:
            dropped["off-script"] += 1
        elif len(word) == 1 and word not in singles:
            dropped["single character"] += 1
        elif word in seen:
            dropped["duplicate"] += 1
        else:
            seen.add(word)
            kept.append(word)
        if len(kept) == count:
            break
    return kept, dropped


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--count", type=int, default=DEFAULT_COUNT,
        help=f"words per language (default {DEFAULT_COUNT})",
    )
    args = parser.parse_args()

    RESOURCES.mkdir(parents=True, exist_ok=True)
    (RESOURCES / "GroupedLexicon-NOTICE.txt").write_text(NOTICE, encoding="utf-8")

    for lang, url in CORPORA.items():
        print(f"\n{lang}:")
        archive = fetch(url)
        ranked = words_from_archive(archive)
        words, dropped = build(lang, args.count, ranked)
        out = RESOURCES / f"GroupedLexicon-{lang}.txt"
        out.write_text("\n".join(words) + "\n", encoding="utf-8")

        missing = [s for s in SENTINELS[lang] if s not in words]
        if missing:
            sys.exit(f"{lang}: missing sentinels {missing} — the list is not what it claims")

        print(f"  {len(words)} words kept from {len(ranked)} corpus types")
        for rule, n in dropped.items():
            print(f"  dropped by {rule:<17} {n:>7}")
        print(f"  first 10: {' '.join(words[:10])}")
        print(f"  -> {out.name} ({out.stat().st_size / 1024:.0f} KB)")

    print("\nCC BY 4.0. Attribution in GroupedLexicon-NOTICE.txt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
