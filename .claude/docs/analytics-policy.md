# Analytics policy

NIT-16. A decision, not a survey: what this app measures, what it never measures, and
which of the five questions the decision genuinely cannot answer.

## 1. The decision

**Instrument the companion app's own surfaces only, using state the app already
computes for its own screens, and change nothing about what the keyboard extension
or the broadcast extension do.** `AIKeyboardExtension` and `AIKeyboardBroadcast` emit
zero analytics events, forever, independent of Full Access, subscription state, or
any feature shipped later: the boundary is absolute, not a default that a future
feature is allowed to cross quietly. Inside that boundary, the app reports six events
built almost entirely out of measurements it already takes for its own UI:
`SetupState`/`KeyboardPresence` already tell Home and onboarding whether the keyboard
was added and Full Access confirmed; `ScreenContextSession.shared` already tells
`HomeScreenContextCard` whether a real broadcast is live. Turning an existing
on-screen state into a counted event costs nothing new in what the app is capable of
reading. It costs only whether that reading is reported anywhere. That is a narrower
and more defensible line than "instrument the app," because it rules out the obvious
next move (a companion-app proxy for what the keyboard does with real text, argued
for in section 4) rather than leaving it for the first engineer in a hurry to add.

## 2. The exact event list

Every event carries a fixed envelope and nothing else besides its own properties: an
anonymous, locally generated, resettable install identifier (never IDFA, never a
value that identifies a person), app version, OS version, event name, and a
client timestamp. No event below repeats this envelope in its own property list.

Onboarding is **ten steps today**, not the six the issue text names: seven setup
steps (`OnboardingFlow.setupStepCount`) plus three guided practice stages
(`OnboardingPracticeStage.allCases`), confirmed by `AIKeyboardUITests`'s own comment
("Ten steps today, so the bound has to clear ten taps, not equal them"). The schema
below uses the real count so a query written against it does not silently misread
step 7 as "done."

1. **`onboarding_step_advanced`**: `step_index` (Int, 0-9), `step_name` (`welcome`,
   `palette`, `languages`, `add_keyboard`, `full_access`, `switch_confirmation`,
   `microphone`, `practice_writing`, `practice_everyday`, `practice_smart_tools`),
   `via` (`continue` | `skip` | `switch_confirmed`). Fired in
   `OnboardingFlow.primaryAction()` / `skipAction()`, the instant `step` increments.
   Answers **Q1**: the full per-step funnel, including whether people stop at the
   six-step "reach a working keyboard" boundary (`step_index <= 6`) or carry on into
   the practice tour.
2. **`onboarding_completed`**: `skipped_step_count` (Int, how many of the ten were
   advanced via Skip rather than Continue). Fired when `store.hasCompletedOnboarding`
   is set true. Answers **Q1**.
