# aBitBetterKeyboard

A Hebrew/English iOS keyboard with AI text actions, dictation, and a Reply that
answers the message you copied.

**The AI is real; one of its inputs is held back.** Text actions, screen reading
and dictation call real models and are scored against frozen corpora in `Bar/`.
Screen capture is built all the way up to the read: the app hosts Apple's
broadcast picker, a broadcast upload extension fingerprints frames into a shared
page, the keyboard asks it for a reading when you tap Reply, and the capture
process answers by encoding one frame and reading it in the cloud. The whole loop
is written, and **none of the ReplayKit half has ever run**, because the iOS
Simulator ships no `replayd`, so no frame has ever reached any of it.

**So it is not in v1.** `FeatureFlags.screenCaptureReply` is `false`, every entry
point that could start a broadcast is gated on it, and nothing is deleted: 3,792
lines of transport stay in the tree behind the flag (counted 2026-08-18), with a
named condition for turning it back on — NIT-6 passing on a phone, plus NIT-12's
memory number under the ~50 MB cap. **Reply's v1 source is the pasteboard
instead**: copy the message you are answering, let it in with CopyClip's Paste,
then tap Reply. Three taps rather than two, and the middle one is not a
formality: reading the pasteboard's contents outright is what raises iOS's
"Allow Paste?" alert, so Apple's own `UIPasteControl` in the CopyClip panel is
the only route in and the user's tap on it *is* the permission. No entitlement, no
broadcast, and no alert. The reasoning, the line counts and the exact flip
condition are in `.claude/docs/screen-capture-v1-hold.md`.

`ReplySource` (NIT-162) is what picks between the three: the scripted sample, a
live capture session, and the newest clip in the CopyClip ledger. It is in the
tree and reads as finished; nothing here has run it, so treat it as written
rather than measured. **What it costs is stated in the type rather than hidden**:
a keyboard cannot read the pasteboard's contents without either the iOS paste
alert or a tap on `UIPasteControl`, so the message has to reach the CopyClip
ledger before Reply can see it, and a pasteboard that has moved since the ledger
last caught up makes Reply refuse rather than answer the clip behind it. The
table at the end says which parts are measured and which are only compiled.

```
AIKeyboard.xcodeproj
├── AIKeyboard/               companion app
├── AIKeyboardExtension/      the keyboard extension (thin host)
├── AIKeyboardBroadcast/      ReplayKit broadcast upload extension (capture)
├── AIKeyboardUITests/        screenshot walkthrough
├── AIKeyboardCoreTests/      unit tests over AIKeyboardCore
├── Bar/                      frozen corpora the engines are scored against
└── Packages/AIKeyboardCore/  design system, keyboard UI, engines
```

The entire keyboard lives in `AIKeyboardCore`, not in the extension target. The
extension is a thin host for `KeyboardView`. That split is deliberate: it
lets the companion app render the *real* keyboard in onboarding and in the
playground, so the product can be felt before iOS has been talked into
installing anything.

## Running it

```bash
open AIKeyboard.xcodeproj      # ⌘R, iPhone 17 Pro simulator
```

To use it as an actual keyboard, install the app, then Settings → General →
Keyboard → Keyboards → Add New Keyboard → aBitBetterKeyboard. Everything except the
system key-click works without Full Access.

The fastest way to see it is Home → **Try the keyboard**, which runs the same
keyboard against an in-memory document.

Swift files are formatted with Apple's `swift-format` (bundled with Xcode), using
the 4-space `.swift-format` config at the repo root:

```bash
xcrun swift-format --in-place --recursive \
  AIKeyboard AIKeyboardExtension AIKeyboardBroadcast AIKeyboardUITests AIKeyboardCoreTests Packages
```

## What's built

**Keyboard**
- English QWERTY and Hebrew layouts with system-matched metrics (42pt keys,
  6/12pt gaps), press callouts, accelerating delete, shift/caps, numbers and
  symbols planes
- Hebrew is 8/10/9 keys and has no shift key. Delete sits on a strictly shortest
  top row (Hebrew is currently the only one); otherwise it stays on the bottom.
  Every key row is pinned left-to-right, matching Apple's physical key order
  rather than mirroring for right-to-left
- **Landscape, on iPhone only.** The action row is shed for height and its five
  controls are redrawn as chips on the suggestion bar, whose row is already paid
  for, so nothing is unreachable sideways and nothing costs extra height. The
  budget is not a constant: the frame-fingerprint cap is a *fraction* of screen
  height (0.4210526) while the metrics spend points, and a phone's landscape
  height is its portrait width, so it is a different number on every device.
  Landscape spends 154pt, break-even 365.75, below every width this ships to.
  That margin was wrong twice before it was measured — `LandscapeGeometryTests`
  walks all eight shipping widths now rather than the reference one, which is
  what makes the number mean anything
