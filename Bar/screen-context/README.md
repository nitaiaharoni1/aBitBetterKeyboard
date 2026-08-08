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
```

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

**`VisionScreenReader`** — accepts 9 of 30 screens (9 English, **0** Hebrew,
**0** mixed), then answers 5 of those 9 and refuses 4. Refusing is correct in
all four: one is the voice-note screen with nothing to reply to, three are
one-sided Slack layouts where no geometry says who sent what. On the 5 it
answers: sender 5/5, keyboard language 5/5, message 4/5 exact and 5/5 within
90%, no traps, no off-screen text. It answers only when it is right.

**`CloudScreenReader`** — all 30 screens: sender 29/30, keyboard language 29/30,
script 29/30, message 19/30 exact and 26/30 within 90%. No traps, no off-screen
text. Median 5.3s, p90 6.4s.

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
