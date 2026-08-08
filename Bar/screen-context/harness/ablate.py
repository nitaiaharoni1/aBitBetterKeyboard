#!/usr/bin/env python3
"""Re-measures the three prompt-shape claims the screen-context design rests on.

`vertex_vision.py` deliberately exposes nothing about the prompt or the schema to
the environment, because a run that moves two things at once measures nothing.
This is the other half of that rule: a *separate* script that moves exactly one
thing per variant, against the same corpus, in one sitting, and writes each
variant's answers to its own file so the claim has an artifact behind it.

Three claims, each recorded in `.claude/CLAUDE.md` as a measured number with no
committed output to back it:

  enumerate    "`messages` is a list the model must finish before naming an
               answer, because every wrong answer on the bar was a bubble one to
               four positions above the newest — enumerating took sender from
               21/30 to 29/30."
               Variant drops the `messages` field entirely and the STEP 1 half of
               the prompt with it, leaving STEP 2's rule to be applied from
               nothing.

  split        "`script` and `language` are separate fields because they disagree
               on exactly the code-switched sentences this product exists for;
               collapsing them scored 22/30, splitting them 29/30."
               Variant collapses both into one field the model fills once.

  flatten      "Flattening the list into a JSON string costs 7 points, which is
               why `CloudField` carries nested `items`."
               Variant is the *inverse* of the others: the shipping product sends
               a nested array schema, and the baseline here already flattens to a
               STRING. So this variant is the nested one, and a gain over the
               baseline is the cost of flattening.

Run:  VERTEX_ACCESS_TOKEN=$(gcloud auth print-access-token --account=…) \
      python3 harness/ablate.py [variant …]

Writes `Bar/screen-context/ablation/<variant>.json`, scoreable by `score_cloud.py`
exactly like any other output file. The baseline is not re-run here: use
`size-encoder/scale2-jpeg.json`, which is the same configuration, and take it from
the same sitting as these or the comparison is worthless. See the alias hazard in
`vertex_vision.py`.
"""

import concurrent.futures
import json
import sys
import time
from pathlib import Path

import vertex_vision as base

HERE = Path(__file__).resolve().parent
BAR = HERE.parent
OUT = BAR / "ablation"

# The baseline prompt, cut at the seam between its two steps so a variant can
# drop one without rewriting the other.
STEP_ONE, STEP_TWO = base.PROMPT.split("STEP 2.", 1)
STEP_TWO = "STEP 2." + STEP_TWO
TAIL = STEP_TWO[STEP_TWO.index("script  —"):]
PICK = STEP_TWO[: STEP_TWO.index("script  —")]

VARIANTS = {
    # One thing moved: the model is no longer made to enumerate before choosing.
    "enumerate": {
        "prompt": (
            "You are looking at a screenshot of a phone messaging app.\n\n"
            + PICK.replace("Take the LAST entry in your list whose from is \"them\".", "Find the newest message someone else sent to the phone's owner.")
                  .replace("STEP 2. ", "")
                  .replace("your list", "the screen")
            + TAIL
        ),
        "schema": {
            "type": "OBJECT",
            "properties": {
                "sender": {"type": "STRING", "nullable": True},
                "message": {"type": "STRING", "nullable": True},
                "script": {"type": "STRING", "nullable": True, "enum": ["hebrew", "latin", "mixed"]},
                "language": {"type": "STRING", "nullable": True, "enum": ["hebrew", "english"]},
            },
            "propertyOrdering": ["sender", "message", "script", "language"],
        },
    },
    # One thing moved: the two questions become one field.
    "split": {
        "prompt": base.PROMPT[: base.PROMPT.index("script  —")]
        + (
            "language — which language to reply in AND what is physically on\n"
            "          screen, as one answer: \"hebrew\", \"english\" or \"mixed\".\n"
        ),
        "schema": {
            "type": "OBJECT",
            "properties": {
                "messages": {"type": "STRING"},
                "sender": {"type": "STRING", "nullable": True},
                "message": {"type": "STRING", "nullable": True},
                "language": {
                    "type": "STRING", "nullable": True, "enum": ["hebrew", "english", "mixed"]
                },
            },
            "propertyOrdering": ["messages", "sender", "message", "language"],
        },
    },
    # One thing moved: `messages` becomes the nested array the product sends,
    # instead of the flat string this harness has always used.
    "flatten": {
        "prompt": base.PROMPT,
        "schema": {
            "type": "OBJECT",
            "properties": {
                "messages": {
                    "type": "ARRAY",
                    "items": {
                        "type": "OBJECT",
                        "properties": {
                            "from": {"type": "STRING"},
                            "kind": {"type": "STRING"},
                            "sender": {"type": "STRING", "nullable": True},
                            "text": {"type": "STRING", "nullable": True},
                        },
                        "propertyOrdering": ["from", "kind", "sender", "text"],
                    },
                },
                "sender": {"type": "STRING", "nullable": True},
                "message": {"type": "STRING", "nullable": True},
                "script": {"type": "STRING", "nullable": True, "enum": ["hebrew", "latin", "mixed"]},
                "language": {"type": "STRING", "nullable": True, "enum": ["hebrew", "english"]},
            },
            "propertyOrdering": ["messages", "sender", "message", "script", "language"],
        },
    },
}


def call(image_bytes, mime_type, prompt, schema):
    """`base.call` with the prompt and schema opened up. Same everything else —
    same endpoint, same temperature, same thinking budget, same retries."""
    saved_prompt, saved_schema = base.PROMPT, base.SCHEMA
    try:
        base.PROMPT, base.SCHEMA = prompt, schema
        return base.call(image_bytes, mime_type)
    finally:
        base.PROMPT, base.SCHEMA = saved_prompt, saved_schema


def run(entry, name, variant):
    image_bytes, mime_type = base.frame(BAR / entry["file"])
    started = time.monotonic()
    result = call(image_bytes, mime_type, variant["prompt"], variant["schema"])
    messages = result.get("messages")
    language = result.get("language")
    # The collapsed variant answers one field for two questions, so it is read
    # into both columns rather than scored on a column it was never asked for.
    script = result.get("script", language)
    return {
        "id": entry["id"],
        "language": entry["language"],
        "config": f"{base.MODEL} scale={base.IMAGE_SCALE} {base.IMAGE_FORMAT} ablation={name}",
        "sender": result.get("sender"),
        "message": result.get("message"),
        "messages": messages if isinstance(messages, str) else json.dumps(messages, ensure_ascii=False),
        "detectedScript": script,
        "detectedLanguage": None if language == "mixed" else language,
        "bytes": len(image_bytes),
        "seconds": round(time.monotonic() - started, 2),
    }


def main():
    names = [a for a in sys.argv[1:] if not a.startswith("-")] or list(VARIANTS)
    truth = json.loads((BAR / "ground-truth.json").read_text())
    entries = truth["images"]
    OUT.mkdir(exist_ok=True)

    for name in names:
        variant = VARIANTS[name]
        rows = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            for row in pool.map(lambda e: run(e, name, variant), entries):
                rows.append(row)
                sys.stderr.write(".")
                sys.stderr.flush()
        sys.stderr.write("\n")
        rows.sort(key=lambda r: r["id"])
        path = OUT / f"{name}.json"
        path.write_text(json.dumps(rows, ensure_ascii=False, indent=2))
        print(f"wrote {len(rows)} results to {path}")


if __name__ == "__main__":
    main()