- **Dynamic Type above the default size**, on the glyph rather than on the key.
  `Theme.DynamicType.scale(for:)` is Apple's Body ramp read relative to `.large`,
  the size every hardcoded number here was tuned against. Key height deliberately
  does not move: the user already chose it in the layout editor, and
  `keyAreaHeight` feeds the 368pt cliff above. A cap grows from about 25 to 32 on
  a shipped 43pt key and then holds, and it is floored at its base size so the
  compressed numbers row cannot end up *smaller* than the build without Dynamic
  Type — which it did once, on the space bar, at the setting most people are on.
  Control icons (shift, backspace, globe, return) do not scale, matching Apple's
  own keyboard; the caption under an action key does
- Language switching by sliding along the space bar or tapping the globe, one
  language per gesture either way, with the space bar naming where the slide is
  going while the thumb is still down. The keyboard opens on the language it was
  left on rather than on the head of the enabled list, and moves off a language
  only when its owner switches that language off in the app
- Suggestion bar with three fixed slots edge to edge; the AI actions live in a
  row above the keys, and both of the bar's ends ship empty
- Select a whole word anywhere in the field and the bar answers about *that*
  word: corrections for a misspelling, inflections for one that is already right
  (`receive` offers `received` and `receiver`). A tap swaps it in place, adds no
  space, and the next space bar does not second-guess the word you picked
- Code-switching predictions: Latin words typed inside a Hebrew sentence get
  offered from a loanword list and tagged with the language they came from
- Emoji panel, nine categories, plain Unicode with no bundled images. Hold a
  hand or a face and a strip of the six skin tones opens over the grid; the
  one you lift on is the one the whole panel is drawn in from then on
- AI actions: Reply, Fix, Rewrite, Tone. Each writes its answer straight into the
  field, with a progress line above the suggestion bar while the model is
  thinking and an undo button beside the candidates. **The undo survives typing**,
  which it did not use to: `RevertibleEdit.rebased(onto:)` and `.spanUndo(behind:)`
  locate what the edit wrote *inside* the document and put back exactly that span,
  so a clause typed after a Fix is still there once the Fix is taken back. It
  retires on three conditions, and only two of them are about safety: what it
  wrote is gone, or what it wrote appears more than once and nothing can say which
  occurrence this edit made. The third is `RevertibleEdit.charactersOfTypingAllowed`,
  60 characters, roughly a line of a chat message — a stated guess rather than a
  measurement, and its own comment says it is the suggestion bar buying back the
  ~52pt that the undo control costs its three candidate slots, not a safety bound.
  Reply answers the message you copied — `Prompts.reply(for:)` reads `message` and
  `language` and nothing else, so it always needed the *text* of the message
  rather than a picture of it, and the CopyClip ledger already had one. Three of
  `ScreenContext`'s five fields come back empty from a clip and are deliberately
  left empty: inventing a sender would put a stranger's name into the prompt and,
  in Hebrew, into the grammatical gender the reply is written in. The
  screen-capture source is behind `FeatureFlags.screenCaptureReply` and off
- Dictation driven by a real recording, with the words appearing in the field as
  they are spoken rather than all at once at the end. The live words come from
  Apple's own on-device dictation model, free and offline; the cloud transcript
  replaces them when you stop, because that is the one measured to keep English
  loanwords in Latin letters inside Hebrew. The microphone key is the whole
  control: it starts, it turns record red while listening, it stops. The
  microphone itself is held by the companion app, because a keyboard cannot open
  one — see below
- Screen-context strip: the capture indicator, the message that was read, and
  one-tap Reply; it also carries "paused" and "stopped unexpectedly, restart it
  in aBitBetterKeyboard". Written and unit-tested, and unreachable in v1 while
  `FeatureFlags.screenCaptureReply` is false, because nothing can raise the
  session it renders

**Companion app**
- **Onboarding is three screens, down from ten** (NIT-15): welcome, add the
  keyboard, type a sentence. Five more sit behind a "Show me more" button on the
  last of those three — palette, languages, microphone, and the other two
  practice stages — because every screen in front of a first useful keystroke is
  a place people leave, and none of those five gated anything. The old standalone
  switch step was *merged into* add-keyboard rather than demoted, so
  `hasAcknowledgedKeyboardSwitch` is still collected on the required path: the
  merged step's primary button is still the globe-key confirmation.
  `OnboardingStep.required` and `.extras` hold the ordering, so the two lengths
  cannot disagree with a hand-written tab tag the way `switchStep = 4` once did
- **There is no Full Access ask anywhere in onboarding.** It is a status row plus
  one consequence line on the add-keyboard step, the same note beside the
  language picker, and the ask itself on Home's setup card, where it is next to
  the thing it buys
- Home with session state, setup checklist and playground. There is no stat row;
  it read "1,284 words fixed" and "37m time saved", both invented constants, and
  neither is measurable today
