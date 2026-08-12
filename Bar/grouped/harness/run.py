#!/usr/bin/env python3
"""Run the grouped-key sweep and write `results.json`.

    Bar/grouped/harness/run.sh

Needs no simulator, no Swift and no network — which is the point. `Bar/typing`
has to build for the iOS Simulator because `UITextChecker` is UIKit, and takes
minutes per run; a dial cannot be swept at that price.
"""

from __future__ import annotations

import json
import statistics
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from decode import Bigrams, Decoder, Lexicon  # noqa: E402
from grouping import (  # noqa: E402
    HEBREW_CLITICS,
    Layout,
    fold_final_forms,
    normalise,
    rows_without_final_forms,
    word_core,
)

DATA = HERE.parent / "data"
RESULTS = HERE.parent / "results.json"


def require_data(*names: str) -> None:
    """Fail with the command that fixes it, rather than a traceback.

    `data/lexicon-*.json` is gitignored — 11.7 MB of licence-encumbered wordfreq
    output that `make-lexicon.py` reproduces exactly — so a fresh checkout is
    *expected* to be missing it, and that must not read as a broken harness.
    Lives here rather than in each entry point so the three of them cannot drift.
    """
    missing = [name for name in names if not (DATA / name).exists()]
    if not missing:
        return
    sys.exit(
        "missing "
        + ", ".join(missing)
        + " in Bar/grouped/data/\n"
        + "  python3 Bar/grouped/make-rows.py\n"
        + "  Bar/grouped/.venv/bin/python Bar/grouped/make-lexicon.py\n"
        + "  python3 Bar/grouped/make-testtext.py"
    )


EVERYTHING = ("rows.json", "testtext.json", "lexicon-en.json", "lexicon-he.json")

# k=1 is the control, not a dial stop: with one letter per key every code is
# unique, so `commit` must equal exactly the words the lexicon knows. Anything
# else is a bug in the harness rather than a finding about the keyboard.
SWEEP = [1, 2, 3, 4, 5, 6, 7]

DIAL = {3: "L1", 4: "L2", 5: "L3"}


def tokenise(text: str) -> list[str]:
    out = []
    for raw in text.split():
        word = word_core(normalise(raw))
        if word:
            out.append(word)
    return out


def evaluate(entries, layout, decoder, bigrams=None) -> dict:
    typed = unmappable = oov = commit = offered = 0
    collisions: list[int] = []
    taps = 0

    for index, entry in enumerate(entries):
        if bigrams:
            bigrams.hold_out(index)
        words = entry["tokens"]
        previous = None
        for word in words:
            typed += 1
            code = layout.code(word)
            if code is None:
                unmappable += 1
                previous = word
                continue
            if word not in decoder.lexicon.freq:
                oov += 1
                taps += 4  # not reachable through the bar at all; charge a repair
                previous = word
                continue
            ranked = decoder.ranked(code, previous, bigrams)
            collisions.append(len(ranked))
            position = ranked.index(word)
            if position == 0:
                commit += 1
                taps += 1
            elif position < 3:
                offered += 1
                taps += 2
            else:
                taps += 4
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
        "offeredOnly": offered,
        "offered": commit + offered,
        # Of every word this layout is responsible for. OOV counts as a failure,
        # because a word the lexicon has never heard of is not going to appear.
        "commitRate": commit / in_scope if in_scope else 0.0,
        "offeredRate": (commit + offered) / in_scope if in_scope else 0.0,
        "oovRate": oov / in_scope if in_scope else 0.0,
        # Of the words the lexicon knows. Separates "the ranker is wrong" from
        # "the candidate never existed", the same split `Bar/typing` keeps.
        "rankerRate": commit / known if known else 0.0,
        "meanCollision": statistics.mean(collisions) if collisions else 0.0,
        "medianCollision": statistics.median(collisions) if collisions else 0.0,
        "maxCollision": max(collisions) if collisions else 0,
        "tapsPerWord": taps / in_scope if in_scope else 0.0,
    }


