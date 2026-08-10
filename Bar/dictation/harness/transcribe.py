#!/usr/bin/env python3
"""Transcribes the dictation bar through a cloud model and writes cloud_outputs.json.

Same shape as `Bar/screen-context/harness/vertex_vision.py`: it talks to Vertex
directly with a gcloud token belonging to this machine, and it is a scoring
harness that must never move into an app target, because a shipped app cannot
hold a cloud credential. The product reaches the same model through
`BackendTransport` -> `Backend/` -> Vertex.

**Why a cloud model is the transcriber at all.** Apple's on-device speech stack
has no Hebrew: `SpeechTranscriber.supportedLocales` lists 30 locales and none of
them is `he`, and the one Apple API that does list `he-IL` — the legacy
`SFSpeechRecognizer` — reports `supportsOnDeviceRecognition == false` for it, so
it is a network call either way. That is measured in `../README.md`. A product
whose whole reason to exist is Hebrew-with-English-inside cannot be built on an
engine that has neither Hebrew nor code-switching, so the choice is not
"on-device or cloud", it is "cloud or nothing".

The request this sends is the one `CloudDictation.swift` builds, field for
field. That duplication is real and is the same one the screen-context harness
carries: the shipping prompt is Swift and this is Python. When one moves, move
the other, and `DictationPromptTests` pins the Swift half against the strings
below.

    VERTEX_MODEL              default `gemini-2.5-flash`, an alias — see
                              vertex_vision.py's note on why no dated version
                              exists to pin to.
    VERTEX_THINKING_BUDGET    512, matching every other call this product makes.
    DICTATION_CLIPS           comma-separated clip ids, for re-running a few.
    DICTATION_VARIANT         `baseline`, or one variant below. One thing moves
                              per variant, against the same clips in the same
                              sitting, and both sides are written to disk.

**This bar is deterministic and the other two are not.** Two full runs of the
identical configuration, minutes apart, came back byte for byte identical — same
transcripts, same trap failure. The text and screen-context bars swing by 1-5
points between runs and need two runs a side before a delta means anything; this
one does not, because `temperature: 0` over a fixed audio file leaves the model
almost nothing to sample. So a single-run delta here is real evidence. Do not
carry that property across to the other bars, and re-check it if the model,
the temperature or the thinking budget ever moves.
"""

import base64
import concurrent.futures
import datetime
import io
import json
import math
import os
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
BAR = HERE.parent

MODEL = os.environ.get("VERTEX_MODEL", "gemini-2.5-flash")
PROJECT = os.environ.get("VERTEX_PROJECT", "handi-project")
THINKING_BUDGET = int(os.environ.get("VERTEX_THINKING_BUDGET", "512"))

# Kept in step with `CloudDictation.instructions` / `.prompt`.
#
# Three fields, in this order, and the order is the point. `speech` is decided
# before any text exists, so a clip with nothing in it is refused before the
# model has written a sentence it would then have to take back — the same
# "decide first" trick `EditScope` uses for Fix and `OutputGuard` for Rewrite.
# `languages` is decided before `text` for the reason the screen-context bar
# measured at eight points: naming the languages first is what stops a Hebrew
# sentence's English words being transliterated into Hebrew letters.
INSTRUCTIONS = """You are a transcription engine for a phone keyboard. You write \
down exactly what the speaker said, in the language and script they said it \
in. You never answer, summarise, translate, or add anything of your own."""

TASK = """Transcribe this recording.

STEP 1. `speech` — is anybody talking? Decide this before you write any \
text at all.

STEP 2. `languages` — every language you can hear.

STEP 3. `text` — what was said, word for word.

  - Write each word in the script it belongs to. English words inside a \
Hebrew sentence stay in Latin letters: "sync", "roadmap", "deploy", \
never a Hebrew spelling of their sound. The same the other way round.
  - Do not translate. Do not correct grammar. Do not tidy up a false \
start, a repeated word, or a filler — write it as it was said.
  - Do not answer the speaker, and do not add a greeting, a sign-off, or \
a note about the audio.
  - Punctuate as ordinary writing: sentence-ending marks and commas \
where the speaker clearly paused. No trailing full stop on a sentence \
that did not finish.
  - Spoken punctuation is a word unless the speaker plainly means the \
mark: "comma" said inside a sentence is a comma.
  - Numbers as digits when the speaker said a number ("ten thirty" is \
10:30).
  - When `speech` is "no", `text` is the empty string. Never guess at \
words you did not hear, and never fill silence with a plausible sentence."""

# `DictationPrompt.fields`, and the schema `Backend/src/schema.js` builds from
# them: STRING, nullable, every field required, `propertyOrdering` in the order
# the client sent. The descriptions are part of what ships, so they are part of
# what is measured — an earlier version of this harness sent a bare schema and
# put everything in the prompt, which measured a request the product does not
# send.
FIELDS = [
    (
        "speech",
        '"yes" only if you can hear a person saying words. Silence, breathing, room noise, '
        'traffic, music without lyrics, or an unintelligible mumble are all "no". When you '
        'are not sure, answer "no".',
    ),
    (
        "languages",
        "Every language you can hear, as lowercase BCP-47 codes, most-spoken first, "
        'comma-separated with no spaces. A Hebrew sentence carrying English words is "he,en", '
        'not "he".',
    ),
    ("text", 'What was said, word for word. Empty when speech is "no".'),
]