- Keys: the layout editor. Drag keys between rows, three height bands, a number
  row, one-handed reach, five presets, and a canvas that is the live
  `KeyboardView` rather than a preview of it. **The Grouped keys picker that sat
  under it is gone, and only the control went.** It printed the measured top-1
  rate beside each `GroupedKeys.Level`, out of `Bar/grouped/results.json` — the
  note left in `KeysView.swift` quotes "the right word is chosen 91% of the time
  in English", and which row of that file the figure came from is not re-derived
  here. The number being honest is the problem: a buyer reads it as "the wrong
  word one time in ten", which is a research result wearing a product's clothes.
  `GroupedKeys`, `GroupedDecoder`, `GroupedLexiconResource`,
  `KeyboardController+Grouped` and all of `Bar/grouped/` stay, because the decoder
  is the substrate glide typing would reuse (NIT-17, NIT-161), and
  `SharedStore.groupedLevel` already defaulted to `.off`, so removing the only
  control leaves every install on the shipped default rather than stranding
  anyone on a level they cannot leave
- Screen Context: Apple's broadcast picker, the capture process's own counters,
  a sample conversation to try it without starting anything, what it does and
  does not do. **Written, and unreachable in v1.** `HomeScreenContextCard` is the
  only surface in the app that can start a broadcast, so it is what the flag
  turns off: `HomeView` draws it only while `FeatureFlags.screenCaptureReply` is
  true, and `AppSearch` withholds the row that lands on the screen
- **The scripted sample is unreachable too, and not because it was gated.**
  `ScreenContextSession.start()` — the fake conversation, `source == .scripted` —
  has no call site outside `AIKeyboardCoreTests`: the button that played it is
  gone, and `SharedStore.screenContextAllowed`, its only other way in, has no
  control in the app that writes it and is false on every install. The type is
  now a test fixture, kept rather than deleted. The reason it went is worth
  recording: v1 Reply reads the pasteboard rather than the screen, so a sample
  acting out "Reply reads the conversation on your screen" would demonstrate a
  capability this build does not have
- Languages, personal dictionary, settings
- **The paywall is written and unreachable in v1**, behind
  `AppFeatureFlags.subscriptionPaywall == false` (`AIKeyboard/Main/AppFeatureFlags.swift`).
  `SubscriptionView` is intact and untouched: it says "MOCK PAYWALL" on itself,
  its CTA toggles `SharedStore.isSubscribed` instead of charging anything, the
  two prices are invented, and nothing in the build is gated on that flag. NIT-20
  (real StoreKit and a pricing model) is the named condition for flipping it

## Design decisions worth arguing with

**The AI actions sit in a row of their own above the keys, and nothing they do
covers the keys.** They act on text you are looking at rather than characters you
are inserting, so they are kept off the bottom row, which stays close to the
system layout where muscle memory lives. Every outcome — running, answered,
failed, or refused because there is nothing to work on — is said in the strip
above the keys. The three panels that used to paint over the key grid are
deleted.

**Autocorrect defaults to not correcting, and "confident" is a number now.**
A space commits what you typed unless a named rule says otherwise, and each rule
carries a price out of 100: a dropped apostrophe is 98, a Hebrew final form 96, a
transposition 92, a slip one adjacent key wide 92, a displaced hand leaving two
adjacent-tier slips 87, and the catch-all "four-plus letters no dictionary knows,
take whatever ranked first" is 68. The setting is
three positions rather than a switch — Off, High confidence, Full — and High
confidence, which is what ships, is a floor of 86 on that number. Measured over
107 real misspellings it commits 88 of them and puts a word nobody typed or meant
into the message 3 times, against 90 and 10 with every rule allowed to fire. The
first version of any of this turned `I` into `idea`, which is exactly how
autocorrect earns its reputation.

**AI actions are small and reversible, never a chat box.** Fix and Rewrite write
into the field, with one tap of undo in the suggestion bar. Nothing is
applied silently.

**Reply explains itself when it cannot run.** *This paragraph describes the
screen-capture path, which is behind `FeatureFlags.screenCaptureReply` and off in
v1; it stays because the flag is a hold, not a teardown. What a v1 user sees when
Reply has nothing to work with is a refusal that names the fix rather than the
feature. With nothing copied: "Copy the message you want to answer, then let it in
with CopyClip's Paste." With a copy the keyboard has not been allowed to read:
"Tap Paste in CopyClip, then tap Reply and it answers what you copied", and that
one draws the button that opens the panel.* Tapping it
without a capture session says what screen context is and, when a broadcast
started now could actually get somewhere, hosts Apple's own picker so it can be
started from the keyboard. `RPSystemBroadcastPickerView` is a plain `UIView` that
talks to `replayd`, so it needs no `UIApplication`; what is not proven is that
`replayd` answers a keyboard extension, which is why the words sending the user
to the app stay under the button. With no Full Access, an unrecoverable ending or
no cloud model, the picker is withheld and the reason is printed instead.

