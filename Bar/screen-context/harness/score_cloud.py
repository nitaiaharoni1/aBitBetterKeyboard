#!/usr/bin/env python3
"""Scores a structured screen-reading pass against the screen-context bar.

Three independent checks per image, because they fail in different ways:

  message  — the text the keyboard would reply to. Exact after normalising
             whitespace and bidi marks. Near-misses are reported separately so
             a transcription that is 98% right is not filed next to one that
             returned a timestamp.
  sender   — who said it. Wrong here means the reply is addressed to the wrong
             person, which is worse than a clumsy reply.
  language — which keyboard layout to switch to.

Returning a chrome string listed in `traps`, or any text listed in
`notOnScreen`, is counted separately: those are not near-misses, they are the
two failure modes the bar was built to catch.
"""

import json
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path

HERE = Path(__file__).resolve().parent
BAR = HERE.parent


def normalise(text):
    text = re.sub(r"[‎‏‪-‮⁦-⁩]", "", text or "")
    return re.sub(r"\s+", " ", text).strip()


def similarity(a, b):
    a, b = normalise(a), normalise(b)
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return SequenceMatcher(None, a, b, autojunk=False).ratio()


def main():
    truth = json.loads((BAR / "ground-truth.json").read_text())
    outputs = json.loads((BAR / (sys.argv[1] if len(sys.argv) > 1 else "cloud_outputs.json")).read_text())
    by_id = {entry["id"]: entry for entry in truth["images"]}

    tally = {}
    failures = []

    for row in outputs:
        entry = by_id[row["id"]]
        expected = entry.get("expected")
        language = entry["language"]
        bucket = tally.setdefault(language, {"n": 0, "message": 0, "near": 0, "sender": 0, "lang": 0, "script": 0, "trap": 0, "ghost": 0})
        bucket["n"] += 1

        got_message = normalise(row.get("message"))
        got_sender = normalise(row.get("sender"))

        if expected is None:
            # The deliberate nothing-to-reply-to screen: silence is the answer.
            ok = not got_message
            bucket["message"] += ok
            bucket["sender"] += ok
            bucket["lang"] += ok
            bucket["script"] += ok
            if not ok:
                failures.append((row["id"], language, "invented a message on an empty screen", got_message))
            continue

        score = similarity(expected.get("message"), got_message)
        if score == 1.0:
            bucket["message"] += 1
        elif score >= 0.9:
            bucket["near"] += 1
            failures.append((row["id"], language, f"message {score:.0%}", got_message))
        else:
            failures.append((row["id"], language, f"message {score:.0%}", got_message))

        if similarity(expected.get("sender"), got_sender) == 1.0:
            bucket["sender"] += 1
        else:
            failures.append((row["id"], language, "sender", f"{got_sender!r} != {expected.get('sender')!r}"))

        if row.get("detectedLanguage") == expected.get("language"):
            bucket["lang"] += 1
        else:
            failures.append(
                (row["id"], language, "language",
                 f"{row.get('detectedLanguage')!r} != {expected.get('language')!r}"))
        if row.get("detectedScript") == expected.get("script"):
            bucket["script"] += 1

        # The two failure modes the bar exists to catch.
        for trap in entry.get("traps", []):
            if normalise(trap["text"]) and normalise(trap["text"]) == got_message:
                bucket["trap"] += 1
                failures.append((row["id"], language, "RETURNED A TRAP", trap["why"]))
        for ghost in entry.get("notOnScreen", []):
            text = ghost if isinstance(ghost, str) else ghost.get("text", "")
            # Short clipped fragments ("N") match by accident inside any
            # sentence; only a run long enough to be evidence counts.
            if len(normalise(text)) >= 8 and normalise(text) in got_message:
                bucket["ghost"] += 1
                failures.append((row["id"], language, "RETURNED OFF-SCREEN TEXT", text))

    print(f"{'language':9} {'n':>3} {'message':>9} {'+near':>7} {'sender':>8} {'lang':>7} {'script':>7} {'traps':>6} {'ghosts':>7}")
    print("-" * 62)
    total = {"n": 0, "message": 0, "near": 0, "sender": 0, "lang": 0, "script": 0, "trap": 0, "ghost": 0}
    for language in ("english", "mixed", "hebrew"):
        b = tally.get(language)
        if not b:
            continue
        for key in total:
            total[key] += b[key]
        print(
            f"{language:9} {b['n']:>3} {b['message']:>4}/{b['n']:<4} {b['near']:>7} "
            f"{b['sender']:>4}/{b['n']:<3} {b['lang']:>3}/{b['n']:<3} {b['trap']:>6} {b['ghost']:>7}"
        )
    print("-" * 62)
    b = total
    print(
        f"{'ALL':9} {b['n']:>3} {b['message']:>4}/{b['n']:<4} {b['near']:>7} "
        f"{b['sender']:>4}/{b['n']:<3} {b['lang']:>3}/{b['n']:<3} {b['trap']:>6} {b['ghost']:>7}"
    )
    exact = b["message"] / b["n"]
    print(f"\nexact message {exact:.0%}   exact-or-near {(b['message'] + b['near']) / b['n']:.0%}")

    if failures and "-q" not in sys.argv:
        print("\nmisses:")
        for ident, language, kind, detail in failures:
            print(f"  {ident:8} {language:8} {kind:22} {detail[:90]}")


if __name__ == "__main__":
    main()
