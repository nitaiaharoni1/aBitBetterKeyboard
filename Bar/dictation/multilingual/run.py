#!/usr/bin/env python3
"""Runs the multilingual probe through the transcriber and scores it.

Reuses `../harness/transcribe.py` verbatim — same request, same schema, same
model settings — so this measures the shipping path and not a second one.

Two questions, and neither is a word error rate. One sentence per language
cannot support one, and pretending otherwise is how a number ends up quoted as
if it meant something.

  script      did the transcript come back in that language's own writing
              system? A Russian sentence returned in Latin letters is not a
              near miss, it is unusable.
  loanwords   did `document` and `standup` survive in Latin letters, in a
              sentence the voice pronounced through its own phonology? This is
              the same question the `mix-*` clips ask for Hebrew, asked in 28
              more alphabets.

`words` is reported beside them as a rough similarity, useful for spotting a
language that fell apart, and it carries every caveat in `generate.py`'s
docstring: the reference sentences were written by a language model and no
native speaker has read them.

    DICTATION_VARIANT   passed straight through to the harness, so the language
                        hint can be measured here — which is the one place it
                        could plausibly matter, since the model has to guess
                        between 60-odd languages instead of two.
"""

import json
import os
import sys
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "harness"))

import transcribe  # noqa: E402
from score import normalise, wer  # noqa: E402

LATIN = "LATIN"


def script_of(text):
    """The dominant Unicode script name of the letters in `text`."""
    counts = {}
    for character in text:
        if not character.isalpha():
            continue
        try:
            name = unicodedata.name(character).split()[0]
        except ValueError:
            continue
        counts[name] = counts.get(name, 0) + 1
    if not counts:
        return "NONE"
    return max(counts, key=lambda key: counts[key])


def main():
    truth = json.loads((HERE / "ground-truth.json").read_text())
    variant = os.environ.get("DICTATION_VARIANT", "baseline")

    results = []
    for clip in truth["clips"]:
        audio = (HERE / clip["file"]).read_bytes()
        # The hint the product would build for a speaker of this language: their
        # own keyboard plus English, which is what an Israeli's keyboard list
        # looks like and what everyone else's does too.
        if "hint" in variant:
            transcribe.HINT = (
                f"\n\nThe speaker types on these keyboards: {clip['language'].title()} and "
                "English. Expect one of those, or one of them with words from another mixed "
                "into it, and nothing else."
            )
        transcribe.VARIANT = variant
        answer = transcribe.call(audio)
        results.append({
            "id": clip["id"],
            "language": clip["language"],
            "speech": answer.get("speech", ""),
            "languages": answer.get("languages", ""),
            "text": (answer.get("text") or "").strip(),
        })
        print(f"  {clip['id']:<4} {results[-1]['text'][:70]}", file=sys.stderr)

    out = HERE / f"outputs-{variant}.json"
    out.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")

    by_id = {row["id"]: row for row in results}
    right_script = kept = kept_total = 0
    scores = []
    print(f"\n{'lang':<6}{'script':<10}{'loan':<7}{'WER':>7}  transcript")
    for clip in truth["clips"]:
        row = by_id[clip["id"]]
        want, got = script_of(clip["transcript"]), script_of(row["text"])
        ok = want == got
        right_script += ok
        loan = sum(1 for word in clip["embedded_english"] if word in row["text"].lower())
        kept += loan
        kept_total += len(clip["embedded_english"])
        score = wer(normalise(clip["transcript"]), normalise(row["text"]))
        scores.append(score)
        print(
            f"{clip['id']:<6}{('ok' if ok else got):<10}{f'{loan}/2':<7}{score:>7.1%}  {row['text'][:60]}"
        )

    total = len(truth["clips"])
    print()
    print(f"variant                  {variant}")
    print(f"right script             {right_script}/{total}")
    print(f"English kept in Latin    {kept}/{kept_total}")
    print(f"mean word error rate     {sum(scores)/len(scores):.1%}  (one sentence each — indicative only)")
    print(f"exact                    {sum(1 for s in scores if s == 0)}/{total}")


if __name__ == "__main__":
    main()
