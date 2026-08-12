#!/usr/bin/env python3
"""Assemble Bar/grouped/data/testtext.json from the repo's four frozen corpora.

Read-only over the corpora. Everything it emits is text that already exists in
one of them; nothing is invented, and every entry carries a `source` that names
the file and the key it came from.

    python3 Bar/grouped/make-testtext.py [--out PATH] [--report]

The four sources, and what is taken from each:

  Bar/typing/corpus.json          `context` plus the finished word (see below)
  Bar/ai-text/corpus.json         `input`, or `context.message` for replies
  Bar/dictation/ground-truth.json `transcript`
  Bar/screen-context/ground-truth.json  every `messagesOnScreen[].text`

The typing corpus is the only one that needs a rule. Its entries are frozen
*mid-typing* moments: `context` is committed text and `prefix` is the partial or
deliberately-misspelled word under the cursor, so `context + prefix` ends in a
non-word ("I'll be there in ten minu") which no lexicon decoder can ever return.
The finished word is taken from the entry's own fields instead, in this order:

  1. empty prefix                -> context, plus `acceptable[0]` when that list is
                                    closed and so is the corpus's own single answer
                                    ("תודה " + "רבה"). An *open* list is documented as
                                    a sample and never a whitelist, so nothing is added.
  2. `intended`                  -> what the corpus says the person meant
  3. `mustNotCorrect`            -> the prefix as typed; it is already right
  4. `acceptable[0]`             -> the corpus's own good completion of the prefix

All 90 entries resolve through one of those four, and the rule used is recorded
in the entry's `source` string.
"""

from __future__ import annotations

import argparse
import json
import os
import unicodedata
from collections import Counter, OrderedDict

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GENERATED = "2026-08-12"
GENERATOR = "Bar/grouped/make-testtext.py"

TYPING = "Bar/typing/corpus.json"
AITEXT = "Bar/ai-text/corpus.json"
DICTATION = "Bar/dictation/ground-truth.json"
SCREEN = "Bar/screen-context/ground-truth.json"

PROVENANCE = (
    "Every text here was authored for this repo as test material and then frozen; none of it is "
    "naturally occurring keyboard input. The typing entries are mid-typing moments reconstructed "
    "into whole words from the corpus's own `intended` / `mustNotCorrect` / `acceptable` fields, so "
    "the last word of such an entry is the corpus's answer rather than a keystroke record. The "
    "ai-text entries are inputs written to probe specific failure modes (already-correct sentences, "
    "meaning traps, mixed script). The dictation transcripts are human-authored sentences, but the "
    "audio in that corpus is synthetic macOS `say` speech and its own header says so; only the text "
    "is used here, so that warning does not transfer, while the sentences were still written to be "
    "read aloud cleanly. The screen-context messages are the chat bodies drawn into 30 generated "
    "screenshots of WhatsApp, Slack, Messages, Telegram and Mail. What this means for the numbers: "
    "vocabulary, sentence length and the rate of code-switching were all chosen by a person to "
    "exercise hard cases, so word frequencies do not match a real user's stream and any absolute "
    "accuracy figure measured on this file is a statement about this file. Differences between two "
    "decoders measured on the same entries are the number worth reading."
)

HEBREW = range(0x0590, 0x0600)


def script_of(ch: str) -> str | None:
    if not ch.isalpha():
        return None
    if ord(ch) in HEBREW:
        return "he"
    name = unicodedata.name(ch, "")
    if name.startswith("LATIN"):
        return "en"
    return None


def classify(text: str) -> tuple[str | None, bool]:
    """(language, code_switched). language is None when the text has no letters."""
    counts = Counter(s for s in (script_of(c) for c in text) if s)
    if not counts:
        return None, False
    code_switch = counts["he"] > 0 and counts["en"] > 0
    if counts["he"] > counts["en"]:
        return "he", code_switch
    if counts["en"] > counts["he"]:
        return "en", code_switch
    for ch in text:  # a tie is broken by whichever script opens the text
        s = script_of(ch)
        if s:
            return s, code_switch
    return None, False


def words(text: str) -> list[str]:
    return text.split()


def normalise(word: str) -> str:
    return word.strip("\"'“”‘’.,!?:;()[]{}…-–—״׳").lower()


def load(rel: str):
    with open(os.path.join(REPO, rel), encoding="utf-8") as fh:
        return json.load(fh)


