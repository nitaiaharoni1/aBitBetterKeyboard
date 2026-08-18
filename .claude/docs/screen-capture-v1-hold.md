# Screen-capture Reply is held out of v1

NIT-159. A product decision written down so it stays findable and reversible, and so
nobody re-derives it from scratch in six weeks. The flag is
`FeatureFlags.screenCaptureReply`, it is `false`, and the code it gates is still in
the tree.

Written 2026-08-18. Every absolute number below is a reading with a date on it, the
same way `README.md` treats its own, and the commands that re-take them are named.

## What was cut

**The ReplayKit-sourced path into Reply.** A user starts a broadcast through Apple's
system picker, `AIKeyboardBroadcast` receives sampled frames, fingerprints them into
a shared page, and answers the keyboard's `intent.readNow` by encoding one frame and
reading it in the cloud. Every entry point that could start or offer that broadcast
is gated on the flag.

**Nothing is deleted.** Measured today with `wc -l`:

| Half | Files | Lines | Fate |
|---|---|---|---|
| ReplayKit transport (`AIKeyboardBroadcast/*`, `Capture*`, `ScreenContextChannel`, `ScreenContextSession*`, `BroadcastPickerButton`, `CaptureChannelProbe`, `ScreenContextEndReason`, `Models+ScreenContext`) | 22 | 3,792 | stays, unreachable while the flag is false |
| Reading (`VisionScreenReader*`, `RoutedScreenReader`, `CloudScreenReader`, `ScreenReadService*`, `ScreenPrompt`, `ScreenContextPrompt`, `ScreenReader`) | 9 | 1,592 | stays, measured, with no source of frames in v1 |
| Tests over both (`AIKeyboardCoreTests/ScreenContext*`, `Capture*`, `ScreenReaderTests`, plus the cross-process UI test) | 17 | 3,961 | stays, still runs |

That is a hold on shipping, not a teardown. The distinction matters because the two
halves have completely different evidence behind them, and only one of them is being
held.

## Why

Three reasons. The first is sufficient on its own; the other two are why the first
one is not worth waiting out.

**1. Not one line of the ReplayKit half has ever executed.** The iOS Simulator ships
no `replayd`, so no broadcast session has ever started here and `SampleHandler` has
never been called. `Scripts/prove-capture-channel.sh` proves the channel and says so
in its own verdict: the producer in that run is the app driving the same writer over
synthetic frames, not the broadcast extension. There is no device measurement of any
of it. Four open issues exist precisely because a phone is the only instrument that
can answer them:

- **NIT-6**, prove the ReplayKit capture loop on a real device.
- **NIT-12**, measure the broadcast extension's peak memory against the ~50 MB cap.
- **NIT-13**, confirm what frames actually arrive: pixel format, size and rate.
- **NIT-14**, confirm the broadcast picker works from inside the keyboard extension.

NIT-12 is not a formality. On the 30 screens in `Bar/screen-context/`, in one
process, `VNDetectTextRectanglesRequest` alone peaks at roughly 10-11 MB on the iOS
Simulator and 67-75 MB on macOS 26.5.1, and `.fast` recognition at 21-25 MB against
85-95 MB (four runs, with a fifth landing outside those ranges on two of the four
cells, so read them as an order of magnitude). Which of those two numbers a phone
charges to the jetsam ledger is unknown. If it behaves like the macOS figure, the
extension does not fit its cap and the feature does not exist regardless of how good
the reading is. Shipping the flag on would be betting the most visible feature in the
product on the answer to a question nobody has asked a phone yet.

**2. The product cost is the highest ask in the app.** It invites a user to start a
**screen recording**, on top of Full Access, to get a text reply. That is the hardest
trust sell this product makes, attached to its least proven path. Every other feature
either needs no permission (typing, autocorrect, layout editing) or needs one the
user already understands (a microphone). A screen recording is in a different
category, and it is not the thing to spend a first-run user's trust on.