**The AI button stays tappable on an empty field**, which is the state that
matters: you tap the compose box in WhatsApp and want to answer the message
above it, having typed nothing. The menu greys Fix, Rewrite and Tone itself.
It used to be disabled by "text or a live session", so the one panel that had
something to say in that state was behind a button that would not open.

**The brand gradient only appears on AI moments.** Everything else is system
grey, so the keyboard reads as native rather than as a web page glued to the
bottom of the screen.

## Constraints this keyboard takes seriously

These shape the UI, so they are modelled rather than glossed over.

**A keyboard extension cannot open the microphone.** That is an OS boundary, not
a permission: Apple's guidance lists "No access to microphone and speaker" under
the keyboard sandbox, open access adds Location, Contacts, a shared container,
network and iCloud but never the microphone, and a keyboard that tries anyway
gets `AVAudioSession` error 561145187, `cannotStartRecording`. So the audio
session lives in the companion app and the transcript crosses the App Group —
the same shape screen context already uses, and the same shape Wispr Flow ships.

The same error code shapes the interaction, and it is the part users notice. An
app in the *background* cannot begin recording either; an app whose session is
already active keeps it across an app switch under the `audio` background mode.
So dictation is a **session**: start it in aBitBetterKeyboard, switch to WhatsApp, and
the keyboard's microphone key works until the session closes itself. Nothing in
an extension can launch its containing app — `UIApplication` is unavailable
there and the responder-chain `openURL` workaround is explicitly disallowed — so
when no session is running the keyboard says so and says where to go, rather
than spinning. This is still the part most likely to break on an iOS update.

*Everything from here down to "Full Access is optional in English" describes the
ReplayKit capture path, which is behind `FeatureFlags.screenCaptureReply` and not
in v1. It stays because the flag is a hold rather than a teardown, and because
every measurement in it was taken and still stands. None of it is reachable in a
shipping build today, including the picker the app and the keyboard host, and
including the reading half, which has nothing to read once no frames arrive.
`.claude/docs/screen-capture-v1-hold.md` has the decision.*

**Screen context is a session, not a permission.** Apple's persistent-capture
entitlement is meant for remote-desktop apps, so "allow once, works forever" is
not something to build on. The user starts a session, it is visible the whole
time it runs, and it stops. That is why Screen Context is on Home rather than in
onboarding: it is something you start, not something you set up once.

**And the app cannot start it either.** `RPSystemBroadcastPickerView` is the only
supported entry point and its button is system-vended, so no code can press it —
the Screen Context screen hosts the picker, says what the three taps after it
look like, and says plainly that only iOS can start this. The keyboard's Reply
panel hosts the same picker rather than the "Start screen context" button it
once had, which started the scripted sample and no capture at all.

**Capture is never silent, and a session that ends says so.** iOS shows its own
indicator; the keyboard shows a red dot — red only while frames are actually
being sampled — and the message it read. A session that stops without the user
stopping it reads as "stopped unexpectedly" with a way back, never as "screen
context is off", which is the only signal a jetsam kill leaves behind: it fires
no ReplayKit callback at all, so the evidence is a heartbeat that stopped. The
Screen Context screen also lists what the feature will not do. One item there is
hedged rather than claimed: apps can exclude themselves from a recording and
banking and video apps usually do, but that has not been verified on a device
here, and nothing in the design relies on it.

**Reading a Hebrew screen means the screenshot leaves the device.** Apple's text
recogniser has no Hebrew — 30 languages, measured on both iOS and macOS, and
Arabic is one of them, so it is not a right-to-left limitation. Over the 30
screens in `Bar/screen-context/` it recovers 100% of the expected message on
English screens and 13% on Hebrew ones. So `RoutedScreenReader` reads what it
can on device and sends the rest to the cloud, and it decides which is which
without ever naming a script: `VNDetectTextRectanglesRequest` finds text by
shape regardless of language, so comparing regions *found* against regions
*read* measures "there is writing here I could not read" directly. No Hebrew or
mixed screen is ever kept on device. That asymmetry is deliberate: a misread
Hebrew screen produces a confident wrong reply in the user's name, while an
unnecessary cloud call costs five seconds.

**The on-device half is not currently earning its place, and the honest numbers
say so.** Measured end to end on iOS against one recording taken 2026-08-08:
routed scores sender 27/30 and message 24/30 within 90%, while asking the cloud
for every frame scores 30/30 and 25/30. Vision behaves differently on iOS than on
macOS — it answers three frames there that it correctly refuses on macOS,
including the one whose only right answer is silence.