def typing_entries() -> list[dict]:
    out = []
    for e in load(TYPING)["entries"]:
        context, prefix = e["context"], e["prefix"]
        if not prefix:
            if e.get("acceptableIsClosed") and e.get("acceptable"):
                text, rule = context + e["acceptable"][0], "context+acceptable[0]"
            else:
                text, rule = context, "context"
        elif e.get("intended"):
            text, rule = context + e["intended"], "context+intended"
        elif e.get("mustNotCorrect"):
            text, rule = context + prefix, "context+prefix"
        elif e.get("acceptable"):
            text, rule = context + e["acceptable"][0], "context+acceptable[0]"
        else:
            text, rule = context + prefix, "context+prefix"
        out.append(
            {
                "id": "typing-" + e["id"],
                "source": f"{TYPING}#{e['id']}.{rule}",
                "text": text,
            }
        )
    return out


def aitext_entries() -> list[dict]:
    out = []
    for e in load(AITEXT)["entries"]:
        if "input" in e:
            out.append(
                {
                    "id": "aitext-" + e["id"],
                    "source": f"{AITEXT}#{e['id']}.input",
                    "text": e["input"],
                }
            )
        elif isinstance(e.get("context"), dict) and e["context"].get("message"):
            out.append(
                {
                    "id": "aitext-" + e["id"],
                    "source": f"{AITEXT}#{e['id']}.context.message",
                    "text": e["context"]["message"],
                }
            )
    return out


def dictation_entries() -> list[dict]:
    return [
        {
            "id": "dictation-" + c["id"],
            "source": f"{DICTATION}#{c['id']}.transcript",
            "text": c["transcript"],
        }
        for c in load(DICTATION)["clips"]
    ]


def screen_entries() -> list[dict]:
    out = []
    for img in load(SCREEN)["images"]:
        for i, msg in enumerate(img.get("messagesOnScreen", [])):
            out.append(
                {
                    "id": f"screen-{img['id']}-m{i:02d}",
                    "source": f"{SCREEN}#{img['id']}.messagesOnScreen[{i}].text",
                    "text": msg["text"],
                    "clipped": not msg.get("fullyVisible", True),
                }
            )
    return out


def build():
    raw = typing_entries() + aitext_entries() + dictation_entries() + screen_entries()

    entries, seen = [], {}
    dropped_duplicate, dropped_short, dropped_no_letters = [], [], []

    for item in raw:
        text = item["text"].strip()
        if len(text) <= 1:
            dropped_short.append(item["id"])
            continue
        language, code_switch = classify(text)
        if language is None:
            dropped_no_letters.append(item["id"])
            continue
        if text in seen:
            dropped_duplicate.append((item["id"], seen[text]))
            continue
        seen[text] = item["id"]
        entry = OrderedDict(
            [
                ("id", item["id"]),
                ("language", language),
                ("source", item["source"]),
                ("text", text),
            ]
        )
        if code_switch:
            entry["codeSwitch"] = True
        if item.get("clipped"):
            entry["clipped"] = True
        entries.append(entry)

    counts = {
        lang: {
            "entries": sum(1 for e in entries if e["language"] == lang),
            "words": sum(len(words(e["text"])) for e in entries if e["language"] == lang),
        }
        for lang in ("en", "he")
    }

    doc = OrderedDict(
        [
            ("generated", GENERATED),
            ("generator", GENERATOR),
            ("provenance", PROVENANCE),
            ("counts", counts),
            ("entries", entries),
        ]
    )
    stats = {
        "duplicates": dropped_duplicate,
        "short": dropped_short,
        "no_letters": dropped_no_letters,
    }
    return doc, stats


def report(doc, stats):
    entries = doc["entries"]
    print(f"entries: {len(entries)}")
    for lang in ("en", "he"):
        rows = [e for e in entries if e["language"] == lang]
        distinct = {normalise(w) for e in rows for w in words(e["text"])} - {""}
        print(
            f"  {lang}: {len(rows)} entries, "
            f"{doc['counts'][lang]['words']} words, {len(distinct)} distinct words"
        )
        if lang == "he" and len(distinct) < 500:
            print(f"  !! Hebrew has only {len(distinct)} distinct words; the sample is thin.")
    by_source = Counter(e["source"].split("#")[0] for e in entries)
    for path, n in by_source.most_common():
        print(f"  {path}: {n}")
    print(f"  code-switched: {sum(1 for e in entries if e.get('codeSwitch'))}")
    print(f"  clipped (screenshot cut the message): {sum(1 for e in entries if e.get('clipped'))}")
    print(f"  dropped duplicates: {len(stats['duplicates'])}")
    for dup, kept in stats["duplicates"]:
        print(f"    {dup} == {kept}")
    print(f"  dropped too short: {len(stats['short'])} {stats['short']}")
    print(f"  dropped no letters: {len(stats['no_letters'])} {stats['no_letters']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(REPO, "Bar/grouped/data/testtext.json"))
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    doc, stats = build()
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    print(f"wrote {args.out}")
    if args.report:
        report(doc, stats)


if __name__ == "__main__":
    main()