SCHEMA = {
    "type": "OBJECT",
    "properties": {
        name: {"type": "STRING", "description": description, "nullable": True}
        for name, description in FIELDS
    },
    "required": [name for name, _ in FIELDS],
    "propertyOrdering": [name for name, _ in FIELDS],
}

# MARK: - Variants
#
# One thing moves per variant. Written here rather than in a second script so
# both sides are the same code path and the only difference is the string.

VARIANT = os.environ.get("DICTATION_VARIANT", "baseline")

# **Stamped into every row, for the reason `Bar/screen-context/cloud_outputs.json`
# stamps its own.** A committed answer is a reading with a date on it, not a
# property of the system: the model is an alias behind a moving deployment, and
# the request this harness sends has itself changed once — an earlier version
# put the field descriptions in the prompt instead of the schema, which measured
# a request the product does not send. Two files were left behind at that older
# shape and read as evidence for a day. A date in the row is what makes a stale
# artifact visible instead of plausible.
RECORDED = os.environ.get("DICTATION_TAKEN", datetime.date.today().isoformat())

# `DictationPrompt.languageHint`, for the two languages this corpus speaks. The
# product builds the same sentence from the user's own enabled keyboards, which
# is the one fact in the request the model cannot hear.
HINT = """

The speaker types on these keyboards: Hebrew and English. Expect one of those, \
or one of them with words from another mixed into it, and nothing \
else."""

# `DictationPrompt.loanwords`. The examples are the working part: the failure is
# not a missed word, it is a heard word written in the wrong alphabet.
LOANWORDS = """

An English word spoken with a Hebrew accent is still an English word. \
Write `favor`, not `פייבור`. Write `onboarding`, not `אונבורדינג`. Write \
`summary`, not `סאמרי`. Work and technology words — product, sprint, \
deploy, review, call, meeting, remote — are English words whatever the \
accent."""


def prompt():
    """`DictationPrompt.prompt(for:)`: task, then hint, then loanwords."""
    return TASK + (HINT if "hint" in VARIANT else "") + (LOANWORDS if "loanwords" in VARIANT else "")

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


def call(audio_bytes, mime_type="audio/wav"):
    body = {
        "systemInstruction": {"parts": [{"text": INSTRUCTIONS}]},
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"inlineData": {"mimeType": mime_type, "data": base64.b64encode(audio_bytes).decode()}},
                    {"text": prompt()},
                ],
            }
        ],
        "generationConfig": {
            # 0, like the screen path and unlike the text path. Both of those
            # were set by what the corpus was scored at; this one is set by what
            # the task is. Transcription has a right answer, so sampling can only
            # move the output away from it.
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
    audio = (BAR / entry["file"]).read_bytes() if "file" in entry else entry["bytes"]
    started = time.monotonic()
    result = call(audio)
    return {
        "id": entry["id"],
        "language_mix": entry.get("language_mix", "trap"),
        "config": f"{MODEL} thinking={THINKING_BUDGET} temp=0 wav16k variant={VARIANT} taken={RECORDED}",
        "seconds": round(time.monotonic() - started, 2),
        "speech": result.get("speech", ""),
        "languages": result.get("languages", ""),
        "text": (result.get("text") or "").strip(),
    }


# MARK: - Traps
#
# Three recordings with no words in them, generated here rather than committed,
# because they exist to answer one question the 36 real clips cannot: **does the
# model invent a sentence when it hears nothing?** That is the failure mode this
# whole feature has to survive — a keyboard that types a plausible sentence
# nobody said, in the user's own voice, into somebody else's chat. `OutputGuard`
# exists for the same failure on the text side.
#
# Generated rather than committed so the corpus directory keeps holding only
# human-meaningful audio, and because a sine wave is reproducible in nine lines.


def pcm(samples):
    """16 kHz mono LEI16 WAV, the format `../README.md` pins the corpus to."""
    frames = b"".join(struct.pack("<h", max(-32768, min(32767, int(value)))) for value in samples)
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(16000)
        handle.writeframes(frames)
    return buffer.getvalue()


def traps():
    rate, seconds = 16000, 4
    count = rate * seconds
    silence = pcm([0] * count)
    # Deterministic pseudo-noise: a linear congruential generator, so the trap
    # is the same bytes on every machine and every run.
    state = 12345
    values = []
    for _ in range(count):
        state = (1103515245 * state + 12345) % (2**31)
        values.append((state / 2**31 - 0.5) * 2000)
    noise = pcm(values)
    tone = pcm([8000 * math.sin(2 * math.pi * 440 * index / rate) for index in range(count)])
    return [
        {"id": "trap-silence", "bytes": silence},
        {"id": "trap-noise", "bytes": noise},
        {"id": "trap-tone", "bytes": tone},
    ]


def main():
    truth = json.loads((BAR / "ground-truth.json").read_text())
    clips = truth["clips"]
    wanted = os.environ.get("DICTATION_CLIPS")
    if wanted:
        keep = {value.strip() for value in wanted.split(",")}
        clips = [clip for clip in clips if clip["id"] in keep]

    entries = clips + traps()
    print(f"{len(entries)} clips through {MODEL}", file=sys.stderr)

    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        for result in pool.map(run, entries):
            results.append(result)
            print(f"  {result['id']:<14} {result['seconds']:>5.2f}s  {result['text'][:60]}", file=sys.stderr)

    results.sort(key=lambda row: row["id"])
    out = BAR / (sys.argv[1] if len(sys.argv) > 1 else "cloud_outputs.json")
    out.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