3. **`full_access_confirmed`**: no properties. Fired once per install, on the first
   `SetupState.current(store:)` recompute (Home's `onAppear`/`scenePhase`, or
   onboarding's own) where `fullAccess` reads `.confirmed`. Needs a one-time local
   flag so it fires once, not on every return to foreground. Answers **Q2**, the
   grant side.
4. **`keyboard_added_confirmed`**: no properties. Same shape as 3, on the
   0-to-confirmed transition of `SetupState.keyboardAdded`. Answers **Q2**'s second
   half: joined against event 2 (onboarding completed, no event 3 or 4), it separates
   "never added" from "added, no Full Access": the dominant failure mode
   `SetupState.unresolvedExplanation` already names as indistinguishable from the
   app's side without a current record.
5. **`app_session_started`**: `days_since_install` (Int). Fired once per calendar
   day, on the first time the app becomes active that day. Answers **Q5**, partially
   (see section 4 for the gap this event cannot close).
6. **`screen_context_session_started`**: no properties. Fired the instant
   `ScreenContextSession.shared` (already observed by `HomeScreenContextCard`)
   transitions `isCapturing` false to true with `source == .capture`, a real
   broadcast rather than the scripted sample. Answers **Q3**'s first half: whether
   anyone starts the feature at all.

That is the complete list. Nothing else goes in. In particular, no event fires for
which AI action a user picks in the onboarding practice tour or the Playground:
section 4 explains why that tempting addition does not belong here even though it
would be easy to build.

## 3. The never list

Quotable as written:

- **The keyboard extension and the broadcast extension send nothing, ever.** Not a
  counter, not a timestamp, not a crash report with a string in it, whether or not
  Full Access is on, whether or not a subscription is active, whether or not a
  future feature ships. If that boundary is ever crossed, it is a new decision, not
  an extension of this one.
- **No event carries anything typed, corrected, dictated, or read off a screen.** No
  keystroke, no autocorrect, no accepted or rejected suggestion, no personal
  dictionary entry, no AI input or output, no screen-context reading, no message,
  contact name, or app name. Not in a property, not in a free-text field, not
  truncated, not hashed. The six events above are counters and state transitions;
  none of them has a slot a string could go in.
- **No AI action tap is logged from inside a real conversation.** Fix, Rewrite,
  Reply and Tone running against real text in WhatsApp, Notes, or anywhere else are
  invisible to this policy by construction, because that code runs in the extension.
  This is the concession named openly in section 4, not something worked around by
  moving the count somewhere else.
- **No advertising or cross-app identifier.** No IDFA, no fingerprinting, nothing
  that survives a reinstall or that another app's SDK could correlate against. The
  envelope's install ID is locally generated and resettable.
- **Nothing here is sold, shared with a third party for their own purposes, or used
  for advertising.** Consistent with the existing "Never sold" line on the privacy
  page, extended explicitly to analytics rather than left to imply it.
- **This policy governs product analytics, not the backend's own operational
  logging.** `Backend/`'s App Attest verification and rate-limit counters already
  exist for abuse prevention and are out of scope here; they are not repurposed to
  answer any of the five questions, and this document does not touch them.

## 4. The unanswerable questions

**Q1, onboarding funnel: fully answered.** Events 1 and 2 give the complete ten-step
funnel, including the split between "reached a working keyboard" and "went on
through the practice tour."

**Q2, Full Access grant rate and where the rest stop: answered, with one gap.**
Events 3 and 4 need the app to be reopened after the user leaves Settings:
`SetupState` is recomputed on foreground, not pushed from the extension. Someone who
grants Full Access and never reopens the app is invisible to this measurement, same
as they are invisible to the checklist itself.

**Q3, is Reply used, is screen context a feature nobody starts: split, and half of it
is given up.** "Does anyone start it" is answered by event 6, because
`ScreenContextSession.shared` is a real, local, already-computed signal the app reads
for its own Home card. "Is Reply used," meaning does the action actually run against
a live screen, in a real conversation, and produce something the user keeps, is not
answered and is not answerable under this policy, because that entirely happens
inside the keyboard extension, against a real screen, in front of a real recipient.
This is the exact shape of instrumentation the issue's own tension paragraph warns
against, so it is given up rather than approximated. What it would cost to answer:
a keyboard-side event on every Reply tap, which is precisely "a keyboard that phones
home about typing."

**Q4, which AI action is actually used: given up entirely.** The real answer lives
inside the extension, against real text, and stays there. Do not build the tempting
substitute: logging which action a user taps in the onboarding practice tour or the
Playground, as if it answered this question. A tap on Fix inside a guided tutorial
step is someone completing a task they were told to do, not someone choosing Fix
over Rewrite while writing to a person; conflating the two produces a plausible-looking
number that measures the wrong thing, which is worse than no number, because it will
be trusted. If tutorial-step completion is worth watching, it is already covered by
event 1's `step_name` values for the three practice stages: that is a funnel
measurement, not a usage measurement, and should never be relabeled as one. What it
would cost to genuinely answer this: a local, count-only tally inside
`AIKeyboardExtension` (four integers, no text, incremented on each action) written to
the App Group the same way `KeyboardPresence` already is, then read and reported by
the app on its next launch. That shape stays within "the keyboard makes no network
call," but it is not what ships today. `KeyboardPresence` records a one-time
capability fact ("Full Access is on"), and a per-action tally is a standing
behavioral log the extension would carry from that point on. That is a materially
different privacy posture from anything the extension does now, and it deserves its
own explicit decision rather than being smuggled in as an implementation detail of
this one.

**Q5, retention past week one: the weakest of the five, and mostly given up.** Event
5 measures whether the *companion app* gets reopened, which Apple's own App Analytics
already gives for free (see section 5). The question actually being asked is whether
the *keyboard* keeps getting used, and a keyboard's whole value is running invisibly
inside other apps without the companion app ever needing to reopen, so a happy,
daily user who set up once and never looked back reads as churned by this
measurement, while someone who reopens the app to fight with a stuck setup reads as
retained. `KeyboardPresence`'s local record (last seen within 72 hours, per
`SetupState.isCurrent`) is a closer proxy for actual keyboard use and could ride
along as a property on event 5 (`keyboard_seen_recently: Bool`), but it is still
gated on the app being reopened to report it, so it under-samples exactly the
retained-but-invisible user it is trying to measure. Full keyboard retention,
independent of app opens, is not answerable without extension-side telemetry, which
this policy rules out. Ship event 5 as the closest honest proxy, and read it as
"companion app retention," never as "keyboard retention," in any report that uses it.

