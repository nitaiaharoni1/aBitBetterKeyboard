# Dictation bar

36 audio clips with exact transcripts, for measuring the word error rate (WER) of a real
speech engine in place of the scripted fake in `MockDictation`.

---

## Read this before you quote a number from this corpus

**Every clip is a computer voice. There is not one human recording here.**

They were produced with macOS `say` text-to-speech, because this machine has no microphone
access and no real recordings. Synthetic speech is cleaner, better enunciated, more evenly
paced and completely noise-free compared to a person talking into a phone on Ibn Gabirol
with a bus going past.

So:

> **A WER measured on this corpus is an optimistic ceiling, not a prediction of field
> accuracy. The real number will be worse. How much worse is unknown and cannot be
> estimated from this data.**

Passing here is **necessary but not sufficient**. It proves the engine is wired up, decodes
the audio format, handles the language mix, and returns text. It proves nothing about
whether the product works for an actual Israeli user. Do not present a number from this
corpus as evidence that dictation works.

---

## Blocking finding: SpeechTranscriber has no Hebrew

Measured on this machine (macOS 26.5.1, build 25F80, Swift 6.2.3) by calling the APIs
directly:

| API | Locales | Hebrew? | On-device Hebrew? |
| --- | --- | --- | --- |
| `SpeechTranscriber` (iOS/macOS 26, the one `plan.md` §6 wants) | 30 | **No** | n/a |
| `SFSpeechRecognizer` (legacy) | 63 | Yes (`he-IL`) | **No** (`supportsOnDeviceRecognition == false`) |

`SpeechTranscriber.supportedLocales` is `de-*, en-*, es-*, fr-*, it-*, ja-JP, ko-KR, pt-*,
yue-CN, zh-*`. No `he`. Requesting `he-IL` logs `No Assistant asset for language he-IL`.

What this means for the product:

1. The engine `plan.md` prefers **cannot transcribe Hebrew at all**, which is 24 of the 36
   clips here and the majority of the actual use case.
2. The only Apple path with Hebrew is the legacy `SFSpeechRecognizer`, and for Hebrew it is
   **cloud-only**. That removes the on-device privacy story and adds network latency.
3. This strengthens the case for Deepgram Nova-3 (Hebrew production model, Feb 2026) that
   `plan.md` §6 raises as the alternative.

**Caveat on that finding:** it was measured on macOS, not on an iOS 26 device. Apple's
speech asset catalogs are usually shared across platforms, but this must be re-confirmed on
a real iOS 26 device before any architecture decision rests on it.

---

## What is in here

