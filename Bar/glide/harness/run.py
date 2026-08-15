#!/usr/bin/env python3
"""The glide-typing spike (NIT-17): can the grouped-keys decoder be reused to
rank a swiped word?

    Bar/glide/harness/run.sh

No simulator, no Swift, and no real finger — every path swept here is
synthesised; see `path.py`'s module docstring and `Bar/glide/README.md`
before quoting anything out of `results.json`. This is a SPIKE answering
whether the idea is worth building, not a feature: nothing here ships.

Reuses `Bar/grouped/harness/decode.py`'s `Decoder`, `Lexicon` and `Bigrams`
unmodified — only `GlideLayout.code` (`keyboard.py`) and the path generator
(`path.py`) are new. It also reuses `Bar/grouped/data/{rows,testtext,
lexicon-en,lexicon-he}.json` rather than freezing a second copy of the same
inputs.
"""

from __future__ import annotations

import json
import random
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
GROUPED_HARNESS = HERE.parent.parent / "grouped" / "harness"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(GROUPED_HARNESS))

from decode import Bigrams, Decoder, Lexicon  # noqa: E402 — Bar/grouped/harness, reused unmodified
import run as grouped_run  # noqa: E402 — require_data() and tokenise(), reused rather than copied

from keyboard import GlideLayout  # noqa: E402
from path import word_to_glide_code  # noqa: E402

DATA = GROUPED_HARNESS.parent / "data"
RESULTS = HERE.parent / "results.json"

# Gaussian jitter per sample, in key-width units — the same scale
# `Bar/grouped/harness/miss.py` uses for tap noise, so the two are directly
# comparable. See `path.curved_path` for what each stop is meant to model.
SIGMAS = (0.15, 0.25, 0.35)
# How much a waypoint rounds toward a straight line between its neighbours
# instead of being hit exactly; 0 is a careful, deliberate swipe, 0.5 a fast
# one that cuts corners.
CORNER_CUTS = (0.0, 0.5)
SAMPLES_PER_SEGMENT = 6
# Fixed, not swept in the main grid: a small one-shot check across 2-60
# degrees (in Bar/glide/README.md) showed accuracy falling off monotonically
# as the threshold rises at every sigma tried, with no interior optimum, so a
# low value dominates everywhere in the range that matters here. 5 degrees is
# comfortably above the near-zero angle a straight segment's own interior
# picks up from per-waypoint noise, and comfortably below a genuine turn.
ANGLE_THRESHOLD_DEG = 5
# Five seeds per setting, per AGENTS.md: one run is not evidence. The spread
# across these five is reported alongside every mean in the README.
SEEDS = (20260815, 20260816, 20260817, 20260818, 20260819)


def rank_words(words, lexicon, previous, bigrams):
    """The same tie-break `Bar/grouped/harness/decode.Decoder.ranked` applies
    — frequency order, promoted by a known bigram follower — but over an
    arbitrary candidate list rather than only `self.index[code]`. Needed so
    the fuzzy rescue below can be ranked the same way as an exact match
    without editing that frozen, shared harness file: `Bar/grouped/README.md`
    is explicit that its corpora and code are not to be touched, since doing
    so would invalidate every historical comparison recorded against it.
    """
    if not bigrams or previous is None or len(words) < 2:
        return words
    following = bigrams.following(previous)
    if not following:
        return words
    return sorted(words, key=lambda w: (-following.get(w, 0), -lexicon.freq[w], w))


def fuzzy_candidates(decoder, code, alphabet):
    """Exact match if `Decoder`'s own index already has it. Otherwise every
    lexicon word one edit away in the same code space — one key deleted,
    substituted, or inserted — merged and ranked by frequency.

    This is the measured answer to "what would the next cheapest step buy":
    `Decoder.index` itself is untouched, only the query widens, which is why
    it lives here rather than as a change to `decode.py`.
    """
    exact = decoder.candidates(code)
    if exact:
        return exact
    seen: dict[str, float] = {}
    variants = set()
    for i in range(len(code)):
        variants.add(code[:i] + code[i + 1 :])
    for i in range(len(code)):
        for letter in alphabet:
            if letter != code[i]:
                variants.add(code[:i] + (letter,) + code[i + 1 :])
    for i in range(len(code) + 1):
        for letter in alphabet:
            variants.add(code[:i] + (letter,) + code[i:])
    for variant in variants:
        for word in decoder.candidates(variant):
            seen.setdefault(word, decoder.lexicon.freq[word])
    return sorted(seen, key=lambda w: -seen[w])


