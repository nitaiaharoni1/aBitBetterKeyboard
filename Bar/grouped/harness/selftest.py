#!/usr/bin/env python3
"""Assertions that reject a broken grouping, run before every sweep.

Each one is written to fail on a *specific* wrong implementation rather than to
be true of anything plausible — the rule `.claude/rules` states as "work out what
the broken version returns and check the assertion rejects it". The rounding and
the leading-extra rule in particular each have an obvious wrong twin that
produces a different keyboard.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from grouping import (  # noqa: E402
    FINAL_TO_ORDINARY,
    HEBREW_CLITICS,
    Layout,
    clitic_forms,
    fold_final_forms,
    key_count,
    rows_without_final_forms,
    split_row,
    split_row_avoiding,
    word_core,
)

FAILURES: list[str] = []


def check(label: str, got, want) -> None:
    if got != want:
        FAILURES.append(f"{label}\n     got  {got}\n     want {want}")


def main() -> None:
    import run  # noqa: E402  — owns the one list of required data files

    run.require_data("rows.json")
    rows = json.loads((HERE.parent / "data" / "rows.json").read_text(encoding="utf-8"))
    en = rows["languages"]["en"]["rows"]
    he = rows["languages"]["he"]["rows"]

    # --- the rounding rule ---------------------------------------------------
    # Banker's rounding sends 10/4 to 2 and half-up sends it to 3. A row of ten
    # letters becoming two keys instead of three is a different keyboard.
    check("key_count(10, 4) must round half-up", key_count(10, 4), 3)
    check("key_count(9, 4)", key_count(9, 4), 2)
    check("key_count(7, 5)", key_count(7, 5), 1)
    check("key_count never returns 0", key_count(2, 9), 1)

    # --- the leading-extra rule ----------------------------------------------
    # Trailing-extra gives ['qwe','rty','uiop'], which is the same key count and
    # a different layout, so a key-count assertion alone cannot see it.
    check("split leading-extra", split_row("qwertyuiop", 3), ["qwer", "tyu", "iop"])
    check("split exact", split_row("asdfghjkl", 3), ["asd", "fgh", "jkl"])
    check("split k=5 row of 7", split_row("zxcvbnm", 5), ["zxcvbnm"])

    # every letter survives a split, in order
    for row in en + he:
        for k in range(1, 8):
            check(f"split preserves {row!r} k={k}", "".join(split_row(row, k)), row)

    # --- the dial, against the spec table ------------------------------------
    check("EN L1 keys", Layout(en, 3).keys, 8)
    check("EN L2 keys", Layout(en, 4).keys, 7)
    check("EN L3 keys", Layout(en, 5).keys, 5)
    check("HE L1 keys", Layout(he, 3).keys, 9)
    check("HE L2 keys", Layout(he, 4).keys, 7)
    check("HE L3 keys", Layout(he, 5).keys, 6)

    # A key is a column slice of the banded top two rows, so the top-row letters
    # come first inside each cap and the third row groups sideways alone. Written
    # out rather than derived: a derivation is only the implementation twice.
    check(
        "EN L3 groups",
        Layout(en, 5).groups,
        ["qweasd", "rtyfgh", "uijk", "opl", "zxcvbnm"],
    )

    # --- the Hebrew clitic collisions, as measured ---------------------------
    # Banding moved these: the band's own columns hold no two clitics — ו sits
    # over ע, and ש, כ and ל are each in a column of their own — so what is left
    # to collide is `זסבהנמצתץ`, the row that keeps delete and groups sideways.
    check("HE L1 collisions", Layout(he, 3).collisions(HEBREW_CLITICS), ["הנמ"])
    check("HE L2 collisions", Layout(he, 4).collisions(HEBREW_CLITICS), ["זסבהנ"])
    check(
        "HE L3 collisions",
        Layout(he, 5).collisions(HEBREW_CLITICS),
        ["טוןכעי", "זסבהנ"],
    )

    # --- separating them -----------------------------------------------------
    for k in (3, 4, 5):
        layout = Layout(he, k, avoid=HEBREW_CLITICS)
        if not layout.infeasible:
            check(f"separated k={k} has no collision", layout.collisions(HEBREW_CLITICS), [])
            check(f"separated k={k} keeps the key count", layout.keys, Layout(he, k).keys)
        # **Order is asserted per source row, not per drawn row**, because a
        # banded key holds letters from two of them: `[קרשד]` is ק and ר over ש
        # and ד. Reading one row's letters back out of the keys in order is the
        # claim that survives banding, and it is the one that matters — it is
        # what says a thumb still finds its letters where it left them.
        for row in he:
            seen = "".join(c for g in layout.groups for c in g if c in row)
            check(f"separated k={k} preserves {row!r}", seen, row)

    # infeasibility must be reported, never silently papered over
    check(
        "a row of two clitics cannot be one key",
        split_row_avoiding("הב", 5, HEBREW_CLITICS),
        None,
    )

    # --- final forms ---------------------------------------------------------
    folded = rows_without_final_forms(he)
    check("22 letters without final forms", sum(len(r) for r in folded), 22)
    check("no final form survives", [c for r in folded for c in r if c in FINAL_TO_ORDINARY], [])
    check("folding שלום", fold_final_forms("שלום"), "שלומ")
    check("folding is a no-op mid-word", fold_final_forms("מכונית"), "מכונית")

    # --- coding --------------------------------------------------------------
    layout = Layout(en, 3)
    check("same group, same key", layout.code("qw"), layout.code("as"))
    # **The letter underneath is on the same key, and that is the whole of what
    # banding changed.** Against the row-at-a-time build `q` and `a` are two
    # keystrokes, every key count is identical, and every other assertion in this
    # file still passes.
    check("the letter underneath shares the key", layout.code("q"), layout.code("a"))
    check("different group, different key", layout.code("q") == layout.code("e"), False)
    check("different group, different key", layout.code("q") == layout.code("t"), False)
    check("an apostrophe passes through", layout.code("don't")[3], "'")
    check("Hebrew is untypable on the Latin layout", layout.code("שלום"), None)
    check("Latin is untypable on the Hebrew layout", Layout(he, 3).code("hello"), None)
    check(
        "k=1 gives every word its own code",
        len({Layout(en, 1).code(w) for w in ("cat", "cab", "car", "bat")}),
        4,
    )

    # --- morphology and trimming --------------------------------------------
    check("clitic forms include the plain glue", "לעבודה" in clitic_forms("עבודה"), True)
    check("and the ה after another", "מהעבודה" in clitic_forms("עבודה"), True)
    check("word_core trims both ends", word_core("(recieve,"), "recieve")
    check("word_core keeps an inner apostrophe", word_core("don't"), "don't")
    check("word_core survives a bare mark", word_core("..."), "")

    # --- leave-one-out is the claim the context numbers rest on --------------
    # A version that forgot to hold out would score its own sentence's pairs and
    # every context gain in results.json would be leakage. These assert on
    # counts that are only correct when the held-out view is actually built.
    from decode import Bigrams  # noqa: E402

    bg = Bigrams([["a", "b"], ["a", "b"], ["a", "c"], ["x", "b", "x", "b"]])
    check("pooled counts", dict(bg.total["a"]), {"b": 2, "c": 1})

    bg.hold_out(0)  # removes one a->b
    check("holding out one sentence", bg.following("a"), {"b": 1, "c": 1})
    check("an untouched word is unchanged", bg.following("x"), {"b": 2})

    bg.hold_out(2)  # removes the only a->c
    check("a pair held to zero disappears", bg.following("a"), {"b": 2})

    bg.hold_out(3)  # x->b twice, b->x once; both x->b must go
    check("a repeated pair is removed every time", bg.following("x"), {})
    check("and its reverse too", bg.following("b"), {})

    bg.hold_out(1)
    check("holding out is not cumulative", bg.following("x"), {"b": 2})

    # --- a synthesised form may not overwrite a measured one -----------------
    # The version without the guard replaced the real frequency of 28.9% of the
    # Hebrew lexicon with a derived estimate, inflating `ללא` 3.1x off `לא` and
    # `בעל` 3.5x off `על`. A toy lexicon reproduces it in three rows: `מלא` is a
    # real word AND a clitic form of `לא`, so the buggy version overwrites it.
    from decode import Lexicon  # noqa: E402

    toy = Lexicon("he", [("לא", 0.02), ("מלא", 0.0002), ("עבודה", 0.001)], "toy")
    grown = toy.with_clitic_forms(0.1)
    check("a measured word keeps its own frequency", grown.freq["מלא"], 0.0002)
    check(
        "no measured frequency moves at all",
        [w for w, f in toy.freq.items() if grown.freq[w] != f],
        [],
    )
    check("a form the corpus never saw is still added", "לעבודה" in grown.freq, True)
    check("and it carries the penalty", grown.freq["לעבודה"], 0.0001)
    check("expansion never removes anything", set(toy.freq) <= set(grown.freq), True)

    if FAILURES:
        print(f"FAILED {len(FAILURES)}:\n", file=sys.stderr)
        for failure in FAILURES:
            print(f"  {failure}\n", file=sys.stderr)
        sys.exit(1)
    print("selftest: all assertions hold")


if __name__ == "__main__":
    main()