**3. It is the largest single surface in the codebase and it currently carries no
measured user value.** 3,792 lines of transport, and the only evidence any of it
works is a cross-process script driving synthetic frames.

## What is not cut

**The reading half is real, it is measured, and it stays** — though with capture
off it has no source of frames, so it is dormant in v1 rather than live.
`RoutedScreenReader`
decides on device whether a frame can be read without ever naming a script:
`VNDetectTextRectanglesRequest` finds text by shape regardless of language, so
comparing regions *found* against regions *read* measures "there is writing here I
could not read" directly. Scored against `Bar/screen-context/`, as dated readings:

- Over the 30 screens, Vision recovers **100% of the expected message on English
  screens and 13% on Hebrew ones**, which is why no Hebrew or mixed screen is ever
  kept on device.
- Measured end to end on iOS against one recording taken **2026-08-08**: routed
  scores **sender 27/30 and message 24/30** within 90%, against **30/30 and 25/30**
  for asking the cloud about every frame. The on-device half costs about three points
  of sender; it is not free accuracy that happens to be private.
- Both figures are taken at the size and encoding the capture process actually
  uploads, **602x1310 as a JPEG**, which costs nothing in accuracy and saves 74% of
  the bytes (66 KB median against 250 KB).

Read all of those as readings with a date on them. The model behind them is served
behind a moving alias with no dated version to pin to; within one sitting a repeat
run disagreed on 2 of 30 frames, and `cloud_outputs_repeat.json` is committed so the
spread stays a measured quantity. `Bar/screen-context/harness/` re-takes all of it,
and `Bar/drift/` re-runs it unattended.

**The scripted in-app sample is a separate thing from the flag, and it went anyway.**
`ScreenContextSource.scripted` photographs nothing and needed no gate, because
nothing offers it any more: `ScreenContextSession.start()` has no call site outside
`AIKeyboardCoreTests`, the button on the Screen Context screen that played it is
gone, and `SharedStore.screenContextAllowed` — its only other way in — has no control
in the app that writes it, so it is false on every install. `MockScreenContext` is now
a test fixture rather than a demo, and it stays in `AIKeyboardCore` as one.

That is the right outcome rather than an accident of the hold. A sample acting out
"Reply reads the conversation on your screen" would be demonstrating a capability
this build does not have, which is the one thing the app may not do. It comes back
with the feature, not before it.

**The code stays.** See the table above. A flag with a stated condition is a hold; a
deleted directory is a decision to never revisit, and that is not the decision here.

## What replaces it in v1

**Reply is sourced from the pasteboard: copy the message you are answering, then tap
Reply.** NIT-162. `ReplySource` (`Packages/AIKeyboardCore/Sources/AIKeyboardCore/ReplySource.swift`)
landed while this document was being written; what follows is read off that file
rather than off the issue, but **nothing here has been run, so read it as written
rather than measured**:

- Three sources, in preference order: `.scripted`, `.capture` (unreachable while the
  flag is false, kept for the day it flips), and `.clipboard(ScreenContext)`, the
  newest clip in the CopyClip ledger already turned into a context.
- The clip becomes the `ScreenContext` the existing prompt already consumes.
  `Prompts.reply(for:)` reads `message` and `language` and nothing else, checked
  against the code rather than assumed. Screen capture was one way to get that text,
  and it was the expensive, unproven one.
- Three of `ScreenContext`'s five fields come back empty from a clip and are left
  empty on purpose. A clip is a string: it does not know which app it came from or
  who wrote it. `sender` is the one worth saying out loud, because inventing a
  plausible name would put a stranger into the prompt and, in Hebrew, into the
  grammatical gender the whole reply is written in.
- Reply reads the existing `ClipboardHistory` ledger and its `ClipText` validity rule
  rather than opening its own pasteboard reader. That matters for NIT-23
  (`UIPasteControl`): reading `UIPasteboard` programmatically raises the iOS paste
  alert, and a Reply that pops an alert every time is a visible regression.
