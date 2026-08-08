#!/usr/bin/env python3
"""
Regenerates Bar/dictation/audio/ and Bar/dictation/ground-truth.json.

Every clip is macOS text-to-speech (`say`), not a human being. Read README.md
before you use anything measured on this corpus as evidence about real accuracy.

    python3 Bar/dictation/generate.py

Deterministic: same manifest in, same audio out. Safe to re-run.
"""

import json
import re
import shutil
import subprocess
import sys
import wave
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUDIO_DIR = HERE / "audio"
GROUND_TRUTH = HERE / "ground-truth.json"

# 16 kHz mono 16-bit PCM. The canonical input shape for speech models; the test
# harness should still convert to whatever SpeechTranscriber.bestAvailableAudioFormat
# reports rather than assuming this is accepted verbatim.
SAMPLE_RATE = 16000
DATA_FORMAT = f"LEI16@{SAMPLE_RATE}"

HEBREW = re.compile(r"[֐-׿]")
LATIN = re.compile(r"[A-Za-z]")

# Carmit is the only he_IL voice macOS ships. Hebrew and code-switched clips are
# therefore all one speaker, one gender, one accent — see README, limitation 2.
HE_VOICE = "Carmit"

# clip = (id, text, voice, rate_wpm, [named entities the engine is likely to fumble])
HEBREW_CLIPS = [
    ("he-01", "נועה, תעדכני בבקשה את הדוח לפני הישיבה עם ההנהלה מחר בעשר וחצי",
     HE_VOICE, 175, ["נועה"]),
    ("he-02", "דיברתי עם יואב מהצוות של מובילאיי, הם רוצים לראות הדגמה בשבוע הבא",
     HE_VOICE, 160, ["יואב", "מובילאיי"]),
    ("he-03", "צריך לסגור את התקציב לרבעון הבא עד יום חמישי, אחרת זה נדחה לינואר",
     HE_VOICE, 190, []),
    ("he-04", "שלחתי לשירה את החוזה בווטסאפ, היא אמרה שתחזור אלי אחרי הצהריים",
     HE_VOICE, 175, ["שירה", "ווטסאפ"]),
    ("he-05", "הפגישה עם המשקיעים של פיטנגו נדחתה ליום שלישי הבא בשעה תשע בבוקר",
     HE_VOICE, 150, ["פיטנגו"]),
    ("he-06", "אבישי ביקש שנעביר את כל הקבצים לתיקייה המשותפת לפני סוף החודש",
     HE_VOICE, 185, ["אבישי"]),
    ("he-07", "יש לנו תקלה בשרת של הלקוח בחיפה, אני נוסע לשם מחר בבוקר",
     HE_VOICE, 200, ["חיפה"]),
    ("he-08", "תגידי לרונית שאני מאחר לישיבת הצוות, יש פקקים בכביש שש",
     HE_VOICE, 175, ["רונית", "כביש שש"]),
    ("he-09", "המנהל הכללי של צ'ק פוינט אמר שהם מגייסים עוד מאתיים מהנדסים השנה",
     HE_VOICE, 165, ["צ'ק פוינט"]),
    ("he-10", "אני חושב שכדאי לנו לבדוק את זה עוד פעם לפני שאנחנו מעלים לאוויר",
     HE_VOICE, 195, []),
    ("he-11", "כתבי לי בבקשה סיכום קצר של השיחה עם הלקוח ותשלחי לכולם במייל",
     HE_VOICE, 175, []),
    ("he-12", "הגשנו את הבקשה לרשות החדשנות, התשובה אמורה להגיע תוך שישה שבועות",
     HE_VOICE, 155, ["רשות החדשנות"]),
]

