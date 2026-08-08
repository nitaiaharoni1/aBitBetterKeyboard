# Screen-context corpus

Thirty chat screenshots at iPhone 17 Pro resolution, plus the ground truth for what each one
contains. The bar that `MockScreenContext` has to clear when it is replaced by real Vision OCR.

`MockScreenContext` currently returns three hardcoded `ScreenContext` values: an app name, a
sender, a message, a language. This corpus is the same shape of answer, thirty times, against
pixels instead of a literal.

## Reproduce

```sh
cd Bar/screen-context
npm install
npm run generate      # or: node generate.mjs
```

Rewrites `images/` and `ground-truth.json` from scratch in about three seconds. The Playwright
Chromium build is already in `~/Library/Caches/ms-playwright`; if it is not,
`npx playwright install chromium` fetches it.

## What is here

| File | |
| --- | --- |
| `scenes.mjs` | The corpus as data: thirty conversations, their hard cases, their traps |
| `skins.mjs` | HTML/CSS renderings of WhatsApp, Slack, Messages, Telegram and Mail |
| `generate.mjs` | Screenshots each scene and measures the ground truth off the rendered page |
| `images/*.png` | 30 screenshots, 1206x2622 px (402x874 pt at 3x) |
| `ground-truth.json` | Per image: full visible text, the fields the product needs, and the chrome |

The apps are reproduced, not installed. Each skin matches the real app's type sizes, bubble
colours, corner radii, spacing, wallpaper and right-to-left handling closely enough that the OCR
problem is the same shape: same contrast, same bubble-on-background, same chrome crowding the
text. They are not pixel-identical and are not meant to be.

## The two questions the corpus asks

**Can you read the pixels.** `fullText` is every line visible on screen in reading order, fused
the way Vision fuses them, so `D  Daniel Cohen  10:24 AM` arrives as one line directly above the
message body.

**Can you pick the right line.** That is the part that decides whether the feature ships.
`expected` holds the three fields a real implementation must produce:

```json
"expected": {
  "sender": "Daniel Cohen",
  "message": "Can you take the standup tomorrow? I have a conflict at 9.",
  "language": "english",
  "script": "latin",
  "messageLines": ["Can you take the standup tomorrow? I have a", "conflict at 9."],
  "fullyVisible": true
}
```

`language` is what the keyboard switches to (`hebrew` or `english`, mirroring
`KeyboardLanguage`). `script` is separate and finer: `hebrew`, `latin` or `mixed`. A message can
be `language: "hebrew"` and `script: "mixed"`, which is most of how Israelis actually write.

Against that sit the fields that say what a correct implementation must *not* return:

- **`chrome`**: every non-message run on screen. Nav bars, sender labels, timestamps, delivery
  receipts, reaction counts, date dividers, composer placeholders, keyboard key caps. 600 runs
  across the corpus. Reading them is fine; returning one as the message is a failure.
- **`traps`**: the 74 specific runs most likely to be returned instead, each with the reason.
  A link preview headline, a quoted reply, a forwarded news blurb, a contact saved as
  `מרפאת שיניים - ד"ר לוין`, the user's own bottom-most bubble.
- **`notOnScreen`**: text measured as unreadable, either clipped by an edge or covered by the
  keyboard, with which. Returning any of it means hallucinating.
- **`lastMessageIsOutgoing`** / **`noRepliableText`**: flags for the two shapes of screen where
  the obvious answer is wrong.

`messagesOnScreen` lists every message body for partial credit.

## Ground truth is measured, not typed

`generate.mjs` screenshots the page, then walks it line by line and asks two questions per line:
is it inside the clip box of every scrolling ancestor, and does a hit test at its centre still
reach it? A line that fails either is off the top of the thread or under the keyboard, and it
does not enter the ground truth no matter what `scenes.mjs` claims.

That is what makes the awkward cases trustworthy. In `wa-06` the corpus says the newest message
is cut through its middle and the answer is only its visible tail; it says so because it measured
the clip. In `sl-05` it says three messages are under the keyboard; it verified they have zero
visible lines. The generator throws rather than emit a claim it cannot prove:

