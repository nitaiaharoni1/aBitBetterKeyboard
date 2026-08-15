#!/usr/bin/env python3
"""Assertions that reject a broken glide pipeline, run before every sweep.

Each one is written to fail on a specific wrong implementation, per
`AGENTS.md`'s rule: work out what the broken version returns and check the
assertion rejects it.
"""

from __future__ import annotations

import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GROUPED_HARNESS = HERE.parent.parent / "grouped" / "harness"
sys.path.insert(0, str(GROUPED_HARNESS))
sys.path.insert(0, str(HERE))

from decode import Decoder, Lexicon  # noqa: E402
from keyboard import GlideLayout, letter_centers  # noqa: E402
from path import (  # noqa: E402
    corner_indices,
    curved_path,
    reduce_to_keys,
    waypoints,
    word_to_glide_code,
)

FAILURES: list[str] = []


def check(label: str, got, want) -> None:
    if got != want:
        FAILURES.append(f"{label}\n     got  {got}\n     want {want}")


def main() -> None:
    # --- geometry: centring, not flush-left ----------------------------------
    # A row shorter than the widest one is centred under it. Flush-left would
    # put "a" directly under "q"; it does not, on the real keyboard, and this
    # is the whole reason "he" needs its own offset math rather than QWERTY's.
    rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    centers = letter_centers(rows)
    check("q sits at the left edge of the widest row", centers["q"], (0.5, 0.5))
    check("a is centred under qw, not flush under q", centers["a"], (1.0, 1.5))
    check("z is centred further in still, under zxc", centers["z"], (2.0, 2.5))

    # --- waypoints collapse doubled letters -----------------------------------
    check("hello visits 4 points, not 5 — the double collapses", len(waypoints("hello", centers)), 4)
    check("ball visits 3 points", len(waypoints("ball", centers)), 3)
    check("a punctuation-only word has no waypoints", waypoints("...", centers), [])

    # --- GlideLayout.code ------------------------------------------------------
    layout = GlideLayout(rows)
    check("later's code has no doubled letter", layout.code("later"), ("l", "a", "t", "e", "r"))
    check(
        "latter collapses onto the same code as later — the real ambiguity",
        layout.code("latter"),
        layout.code("later"),
    )
    check("an apostrophe makes the whole word unmappable", layout.code("don't"), None)
    check("a foreign letter makes the word unmappable", layout.code("café"), None)
    check("an empty word has no code", layout.code(""), None)

    # --- the zero-noise round trip ---------------------------------------------
    # With no jitter and no corner-cutting, the sampled-and-reduced path must
    # reconstruct exactly the same collapsed code `GlideLayout.code` computes
    # from the spelling alone, for words whose letters are not collinear. A
    # broken sampler, a broken corner detector, or an off-by-one in the
    # segment loop would each drift this apart from the deterministic answer.
    zero_rng = random.Random(1)
    for word in ("hello", "keyboard", "ball", "later", "latter"):
        got = word_to_glide_code(
            word, centers, samples_per_segment=6, corner_cut=0.0, sigma=0.0,
            angle_threshold_deg=5, rng=zero_rng,
        )
        check(f"zero-noise round trip for {word!r}", got, layout.code(word))

    # --- the known, structural limitation: a truly collinear middle letter -----
    # `w`, `i`, `p` sit on QWERTY's top row in that order, so the straight line
    # from `w` to `p` passes exactly through `i` — the true turning angle there
    # is zero, not small, so no threshold can recover it. This is named in
    # `corner_indices`'s docstring and pinned here so the claim is checked
    # rather than only asserted in prose.
    check(
        "swipe loses the collinear i — a real limitation, not a bug",
        word_to_glide_code(
            "swipe", centers, samples_per_segment=6, corner_cut=0.0, sigma=0.0,
            angle_threshold_deg=5, rng=random.Random(1),
        ),
        ("s", "w", "p", "e"),
    )
    check(
        "quick loses the collinear u the same way",
        word_to_glide_code(
            "quick", centers, samples_per_segment=6, corner_cut=0.0, sigma=0.0,
            angle_threshold_deg=5, rng=random.Random(1),
        ),
        ("q", "i", "c", "k"),
    )

    # --- corner detection: threshold separates a real turn from a wobble -------
    # A hand-built path: dead straight from (0,0) to (2,0), then a small 3° dip
    # to (3, -0.05), then dead straight on to (5, 0). A threshold above 3°
    # must not see the dip as a corner; a threshold below it must.
    import math
    wobble_path = [(float(x), 0.0) for x in range(3)] + [(3.0, -0.05)] + [
        (float(x), 0.0) for x in range(4, 6)
    ]
    wobble_angle_deg = math.degrees(
        math.acos(max(-1.0, min(1.0, (2 * 1 + 0 * -0.05) / (2 * math.hypot(1, -0.05)))))
    )
    check("the built wobble is a few degrees, not a real corner", 1 < wobble_angle_deg < 6, True)
    check(
        "a high threshold ignores the small wobble",
        len(corner_indices(wobble_path, angle_threshold_deg=10)),
        2,  # only the anchored start and end
    )
    check(
        "a low threshold catches the same wobble",
        len(corner_indices(wobble_path, angle_threshold_deg=1)) > 2,
        True,
    )
    check("touch-down and touch-up are always corners", corner_indices(wobble_path, angle_threshold_deg=180)[0], 0)
    check(
        "even at an unreachable threshold, the last index is kept",
        corner_indices(wobble_path, angle_threshold_deg=180)[-1],
        len(wobble_path) - 1,
    )

    # --- corner-cutting can skip a middle waypoint ------------------------------
    # `m` sits off the direct line from `l` to `r`. A corner-cut path that
    # blends fully toward the far neighbour approximates that direct line and
    # never turns near `m`'s key, so it drops out of the reduced sequence
    # entirely — the mechanism `path.py`'s docstring claims exists must
    # actually fire, and at corner_cut=0 the same geometry must still recover
    # `m` untouched.
    corner_centers = {"l": (0.0, 0.0), "m": (1.0, -2.0), "r": (3.0, 0.0)}
    cut_path = curved_path(
        [corner_centers["l"], corner_centers["m"], corner_centers["r"]],
        samples_per_segment=8, corner_cut=1.0,
    )
    check(
        "full corner-cutting removes the middle key from an off-line corner",
        "m" in reduce_to_keys(cut_path, corner_centers, angle_threshold_deg=5),
        False,
    )
    uncut_path = curved_path(
        [corner_centers["l"], corner_centers["m"], corner_centers["r"]],
        samples_per_segment=8, corner_cut=0.0,
    )
    check(
        "zero corner-cutting recovers the same middle key",
        reduce_to_keys(uncut_path, corner_centers, angle_threshold_deg=5),
        ("l", "m", "r"),
    )
    check("an empty path has no code", reduce_to_keys([], corner_centers, angle_threshold_deg=5), ())

    # --- Decoder reuse: unmodified, just indexed by a different code -----------
    # The whole spike's central claim in one assertion: `Bar/grouped`'s Decoder
    # class, never touched, ranks a glide-derived code exactly as it ranks a
    # grouped one, and a doubled-letter collision surfaces both candidates.
    toy = Lexicon("en", [("later", 0.01), ("latter", 0.008), ("later's", 0.0001)], "toy")
    decoder = Decoder(toy, layout)
    later_candidates = decoder.candidates(layout.code("later"))
    check("both later and latter share one code", set(later_candidates), {"later", "latter"})
    check("frequency still ranks the commoner one first", later_candidates[0], "later")

    # --- Fuzzy rescue is order-independent ------------------------------------
    # `fuzzy_candidates` builds a `set` of code variants, and Python randomises
    # string hashing per process, so iterating it directly made the sweep
    # disagree with itself at identical seeds: 7 of 60 conditions moved on
    # `commitFuzzyRate` alone. The fix is `sorted(variants)` plus a word
    # tiebreak, and this is what keeps it. Two lexicon words of *exactly* equal
    # frequency are the case that used to flip, so the toy lexicon below is
    # built that way on purpose.
    # **Calling it repeatedly in one process would not catch this.** A set's
    # iteration order is fixed for the life of a process, so the bug only ever
    # showed up between runs. What rejects it is the *order itself*: four words
    # of identical frequency must come back alphabetically, because the tiebreak
    # is now the word. Insertion order would put them in one of 24 arrangements
    # and only one of those is this one.
    from run import fuzzy_candidates  # noqa: E402

    tied_words = ["bat", "cat", "rat", "sat"]
    tied = Lexicon("en", [(w, 0.01) for w in tied_words], "tied")
    tied_decoder = Decoder(tied, layout)
    check(
        "equal-frequency fuzzy candidates are broken alphabetically, not by set order",
        fuzzy_candidates(tied_decoder, layout.code("at"), set(layout.centers)),
        tied_words,
    )

    if FAILURES:
        print(f"FAILED {len(FAILURES)}:\n", file=sys.stderr)
        for failure in FAILURES:
            print(f"  {failure}\n", file=sys.stderr)
        sys.exit(1)
    print("selftest: all assertions hold")


if __name__ == "__main__":
    main()
