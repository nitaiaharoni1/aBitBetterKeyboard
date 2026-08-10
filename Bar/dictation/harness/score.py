#!/usr/bin/env python3
"""Scores cloud_outputs.json against ground-truth.json.

Three numbers, and they are not interchangeable:

  WER              word error rate on the normalised form `../README.md`
                   specifies — case-folded, punctuation stripped, maqaf and
                   hyphen folded to a space. `ה-roadmap` against `ה roadmap` is
                   a formatting difference, not a recognition error, and this
                   scorer refuses to count it as one.
  entity accuracy  named entities recovered, counted separately because for
                   this product getting `מובילאיי` and `Figma` right matters
                   more than a tenth of a point of WER. A transcript that says
                   "מובילאי" instead is wrong in the way a user notices.
  script fidelity  of the English words inside a Hebrew sentence, how many came
                   back in Latin letters. This is the number the product lives
                   or dies on and no general STT benchmark reports it: an engine
                   that writes `סינק` for `sync` has a fine WER against a
                   transliterating reference and is useless here.

The traps are scored apart from everything else and are pass/fail: a clip with
no words in it must come back with `speech: no` and empty text. A number from
the 36 real clips means nothing if the engine also transcribes silence.

Usage: score.py [cloud_outputs.json]
"""

import json
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
BAR = HERE.parent

HEBREW = range(0x0590, 0x05FF)


def normalise(text):
    """Case-folded, punctuation-stripped, maqaf-and-hyphen split words."""
    folded = []
    for character in text:
        if character in "-־–—/":
            folded.append(" ")
        elif unicodedata.category(character).startswith("P"):
            continue
        else:
            folded.append(character)
    return "".join(folded).casefold().split()


def wer(reference, hypothesis):
    """Levenshtein over words, divided by the reference length."""
    if not reference:
        return 0.0 if not hypothesis else 1.0
    previous = list(range(len(hypothesis) + 1))
    for index, word in enumerate(reference, start=1):
        current = [index]
        for position, other in enumerate(hypothesis, start=1):
            current.append(
                min(
                    previous[position] + 1,
                    current[position - 1] + 1,
                    previous[position - 1] + (word != other),
                )
            )
        previous = current
    return previous[-1] / len(reference)


def is_hebrew(word):
    return any(ord(character) in HEBREW for character in word)


def latin_words(text):
    return {word for word in normalise(text) if word.isascii() and word.isalpha()}


def main():
    truth = json.loads((BAR / "ground-truth.json").read_text())
    outputs = json.loads((BAR / (sys.argv[1] if len(sys.argv) > 1 else "cloud_outputs.json")).read_text())
    by_id = {row["id"]: row for row in outputs}
    clips = {clip["id"]: clip for clip in truth["clips"]}

    groups = {"he": [], "en": [], "he-en": []}
    entities_found = entities_total = 0
    latin_kept = latin_total = 0
    rows = []

    for clip_id, clip in clips.items():
        row = by_id.get(clip_id)
        if row is None:
            continue
        reference = normalise(clip["transcript"])
        hypothesis = normalise(row["text"])
        score = wer(reference, hypothesis)
        groups[clip["language_mix"]].append(score)

        for entity in clip["named_entities"]:
            entities_total += 1
            if set(normalise(entity)) <= set(hypothesis):
                entities_found += 1

        # Only the code-switched clips can answer the script question: they are
        # the ones with English words inside a Hebrew sentence to lose.
        if clip["language_mix"] == "he-en":
            for word in latin_words(clip["transcript"]):
                latin_total += 1
                if word in set(hypothesis):
                    latin_kept += 1

        rows.append((clip_id, clip["language_mix"], score, row["text"], clip["transcript"]))

    print(f"{'clip':<8} {'mix':<6} {'WER':>6}  transcript")
    for clip_id, mix, score, got, want in sorted(rows):
        flag = " " if score == 0 else ("~" if score <= 0.25 else "!")
        print(f"{clip_id:<8} {mix:<6} {score:>6.1%} {flag} {got}")
        if score:
            print(f"{'':<8} {'':<6} {'':>6}   want: {want}")

    print()
    for name, scores in groups.items():
        if scores:
            perfect = sum(1 for score in scores if score == 0)
            print(f"{name:<6} n={len(scores):<3} WER {sum(scores)/len(scores):>6.1%}   exact {perfect}/{len(scores)}")
    every = [score for scores in groups.values() for score in scores]
    if every:
        print(f"{'all':<6} n={len(every):<3} WER {sum(every)/len(every):>6.1%}   exact {sum(1 for s in every if s == 0)}/{len(every)}")
    print()
    if entities_total:
        print(f"named entities  {entities_found}/{entities_total}")
    if latin_total:
        print(f"English kept in Latin script (he-en clips)  {latin_kept}/{latin_total}")

    print()
    for trap in ("trap-silence", "trap-noise", "trap-tone"):
        row = by_id.get(trap)
        if row is None:
            continue
        clean = row["speech"] == "no" and not row["text"].strip()
        print(f"{trap:<14} {'PASS' if clean else 'FAIL'}  speech={row['speech']} text={row['text']!r}")


if __name__ == "__main__":
    main()