- a scene tagged `scrolled-off-top` with nothing actually clipped
- a scene tagged `keyboard-occludes-newest-message` with nothing actually covered
- a message declared truncated that renders whole
- an expected message whose text does not match the pixels on screen

## The third question: can you tell two screens apart

The corpus answers one more question, and it is not about OCR at all. `CaptureFreshness`
condition 4 decides whether a reading may still be shown, and it is a single exact-equality
test between the frame the reading was taken from and the newest frame the capture process
has seen. Get the fingerprint wrong in one direction and a reply written about somebody
else's message is offered as current; wrong in the other and every good reading is retired
before it can be used.

```bash
node harness/frame-hash.mjs             # sweeps 7 bands x 3 values, ~2 min
KEEP=1 node harness/frame-hash.mjs      # leave the 210 renders in harness/frame-hash-out/
harness/run-fingerprint.sh              # holds the *shipping* Swift to the same bar
```

Thirty different scenes look different, so the corpus cannot answer this on its own. The
harness builds the near pairs instead: seven renders per scene.

| Render | |
| --- | --- |
| `base` | the scene as the corpus renders it |
| `twin` | every message's letters substituted inside its own script — same character count, word breaks, times and bubble geometry, every glyph different |
| `last` | the same substitution applied to the newest text message only |
| `chrome` | no message touched: the clock ticks over and the header presence line changes |
| `panel` | **our own keyboard** on screen, AI result panel open, `AIResultPanel.loading` at shimmer phase 0.10 |
| `panel2` | the same frame at shimmer phase 0.60 |
| `panellast` | `last`'s conversation switch, under our panel at phase 0.10 |

`last` is the collision test and `chrome` the false-invalidation test. The three `panel`
renders are the same two tests asked of the state a reading is *actually* measured in: a
reading exists only because the user tapped Reply on our keyboard, so our keyboard is on
screen for the whole five-second read, repainting three shimmer lines at 60 Hz. On an
iPhone 17 Pro it covers 292 pt of 874 pt — 32% of the fingerprint band.

Measured 2026-08-08, SHA-256 of the 32x64 reduction:

| Band removed | miss | false | own miss | own false |
| --- | --- | --- | --- | --- |
| top 6.5% / bottom 45% | **23/29** | **19/30** | 3/29 | 0/30 |
| top 6.5% / bottom 8.5% | 0/29 | **19/30** | 0/29 | **30/30** |
| top 14% / bottom 8.5% | **0/29** | **0/30** | 0/29 | **30/30** |
| **top 14% / bottom 33.4%, ours excluded** | 20/29 | **0/30** | **0/29** | **0/30** |
| top 14% / bottom 40%, the clamp | 20/29 | 0/30 | **0/29** | **0/30** |

`miss` and `false` are scored with the host's keyboard or none; `own miss` and `own false`
with ours. `sl-05` is excluded from both miss columns and reported separately: its newest
message is drawn under a keyboard, so those two renders are byte-identical and no
fingerprint of any width can separate them.

The `30/30` is a shipping blocker this variant was added to catch. The harness used to
render only a static system keyboard, so its "0 misses, 0 false invalidations" was a
statement about a frame nobody ever sees. With our own panel on it, the same band gives
every single sampled frame a new identity from nothing but our animation — the freshness
gate then refuses the answer to the very tap that paid for it, twelve seconds and one cloud
call after the user asked.

So the band is chosen per frame: `VisionScreenReader.Band` when no keyboard of ours is up,
and that band with our own rows removed when one is. The keyboard publishes the fraction it
covers in `CaptureIntent.ownUIHeightPermille` and `FrameReduction.bottomCrop(ownUI:)` acts
on it, clamped to 0.40 — the last row of the table, measured rather than assumed, because
past it lies the 45% band and 23 of 29 missed conversation switches. The `20/29` in the miss
column of the last two rows is that split rather than a defect: those bands are never used
on a frame our keyboard is absent from.