**Both figures are now taken at the size and encoding the capture process
actually uploads**, 602x1310 as a JPEG, rather than the corpus's full 1206x2622
PNG that every earlier reading used. That gap was measured rather than assumed:
same prompt, same schema, same model, four combinations of size and encoder, two
to three runs each in one sitting. Halving costs nothing and saves 74% of the
bytes (66 KB median against 250 KB), so the smaller frame is what ships and what
the bar now scores.

**Read every absolute number above as a reading with a date on it.** The model is
served behind a moving alias and there is no dated version to pin to — every
dated handle 404s, and the API answers by echoing the alias back as its own
version. Within one sitting it is nearly reproducible: a second full run minutes
later disagreed on 2 of 30 frames and moved sender by one, and that run is
committed as `cloud_outputs_repeat.json` so the spread stays a measured quantity.
Across days it moves far more. What survives is the comparison, because both
sides are scored against the same recording: the on-device path is not free
accuracy that happens to be private, it costs about three points of sender.

**So in the ReplayKit capture flow every screen read goes to the cloud, English
included, and it goes only when you tap Reply.** The order of the two open
questions was backwards: the accuracy one is answered above, on iOS, and it
decides this on its own. What the Screen Context screen therefore says is that
tapping Reply sends one picture of the screen at half its width and height and
gets text back — the previous wording, "each frame goes through on-device text
recognition", was false under this design and is gone, and "shrunken" is now a
size rather than a hint. There is no setting that changes it, and the switch
that used to promise one ("Use the cloud for replies") is gone too, because
nothing in the code read it.

The memory question is still open and is stranger than it looked. Over the 30
screens in `Bar/screen-context/`, in one process, `VNDetectTextRectanglesRequest`
alone peaks at roughly 10-11 MB on the iOS Simulator and 67-75 MB on macOS
26.5.1, and `.fast` recognition at 21-25 MB against 85-95 MB. Those are ranges
over four runs, and they were quoted a couple of megabytes tighter until a fifth
run landed outside them on two of the four cells — so read them as the order of
magnitude they establish, not as bounds. Both platforms ship
the same Vision model assets and both report the same compute device for these
two requests: `[cpu]`. The gap is where the kernel charges the memory, not what
runs — macOS puts ~63 MB on the footprint ledger jetsam reads, while the iOS
build maps ~11 MB file-backed and charges the ledger ~5 MB. Which of those a
phone does is unknown, and there is no device measurement here.
`Bar/screen-context/harness/run-memory.sh` re-takes all of it.

**Full Access is optional in English and effectively required in Hebrew.** Typing,
autocorrect, predictions and emoji work without it. The on-device AI path works
without it too — but only for the 23 languages Apple's model supports, and Hebrew
is not one of them, so every Hebrew AI action needs the network and therefore Full
Access. Two things follow. iOS only lets a keyboard extension reach a shared
container once Full Access is granted, so without it the keyboard falls back to
shipped defaults instead of the settings the user chose in the app — including
the language list, which leaves a French-only user on an English/Hebrew keyboard
with no way to change it from inside one. The app says that in the places it
matters, and the places changed when onboarding lost its Full Access step.
`SetupState.worksWithoutFullAccess` went with that step and no longer exists. On
the required path the sentence is now `fullAccessConsequence` on the add-keyboard
step, one line under a status row, and it is read off `enabledLanguages` rather
than said the same way to everyone: with Hebrew enabled it says Hebrew needs Full
Access because Apple's on-device model does not speak it, and otherwise it says
Full Access is what reaches the network at all. Beside the language picker it is
still `SetupState.languagesNeedFullAccess`, in onboarding's optional Languages
step and in the Languages tab, withheld once Full Access is confirmed, and
mirrored by the layout editor and the personal dictionary, which have the same
problem for the same reason. And for the audience this keyboard is built for,
"optional" is the wrong word.

**Full Access is not sufficient either, and the app has to say so.** It buys the
network; it does not buy something that will answer. A backend is deployed and
the app ships pointing at it — `BackendTransport.bundledDefaultURL`, which
`configured()` falls back to whenever `cloudBackendURL` is absent or empty — so
"nothing deploys a server for you" stopped being true on 2026-08-10, and with it
the state this paragraph used to describe, where every Hebrew AI action failed on
every install for want of anywhere to send. What still does not ship is the
**access token**: it gates that server, a bundle cannot hold a secret, and it is
filled by `AppAttestation`, not typed in. So a fresh install is "not finished" rather than "not set up",
and the question every surface asks is `BackendTransport.isReady()` — *would a
call be accepted* — not `configured() != nil`, which is true from the first launch
and would credit a keyboard that 401s on every action. Every surface that depends
on it reads that same measurement: `SetupState.fullAccessDetail` branches on
`cloudConfigured` rather than claiming cloud rewrites work, and it is what both
Home's Full Access row and the add-keyboard step's status row print (onboarding's
"What it turns on" list went with the Full Access step it lived on), the four
failures that dead-end on it (`unsupportedLanguage`, `cloudNotConfigured`,
`deviceNotSupported`, `ScreenContextEndReason.notConfigured`) all print that one
path, and the keyboard's Reply panel withholds the broadcast picker rather than
starting a screen recording iOS ends inside a second — moot in v1, where
`FeatureFlags.screenCaptureReply` withholds that picker unconditionally.