- **The cost is in the type rather than hidden.** The message has to reach the ledger
  before Reply can see it, and a pasteboard generation the keyboard has not been
  allowed to read (`CopyClipCaptureState.control`) makes Reply refuse rather than
  answer the clip behind it — answering the previous message in the user's name is
  exactly the failure the capture path's freshness gate existed to prevent.
- Two refusal states rather than one sentence, because the work is different, and
  each names the next move rather than the feature. `nothingCopied`: "Copy the
  message you want to answer, then let it in with CopyClip's Paste."
  `copyNotRead`: "Tap Paste in CopyClip, then tap Reply and it answers what you
  copied", which is the one refusal with a control behind it, since `offersCopyClip`
  opens the panel that draws `UIPasteControl`.
- The secure-field guard must hold. Reply never runs against a password field.

**Three taps, not two.** Copy the message in the app you are reading it in, tap Paste
in CopyClip, then tap Reply — the gesture `HomeView.replySteps` teaches and both
refusals name. The middle tap is the whole point rather than a step to be optimised
away: reading the pasteboard's *contents* is what raises Apple's "Allow Paste?"
alert, so this keyboard does not, and the user's tap on Apple's own `UIPasteControl`
is the permission. NIT-159's issue text says "two taps" and is wrong; this file is
what the copy should be written against.

No entitlement, no broadcast, no alert, and it works in every app that lets you copy
text. Compare with what it replaces: open the app, start a broadcast through Apple's
picker, accept the three-second countdown, keep a screen recording running. It also
stays the better path for many people *after* NIT-6 passes, because it works with no
session running and no recording indicator on screen.

## The exact condition for flipping the flag back on

**NIT-6 passing on a real device** — a broadcast actually starts from the keyboard's
picker, `SampleHandler` is actually invoked, a frame actually reaches
`RoutedScreenReader` — **and NIT-12 measuring the extension under the ~50 MB cap.**

Both, not either. NIT-13 and NIT-14 are likely to be answered on the way, but they
are not the gate; the gate is one working loop and one memory number.

**"The code compiles" is not the condition.** It already compiles, it already passes
its tests, and it has already been proved across two processes over synthetic frames.
None of that is the same as a frame arriving from `replayd`. That is exactly the
inference this repository has been bitten by before, and `FeatureFlags`'s own doc
comment states the general rule: the only thing a flag is allowed to mean here is
"the code is finished, the evidence is not."

## The cost of this decision, stated honestly

**The landing page's entire ImmersiveStory was built around Reply reading the
screen.** Its first beat was, literally, "Reply reads the conversation and sees Maya
asking about Thursday." The hero line, the main feature card and the first scroll
beat were all the same claim, and that claim was the one feature that has never run.
Removing it takes the emotional centre out of the site: "the keyboard sees what you
see" is a better story than anything that replaces it, which is why it was built
first.

What replaces it is smaller and true: Hebrew autocorrect that understands how Hebrew
words are built, a keyboard whose rows the user can rebuild, dictation that keeps
English loanwords in Latin letters. Those are measured (`Bar/typing/`,
`Bar/dictation/`, `Bar/layouts/`), and none of them needs a paragraph explaining a
permission. The trade is a weaker hook for a claim that survives contact with a
reviewer.

Second cost, smaller: the analytics policy's sixth event,
`screen_context_session_started`, is dormant while the flag is false, because the
entry points that could raise a real capture session are not in the build. It is kept
rather than deleted, for the reason its own doc comment gives: this is a dated hold on
shipping the feature, not a decision to stop measuring it, and a policy-approved event
removed and re-added later is a second trip through the same review.

## What this document does not decide

Whether the ReplayKit path is ever finished. That is NIT-6's outcome, not this
document's. This says only that it is not in v1, and what evidence would put it back.
