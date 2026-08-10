# Dictation bar

36 audio clips with exact transcripts, plus a 29-language probe in `multilingual/`,
for measuring the word error rate (WER) of the transcriber the keyboard actually uses
(`CloudDictation`).

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

## Scores

Measured 2026-08-09 through `harness/transcribe.py` (Vertex `gemini-2.5-flash`,
`thinkingBudget: 512`, `temperature: 0`), scored by `harness/score.py`. The
request is the one `CloudDictation` builds — same system instruction, same
prompt, same schema with the same field descriptions and `propertyOrdering` —
because an earlier version of this harness sent a bare schema and therefore
measured a request the product does not send.

| | Hebrew | English | code-switched | all |
| --- | ---: | ---: | ---: | ---: |
| word error rate | 10.7% | 8.5% | 23.5% | **14.2%** |
| exact | 5/12 | 6/12 | 2/12 | 13/36 |

Named entities 38/60. English words kept in Latin letters inside Hebrew
sentences: **25/36** — the number to watch, because an engine that writes `סינק`
for `sync` scores a respectable WER against a transliterating reference and is
useless in this product.

**Word error rate flatters nobody here and punishes one thing unfairly.** The
prompt asks for digits, the references spell numbers out, so `בעשר וחצי` coming
back as `ב-10 וחצי` scores two errors while being exactly what a keyboard should
type. Six of the nineteen non-exact clips differ only, or mostly, in number
style.

### This bar is deterministic and the others are not

Two full runs of the identical configuration, minutes apart, came back **byte for
byte identical** — same transcripts, same trap failure. `Bar/ai-text` and
`Bar/screen-context` swing 1-5 points between runs and need two runs a side
before a delta means anything. This one does not, because `temperature: 0` over a
fixed audio file leaves almost nothing to sample. **Do not carry that property
across to the other two bars**, and re-check it if the model, the temperature or
the thinking budget moves.

### What the prompt is worth, one variant at a time

All four run in one sitting, committed under `ablation/`.

| variant | WER | entities | Latin kept | silence trap |
| --- | ---: | ---: | ---: | --- |
| baseline | 15.6% | 31/60 | 18/36 | invented "Hello" |
| + language hint | 16.3% | 32/60 | 20/36 | invented a sentence |
| + loanword rule | 14.3% | 36/60 | 24/36 | clean |
| **both (ships)** | **14.2%** | **38/60** | **25/36** | clean |

- **The loanword rule is the real win** and it is the examples that work, not the
  rule: `favor` heard through Israeli phonology comes back as `פייבור`, which is
  a faithful phonetic transcription and useless to somebody who meant to type
  `favor`. Worth 6 English words and 5 entities on its own.
- **The language hint is worth nothing here and ships anyway.** On this corpus it
  is neutral at best. It earns its place in `multilingual/`, below.

## Blocking finding, now routed around: no Apple API can transcribe Hebrew

Measured on macOS 26.5.1, build 25F80, Swift 6.2.3, by calling the APIs directly,
and pinned from the simulator by `LegacySpeechRecognizerLanguageTests` and
`SpeechLanguageTests`:

| API | Locales | Hebrew? | On-device Hebrew? |
| --- | --- | --- | --- |
| `SpeechTranscriber` (iOS/macOS 26) | 30 | **No** | n/a |
| `SFSpeechRecognizer` (legacy) | 63 | Yes (`he-IL`) | **No** |

`SpeechTranscriber.supportedLocales` is `de-*, en-*, es-*, fr-*, it-*, ja-JP,
ko-KR, pt-*, yue-CN, zh-*`. No `he`. Requesting `he-IL` logs `No Assistant asset
for language he-IL`.

So the choice is not "on-device or cloud", it is "cloud or nothing", and
`CloudDictation` is the consequence. That is a product fact worth saying out
loud rather than a fallback: **every dictated sentence in this product leaves the
device**, exactly as every Hebrew screen reading does.

**Caveat unchanged:** the table above was measured on macOS, not on an iOS 26
device. Apple's speech asset catalogs are usually shared across platforms, but a
device should confirm it before any architecture decision rests on it.

## The traps, and why the gate is not in the prompt

Three recordings with no words in them — digital silence, deterministic noise, a
440 Hz tone — generated by the harness rather than committed. They answer the one
question the 36 real clips cannot: **does the model invent a sentence when it
hears nothing?**

It does. Four seconds of digital silence came back as `speech: yes` and

> *"I'm not sure if I'm going to be able to make it to the meeting."*

reproducibly, in every variant of the first harness shape, and in two of the four
shipping-shape variants — including, at the best-scoring one, the same sentence
out of stationary noise. **The `speech` field does not save you**, and neither
does any wording tried so far. A keyboard that types a plausible message nobody
said, in the user's own voice, into somebody else's chat is the worst thing this
product can do.

So the question is answered on the device instead, by arithmetic, before anything
is uploaded. `SpeechGate` compares a quiet frame against the loudest one: speech
has gaps between words, a fan or a road or a held note does not.

| | peak | 10th-percentile frame | quietest/peak |
| --- | ---: | ---: | ---: |
| 36 real clips | 0.208 – 0.332 | 0.002 – 0.062 | **0.012 – 0.21** |
| trap-noise | 0.019 | 0.017 | 0.91 |
| trap-tone | 0.174 | 0.171 | 0.98 |
| trap-silence | 0.000 | 0.000 | — |

A factor of four either side of the 0.5 threshold. `SpeechGateTests` re-measures
that table from these same WAVs, so a threshold moved without re-measuring fails.

**Its honest limitation is this corpus.** Every clip is `say` output with true
digital silence between words; a phone in a car has room tone in those gaps,
which lifts the quiet frames toward the refusing side. The threshold leaves room
for that, and the remaining error is deliberately biased: a refusal costs one
more tap, a false accept can put an invented sentence in somebody's name.

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

## The other 62 languages

`multilingual/` is one sentence in each of the 29 catalogue languages macOS has a
voice for — the same template, each carrying an embedded English word. It exists
because this corpus speaks two of the 64 languages this keyboard ships, so it
cannot answer "does dictation work" as a claim about 64 alphabets.

It answers something narrower and still worth having: **29/29 came back in the
right writing system**, Arabic, Greek, Devanagari, Tamil and Cyrillic included.

It is also where the language hint earns its place. Without it, the Polish clip
came back transcribed as **Portuguese** and the Slovak one drifted to Croatian;
with the speaker's own keyboards named in the prompt, both are correct. That is
the failure that makes dictation useless rather than imprecise, and this corpus
is the only place in the repo that can see it. `multilingual/generate.py` carries
its own warnings — the sentences were written by a language model and no native
speaker has read them.

## Regenerate

```sh
python3 Bar/dictation/generate.py               # the 36 Hebrew/English clips
python3 Bar/dictation/multilingual/generate.py  # the 29-language probe
python3 Bar/dictation/harness/transcribe.py     # score either through the model
python3 Bar/dictation/harness/score.py
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