## The mocks, and what replaces them

| Mock | Real thing |
|---|---|
| ~~`MockSuggestionEngine`~~ — now `SuggestionEngine` | **Done, and measured: 75/76 on `Bar/typing/corpus.json`, up from 47/76**, plus **90 of 107 misspellings corrected on `Bar/typing/typos/`, up from 61, with all 21 of its controls intact**. Those two are the engine with every rule allowed to fire (`AUTOCORRECT_LEVEL=full`). What ships is `AutocorrectLevel.shippedDefault`, a confidence floor that reads 73/76 and 88 of 107 and cuts the wrong-word column from 10 to 3; the per-rule prices and the probe behind them are in `AutocorrectConfidence.swift`. Correction used to be one edit deep everywhere — a 353-word neighbour list and Apple's own unranked guesses — so a hand that landed one key over could not be repaired at all: `דוגמטןת` for `דוגמאות` ("examples") drew a single offer, `דוגמטית`, a word that appears nowhere in 50,000 words of real Hebrew. `TypoChannel` prices a slip by what kind of slip it is (an adjacent key, a transposition, a Hebrew final form, a dropped mater lectionis, a homophone letter) rather than counting edits, and `TypoLexicon` ranks the candidates against a frequency list with a Zipfian prior, so two *explainable* mistakes stay in reach and two unrelated ones do not. That list is also the second dictionary the commit decision never had: Apple's Hebrew checker calls `תדוה` and `שלמו` perfectly good words, and 300,000 sentences of real Hebrew have never seen either (it read 73/76 until `score.py` was made to measure the commit column it had been printing the offered column into; the same engine scores 71/76 under the honest one). That corpus — 90 frozen moments mid-typing — had existed for a while with nothing running the engine against it, so every judgement about the suggestion bar was somebody's opinion until `Bar/typing/harness/` was written. Completions, spelling guesses and autocorrect come from `UITextChecker` (the public on-device API a third-party keyboard can call — *not*, as this row used to claim, "the engine the system keyboard's autocorrect draws on", which Apple documents nowhere), ranked against a bundled frequency prior, what the user's own typing has taught the keyboard, and the sentence in front of the cursor. The prior is what the checker has never had: `helo` used to complete to `helot` and `helots`, both real words, and never to `hello`. **Hebrew works here**, unlike Foundation Models, `SpeechTranscriber` and Vision's text recogniser: `UITextChecker.availableLanguages` lists `he_IL` among 42, and `אנ` completes to `אני`. Its Hebrew is weaker than that sounds and the gaps are handled rather than described: `שלומ` ("hello" with a plain mem) has twelve real completions, so the spelling-guess path never runs and the bar used to commit "who are studying" — corrected by orthography, not lookup. Hebrew also glues ה ב ל מ ו ש כ to the front of the next word, so `לעבודה` is one token no dictionary lists; `HebrewMorphology` takes it apart, which is what makes `לעבו` reach `לעבודה` instead of two unrelated verbs. And `akuo` typed on the wrong plane now offers `שלום`, which no keyboard on iOS does. What is *not* claimed: predicting the next word is QuickType's job and Apple ships no public API for it, so `nextWordSuggestions` is a bigram table plus what this user actually writes, and is disclosed as that rather than as a model. The optional async tier (`PredictiveRefiner`) can improve slots 1 and 2 on a typing pause and can never change slot 0 or what the space bar commits; its mechanism is unit-tested and the **quality of its answers is not yet measured**, because the corpus has no pauses in it. |
| ~~`MockAI`~~ — now `RoutedIntelligence` | **Done.** Apple Foundation Models on device for the languages it lists, a cloud LLM behind it for the rest. Hebrew is not one of Apple's supported languages, so it needs the cloud path. The cloud provider sits behind a protocol; a shipped app cannot hold cloud credentials, so it must point at your own backend. The direct-to-Vertex client used to score `Bar/ai-text/` lives in the harness and is deliberately not in the app target. |
| ~~`MockDictation`~~ — now `DictationService` + `CloudDictation` | **Done, and the shape was forced rather than chosen.** The keyboard genuinely cannot record: Apple's guidance lists, verbatim, *"No access to microphone and speaker"* under the standard sandbox, open access adds Location, Contacts, a shared container, server-side processing and iCloud while naming the microphone nowhere, and a keyboard that tries anyway gets `AVAudioSession` error 561145187, `cannotStartRecording`. So the microphone lives in the companion app and the transcript crosses the App Group — the architecture screen context already uses, and the one [Wispr Flow ships on iOS](https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone) as a "Flow Session". The same error code forces the session model: an app cannot *begin* recording from the background, but an active session survives an app switch under the `audio` background mode. Nothing in an extension can launch its own app, so with no session running the keyboard explains rather than spins. **Transcription is cloud-only and that is measured, not conceded**: `SpeechTranscriber` lists 30 locales and no Hebrew, and legacy `SFSpeechRecognizer` lists `he-IL` with `supportsOnDeviceRecognition == false`, so there is no on-device path for the language this product is for. Scored on `Bar/dictation/`'s 36 clips: word error rate 10.7% Hebrew, 8.5% English, 23.5% code-switched, 14.2% overall, 38/60 named entities, 25/36 of the English words inside Hebrew sentences kept in Latin letters. Across 29 more languages in `Bar/dictation/multilingual/`: 29/29 came back in the right writing system. **The model cannot be trusted to say it heard nothing** — four seconds of silence come back as a fluent invented sentence — so `SpeechGate` decides that on the device, by arithmetic, before anything is uploaded. `Scripts/prove-dictation.sh` proves the cross-process half; nothing has yet proved a microphone opens on a real phone. |
| `MockScreenContext` | **Reading a frame is done and measured** — `RoutedScreenReader`, scored against `Bar/screen-context/`. **Getting** one is not. ScreenCaptureKit is `iOS 27.0+` and absent from the iOS 26.2 SDK this project compiles against. The ReplayKit route is built except for the read: the app hosts `RPSystemBroadcastPickerView` so a user can start a broadcast, `AIKeyboardBroadcast` fingerprints every sampled frame and publishes a `CaptureStatus` page, and `ScreenContextSession` consumes that page — the strip and the app screen render no session, starting, watching, a reading, paused and stopped-unexpectedly from it, and Reply raises `intent.readNow` and waits for a reading the freshness gate accepts. The read is there too: a tap makes `AIKeyboardBroadcast` encode one frame and call `CloudScreenReader` on its own serial queue, then publish the text with the identity of the frame it read. **And none of it has ever run**: the iOS Simulator ships no `replayd`, so no broadcast session starts here and `SampleHandler` has never been called. `ScreenContextSession.submit(_:appName:appIcon:)` is the in-app seam. **And as of 2026-08-18 none of this is in v1**: `FeatureFlags.screenCaptureReply` is `false`, so the picker, the Home card and the route to the Screen Context screen are all gated off, Reply is sourced from the pasteboard instead, and the 3,792 lines of transport stay in the tree with a named condition for coming back. The scripted sample used to sit behind a button on the Screen Context screen, labelled as a sample, yielding to a real session the moment one appeared; **that button is gone and nothing replaced it**. `ScreenContextSession.start()` has no call site outside `AIKeyboardCoreTests` and `SharedStore.screenContextAllowed` has no control that writes it, so `MockScreenContext` is now a test fixture rather than a demo — which is the right outcome while Reply answers the clipboard, since a sample acting out "Reply reads your screen" would be showing a capability this build does not have. `.claude/docs/screen-capture-v1-hold.md`. |
| ~~`SharedStore`~~ | **Done.** Both targets carry the App Group entitlement and share one suite. |
| `MockTextTarget` | `UITextDocumentProxy`, already wired via `ProxyTextTarget` |