def evaluate(
    entries, layout, decoder, centers, alphabet, *, sigma, corner_cut, seed, bigrams=None,
) -> dict:
    rng = random.Random(seed)
    typed = unmappable = oov = 0
    commit = offered = commit_fuzzy = offered_fuzzy = 0
    collisions: list[int] = []
    for index, entry in enumerate(entries):
        if bigrams:
            bigrams.hold_out(index)
        previous = None
        for word in entry["tokens"]:
            typed += 1
            true_code = layout.code(word)  # is this word swipeable at all
            if true_code is None:
                unmappable += 1
                previous = word
                continue
            if word not in decoder.lexicon.freq:
                oov += 1
                previous = word
                continue
            glide_code = word_to_glide_code(
                word, centers,
                samples_per_segment=SAMPLES_PER_SEGMENT, corner_cut=corner_cut,
                sigma=sigma, angle_threshold_deg=ANGLE_THRESHOLD_DEG, rng=rng,
            )
            if glide_code:
                ranked = decoder.ranked(glide_code, previous, bigrams)
                fuzzy = rank_words(
                    fuzzy_candidates(decoder, glide_code, alphabet),
                    decoder.lexicon, previous, bigrams,
                )
            else:
                ranked, fuzzy = [], []
            collisions.append(len(ranked))
            position = ranked.index(word) if word in ranked else None
            fuzzy_position = fuzzy.index(word) if word in fuzzy else None
            if position == 0:
                commit += 1
            elif position is not None and position < 3:
                offered += 1
            if fuzzy_position == 0:
                commit_fuzzy += 1
            elif fuzzy_position is not None and fuzzy_position < 3:
                offered_fuzzy += 1
            previous = word

    in_scope = typed - unmappable
    known = in_scope - oov
    return {
        "typed": typed,
        "unmappable": unmappable,
        "inScope": in_scope,
        "oov": oov,
        "known": known,
        "commit": commit,
        "offered": commit + offered,
        "commitRate": commit / in_scope if in_scope else 0.0,
        "offeredRate": (commit + offered) / in_scope if in_scope else 0.0,
        "rankerRate": commit / known if known else 0.0,
        "commitFuzzyRate": commit_fuzzy / in_scope if in_scope else 0.0,
        "offeredFuzzyRate": (commit_fuzzy + offered_fuzzy) / in_scope if in_scope else 0.0,
        "meanCollision": statistics.mean(collisions) if collisions else 0.0,
    }


def condition(language, rows, lexicon, entries, bigrams, *, sigma, corner_cut, seed) -> dict:
    layout = GlideLayout(rows)
    decoder = Decoder(lexicon, layout)
    scores = evaluate(
        entries, layout, decoder, layout.centers, set(layout.centers),
        sigma=sigma, corner_cut=corner_cut, seed=seed, bigrams=bigrams,
    )
    return {
        "language": language,
        "sigma": sigma,
        "cornerCut": corner_cut,
        "seed": seed,
        "keys": len(layout.centers),
        "lexiconSize": len(lexicon),
        "lexiconUntypable": decoder.untypable,
        "scores": scores,
    }


def collapsed_collisions(lexicon: Lexicon, layout: GlideLayout) -> dict:
    """How often two lexicon words share one collapsed code, e.g. `later` /
    `latter` — the ambiguity double letters cost independent of any noise,
    reported once per language rather than per sigma since it does not vary
    with the generator."""
    by_code: dict[tuple, list[str]] = {}
    for word in lexicon.freq:
        code = layout.code(word)
        if code is None:
            continue
        by_code.setdefault(code, []).append(word)
    doubled_pairs = [words for words in by_code.values() if len(words) > 1]
    return {
        "codesWithCollision": len(doubled_pairs),
        "wordsInvolved": sum(len(words) for words in doubled_pairs),
        "examples": sorted(
            (sorted(words) for words in doubled_pairs),
            key=lambda words: -max(lexicon.freq[w] for w in words),
        )[:10],
    }


