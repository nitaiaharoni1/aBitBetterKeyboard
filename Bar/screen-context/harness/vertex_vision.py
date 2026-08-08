#!/usr/bin/env python3
"""Runs a multimodal model over the screen-context bar and writes cloud_outputs.json.

Same shape as Bar/ai-text/harness: this talks to Vertex directly with a gcloud
token belonging to this machine. It is a scoring harness and must never move
into an app target, because a shipped app cannot hold a cloud credential.

Asks for exactly the three fields the product needs off a screen, in the order
the product needs them decided. `propertyOrdering` is load-bearing for the same
reason as in the text harness: the model fills fields in the order it emits
them, so `sender` before `message` makes it commit to whose message it is
reading before it transcribes it.
"""

import base64
import concurrent.futures
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
BAR = HERE.parent

MODEL = os.environ.get("VERTEX_MODEL", "gemini-2.5-flash")
PROJECT = os.environ.get("VERTEX_PROJECT", "handi-project")
THINKING_BUDGET = int(os.environ.get("VERTEX_THINKING_BUDGET", "512"))

PROMPT = """You are looking at a screenshot of a phone messaging app.

STEP 1. List EVERY message bubble on screen, top to bottom, in `messages`, as
a JSON array of objects with the keys "from", "kind", "sender" and "text".
Include bubbles that carry no text of their own: voice notes, images,
stickers, files, call notices. Include the last bubble even if it is only
partly visible.

  from   — "them" if someone else sent it, "me" if the phone's owner did.
           The owner's messages are usually aligned to the opposite side from
           everyone else's and often carry read receipts (checkmarks).
  kind   — "text" only if the bubble's own content is words you can read.
           A voice note is "voice" even though a duration is printed on it.
           An image with a caption under it is "image"; the caption is its own
           "text" entry.
  sender — who sent that bubble, by name. A group chat prints a name above
           each incoming bubble: use it. A one-to-one chat prints no name at
           all, because the contact's name sits in the navigation bar at the
           top of the screen: use that instead. Never leave this empty for a
           bubble from "them".
  text   — the words in the bubble, exactly as written, wrapped lines joined
           with a single space. null when kind is not "text".

Do NOT list app chrome as a message: status bar, navigation bar, contact name,
"online"/"typing…", date dividers, unread dividers, encryption notices,
reaction or tapback pills, the text input placeholder, and bubble timestamps.
A reply bubble that quotes an earlier message is ONE entry. Its text is ONLY
the new text below the quote. The quoted part is a copy of something already
said, set off by an accent bar, a tint, or a smaller font, and it must not
appear in the entry's text at all.

STEP 2. Take the LAST entry in your list whose from is "them". That one, and
only that one, is the answer.

  - If its kind is "text", report its sender and text. `sender` must be a
    name: in a one-to-one chat that is the contact name from the navigation
    bar, never blank.
  - If its kind is anything else, there is nothing to reply to: return null for
    sender, message, script and language. Do NOT fall back to an earlier text
    message. The owner has already moved past it, so answering it would be
    stale.
  - If no entry has from "them", return null as well.

Never pick an earlier message because it reads as more answerable. The last one
is the answer even when it is a statement and an earlier one is a question.

Transcription rules for the reported message:
  - Copy it exactly. Do not translate, correct, or re-spell anything.
  - A time or number inside the text is part of the text. Only the timestamp
    attached to the bubble is chrome.
  - An @mention at the start is part of the text, not a sender label.
  - Emoji inside the message body stay. A reaction pill hanging off the bubble
    corner is not part of it.
  - In a right-to-left message, report logical reading order: a full stop or
    comma rendered at the left edge of a line closes the sentence before it, so
    it belongs at the END of that sentence.

script  — what is physically on screen: "hebrew" for Hebrew letters, "latin"
          for Latin letters, "mixed" when it genuinely contains both, which
          includes a Hebrew sentence with English words embedded in it.
language — a different question: which keyboard opens to reply. A Hebrew
          sentence that borrows English words is answered in Hebrew, so its
          language is "hebrew" while its script is "mixed". Only a message
          actually written in English gets "english".
"""

# Vertex takes OpenAPI-shaped schemas: uppercase type names, and `nullable`
# rather than a union with null.
SCHEMA = {
    "type": "OBJECT",
    "properties": {
        # Enumerating every bubble before choosing one is the whole trick. The
        # measured failure was never bad OCR: it was the model stopping one to
        # four bubbles short of the newest message, or answering a stale line
        # sitting above a voice note. A list it has to finish first turns
        # "which message is newest" from a judgement into an index.
        "messages": {"type": "STRING"},
        "sender": {"type": "STRING", "nullable": True},
        "message": {"type": "STRING", "nullable": True},
        "script": {"type": "STRING", "nullable": True, "enum": ["hebrew", "latin", "mixed"]},
        "language": {"type": "STRING", "nullable": True, "enum": ["hebrew", "english"]},
    },
    # Enumerate, then transcribe, then classify. The model fills fields in the
    # order they appear here, so every later field is decided with the list
    # already written down.
    "propertyOrdering": ["messages", "sender", "message", "script", "language"],
}

ENDPOINT = (
    f"https://aiplatform.googleapis.com/v1/projects/{PROJECT}"
    f"/locations/global/publishers/google/models/{MODEL}:generateContent"
)


def token():
    override = os.environ.get("VERTEX_ACCESS_TOKEN")
    if override:
        return override
    return subprocess.run(
        ["gcloud", "auth", "print-access-token", "--account=nitai@handi.co.il"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


ACCESS_TOKEN = token()


def call(image_bytes):
    body = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"inlineData": {"mimeType": "image/png", "data": base64.b64encode(image_bytes).decode()}},
                    {"text": PROMPT},
                ],
            }
        ],
        "generationConfig": {
            "temperature": 0,
            "responseMimeType": "application/json",
            "responseSchema": SCHEMA,
            "thinkingConfig": {"thinkingBudget": THINKING_BUDGET},
        },
    }
    request = urllib.request.Request(
        ENDPOINT,
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {ACCESS_TOKEN}",
            "Content-Type": "application/json",
        },
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                payload = json.load(response)
            text = payload["candidates"][0]["content"]["parts"][0]["text"]
            return json.loads(text)
        except (urllib.error.HTTPError, urllib.error.URLError, KeyError, IndexError) as error:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))


def run(entry):
    started = time.monotonic()
    result = call((BAR / entry["file"]).read_bytes())
    return {
        "id": entry["id"],
        "language": entry["language"],
        "config": MODEL,
        "sender": result.get("sender"),
        "message": result.get("message"),
        "messages": result.get("messages"),
        "detectedScript": result.get("script"),
        "detectedLanguage": result.get("language"),
        "seconds": round(time.monotonic() - started, 2),
    }


def main():
    truth = json.loads((BAR / "ground-truth.json").read_text())
    entries = truth["images"]

    outputs = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for result in pool.map(run, entries):
            outputs.append(result)
            sys.stderr.write(".")
            sys.stderr.flush()
    sys.stderr.write("\n")

    outputs.sort(key=lambda row: row["id"])
    out = BAR / (sys.argv[1] if len(sys.argv) > 1 else "cloud_outputs.json")
    out.write_text(json.dumps(outputs, ensure_ascii=False, indent=2))

    seconds = sorted(row["seconds"] for row in outputs)
    print(f"wrote {len(outputs)} results to {out}")
    print(f"median {seconds[len(seconds)//2]:.1f}s   p90 {seconds[int(len(seconds)*0.9)]:.1f}s   max {seconds[-1]:.1f}s")


if __name__ == "__main__":
    main()