`run-fingerprint.sh` compiles
`Packages/AIKeyboardCore/Sources/AIKeyboardShared/FrameFingerprint.swift` itself and scores
both configurations with CoreGraphics decoding and the shipping integer box filter instead
of Chromium's resampler, so the two harnesses do not share a resampler and a design that
only worked with one of them would show up. It also carries a witness check: over the band
that does *not* exclude our keyboard, the shimmer still moves the identity on 30/30 scenes.
A harness that cannot fail proves nothing.

## Coverage

30 images. 15 light, 15 dark.

| | WhatsApp | Slack | Messages | Telegram | Mail |
| --- | --- | --- | --- | --- | --- |
| light / dark | 4 / 4 | 3 / 3 | 4 / 3 | 2 / 3 | 2 / 2 |
| hebrew / english / mixed | 4 / 2 / 2 | 0 / 5 / 1 | 3 / 2 / 2 | 2 / 1 / 2 | 1 / 2 / 1 |

10 Hebrew, 12 English, 8 mixed (Hebrew body carrying English words like `build`, `rebase`,
`App Group`, `feedback`). 18 of 30 contain Hebrew.

18 screens use a left-to-right layout and 12 mirror to right-to-left. Both matter: a phone set to
Hebrew mirrors the whole app and puts incoming bubbles on the right, while a phone set to English
leaves the chrome left-to-right and right-aligns only the message text. Most Israeli users are
the second case, so the corpus covers both.

### Hard cases

| Case | Images |
| --- | --- |
| Long message scrolled off the top | `wa-04` `wa-06` `sl-03` `tg-04` `ml-03` |
| Newest message cut through its middle, only the tail readable | `wa-06` |
| Keyboard covering the bottom third | `wa-06` `im-05` `tg-04` `sl-05` |
| Keyboard covering the newest messages outright | `sl-05` |
| Last message is the user's own, not the other person's | `wa-05` `im-03` `tg-03` `ml-04` |
| Nothing repliable on screen (voice note) | `wa-07` |
| Emoji and reaction counts touching the text | `wa-02` `im-02` `sl-02` `tg-02` `tg-05` |
| Sender name and timestamp run into the message | `sl-01` `sl-03` `sl-06` `im-04` `tg-04` `tg-05` |
| Sender name that parses as a sentence | `wa-01` `im-05` `tg-04` |
| Reply quote inside the newest bubble | `wa-08` `tg-01` |
| Forwarded message with an attribution label | `tg-02` |
| Link preview that reads like a message | `sl-04` `im-06` |
| Group chat, several senders | `wa-03` `im-04` `tg-04` `tg-05` |
| Bot / app posts | `sl-03` `sl-06` |
| Unread divider mid-thread | `sl-06` |
| Two date dividers on one screen | `im-04` |
| Image bubble with no text, caption below | `im-07` |
| Mail: subject line, signature block, quoted history | `ml-01` `ml-02` `ml-03` |
| Latin sender name on a Hebrew body | `ml-03` |
| Encryption notice rendered as a bubble | `wa-01` |

## Adding a scene

Append to `scenes.mjs` and rerun. The renderer tags every run of text `data-role="msg"` or
`data-role="chrome"`, and the generator derives the answer as the newest incoming message with a
body. When that derivation is wrong (which is the whole point of the hard cases), mark the real
answer with `target: true` on the message and explain why in `expectedOverride.reason`.

## Scoring an engine against this bar

```bash
cd harness

# Apple's on-device recogniser, raw. Writes ../vision_outputs.json.
xcrun -sdk macosx swiftc -O vision.swift -o /tmp/scvision
/tmp/scvision ../ground-truth.json ../vision_outputs.json
python3 score_ocr.py vision_outputs.json          # character recall of the message

# The shipping VisionScreenReader, compiled from the real sources.
bash run-reader.sh                                # writes ../reader_outputs.json

# The cloud reader. Needs a gcloud login; ~25s for all 30.
python3 vertex_vision.py                          # writes ../cloud_outputs.json
python3 score_cloud.py cloud_outputs.json         # sender / message / language

# The shipping path, end to end: every frame goes through
# ScreenContextSession.submit(_:appName:appIcon:) -> RoutedScreenReader ->
# VisionScreenReader or CloudScreenReader. Only the network is replaced, by a
# transport replaying cloud_outputs.json, so the run needs no credential and
# makes no network call. Writes ../routed_outputs.json; ~30s.
xcodebuild test -project ../../../AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination "platform=iOS Simulator,id=0966F3D6-2589-4E88-BE84-4A69CD64FEE8" \
  -only-testing:AIKeyboardCoreTests/ScreenContextBarTests
python3 score_cloud.py routed_outputs.json
```

