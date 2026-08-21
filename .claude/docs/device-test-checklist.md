# The device checklist

Everything in this repository that a Mac cannot answer, in the order that wastes
the least of your time. Three of the four open "prove it on a phone" issues can be
closed in one sitting of maybe twenty minutes; the fourth (ReplayKit) is longer and
is the only one that can end in "no".

Read this before plugging the phone in, because two of the checks are destroyed by
doing them in the wrong order.

## Before you start

- Build and run on the **device**, not the simulator. Every check here is a check
  precisely because the simulator answers differently or not at all.
- **Do the checks in the order below.** `NIT-86` wants a *fresh install*, and
  reinstalling later would throw away the App Attest state the other checks build
  on. Fresh install first, everything else after.
- Keep Console.app open with the device selected, filtered to
  `com.nitai.aikeyboard`. Several of these leave their evidence only in the log:
  a keyboard extension killed for memory writes no crash report at all.
- Have a second app to type into. WhatsApp is the realistic one because it is a
  Hebrew RTL compose box; Notes is fine as a fallback.

---

## 1. NIT-86 — attestation, on a genuinely fresh install (2 minutes)

**Delete the app first.** This is the check that cannot be redone without another
delete, so it goes first.

1. Delete aBitBetterKeyboard from the phone. Install fresh. Open it once.
2. In Console, filter to `AppAttest`.

**Pass:** `/v1/attest` is called and the app stores a session token.
**Fail:** `/v1/challenge` returns 200 but `/v1/attest` never appears. That is the
2026-08-11 failure exactly, and it means the flow is dying inside
`DCAppAttestService` rather than in the transport or on the server.

The server side is confirmable independently, and is worth checking if the client
half looks wrong, because it separates the three layers in one query:

```bash
gcloud logging read 'resource.labels.service_name="aikeyboard-backend"' \
  --project=handi-project --account=nitai@handi.co.il --limit=50
```

**Why it is first:** every cloud action in the product is dead without it. Fix,
Rewrite, Tone, Reply and cloud dictation all 401 with no token, and the two
symptoms differ (Reply refuses up front, Fix calls and comes back
`cloudNotConfigured`), so a wrong diagnosis here sends you chasing the wrong file.

---

## 2. NIT-8 — the microphone (5 minutes, the most valuable thing on this list)

**Urgent, still open, and nothing else about dictation means anything until it
passes.** `Scripts/prove-dictation.sh` proves the cross-process half; no
microphone has ever opened on real hardware.

1. Add the keyboard: Settings → General → Keyboard → Keyboards → Add New Keyboard
   → aBitBetterKeyboard. Allow Full Access.
2. In the app, Home → start dictation. Say a sentence. Confirm words appear.
3. **Switch to WhatsApp without stopping it.** Tap the microphone key on the
   keyboard. Speak.
4. Confirm the transcript lands in the WhatsApp compose box.
5. Stop from the keyboard. Confirm the microphone closes.

**Pass:** step 4 puts text in another app's field.
**Fail modes worth telling apart:**
- Nothing records at all in step 2 → `AVAudioSession` is failing in the app.
  Console will carry the error from `DictationService+Lifecycle`.
- Step 2 works, step 3 does not → the session did not survive the app switch,
  which is the `audio` background mode not being in the *built* plist. Check the
  built plist, never the build setting: `INFOPLIST_KEY_UIBackgroundModes` is
  accepted by Xcode, echoed by `-showBuildSettings`, and silently never reaches
  the built Info.plist. That is why the key lives in `AIKeyboard/Info.plist`.
- Words appear then vanish or duplicate → the streaming replace path
  (`replaceStreamedDictation`), not the microphone.

**Sessions no longer expire** (2026-08-18 decision), so there is no timeout to
wait out. The only thing that ends a session is you, an audio interruption, or the
process dying. Which makes one extra check worth doing while you are here: leave a
session running, use the phone normally for a few minutes, and confirm it is still
alive and the red microphone cap is still showing. That cap is now the only
continuous signal that a recording is live.

Also try the Action Button or Shortcuts: "Start Dictation" should foreground the
app and open a session. That path has never run either.

---

## 3. Live typing, autocorrect and Hebrew (5 minutes)

Not an issue number, but it is the product, and a device is the only place the
whole loop is real.

1. In WhatsApp, type an English sentence with two or three ordinary typos. Confirm
   the space bar commits sensible corrections.