## 5. The vendor question

**Two sources, no third-party SDK.** Use Apple's own App Store Connect Analytics for
what it gives free, today, with zero code: install counts, session counts, day-1/7/28
retention curves, and crash reports, aggregated with Apple's own privacy thresholds.
It answers the app-open half of Q5 without this project writing a line for it. For the
six events in section 2, add a first-party endpoint on the existing Cloud Run backend
(`Backend/`), reusing the transport this project already ships rather than adding a
second one: `BackendTransport` already exists, and a lightweight, unauthenticated
`/v1/event` path is a reasonable shape for a payload with no cost or abuse profile
worth gating behind App Attestation, though that is an implementation detail for
whoever builds this, not a call this document needs to make.

**Reject a third-party SDK (Firebase, Mixpanel, Amplitude, PostHog, or similar).**
Three reasons, and any one of them is sufficient here. First, this project's own
description is "no third-party dependencies": `AGENTS.md` says so as a stated fact
about the codebase, and an analytics SDK is a dependency running inside the same
process that holds Full Access to a shared container, not an unrelated tool bolted on
the side. Second, the issue's own bar for this decision is "defensible if someone
reads the network log": a first-party endpoint is fully readable by anyone who reads
this repository, because the six events and the one call site are all there is. A
third-party SDK's claim of "no content collected" is a promise made by someone else's
closed binary, and it cannot be checked against source the way this project's own
code can. Third, a keyboard extension's Full Access warning is exactly the fear this
issue opens with, and a stranger's SDK inside the app that holds that access is a
second copy of the same fear this decision exists to put to rest.

## 6. The privacy copy consequence

One sentence, or close to it, has to appear in two places: the landing page's privacy
page (`Landing/app/privacy/page.tsx`), as a new section after "Never sold," and
somewhere in the app itself. The natural spot is beside the existing "What we never
send" row on the Full Access onboarding step (`OnboardingFullAccessStep.swift`) or in
a Settings/About screen, whichever the app's owner prefers; this document recommends
the location but leaves the edit to whoever owns those files.

Recommended wording, matching the existing privacy page's short, declarative
sentences:

> **What we count.** The app counts how far setup gets, whether Full Access and the
> keyboard were confirmed, whether you open a screen-sharing session, and whether you
> come back to the app. It never counts a keystroke, a correction, a dictated word,
> an AI answer, or anything read off your screen. The keyboard itself sends nothing,
> with or without Full Access.

The existing "Cloud, only when you tap" and "Never sold" sections stay as written;
this is a fourth, separate point, not a rewrite of either.