The last one is the number the product actually delivers, and it is the only one
of the four that measures the composition rather than a part. `AIKeyboardCoreTests/
ScreenContextBarTests.swift` ports `score_cloud.py`'s scorer into Swift so the run
asserts its own numbers; the two agree cell for cell on `routed_outputs.json`, which
is what makes the port checkable rather than a second opinion.

`score_ocr.py` answers "did the recogniser put the text on the page at all",
which is the only fair question to ask a raw OCR pass. `score_cloud.py` answers
the product's question — sender, message, keyboard language — and counts two
things separately from near-misses: returning a string the bar lists under
`traps`, and returning text the bar records as not being on screen.

## What the engines actually score

Measured 2026-08-08. Every number below is the same across repeated runs.

**Apple Vision, raw OCR** — character recall of the expected message:

| | English (12) | Mixed (8) | Hebrew (10) |
|---|---|---|---|
| recall | **100%** | 34% | 13% |

Hebrew is not in `supportedRecognitionLanguages()` on either iOS or macOS, and
adding `ar-SA` changes these numbers by nothing at all. The 13% is incidental
overlap on digits, spaces and Latin loanwords, not reading. The 34% on mixed
screens is worse than it looks: it is the English words *inside* Hebrew
sentences, which is the wrong half of the message.

**`VisionScreenReader`, run by `run-reader.sh` on macOS** — accepts 9 of 30
screens (9 English, **0** Hebrew, **0** mixed), then answers 5 of those 9 and
refuses 4. Refusing is correct in all four: one is the voice-note screen with
nothing to reply to, three are one-sided Slack layouts where no geometry says who
sent what. On the 5 it answers: sender 5/5, keyboard language 5/5, message 4/5
exact and 5/5 within 90%, no traps, no off-screen text. It answers only when it
is right.

**The same reader on iOS does not do that.** Run on the simulator by
`ScreenContextBarTests` it accepts **10** and answers **7**, and three of those
answers are wrong. Same source files, same pixels, same thresholds:

| | accepts | answers | wrong |
|---|---|---|---|
| macOS (`run-reader.sh`) | 9 / 30 | 5 | 0 |
| iOS Simulator (`ScreenContextBarTests`) | 10 / 30 | 7 | 3 |

- `ml-01` is a **gate** difference. macOS measures mean confidence 0.896, just
  under the 0.90 threshold, and refuses. The simulator clears it and returns the
  quoted history the user wrote themselves, with `0` as the sender.
- `wa-07` and `sl-05` pass the gate on both, and the recogniser puts different
  lines on the page. `wa-07` is the screen whose correct answer is silence; iOS
  answers it with `hey are you around? 13:40`, which is the bar's own trap plus a
  bubble timestamp. `sl-05` comes back as `X n m C V Z` from a sender called `b`,
  which is keyboard key caps.

The one property that holds on both platforms is the one the routing depends on:
**zero** Hebrew and **zero** mixed screens are accepted on device. So the split
is still safe; it is the "answers only when it is right" half that is macOS-only.
`run-reader.sh` says in its header that "Vision ships the same recognition models
on both platforms". Measured over these 30 images, it does not.

**`CloudScreenReader`** — all 30 screens: sender 29/30, keyboard language 29/30,
message 19/30 exact and 26/30 within 90%. No traps, no off-screen text. Median
5.3s, p90 6.4s. (`script` is 25/30 against the current `cloud_outputs.json`, not
the 29/30 this line used to claim; `score_cloud.py` computes the column but does
not print it, so the number went stale unnoticed. The four misses are all the
model calling a Hebrew message `mixed` because it contains digits.)