ENGLISH_CLIPS = [
    ("en-01", "Can you review the deck before the board meeting on Thursday morning?",
     "Samantha", 175, []),
    ("en-02", "I pushed the fix to staging, but the pipeline is still failing on the integration tests.",
     "Daniel", 165, ["staging", "pipeline"]),
    ("en-03", "Let's move the standup to nine fifteen so Yotam can join from Tel Aviv.",
     "Karen", 180, ["Yotam", "Tel Aviv"]),
    ("en-04", "We closed the seed round last week, twelve million led by Aleph.",
     "Moira", 170, ["Aleph"]),
    ("en-05", "The customer in Berlin wants SOC two compliance before they sign the contract.",
     "Tessa", 175, ["SOC two"]),
    ("en-06", "Please send me the invoice from the vendor, I need it for the quarterly report.",
     "Rishi", 160, []),
    ("en-07", "I think we should ship the beta to a hundred users first and see what breaks.",
     "Tara", 190, []),
    ("en-08", "Ravit is on vacation until Sunday, so ask Dor about the migration script.",
     "Aman", 175, ["Ravit", "Dor"]),
    ("en-09", "The latency went up after the deploy, can you check the database connection pool?",
     "Zoe (Premium)", 170, []),
    ("en-10", "We need to hire two more backend engineers before the end of the quarter.",
     "Samantha", 200, []),
    ("en-11", "I'll be working from home tomorrow, ping me on Slack if anything urgent comes up.",
     "Daniel", 190, ["Slack"]),
    ("en-12", "The demo with Wix went well, they want to start a pilot in September.",
     "Moira", 155, ["Wix"]),
]

CODE_SWITCHED_CLIPS = [
    ("mix-01", "בוא נעשה sync קצר על ה-roadmap של Q3 לפני ה-standup",
     HE_VOICE, 175, ["sync", "roadmap", "Q3", "standup"]),
    ("mix-02", "אני אשלח לך את ה-document מחר בבוקר אחרי שאני מסיים את ה-review",
     HE_VOICE, 165, ["document", "review"]),
    ("mix-03", "צריך לעשות deploy ל-production אחרי שה-tests עוברים ב-CI",
     HE_VOICE, 180, ["deploy", "production", "tests", "CI"]),
    ("mix-04", "שלחתי לך invite ל-meeting בזום, תאשר בבקשה ב-calendar",
     HE_VOICE, 175, ["invite", "meeting", "calendar"]),
    ("mix-05", "ה-designer העלה את ה-mockups ל-Figma, תעברי עליהם לפני ה-sprint planning",
     HE_VOICE, 160, ["designer", "mockups", "Figma", "sprint planning"]),
    ("mix-06", "יש bug ב-login של האפליקציה, ה-QA פתחו ticket בג'ירה",
     HE_VOICE, 190, ["bug", "login", "QA", "ticket", "ג'ירה"]),
    ("mix-07", "המשקיעים רוצים לראות את ה-metrics של ה-churn ברבעון האחרון",
     HE_VOICE, 170, ["metrics", "churn"]),
    ("mix-08", "תעשה לי favor ותכתוב summary של ה-call עם הלקוח",
     HE_VOICE, 195, ["favor", "summary", "call"]),
    ("mix-09", "ה-onboarding של העובדים החדשים מתחיל ביום ראשון עם ה-HR",
     HE_VOICE, 175, ["onboarding", "HR"]),
    ("mix-10", "צריך לעדכן את ה-pricing באתר לפני ה-launch של הגרסה החדשה",
     HE_VOICE, 150, ["pricing", "launch"]),
    ("mix-11", "אני ב-remote היום, אפשר לדבר איתי ב-Slack או ב-WhatsApp",
     HE_VOICE, 185, ["remote", "Slack", "WhatsApp"]),
    ("mix-12", "ה-backend של דניאל מוכן, חסר רק ה-integration עם ה-API של החברה",
     HE_VOICE, 175, ["backend", "דניאל", "integration", "API"]),
]

GROUPS = [
    ("he", "Hebrew only", HEBREW_CLIPS),
    ("en", "English only", ENGLISH_CLIPS),
    ("he-en", "Hebrew sentence with English words inside it", CODE_SWITCHED_CLIPS),
]


def token_counts(text):
    """Split on whitespace and bucket each token by script.

    A token like 'ה-roadmap' has both scripts in it, which is the whole point of
    the code-switched set, so it gets its own bucket rather than being forced
    into one of the two.
    """
    hebrew = english = mixed = 0
    for token in text.split():
        has_he = bool(HEBREW.search(token))
        has_en = bool(LATIN.search(token))
        if has_he and has_en:
            mixed += 1
        elif has_he:
            hebrew += 1
        elif has_en:
            english += 1
    return hebrew, english, mixed


def wav_duration(path):
    with wave.open(str(path), "rb") as handle:
        return round(handle.getnframes() / handle.getframerate(), 3)


