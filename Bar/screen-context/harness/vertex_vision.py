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

Three knobs, and only these three, describe *what the model is shown*. Nothing
about the prompt, the schema, the ordering, the thinking budget or the model is
reachable from the environment, because every one of those is measured and a
run that moves two of them at once measures nothing.

    VERTEX_IMAGE_SCALE    1 (default) sends the corpus PNG untouched, which is
                          the configuration every published score on this bar
                          was taken at. 2 halves both dimensions and rounds
                          down to even, exactly as `FrameScaler.target` does,
                          which is what the capture process actually uploads.
    VERTEX_IMAGE_FORMAT   png (default) or jpeg. The bar has always sent PNG;
                          the shipping path sends JPEG, because
                          `CloudScreenReader.encode` does.
    VERTEX_JPEG_QUALITY   70, matching that encoder's default quality.

Resampling is Pillow's LANCZOS against vImage's `kvImageHighQualityResampling`.
Different implementations of the same idea; the harness does not share a
resampler with the shipping code on purpose, so a result that only held for one
of them would show up.
"""

import base64
import concurrent.futures
import io
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

# An alias, not a pinned version — and, measured on 2026-08-08, **there is no
# pinned version to move to.** Every dated handle 404s on this project
# (`gemini-2.5-flash-001`, `-002`, `-preview-05-20`, `-preview-04-17`), and the
# API answers a successful call by echoing `modelVersion: "gemini-2.5-flash"`,
# the alias itself. So `VERTEX_MODEL` cannot buy reproducibility here, whatever
# an earlier version of this comment implied; it exists to let a future dated
# version be used the day one appears.
#
# What that leaves is a noise floor, and it is worth knowing which kind of noise
# it is, because the two behave differently:
#
#   within a sitting   two full runs minutes apart, this exact configuration,
#                      disagreed on 2 of 30 frames and scored 30/30 and 29/30
#                      sender, 30/30 language both times.
#   across days        an earlier pair at the *other* configuration disagreed on
#                      roughly a third of the corpus with nothing in the repo
#                      changed.
#
# So a delta measured inside one sitting is close to trustworthy and a number
# compared against a recording from another day is not. `cloud_outputs.json`
# carries its recording date in every row's `config`; `cloud_outputs_repeat.json`
# is the second run above, kept so the spread stays a measured number rather
# than a memory.
MODEL = os.environ.get("VERTEX_MODEL", "gemini-2.5-flash")
PROJECT = os.environ.get("VERTEX_PROJECT", "handi-project")
THINKING_BUDGET = int(os.environ.get("VERTEX_THINKING_BUDGET", "512"))
IMAGE_SCALE = int(os.environ.get("VERTEX_IMAGE_SCALE", "1"))
IMAGE_FORMAT = os.environ.get("VERTEX_IMAGE_FORMAT", "png").lower()
JPEG_QUALITY = int(os.environ.get("VERTEX_JPEG_QUALITY", "70"))

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


def frame(path):
    """The bytes that go on the wire, and their MIME type.

    Untouched at the default scale and format, so the published numbers stay
    reproducible byte for byte without Pillow installed at all.
    """
    if IMAGE_SCALE == 1 and IMAGE_FORMAT == "png":
        return path.read_bytes(), "image/png"

    from PIL import Image

    with Image.open(path) as image:
        image = image.convert("RGB")
        if IMAGE_SCALE != 1:
            # `FrameScaler.target`: divide, then round down to even so a 4:2:0
            # chroma plane divides exactly. 1206x2622 -> 602x1310, not 603x1311.
            size = ((image.width // IMAGE_SCALE) & ~1, (image.height // IMAGE_SCALE) & ~1)
            image = image.resize(size, Image.LANCZOS)
        buffer = io.BytesIO()
        if IMAGE_FORMAT == "jpeg":
            image.save(buffer, format="JPEG", quality=JPEG_QUALITY)
            return buffer.getvalue(), "image/jpeg"
        image.save(buffer, format="PNG")
        return buffer.getvalue(), "image/png"


def call(image_bytes, mime_type):
    body = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"inlineData": {"mimeType": mime_type, "data": base64.b64encode(image_bytes).decode()}},
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
    image_bytes, mime_type = frame(BAR / entry["file"])
    started = time.monotonic()
    result = call(image_bytes, mime_type)
    return {
        "id": entry["id"],
        "language": entry["language"],
        "config": f"{MODEL} scale={IMAGE_SCALE} {IMAGE_FORMAT}",
        "sender": result.get("sender"),
        "message": result.get("message"),
        "messages": result.get("messages"),
        "detectedScript": result.get("script"),
        "detectedLanguage": result.get("language"),
        "bytes": len(image_bytes),
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
    payload = sorted(row["bytes"] for row in outputs)
    print(f"wrote {len(outputs)} results to {out}")
    print(f"config {MODEL} scale={IMAGE_SCALE} {IMAGE_FORMAT}"
          + (f" q{JPEG_QUALITY}" if IMAGE_FORMAT == "jpeg" else ""))
    print(f"median {seconds[len(seconds)//2]:.1f}s   p90 {seconds[int(len(seconds)*0.9)]:.1f}s   max {seconds[-1]:.1f}s")
    print(f"bytes  median {payload[len(payload)//2]/1024:.0f} KB   "
          f"p90 {payload[int(len(payload)*0.9)]/1024:.0f} KB   max {payload[-1]/1024:.0f} KB   "
          f"total {sum(payload)/1024/1024:.1f} MB")


if __name__ == "__main__":
    main()
