#!/usr/bin/env python3
"""Builds the two word lists `GroupedLexiconResource` loads for grouped keys.

    Bar/grouped/.venv/bin/python Scripts/generate-grouped-lexicon.py [--count N]

Writes `Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources/GroupedLexicon-en.txt`
and `-he.txt`: plain UTF-8, **one word per line, descending frequency**, no
header and no counts. The line index *is* the rank — `GroupedLexiconResource`
splits the file on newlines and hands the array straight to `GroupedDecoder`, so
the ordering is the entire contract and anything that reorders these files
changes what the keyboard decodes.

**These files are measurement and development only. They may not ship.**
`wordfreq`'s *code* is Apache 2.0, but the *data* it answers from is built out of
corpora with mixed and partly unstated licences — Wikipedia, OpenSubtitles,
SUBTLEX, Google Books, OSCAR and Twitter among them. Nothing here has been
licence-cleared for redistribution inside a binary. So both outputs are
gitignored, a fresh checkout has neither of them, and `GroupedLexiconResource`
falls back to `SeedLanguageModel` and reports `.seedOnly` rather than pretending
a list is present. Shipping grouped keys needs a licence settled first, or a
different source. Same rule, same reason as the measurement lexicons in
`Bar/grouped/README.md`; the feature they feed is described in
`.claude/docs/grouped-keys-design.md`.

**What this data is.** The top N tokens of English and Hebrew by corpus
frequency, out of wordfreq's `best` wordlist, filtered down to what a letter
plane can actually type (see `FILTERS` below). Order is descending frequency and
that is the only claim made: no frequency value is written, because the decoder
only ever needs to know that one candidate beats another.

**What this data is NOT.** Not a dictionary and not a spell-checker's word list.
wordfreq counts *tokens seen in text*, so the tail holds misspellings, foreign
words and proper nouns, none of it curated. It is not a model of what this
keyboard's users type either — it is web text in aggregate, from a snapshot the
wordfreq maintainer froze in 2021. Hebrew has no clitic handling here: `לעבודה`
and `עבודה` are two unrelated lines, where `Resources/LanguageModel.json`
deliberately stores the bare stem and lets `HebrewMorphology` do the joining.

Deterministic: wordfreq ships its counts as a frozen data file, so the same
version in gives the same lines out. Safe to re-run.
"""

import argparse
import pathlib
import sys

try:
    from importlib.metadata import version
    from wordfreq import top_n_list
except ImportError:
    sys.exit(
        "wordfreq is not importable. This script runs from the venv that\n"
        "Bar/grouped/make-lexicon.py already uses:\n"
        "    Bar/grouped/.venv/bin/python Scripts/generate-grouped-lexicon.py"
    )

RESOURCES = (
    pathlib.Path(__file__).resolve().parent.parent
    / "Packages/AIKeyboardCore/Sources/AIKeyboardCore/Resources"
)

DEFAULT_COUNT = 30_000
WORDLIST = "best"

# Only the letters each language's letter plane can produce. Everything else —
# digits, URL fragments, punctuation, and the other script's alphabet — is not
# reachable by any key sequence a grouped keyboard can emit, so a decoder that
# held those rows would only ever be carrying them.
#
# Hebrew is U+05D0-U+05EA exactly: the 22 letters plus the five final forms
# ‎ך ם ן ף ץ‎. Deliberately narrower than `Bar/grouped/make-lexicon.py`'s
# U+0590-U+05FF, which is wide on purpose so a word carrying niqqud or a geresh
# still reports as Hebrew. Here a pointed word is unreachable and must go.
ALPHABETS = {
    "en": set("abcdefghijklmnopqrstuvwxyz"),
    "he": {chr(c) for c in range(0x05D0, 0x05EA + 1)},
}

# One-letter tokens are overwhelmingly stray punctuation, initials and list
# markers. English keeps the two that are words; Hebrew keeps all of its
# letters, because single letters there are real clitics and prepositions —
# ‎ב‎ "in", ‎ל‎ "to", ‎ו‎ "and", ‎ש‎ "that" — that a Hebrew sentence is full of.
SINGLES_KEPT = {"en": {"a", "i"}, "he": ALPHABETS["he"]}

# How much of wordfreq's list to pull per word wanted. The filters throw away
# roughly a third of English, so asking for exactly N would write a short file;
# the pool grows below if even this is not enough.
OVERSAMPLE = 4


def build(lang: str, count: int) -> "tuple[list[str], dict[str, int], int]":
    """`count` words, descending frequency, with a tally of what each rule ate.

    Rules are applied in order and each drop is charged to the *first* rule that
    rejects the word, so the tallies sum with the kept count to the number of
    tokens read and can be reported as a breakdown rather than as overlapping
    sets. Reading stops at the `count`-th keeper, so the tallies describe the
    frequency band the file actually came out of and not the whole wordlist.
    """
    alphabet = ALPHABETS[lang]
    singles = SINGLES_KEPT[lang]

    requested = count * OVERSAMPLE
    while True:
        pool = top_n_list(lang, requested, wordlist=WORDLIST)
        kept: "list[str]" = []
        seen: "set[str]" = set()
        dropped = {"off-script": 0, "single character": 0, "duplicate": 0}

        read = 0
        for token in pool:
            read += 1
            word = token.lower()
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

        if len(kept) == count or len(pool) < requested:
            # Either we have what was asked for, or wordfreq has run out and this
            # is every word it holds. It never pads, so a short file here is the
            # honest answer rather than something to keep asking for.
            return kept, dropped, read
        requested *= 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--count", type=int, default=DEFAULT_COUNT, help=f"words per language (default {DEFAULT_COUNT})"
    )
    args = parser.parse_args()

    RESOURCES.mkdir(parents=True, exist_ok=True)
    print(f"wordfreq {version('wordfreq')}, wordlist={WORDLIST!r}\n")

    for lang in ALPHABETS:
        words, dropped, read = build(lang, args.count)
        out = RESOURCES / f"GroupedLexicon-{lang}.txt"
        out.write_text("\n".join(words) + "\n", encoding="utf-8")

        print(f"{lang}: {len(words)} words kept out of {read} tokens read")
        for rule, n in dropped.items():
            print(f"  dropped by {rule:<17} {n:>7}")
        print(f"  first 10: {' '.join(words[:10])}")
        print(f"  -> {out.name} ({out.stat().st_size / 1024:.0f} KB)\n")

    print("Both files are gitignored and licence-encumbered: measurement only.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
