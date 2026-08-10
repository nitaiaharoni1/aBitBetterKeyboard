#!/usr/bin/env python3
"""Generates a one-sentence-per-language probe set for dictation.

**What this is for.** `Bar/dictation/` is Hebrew, English and the mix of the
two, which is the product's core case and is *all* it can measure. This keyboard
ships 64 languages, so "dictation works" is a claim about 64 alphabets and the
corpus can speak two of them. This directory is the cheapest honest check on the
other 62: one sentence in every catalogue language macOS has a voice for, run
through the same transcriber, scored on whether the sentence came back in the
right script and the right words.

**Every limitation of the main corpus applies here, plus two worse ones.**

1. **The sentences were written by a language model, not by native speakers, and
   nobody has checked them.** They are one template — "I will send you the
   document tomorrow morning, after the standup" — carried across 29 languages.
   A clumsy or wrong translation makes that language look worse than the engine
   is. Treat a single bad language here as a question to investigate, never as a
   measurement.
2. **One sentence per language.** Twelve words cannot produce a word error rate
   worth the name. What this set can honestly answer is narrower and still worth
   having: does the transcriber come back in the right *script* at all, and does
   it keep the embedded English word in Latin letters, in 29 writing systems.

The embedded English word is deliberate and is the same test the `mix-*` clips
run for Hebrew: every one of these voices pronounces `document` and `standup`
through its own phonology, which is what a real speaker of that language does.

macOS only. Deterministic, destructive to `audio/`, safe to re-run.
"""

import json
import subprocess
import sys
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUDIO = HERE / "audio"

# (catalogue id, BCP-47 tag, `say` voice locale, sentence)
#
# The voice is chosen by locale rather than by name, so this survives a macOS
# that ships a different set — the generator asks `say -v '?'` for whatever it
# has for that locale and takes the first.
SENTENCES = [
    ("arabic", "ar", "ar_001", "سأرسل لك الـ document غدًا صباحًا بعد الـ standup"),
    ("bulgarian", "bg", "bg_BG", "Ще ти изпратя document утре сутринта, след standup."),
    ("catalan", "ca", "ca_ES", "T'enviaré el document demà al matí, després del standup."),
    ("croatian", "hr", "hr_HR", "Poslat ću ti document sutra ujutro, nakon standupa."),
    ("czech", "cs", "cs_CZ", "Pošlu ti ten document zítra ráno, po standupu."),
    ("danish", "da", "da_DK", "Jeg sender dig det document i morgen tidlig, efter standup."),
    ("dutch", "nl", "nl_NL", "Ik stuur je het document morgenochtend, na de standup."),
    ("finnish", "fi", "fi_FI", "Lähetän sinulle document huomenna aamulla, standupin jälkeen."),
    ("french", "fr", "fr_FR", "Je t'enverrai le document demain matin, après le standup."),
    ("german", "de", "de_DE", "Ich schicke dir das document morgen früh, nach dem standup."),
    ("greek", "el", "el_GR", "Θα σου στείλω το document αύριο το πρωί, μετά το standup."),
    ("hindi", "hi", "hi_IN", "मैं तुम्हें कल सुबह document भेज दूंगा, standup के बाद।"),
    ("hungarian", "hu", "hu_HU", "Holnap reggel elküldöm neked a document-et, a standup után."),
    ("indonesian", "id", "id_ID", "Saya akan mengirimkan document besok pagi, setelah standup."),
    ("italian", "it", "it_IT", "Ti manderò il document domani mattina, dopo lo standup."),
    ("lithuanian", "lt", "lt_LT", "Atsiųsiu tau document rytoj ryte, po standup."),
    ("malay", "ms", "ms_MY", "Saya akan hantar document esok pagi, selepas standup."),
    ("norwegian", "nb", "nb_NO", "Jeg sender deg document i morgen tidlig, etter standup."),
    ("polish", "pl", "pl_PL", "Wyślę ci document jutro rano, po standupie."),
    ("portuguese", "pt", "pt_PT", "Vou enviar-te o document amanhã de manhã, depois do standup."),
    ("romanian", "ro", "ro_RO", "Îți trimit document mâine dimineață, după standup."),
    ("russian", "ru", "ru_RU", "Я отправлю тебе document завтра утром, после standup."),
    ("slovak", "sk", "sk_SK", "Pošlem ti document zajtra ráno, po standupe."),
    ("slovenian", "sl", "sl_SI", "Poslal ti bom document jutri zjutraj, po standupu."),
    ("spanish", "es", "es_ES", "Te enviaré el document mañana por la mañana, después del standup."),
    ("swedish", "sv", "sv_SE", "Jag skickar dig document imorgon bitti, efter standup."),
    ("tamil", "ta", "ta_IN", "நான் நாளை காலை document அனுப்புகிறேன், standup க்கு பிறகு."),
    ("turkish", "tr", "tr_TR", "Sana document'i yarın sabah, standup'tan sonra göndereceğim."),
    ("ukrainian", "uk", "uk_UA", "Я надішлю тобі document завтра вранці, після standup."),
]


def voices():
    """Locale -> first voice name macOS offers for it."""
    listing = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, check=True).stdout
    found = {}
    for line in listing.splitlines():
        if "#" not in line:
            continue
        head = line.split("#")[0].strip()
        locale = head.split()[-1]
        name = head[: -len(locale)].strip()
        found.setdefault(locale, name)
    return found


def main():
    available = voices()
    missing = [locale for _, _, locale, _ in SENTENCES if locale not in available]
    if missing:
        print(f"no macOS voice for: {', '.join(missing)}", file=sys.stderr)

    AUDIO.mkdir(exist_ok=True)
    for stale in AUDIO.glob("*.wav"):
        stale.unlink()

    clips = []
    for language, tag, locale, sentence in SENTENCES:
        voice = available.get(locale)
        if voice is None:
            continue
        path = AUDIO / f"{tag}.wav"
        command = [
            "say", "-v", voice, "-r", "175", "-o", str(path),
            "--data-format", "LEI16@16000", "--channels", "1", sentence,
        ]
        subprocess.run(command, check=True)
        with wave.open(str(path)) as handle:
            seconds = handle.getnframes() / handle.getframerate()
        clips.append({
            "id": tag,
            "language": language,
            "tag": tag,
            "file": f"audio/{tag}.wav",
            "transcript": sentence,
            "embedded_english": ["document", "standup"],
            "duration_seconds": round(seconds, 3),
            "production": {"method": "macos-say-tts", "voice": voice, "locale": locale, "rate_wpm": 175},
        })
        print(f"  {tag:<4} {voice:<12} {seconds:>5.2f}s", file=sys.stderr)

    (HERE / "ground-truth.json").write_text(
        json.dumps(
            {
                "corpus": "AIKeyboard dictation — multilingual probe",
                "provenance": "SYNTHETIC. macOS `say` text-to-speech, sentences written by a language model and NOT checked by native speakers.",
                "warning": "One sentence per language. This cannot produce a word error rate worth the name. It answers two narrower questions: does the transcript come back in the right script, and does the embedded English word stay in Latin letters.",
                "template": "I will send you the document tomorrow morning, after the standup.",
                "clip_count": len(clips),
                "clips": clips,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    print(f"{len(clips)} clips", file=sys.stderr)


if __name__ == "__main__":
    main()