def synthesize(clip_id, text, voice, rate, out_path):
    argv = [
        "say", "-v", voice, "-r", str(rate),
        "-o", str(out_path),
        "--data-format", DATA_FORMAT,
        "--channels", "1",
        text,
    ]
    result = subprocess.run(argv, capture_output=True, text=True)
    if result.returncode != 0 or not out_path.exists():
        raise RuntimeError(f"{clip_id}: say failed ({result.returncode}) {result.stderr.strip()}")
    # The command as a human would retype it, recorded in ground-truth.json so a
    # single clip can be regenerated without running the whole script.
    return "say -v {!r} -r {} -o {} --data-format {} --channels 1 {!r}".format(
        voice, rate, out_path.name, DATA_FORMAT, text
    )


def main():
    if not shutil.which("say"):
        sys.exit("`say` not found — this script only runs on macOS.")

    voices = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
    if "he_IL" not in voices:
        sys.exit(
            "No he_IL voice installed. Do NOT substitute an English voice reading "
            "transliterated Hebrew — regenerate the en group only, and say so in the README."
        )

    if AUDIO_DIR.exists():
        shutil.rmtree(AUDIO_DIR)
    AUDIO_DIR.mkdir(parents=True)

    clips = []
    out_of_range = []

    for mix, mix_label, group in GROUPS:
        for clip_id, text, voice, rate, entities in group:
            out_path = AUDIO_DIR / f"{clip_id}.wav"
            command = synthesize(clip_id, text, voice, rate, out_path)
            duration = wav_duration(out_path)
            hebrew, english, mixed = token_counts(text)

            if not 3.0 <= duration <= 12.0:
                out_of_range.append((clip_id, duration))

            clips.append({
                "id": clip_id,
                "file": f"audio/{out_path.name}",
                "transcript": text,
                "language_mix": mix,
                "language_mix_label": mix_label,
                "duration_seconds": duration,
                "word_count": len(text.split()),
                "hebrew_tokens": hebrew,
                "english_tokens": english,
                "mixed_script_tokens": mixed,
                "named_entities": entities,
                "production": {
                    "method": "macos-say-tts",
                    "speaker": "synthetic",
                    "voice": voice,
                    "rate_wpm": rate,
                    "command": command,
                },
            })
            print(f"{clip_id}  {duration:5.2f}s  {voice} @ {rate}wpm")

    payload = {
        "corpus": "AIKeyboard dictation bar",
        "generated": date.today().isoformat(),
        "generator": "Bar/dictation/generate.py",
        "provenance": "SYNTHETIC — 100% macOS `say` text-to-speech. Zero human recordings.",
        "warning": (
            "Word error rate measured on this corpus is an OPTIMISTIC CEILING, not a "
            "prediction of field accuracy. Synthetic speech is cleaner, better enunciated "
            "and more evenly paced than a person talking in a noisy room. A real bar needs "
            "100-500 genuine Israeli recordings (plan.md section 6). Passing here is "
            "necessary, not sufficient. See README.md."
        ),
        "audio_format": {
            "container": "wav",
            "encoding": "LEI16 (16-bit signed little-endian PCM)",
            "sample_rate_hz": SAMPLE_RATE,
            "channels": 1,
            "note": (
                "Convert to whatever SpeechTranscriber.bestAvailableAudioFormat reports "
                "before feeding SpeechAnalyzer; do not assume 16 kHz is accepted verbatim."
            ),
        },
        "scoring_note": (
            "Compute WER on a normalized form: case-folded, punctuation stripped, Hebrew "
            "maqaf/hyphen treated consistently. 'ה-roadmap' vs 'ה roadmap' is a formatting "
            "difference, not a recognition error. Track named_entities separately — entity "
            "accuracy matters more than raw WER for this product."
        ),
        "language_mix_values": {
            "he": "Hebrew only",
            "en": "English only",
            "he-en": "Hebrew sentence with English words inside it (code-switching)",
        },
        "counts": {
            mix: sum(1 for c in clips if c["language_mix"] == mix)
            for mix, _, _ in GROUPS
        },
        "clip_count": len(clips),
        "clips": clips,
    }
    payload["counts"]["total"] = len(clips)

    GROUND_TRUTH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    total = sum(c["duration_seconds"] for c in clips)
    print(f"\n{len(clips)} clips, {total:.1f}s total -> {GROUND_TRUTH}")
    if out_of_range:
        print("WARNING: outside the 3-12s window: " +
              ", ".join(f"{cid} ({d:.2f}s)" for cid, d in out_of_range))


if __name__ == "__main__":
    main()
