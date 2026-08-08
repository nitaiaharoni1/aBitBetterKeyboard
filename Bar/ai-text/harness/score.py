#!/usr/bin/env python3
"""Scores real_outputs.json against reference.json.

Two independent passes, reported separately on purpose:

  mechanical  Deterministic checks that need no judgement — script preservation,
              loanwords still in Latin, already-correct inputs left alone,
              question marks, no invented digits. These are trustworthy.

  judged      The `must` / `must_not` lists, which are natural language and
              cannot be regex'd. A model reads each criterion against the
              candidate. This is a model grading a model: treat it as a strong
              signal, not as ground truth, and spot-check it.

Usage: VERTEX_ACCESS_TOKEN=... ./score.py [--judge]
"""
import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
BAR = HERE.parent

HEBREW = re.compile(r"[֐-׿יִ-ﭏ]")
LATIN = re.compile(r"[A-Za-z]")
# Loanwords the corpus explicitly requires to survive in Latin script.
LATIN_WORD = re.compile(r"[A-Za-z][A-Za-z0-9]{2,}")


def load():
    corpus = {e["id"]: e for e in json.loads((BAR / "corpus.json").read_text())["entries"]}
    reference = {e["id"]: e for e in json.loads((BAR / "reference.json").read_text())["entries"]}
    real = json.loads((BAR / "real_outputs.json").read_text())
    return corpus, reference, real


def candidate_text(value):
    """Flattens whatever shape the action produced into text for checking."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    return "\n".join(v.get("text", "") for v in value)


def source_text(entry):
    return entry.get("input") or entry["context"]["message"]


def normalise(s):
    return re.sub(r"[\s.]+$", "", s.strip())


def mechanical(entry, ref, candidate):
    """Returns {check: (passed, detail)} for the checks that need no judgement."""
    out = {}
    src = source_text(entry)
    if candidate is None:
        return {"answered": (False, "no output")}
    out["answered"] = (True, "")

    # Script preservation. The single most visible tell that a model translated.
    if HEBREW.search(src):
        out["kept_hebrew"] = (bool(HEBREW.search(candidate)), "output has no Hebrew at all")

    # Latin-script loanwords must survive as Latin. This is the code-switching
    # promise, and it is what breaks when a model transliterates.
    # Checked against the reference's Latin words, not the input's: a word the
    # reference also changes (its -> it's) is a correction, not a lost loanword.
    reference = ref.get("reference")
    reference_text = reference if isinstance(reference, str) else " ".join(
        v["text"] for v in (reference or [])
    )
    if HEBREW.search(src) and reference_text:
        loanwords = {
            w.lower() for w in LATIN_WORD.findall(src)
        } & {w.lower() for w in LATIN_WORD.findall(reference_text)}
        if loanwords:
            lost = sorted(w for w in loanwords if w not in candidate.lower())
            out["kept_loanwords"] = (not lost, f"lost from Latin script: {', '.join(lost)}")

    # An already-correct input is supposed to come back unchanged. Only scored on
    # single-output actions; rewrite/reply are meant to change the text.
    # Fix only. Tone is asked to change the register even when the grammar is
    # already right, so "unchanged" is not the bar there.
    if "already-correct" in entry.get("tags", []) and entry["action"] == "fix":
        out["left_alone"] = (
            normalise(candidate) == normalise(src),
            "changed an input that was already correct",
        )

    # A question that comes back without a question mark is a failure in both
    # languages, per the corpus conventions.
    if "question-mark" in entry.get("tags", []):
        out["question_mark"] = ("?" in candidate, "question came back without a question mark")

    # Times and numbers may only be ones the message already contained.
    invented = sorted(set(re.findall(r"\d+", candidate)) - set(re.findall(r"\d+", src)))
    if invented:
        out["no_invented_numbers"] = (False, f"numbers not in the input: {', '.join(invented)}")
    else:
        out["no_invented_numbers"] = (True, "")

    return out


JUDGE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "must_results": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "criterion": {"type": "STRING"},
                    "met": {"type": "BOOLEAN"},
                    "why": {"type": "STRING"},
                },
                "required": ["criterion", "met", "why"],
            },
        },
        "must_not_results": {
            "type": "ARRAY",
            "items": {
                "type": "OBJECT",
                "properties": {
                    "criterion": {"type": "STRING"},
                    "violated": {"type": "BOOLEAN"},
                    "why": {"type": "STRING"},
                },
                "required": ["criterion", "violated", "why"],
            },
        },
        "verdict": {"type": "STRING", "description": "one of: good, partial, bad"},
    },
    "required": ["must_results", "must_not_results", "verdict"],
}

JUDGE_INSTRUCTIONS = """You grade the output of a keyboard's AI text action against a rubric.

You are given the original message, what a good writer would have produced, and \
what the engine actually produced. You are also given `must` criteria (things the \
output has to do) and `must_not` criteria (things it must not do).

Grade each criterion independently and literally. The reference is one good answer, \
not the only one: an output that differs in wording but satisfies the criterion \
passes. Judge the criterion, not the resemblance.