2. Switch to Hebrew (slide along the space bar). Type a Hebrew sentence including
   an English word in the middle, e.g. a product name. Confirm the English word
   stays in Latin letters.
3. Type `שלומ` with a plain mem and confirm the bar offers `שלום`.
4. Type `akuo` on the Hebrew plane and confirm it offers `שלום`.
5. **Watch for the stock keyboard replacing ours.** If it happens, note whether it
   was reproducible in that same field (Apple's substitution: secure field, phone
   pad, or an app that opted out) or intermittent (a memory kill). The ten second
   test is the globe key: after a kill it brings ours straight back and it stays.

**NIT-90 — are the proxy's traits fresh when the keyboard appears?** Thirty
seconds, and it is the one part of the NIT-9 / NIT-10 work a Mac cannot settle:
all 19 tests use mocks, and there are long-standing reports that
`UITextDocumentProxy`'s trait properties are stale in `viewWillAppear`.

6. Find a screen with a **number field and a text field**, and tap the number
   field first. Confirm the keyboard opens as a number pad.
7. Now tap the text field and **type nothing**. Confirm the keyboard is a full
   QWERTY rather than still the number pad.

Step 7 is the whole check. A nil trait is handled by construction, so the failure
this is looking for is a **stale non-nil**: the proxy still reporting the previous
field's `.numberPad`. Typing would hide it, because the first `textDidChange`
adopts correctly, which is exactly why step 7 says type nothing.

If it is stale, do not fix it speculatively. The fallback is to adopt on the first
document callback instead of on appearance, which trades a guaranteed hook for an
unproven one and costs a frame of the wrong plane.

### NIT-185 — why the stock keyboard sometimes wins the first tap

Reported 2026-08-21: tapping a field brings up the stock iOS keyboard, and
tapping the *same field* again brings ours back. That detail does real work.
Apple's three substitutions — secure field, phone pad, opted-out app — are all
per-field and deterministic, so the same box would give the stock keyboard every
time. It does not. Ours was on offer and iOS did not have it ready.

**Settings → Diagnostics now has two rows, and you need both.** The second one
is new (`KeyboardLaunchRecord`) and counts `viewDidLoad` against the first
`viewDidAppear` of each instance, so a launch that began and never reached the
screen shows up as a gap.

| Keyboard memory | Keyboard launches | What it means |
|---|---|---|
| warnings above zero | anything | The jetsam kill. Work is footprint; `GroupedLexiconResource.load` first. |
| zero warnings | launches above presentations | Not memory. Runs start and do not arrive. |
| zero warnings | counters equal, slowest small | Both current hypotheses are wrong. What is left is the unconditional `primaryLanguage` write in `viewWillAppear`. |

One point of gap is noise, because iOS may build a controller it never presents.
A persistent ratio is the evidence. Use the keyboard normally until the bug has
happened at least twice before reading it, and note **which app** it happened in:
if it is always the same one, that changes the answer.

Both rows are boot-scoped, so a restart wipes them and you start again.

---

## 3b. NIT-184 — does the emoji grid still stick? (1 minute)

Reported 2026-08-21: the grid sometimes stops scrolling sideways. Two mechanisms
were found; **one is fixed and the other is not**, and this check is what decides
whether the second one needs doing at all.

1. Open the emoji grid and scroll it hard, back and forth, through every
   category.
2. If it sticks, note **which tab you were in** before anything else. That is the
   whole check.

**All 304 skin-toned emoji are in People**, where they are 83.7% of the cells,
and every other category has exactly zero. Only those cells carry the extra
`DragGesture(minimumDistance: 0)` that competes with the scroll.

- Sticks in **People or Recents only** → the gesture arbitration is real. The
  repair is *not* simply `LongPressGesture.sequenced(before: DragGesture)`: that
  rewrite loses `pickerTookTouch`'s only reset point, and the cell then swallows
  every later tap on it, permanently. NIT-184 has the detail; it needs solving
  before that road is taken.
- Sticks in **Flags, Food, Symbols or any other tab** → arbitration is refuted,
  those tabs have no such gesture, and the cause is somewhere nobody has looked.
- **Does not stick at all** → the stranded tone strip was the whole of it, and
  that is already fixed.

Also worth one try while you are here: hold 👋 to open the tone strip, then tap
somewhere else on the panel. It should close. Until this change there was no way
to dismiss a strip except by lifting the finger that opened it, which is why a
stranded one froze the grid until the panel was closed and reopened.

---

## 4. Reply, the v1 way (2 minutes)