def condition(name, language, rows, k, lexicon, entries, bigrams, avoid=None, fold=None):
    layout = Layout(rows, k, avoid=avoid, fold=fold)
    decoder = Decoder(lexicon, layout)
    scores = evaluate(entries, layout, decoder, bigrams)
    scores_nc = evaluate(entries, layout, decoder, None)
    return {
        "condition": name,
        "language": language,
        "k": k,
        "dial": DIAL.get(k),
        "keys": layout.keys,
        "groups": layout.describe(),
        "infeasible": layout.infeasible,
        "cliticCollisions": layout.collisions(HEBREW_CLITICS) if language == "he" else [],
        "lexiconSize": len(lexicon),
        "lexiconUntypable": decoder.untypable,
        "withContext": scores,
        "noContext": scores_nc,
    }


def main() -> None:
    started = time.time()
    require_data(*EVERYTHING)
    rows_payload = json.loads((DATA / "rows.json").read_text(encoding="utf-8"))
    text_payload = json.loads((DATA / "testtext.json").read_text(encoding="utf-8"))

    entries_by_language: dict[str, list[dict]] = {"en": [], "he": []}
    for entry in text_payload["entries"]:
        entry = dict(entry)
        entry["tokens"] = tokenise(entry["text"])
        if entry["tokens"]:
            entries_by_language[entry["language"]].append(entry)

    results = []
    for language in ("en", "he"):
        rows = rows_payload["languages"][language]["rows"]
        entries = entries_by_language[language]
        if not entries:
            print(f"!! no {language} test entries; skipping", file=sys.stderr)
            continue
        lexicon = Lexicon.load(DATA / f"lexicon-{language}.json")
        bigrams = Bigrams([e["tokens"] for e in entries])
        print(
            f"{language}: {len(entries)} entries, "
            f"{sum(len(e['tokens']) for e in entries)} words, "
            f"lexicon {len(lexicon)}",
            file=sys.stderr,
        )

        for k in SWEEP:
            results.append(
                condition("adjacent", language, rows, k, lexicon, entries, bigrams)
            )

        if language == "he":
            expanded = lexicon.with_clitic_forms()
            folded_rows = rows_without_final_forms(rows)
            for k in SWEEP:
                results.append(
                    condition(
                        "clitic-separated", language, rows, k, lexicon, entries,
                        bigrams, avoid=HEBREW_CLITICS,
                    )
                )
                results.append(
                    condition(
                        "no-final-forms", language, folded_rows, k, lexicon, entries,
                        bigrams, fold=fold_final_forms,
                    )
                )
                results.append(
                    condition(
                        "clitic-lexicon", language, rows, k, expanded, entries, bigrams
                    )
                )
                results.append(
                    condition(
                        "clitic-separated+lexicon", language, rows, k, expanded,
                        entries, bigrams, avoid=HEBREW_CLITICS,
                    )
                )

    payload = {
        "generated_by": "Bar/grouped/harness/run.py",
        "rows": rows_payload["source"],
        "testText": {
            "generator": text_payload.get("generator"),
            "counts": text_payload.get("counts"),
        },
        "warning": (
            "Measures the DECODER, assuming the thumb always hits the intended "
            "group. Real thumbs miss. So every number here is an upper bound on "
            "decode quality and a lower bound on end-to-end benefit, because it "
            "never counts the mistypes that bigger keys prevent."
        ),
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
        print(f"\n{'=' * 96}\n{language.upper()}\n{'=' * 96}")
        conditions = []
        for row in rows:
            if row["condition"] not in conditions:
                conditions.append(row["condition"])
        for name in conditions:
            print(f"\n-- {name}")
            print(
                f"{'k':>2} {'dial':>4} {'keys':>5} {'commit':>7} {'offered':>8} "
                f"{'ranker':>7} {'oov':>6} {'coll':>6} {'taps':>5}   groups"
            )
            for row in [r for r in rows if r["condition"] == name]:
                s = row["withContext"]
                flag = " INFEASIBLE" if row["infeasible"] else ""
                print(
                    f"{row['k']:>2} {row['dial'] or '':>4} {row['keys']:>5} "
                    f"{s['commitRate']:>6.1%} {s['offeredRate']:>7.1%} "
                    f"{s['rankerRate']:>6.1%} {s['oovRate']:>5.1%} "
                    f"{s['meanCollision']:>6.1f} {s['tapsPerWord']:>5.2f}   "
                    f"{row['groups']}{flag}"
                )


if __name__ == "__main__":
    main()