Then give an overall verdict: `good` if it satisfies the rubric and is something the \
user could send, `partial` if it is usable but breaks a criterion or drifts in \
register, `bad` if it is wrong, damaging, in the wrong language, or unusable."""


def judge_one(args):
    entry, ref, candidate, token, project = args
    if candidate is None:
        return entry["id"], None
    reference = ref.get("reference")
    if not isinstance(reference, str):
        reference = json.dumps(reference, ensure_ascii=False)

    prompt = (
        f"Action: {entry['action']}\n"
        f"Language: {entry['language']}\n"
        f"Original message:\n{source_text(entry)}\n\n"
        f"Reference (one good answer):\n{reference}\n\n"
        f"Engine output:\n{candidate}\n\n"
        f"must: {json.dumps(ref.get('must') or [], ensure_ascii=False)}\n"
        f"must_not: {json.dumps(ref.get('must_not') or [], ensure_ascii=False)}"
    )

    body = json.dumps(
        {
            "systemInstruction": {"parts": [{"text": JUDGE_INSTRUCTIONS}]},
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {
                "responseMimeType": "application/json",
                "responseSchema": JUDGE_SCHEMA,
            },
        }
    ).encode()

    url = (
        f"https://aiplatform.googleapis.com/v1/projects/{project}"
        f"/locations/global/publishers/google/models/gemini-2.5-pro:generateContent"
    )
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=180) as response:
            payload = json.load(response)
        text = payload["candidates"][0]["content"]["parts"][0]["text"]
        return entry["id"], json.loads(text)
    except Exception as error:  # noqa: BLE001 - a failed grade is data, not a crash
        return entry["id"], {"error": str(error)}


def main():
    corpus, reference, real = load()
    run_judge = "--judge" in sys.argv

    results = {}
    for entry_id, entry in corpus.items():
        candidate = candidate_text(real.get(entry_id))
        results[entry_id] = {"mechanical": mechanical(entry, reference[entry_id], candidate)}

    if run_judge:
        token = os.environ.get("VERTEX_ACCESS_TOKEN", "")
        project = os.environ.get("VERTEX_PROJECT", "handi-project")
        if not token:
            sys.exit("VERTEX_ACCESS_TOKEN required for --judge")
        work = [
            (entry, reference[i], candidate_text(real.get(i)), token, project)
            for i, entry in corpus.items()
        ]
        with ThreadPoolExecutor(max_workers=6) as pool:
            for entry_id, verdict in pool.map(judge_one, work):
                results[entry_id]["judged"] = verdict

    (BAR / "scores.json").write_text(json.dumps(results, ensure_ascii=False, indent=2, sort_keys=True))
    report(corpus, results, run_judge)


def report(corpus, results, run_judge):
    langs = ["en", "he", "he-en"]
    actions = ["fix", "rewrite", "tone", "reply"]

    print("MECHANICAL (deterministic)\n")
    checks = ["kept_hebrew", "kept_loanwords", "left_alone", "question_mark", "no_invented_numbers"]
    print(f"{'check':22}" + "".join(f"{l:>10}" for l in langs) + f"{'total':>10}")
    for check in checks:
        row, totals = "", [0, 0]
        for lang in langs:
            ids = [i for i, e in corpus.items() if e["language"] == lang and check in results[i]["mechanical"]]
            ok = sum(1 for i in ids if results[i]["mechanical"][check][0])
            totals[0] += ok
            totals[1] += len(ids)
            row += f"{(f'{ok}/{len(ids)}' if ids else '-'):>10}"
        print(f"{check:22}{row}{f'{totals[0]}/{totals[1]}':>10}")

    print("\nfailures:")
    for entry_id in sorted(results):
        for check, (ok, detail) in results[entry_id]["mechanical"].items():
            if not ok:
                print(f"  {entry_id:12} {check:20} {detail}")

    if not run_judge:
        return

    print("\n\nJUDGED (model grading model — spot-check before trusting)\n")
    print(f"{'':10}" + "".join(f"{l:>12}" for l in langs))
    for action in actions:
        row = ""
        for lang in langs:
            ids = [
                i for i, e in corpus.items()
                if e["language"] == lang and e["action"] == action and isinstance(results[i].get("judged"), dict)
                and "verdict" in results[i]["judged"]
            ]
            good = sum(1 for i in ids if results[i]["judged"]["verdict"] == "good")
            partial = sum(1 for i in ids if results[i]["judged"]["verdict"] == "partial")
            row += f"{(f'{good}+{partial}p/{len(ids)}' if ids else '-'):>12}"
        print(f"{action:10}{row}")

    violations = [
        (i, c["criterion"])
        for i in sorted(results)
        if isinstance(results[i].get("judged"), dict)
        for c in results[i]["judged"].get("must_not_results", [])
        if c.get("violated")
    ]
    print(f"\nmust_not violations: {len(violations)}")
    for entry_id, criterion in violations:
        print(f"  {entry_id:12} {criterion}")

    unmet = [
        (i, c["criterion"])
        for i in sorted(results)
        if isinstance(results[i].get("judged"), dict)
        for c in results[i]["judged"].get("must_results", [])
        if not c.get("met")
    ]
    print(f"\nunmet must criteria: {len(unmet)}")
    for entry_id, criterion in unmet:
        print(f"  {entry_id:12} {criterion}")


if __name__ == "__main__":
    main()