`SharedStore` now writes to the App Group container, and the keyboard extension
reads what the app wrote. `SharedStore.storage` says which of the two stores an
instance actually got: `.appGroup`, or `.processLocal` when the container was out
of reach, which it also logs as an error rather than pretending to be shared.

Verify it end to end with `Scripts/prove-app-group.sh`. The check that matters is
the last one — it turns English off in the app, brings the keyboard up in a real
text field, and confirms the extension process, which iOS runs separately,
rendered Hebrew because of it. A unit test cannot show this: a process always
sees its own writes.

The capture channel rides the same container and is proved the same way, by
`Scripts/prove-capture-channel.sh`. Two fixed-layout pages are `mmap`'d
`MAP_SHARED` behind a seqlock — 256 bytes of status from the capture process,
64 bytes of intent back from the keyboard — and one JSON file carries the
reading. **Only text and hashes cross.** The pages hold timestamps, counters and
a 32-byte SHA-256 of a greyscale reduction; `ScreenReadingRecord` has a sender, a
message and a language and no field an image could go in. The script drives two
real processes and takes its verdict from the keyboard extension's own log
lines: it read a session identifier and a live sequence of frame identities
written by another process, found a reading of the frame on screen offerable,
and retired it the moment that frame changed. What it explicitly does **not**
prove is that the producing process is the broadcast extension. There is no
`replayd` here, so the producer in that run is the app driving the same writer
over synthetic frames, and ReplayKit's half is untested on any hardware.