| Group | Clips | Prefix | Content |
| --- | --- | --- | --- |
| Hebrew only | 12 | `he-*` | Israeli names (נועה, יואב, שירה, אבישי, רונית), companies (מובילאיי, פיטנגו, צ'ק פוינט), places (חיפה, כביש שש), work talk |
| English only | 12 | `en-*` | Startup/office English, Israeli names and companies inside it (Yotam, Ravit, Dor, Tel Aviv, Aleph, Wix) |
| Code-switched | 12 | `mix-*` | Hebrew sentences with English words inside, the way people actually talk: `בוא נעשה sync קצר על ה-roadmap של Q3` |

All 36 clips are between 3.0 and 6.3 seconds; 156 seconds total; 5.0 MB.

### Voices

- **Hebrew and code-switched (24 clips): `Carmit` only.** She is the *only* `he_IL` voice
  macOS ships. So the entire Hebrew half of this corpus is one speaker, one gender, one
  accent, no variation. Rate is varied 150-200 wpm to add a little spread, and that is the
  only spread there is.
- **English (12 clips): `Samantha` (en_US), `Daniel` (en_GB), `Karen` (en_AU), `Moira`
  (en_IE), `Tessa` (en_ZA), `Rishi` (en_IN), `Tara` (en_IN), `Aman` (en_IN),
  `Zoe (Premium)` (en_US)**, at 155-200 wpm.

### Audio format

WAV, 16-bit signed little-endian PCM, 16 kHz, mono. Convert to whatever
`SpeechTranscriber.bestAvailableAudioFormat(compatibleWith:)` reports before feeding
`SpeechAnalyzer`; do not assume 16 kHz is accepted verbatim.

### `ground-truth.json`

One entry per clip: exact transcript, `language_mix` (`he` / `en` / `he-en`), duration,
token counts split by script, `named_entities`, and the full `say` command that produced it
so any single clip can be regenerated on its own.

**Scoring:** compute WER on a normalized form (case-folded, punctuation stripped, Hebrew
maqaf/hyphen handled consistently). `ה-roadmap` vs `ה roadmap` is a formatting difference,
not a recognition error. Score `named_entities` separately: for this product, getting
"מובילאיי" and "Figma" right matters more than raw WER.

---

## Regenerate

```sh
python3 Bar/dictation/generate.py
```

macOS only. Deterministic, destructive to `audio/`, safe to re-run. It refuses to run if no
`he_IL` voice is installed rather than faking Hebrew with an English voice reading
transliteration, which would make this bar actively misleading.

---

## Limitations, in order of how badly they flatter the engine

1. **No human speech.** No breath, no filler ("אה", "כאילו"), no false starts, no
   self-correction mid-sentence, no trailing off. Real dictation is full of these and they
   are where engines break.
2. **No acoustic variation.** No background noise, no music, no second speaker, no street,
   no car, no room reverb, no phone-held-at-arms-length. Every clip is studio-clean at a
   constant level.
3. **One Hebrew speaker.** Carmit, for all 24 Hebrew and code-switched clips. No male
   voice, no Mizrahi or Russian or Arabic-influenced Hebrew accent, no old, no young, no
   fast mumbling. Israeli Hebrew is far more varied than one TTS voice.
4. **Native-accented English.** The English clips are US/UK/AU/IE/ZA/IN voices. **None of
   them is Israeli-accented English**, which is what the product will actually hear. This
   makes the English number specifically optimistic in a way the Hebrew number is not.
5. **TTS prosody is not human prosody.** `say` gets stress and intonation from a rule
   engine. It is more regular than a person, which helps the recognizer.
6. **Written sentences, not spoken ones.** These were composed as text. People speak in
   looser, less grammatical, more run-on chunks.
7. **Code-switching is approximated.** Carmit pronounces the embedded English words with
   Hebrew phonology, which is genuinely what Israelis do, so this is the most defensible
   part of the set. But it is still one voice's rule-based guess, not a bilingual speaker
   switching naturally.
8. **Small.** 36 clips, 156 seconds. Not enough for a statistically meaningful WER. A
   couple of unlucky clips will swing the number several points.

## What was actually verified

- **English audio: verified intelligible.** Transcribed back through the real
  `SpeechTranscriber` on macOS 26.5.1. `en-01` came back exactly right; `en-03` came back
  right apart from formatting ("stand-up", "915") and "Yottam" for "Yotam".
- **Hebrew audio: not machine-verified.** `SpeechTranscriber` has no Hebrew, and
  `SFSpeechRecognizer` aborts under TCC from a command-line binary without a signed bundle.
  The audio is Apple's own Hebrew voice reading valid Hebrew, so it is well-formed by
  construction, but nobody has listened to it.
- **Embedded English words: checked crudely, not by ear.** Carmit renders "sync" in 0.50s
  versus 1.04s for the spelled-out form, and "roadmap" 0.59s, "deploy" 0.54s, "production"
  0.71s, "standup" 0.62s, "Figma" 0.48s. Those are all single-word durations, so she is
  reading them as words rather than spelling them out. **How good the pronunciation is was
  not assessed.** A human should spot-check the `mix-*` clips before anyone trusts the
  code-switched numbers.

## What a real corpus needs

`plan.md` §6 calls for **100-500 genuine Israeli recordings** before picking an STT vendor,
and it is right. Specifically:

- Real people, 20+ distinct speakers, mixed gender and age, spread across Israeli Hebrew
  accents.
- Recorded on phones, in the places people actually dictate: street, car, open-plan office,
  kitchen with kids.
- Natural code-switching from bilingual speakers, not TTS.
- Israeli-accented English, not native English.
- Hand-transcribed ground truth with an agreed convention for how English-in-Hebrew is
  written down.
- Held-out split, so vendor selection is not tuned on the same clips it is scored on.

Until that exists, treat every number produced from this directory as a smoke test.
