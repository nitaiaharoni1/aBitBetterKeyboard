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

Then check Settings → Diagnostics in the app for the keyboard's own memory peak.
Anything with zero memory warnings has never been close to the ~50 MB cap.

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

## What none of this covers

- Landscape and iPad. Not built.
- Dynamic Type above the default size. Not built (another session is working on
  it as of 2026-08-18).
- Real StoreKit. The paywall is unreachable behind `AppFeatureFlags.subscriptionPaywall`
  until NIT-20 lands.
- Whether the keyboard survives a day of real use. Nothing here can tell you that
  and the Diagnostics memory row is the closest proxy.