## What the app counts

**Six events, in the companion app only, and the boundary is structural rather
than promised.** `AIKeyboardExtension` and `AIKeyboardBroadcast` emit zero events,
forever, independent of Full Access, subscription state or any feature shipped
later. `Analytics` lives in the app target, not in `AIKeyboardCore` or
`AIKeyboardShared`, so a keyboard-side call site would have to import a module the
extension does not have and cannot get: "please don't" is a compiler error here.
The install identifier is locally generated, resettable, never IDFA, and is kept
in the app's own `UserDefaults.standard` rather than the App Group, where the
keyboard structurally cannot reach it.

The six are `onboarding_step_advanced`, `onboarding_completed`,
`full_access_confirmed`, `keyboard_added_confirmed`, `app_session_started` and
`screen_context_session_started`. **No event carries anything typed, corrected,
dictated or read off a screen** — `AnalyticsEvent` has no `case custom(String,
[String: Any])` and every associated value is an `Int`, a `Bool` or a closed enum,
so there is no slot a message could go in and adding one is a visible edit to that
file. The sixth event is dormant while `FeatureFlags.screenCaptureReply` is false,
because nothing in the build can raise a real capture session; it is kept rather
than deleted, since the flag is a hold on shipping and not a decision to stop
measuring.

Two of the five questions this was built to answer are given up rather than
approximated: which AI action people actually use, and whether the *keyboard*
keeps getting used, both of which live inside the extension. `app_session_started`
is companion-app retention and must never be reported as keyboard retention.
`.claude/docs/analytics-policy.md` is the decision, including the never-list and
why no third-party SDK is used.

## Testing

`AIKeyboardUITests` drives the app by accessibility identifier and writes a PNG
per screen. It runs inside the simulator, so it does not take over the pointer.

```bash
# Run the suite, keeping the screenshots
TEST_RUNNER_SHOT_DIR=/tmp/shots xcodebuild test \
  -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Coverage report
xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -resultBundlePath /tmp/AIKeyboard.xcresult
xcrun xccov view --report /tmp/AIKeyboard.xcresult
```

Four tests live in `AIKeyboardUITests/DemoWalkthroughTests.swift`, and the unit
tests in `AIKeyboardCoreTests`. The two cross-process suites,
`AppGroupCrossProcessTests` and `CaptureChannelCrossProcessTests`, are driven by
the `Scripts/prove-*.sh` scripts rather than judged by their own assertions; see
`.claude/docs/testing.md`.

## Not built

- Anything about ReplayKit that a device would settle: that frames arrive, in
  what pixel format and size, whether the extension fits its ~50 MB cap, and
  whether the picker's button works from inside a keyboard extension (NIT-6,
  NIT-12, NIT-13, NIT-14). That is why the path is flagged off rather than
  shipped, and NIT-6 plus NIT-12 are the two that flip the flag back
- The keyboard extension runs in a real text field — `Scripts/prove-app-group.sh`
  drives it — but only far enough to prove it reads shared settings; the panels
  are still exercised through the in-app playground
- **iPad layouts.** Landscape iPhone and Dynamic Type both shipped and moved up
  to "What's built"; iPad did not, and it is a different question rather than a
  wider answer to the same one — a split or floating keyboard changes shape, not
  aspect ratio. Version 1.0 therefore targets device family `1` and is iPhone-only.
  iPad support returns only after that separate layout and device pass (NIT-177)
- Real StoreKit or accounts. The **backend is real and deployed** (`Backend/`,
  Cloud Run, `Scripts/prove-cloud-backend.sh` exercises the shipping client
  against it); what is untested there is a shared-state rate limit and the token
  living in the Keychain rather than the App Group plist
- **App Attest is measured on the server and only compiled on the device.** The
  backend half is real and tested against real cryptography: `Backend/test/`
  mints a certificate authority, builds a valid attestation against it, and runs
  all ten of Apple's checks — two tests prove acceptance and twelve prove
  refusal, one per way in. The client half (`AIKeyboard/Cloud/AppAttestation.swift`)
  has never run: `DCAppAttestService` needs a Secure Enclave, so no simulator and
  no CI machine can raise an attestation, and nothing here has yet been through a
  device. What that leaves unproven is the round trip, not the verifier: whether a
  real `attestKey` blob passes the checks a synthetic one passes. Prove it by
  running the app on a phone and watching `/v1/attest` return 200

## License

The source code is available under the
[PolyForm Noncommercial License 1.0.0](LICENSE). You may read, modify, and share
it for permitted noncommercial purposes. Commercial use is not licensed without
a separate written agreement from the repository owner.

This project is source-available, not open source under the Open Source
Initiative definition. See [CONTRIBUTING.md](CONTRIBUTING.md) before proposing a
change.