Two prompt changes are worth more than they look, and both are recorded in
`CloudScreenReader`'s doc comment: making the model enumerate every bubble
before naming one took sender from 21/30 to 29/30, and splitting `script` from
`language` took the keyboard-language call from 22/30 to 29/30. Flattening the
enumeration into a JSON string costs 7 points of message accuracy, which is why
`CloudField` carries nested `items`.

Two changes measured *worse* and were reverted rather than kept on the theory
that they should help: a paragraph explaining bubble tint and edge, and "a
printed name always means the message is incoming". Both are listed in the same
doc comment so nobody re-adds them.

### The shipping path — the only number the product delivers

`ScreenContextSession` + `RoutedScreenReader`, driven frame by frame through
`submit(_:appName:appIcon:)` with the cloud half replaying `cloud_outputs.json`.
Measured on the simulator by `AIKeyboardCoreTests/ScreenContextBarTests.swift`,
scored by `score_cloud.py routed_outputs.json`:

| | n | message | +near | sender | language |
|---|---|---|---|---|---|
| english | 12 | 6 | 1 | 7 | 9 |
| mixed | 8 | 3 | 4 | 7 | 7 |
| hebrew | 10 | 5 | 3 | 10 | 10 |
| **ALL** | **30** | **14** | **8** | **24** | **26** |

Exact message 47%, exact-or-near 73%. Split by which engine answered:

| engine | frames | message | +near | sender | language |
|---|---|---|---|---|---|
| `VisionScreenReader` | 10 | 4 | 1 | 5 | 7 |
| `CloudScreenReader` | 20 | 10 | 7 | 19 | 19 |

On device: `wa-04 wa-07 sl-01 sl-03 sl-05 sl-06 im-01 im-06 tg-03 ml-01`, median
0.94s, p90 1.06s. Everything else goes to the cloud, which is every Hebrew and
every mixed screen plus three English ones.

**This is 5 points of sender, 3 of keyboard language and 5 of exact message below
the cloud reader on its own**, and none of it is the cloud reader getting worse.
Two separate defects account for all of it, and each has a test named after it:

1. **`RoutedScreenReader` only falls back on a thrown error.**
   `VisionScreenReader` declines two different ways: it *throws*
   `.notReadableOnDevice` when its readability gate fails, and it *returns nil*
   when the gate passed but a one-sided layout left no geometry to say who sent
   what. Its own doc comment says of the second case that "the router turns it
   into a cloud call rather than a wrong name" — it does not, because nil is an
   answer. `sl-01` and `sl-03` carry plain, answerable English messages that the
   cloud transcribes correctly, and the user is offered nothing on both.
   (`testTheRouterDropsAnswerableScreensInsteadOfAskingTheCloud`.)
2. **iOS Vision is not macOS Vision**, as above: `wa-07`, `sl-05` and `ml-01`.
   (`testTheShippingPathScoresTheBar`, the `disagreesWithHarness` assertion.)

What does *not* differ is the cloud half. On all 20 frames that reach it, the
shipping path's `sender`, `message` and `language` are byte-identical to
`cloud_outputs.json`: same prompt (`ScreenPrompt.instructions` is asserted
against the request the transport receives), same field order, same parse. The
only field that moves is `script`, on `wa-06`, `im-02`, `im-05` and `ml-02`,
because `CloudScreenReader.parse` discards the model's `script` answer and
recomputes it from the transcribed text with `LanguageDetector`. That is worth
knowing but not worth fixing: on those four the recomputed answer is the *right*
one, and `ScreenContext` does not carry `scripts` anyway, so nothing downstream
reads it.

One more thing this run turned up about the bar itself rather than the product:
**`traps` is an exact-string check**, so a trap returned with chrome glued to it
counts as an ordinary near-miss. Three answers contain a named trap and score
zero traps — `wa-07` (the trap plus a timestamp), `ml-01` (quoted history) and
`ml-02`, which is a *cloud* answer, so the "no traps" on the `CloudScreenReader`
line above carries the same caveat. `ScreenContextBarTests` counts containment
separately rather than widening `score_cloud.py`, because changing the bar's
scorer would move every published number on this page at once.