def main() -> None:
    started = time.time()
    grouped_run.require_data("rows.json", "testtext.json", "lexicon-en.json", "lexicon-he.json")
    rows_payload = json.loads((DATA / "rows.json").read_text(encoding="utf-8"))
    text_payload = json.loads((DATA / "testtext.json").read_text(encoding="utf-8"))

    entries_by_language: dict[str, list[dict]] = {"en": [], "he": []}
    for entry in text_payload["entries"]:
        entry = dict(entry)
        entry["tokens"] = grouped_run.tokenise(entry["text"])
        if entry["tokens"]:
            entries_by_language[entry["language"]].append(entry)

    results = []
    collision_reports = {}
    for language in ("en", "he"):
        rows = rows_payload["languages"][language]["rows"]
        entries = entries_by_language[language]
        if not entries:
            print(f"!! no {language} test entries; skipping", file=sys.stderr)
            continue
        lexicon = Lexicon.load(DATA / f"lexicon-{language}.json")
        bigrams = Bigrams([e["tokens"] for e in entries])
        collision_reports[language] = collapsed_collisions(lexicon, GlideLayout(rows))
        print(
            f"{language}: {len(entries)} entries, "
            f"{sum(len(e['tokens']) for e in entries)} words, lexicon {len(lexicon)}, "
            f"{collision_reports[language]['codesWithCollision']} collapsed-code collisions "
            f"({collision_reports[language]['wordsInvolved']} words)",
            file=sys.stderr,
        )
        for corner_cut in CORNER_CUTS:
            for sigma in SIGMAS:
                for seed in SEEDS:
                    row = condition(
                        language, rows, lexicon, entries, bigrams,
                        sigma=sigma, corner_cut=corner_cut, seed=seed,
                    )
                    results.append(row)
                print(
                    f"  corner_cut={corner_cut} sigma={sigma}  commit "
                    + ", ".join(
                        f"{r['scores']['commitRate']:.1%}"
                        for r in results[-len(SEEDS):]
                    ),
                    file=sys.stderr,
                )

    payload = {
        "generated_by": "Bar/glide/harness/run.py",
        "synthetic": True,
        "warning": (
            "SYNTHETIC. No real finger produced any path in this file. Every "
            "swipe is generated from a stated, parameterised model of a hand — "
            "see path.py and Bar/glide/README.md. Read every number here as a "
            "sensitivity sweep over that model's assumptions, never as a "
            "measurement of real users."
        ),
        "rows": rows_payload["source"],
        "testText": {
            "generator": text_payload.get("generator"),
            "counts": text_payload.get("counts"),
        },
        "generator": {
            "samplesPerSegment": SAMPLES_PER_SEGMENT,
            "angleThresholdDeg": ANGLE_THRESHOLD_DEG,
            "sigmas": list(SIGMAS),
            "cornerCuts": list(CORNER_CUTS),
            "seeds": list(SEEDS),
        },
        "collapsedCodeCollisions": collision_reports,
        "seconds": round(time.time() - started, 1),
        "results": results,
    }
    RESULTS.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\nwrote {RESULTS}  ({payload['seconds']}s)", file=sys.stderr)
    report(results)


def report(results: list[dict]) -> None:
    for language in ("en", "he"):
        rows = [r for r in results if r["language"] == language]
        if not rows:
            continue
        print(f"\n{'=' * 100}\n{language.upper()} (SYNTHETIC)\n{'=' * 100}")
        print(
            f"{'corner_cut':>10} {'sigma':>6} {'mean commit':>12} {'spread':>9} "
            f"{'mean offered':>13} {'+fuzzy commit':>14}"
        )
        for corner_cut in CORNER_CUTS:
            for sigma in SIGMAS:
                cell = [r for r in rows if r["cornerCut"] == corner_cut and r["sigma"] == sigma]
                commits = [r["scores"]["commitRate"] for r in cell]
                offers = [r["scores"]["offeredRate"] for r in cell]
                fuzzy = [r["scores"]["commitFuzzyRate"] for r in cell]
                spread = max(commits) - min(commits) if len(commits) > 1 else 0.0
                print(
                    f"{corner_cut:>10.2f} {sigma:>6.2f} {statistics.mean(commits):>11.1%} "
                    f"{spread:>8.1%} {statistics.mean(offers):>12.1%} {statistics.mean(fuzzy):>13.1%}"
                )


if __name__ == "__main__":
    main()