Reply no longer reads the screen. It answers the message you copied.

1. In WhatsApp, long-press a message somebody sent you and copy it.
2. In the compose box, open CopyClip on the keyboard and tap **Paste**. That tap
   is what lets the keyboard see the clipboard: reading it outright would raise
   Apple's "Allow Paste?" alert, which is why the flow has this step.
3. Tap Reply. Confirm a reply is written into the field.
4. Tap Reply with nothing copied and confirm the refusal names the fix rather than
   naming screen context.
5. **Without Full Access** (turn it off in Settings), tap Reply and confirm it says
   "Needs Full Access" and names the Settings path, rather than "reconnecting".
   That last one was a real defect fixed on 2026-08-18 and is worth confirming.

---

## 5. NIT-6, NIT-12, NIT-13, NIT-14 — ReplayKit (longer, and can end in "no")

**Do this last, and only if you want to.** The whole capture path is currently
flagged out of the build (`FeatureFlags.screenCaptureReply == false`, NIT-159), so
none of it ships either way. To test it you have to flip that flag to `true` and
rebuild.

The four questions, in the order they fail:

1. **NIT-14, and the one most likely to fail:** does the broadcast picker work
   from *inside the keyboard extension*? `RPSystemBroadcastPickerView` is a plain
   `UIView` that talks to `replayd`, so it needs no `UIApplication` — but nothing
   has ever confirmed `replayd` answers a keyboard extension. If this fails,
   nothing below it matters and the feature needs a different entry point.
2. **NIT-6:** does a broadcast actually start, and is `SampleHandler` actually
   invoked? Put a log line in it. The simulator ships no `replayd`, so this has
   never executed anywhere.
3. **NIT-13:** what frames actually arrive — pixel format, size, rate? Log them.
   The whole reduction pipeline is written against assumptions.
4. **NIT-12:** does the broadcast extension fit under the ~50 MB cap? This is the
   one that decides whether the feature is viable at all on a real phone, and the
   memory numbers in `README.md` differ by a factor of six between iOS and macOS
   for reasons nobody has explained.

**Flip the flag back to `false` before you commit anything**, unless all four
passed.

---

## 6. Landscape and Dynamic Type — the two that only a screen can settle (3 minutes)

Both of these shipped, and both left specific questions that no test can answer
because the answer is "does it look wrong". Neither blocks anything; do them while
the phone is already in your hand.

**Landscape** (NIT-18, shipped). Rotate the phone in WhatsApp.

1. Confirm Fix, Rewrite, CopyClip, Dictation and Settings are all reachable. They
   are drawn as chips on the suggestion bar rather than in an action row, because
   the row is shed for height (NIT-101).
2. Open CopyClip or Emoji sideways and confirm you can close it again. The row
   carrying the key that closes a panel is the row that was shed, so the bar keeps
   the action strip rather than becoming a search box. Rotating back used to be the
   only way out.
3. On a small phone (SE, 12 mini, 13 mini) confirm the keyboard does not look
   cramped. Landscape row spacing was cut 8 pt to 4 to get under the fingerprint
   cap on those widths (NIT-114). The gap is dead space and no touch target moved,
   but nobody has looked at it.

**Dynamic Type** (NIT-19, shipped). Settings → Accessibility → Display & Text Size
→ Larger Text.

4. At **AX5**, confirm a Hebrew letter at roughly 32 pt still sits inside the key
   rather than crowding `Theme.Radius.key`'s corner. This is the one the commits
   flagged three separate times as needing a screen.
5. At AX5, confirm the space bar's two-line badge tier does not read as cramped.
6. Confirm the emoji category row is legible. **Its icons are deliberately not
   scaled**, matching Apple's own keyboard, which grows the letter glyph at
   accessibility sizes but not its control icons. NIT-19 named that row and left
   it out on purpose, so the question is whether that decision holds at AX5.
7. Back at the **default** size, confirm nothing got smaller. That is the failure
   mode this work already hit once: the space bar drew its language name at 14.4 pt
   where the shipped size is 15, on a 36 pt bottom row.

---

## What none of this covers

- iPad. Not built, and it currently ships to iPad with the iPhone geometry
  stretched (NIT-177).
- Real StoreKit. The paywall is unreachable behind `AppFeatureFlags.subscriptionPaywall`
  until NIT-20 lands.
- Whether the keyboard survives a day of real use. Nothing here can tell you that
  and the Diagnostics memory row is the closest proxy.
