# The App Store story

NIT-25. The positioning argument for leading with the layout editor rather than the
AI actions, and the concrete assets it implies. Every claim below is checked against
`README.md`'s table of what is measured versus what is only compiled, and against the
code that implements it. Where the strongest line would overclaim, the weaker line
is written instead, with a note on what would have to become true to earn the
stronger one.

**This entire story depends on NIT-24 landing.** A custom layout is stored in the App
Group, which the keyboard extension cannot reach until Full Access is granted, so a
user who declines the permission today can design a keyboard in the editor and then
type on the default one in every other app, with nothing on screen telling them the
two have diverged. NIT-24 gives the layout editor and the language picker a visible
state saying the setting is saved but the keyboard will not use it until Full Access
is on. This document is written on the assumption that state ships alongside the
screenshots and copy below. See "Without NIT-24" at the end for exactly which asset
becomes dishonest if it does not.

## The positioning argument

**The most differentiated thing in this product is the one nothing sells: the fact
that a user can rebuild the keyboard itself.** Rearrange the action row and the
bottom row, resize three independent height bands, add a number row, pick a brand
accent, choose from five named presets. `LayoutValidator` refuses a layout that would
not work; `CustomLayoutCompiler` turns whatever is built into the same `KeySpec` rows
the measured layouts produce, so the width solver and `KeyView` never learn the
feature exists. No screenshot has to argue this is a real feature rather than a demo,
because the compiled output is indistinguishable, in the code, from the shipped
default.

Lead with the layout editor, not the AI actions, for four separable reasons, and none
of them is "the AI features are weak." They are real and measured; the case for
leading with the editor instead is about what a static screenshot can prove, and
about what makes this specific product different from every other keyboard on the
store, AI or otherwise.

**A screenshot of the editor is not a mockup of the product, it is the product.**
`LayoutView`'s own comment states the design directly: "the canvas is the real
`KeyboardView`. Nothing here redraws the keyboard for editing, so what the user
arranges is literally what they get." A screenshot of dragging a key or resizing a
row shows exactly what a user gets a second after taking the same action, which
satisfies Apple's screenshot-accuracy expectations by construction, with zero risk of
a screenshot depicting something the shipped build does not do.

**The editor's value is legible in one still image; the AI actions' value is not.**
"Drag this key here" and "make this row taller" are understood from a single frame.
"This AI fixed my sentence" is not: a static before/after of a Fix action looks
identical to any keyboard's spell-check screenshot to someone scrolling the App
Store, because the thing that is actually different (that a model, not a dictionary,
produced it) is invisible in a still frame. That gap is a property of the screenshot
medium, not of the feature.

**The editor is the more differentiated claim for what this product actually is.**
An "AI keyboard" is a crowded, already-familiar pitch in 2026. A keyboard whose rows
you rearrange and resize, and whose one saved shape then applies across all 64
languages it types (`KeyboardLanguage.allCases`, confirmed at 14 entries in
`LanguageCatalogue.swift` and 50 more in `LanguageCatalogueExtended.swift`), is a
narrower and more concrete claim that a genuinely bilingual product can make and a
single-language competitor cannot: the three letter rows stay per-language
(`letterLayouts`), but the action row, the bottom row, the number row, key height,
row spacing, and one-handed reach are one `KeyboardCustomization` that applies to
every one of them, per `.claude/rules/keyboard-layout.md`'s own note that this is
"what makes *one* stored layout correct for all 64."

**The editor's feature set has no "not built" caveat attached to it, and the AI
actions' screen-reading half does.** `LayoutEditorTests` and
`AIKeyboardUITests/CustomLayoutRenderingTests` exercise dragging, resizing, presets,
one-handed reach on both languages, and a key added in the editor actually typing
into the host. Nothing in README's "Not built" section names the editor. Reply's
screen-reading path, by contrast, has never executed anywhere: "the iOS Simulator
ships no `replayd`, so no broadcast session starts here and `SampleHandler` has never
been called." Leading the store page with a feature that has run, end to end, on a
real device is a materially safer marketing decision than leading with one that has
not. See "What would have to become true" below for what closes that gap.

This does not mean the AI actions disappear from the page. Fix, Rewrite and Dictate
are real, measured, and stay in the sequence below; Reply and screen context are the
one feature this document recommends holding back from the launch set, for the
specific reason above.

**"No other iOS keyboard lets a user build their own keyboard this way" is a claim
about the App Store category, not about this codebase, and this document cannot
verify it.** Nothing in `README.md`, `AGENTS.md` or the code speaks to what competing
keyboard apps ship. Treat it as the issue author's own read of the market, worth
using as the positioning premise, but confirm it against the current App Store
listing pages for the obvious competitors before it appears as a comparative claim in
copy Apple or a user could check.

**This story does not sidestep the Full Access problem, and does not hide it
either.** Editing a layout needs no backend and no network: the canvas the user drags
and resizes is a local SwiftUI view, and the presets, validator and compiler all run
in-process. What needs Full Access is the *keyboard extension* reading that saved
layout back, because `SharedStore` only reaches the App Group once Full Access is
granted; without it, `SharedStore` falls back to `.processLocal`, invisible to the
extension, and the user types on the default layout everywhere outside this app.
NIT-24 is what turns that silent gap into a stated fact on screen, in the editor and
in the language picker, and this document's screenshots and captions are written to
show that state rather than to talk around it: screenshot 2 below carries it directly
in its caption. A store listing that promised a rebuildable keyboard while leaving
part of the audience typing on the unchanged default, with nothing telling them so,
is exactly the kind of overclaim this document exists to prevent.

## The counter-argument: lead with Hebrew (added 2026-08-18)

**The landing page now leads with Hebrew, not with the layout editor, and that is a
deliberate disagreement with the section above rather than an oversight.** It is
recorded here rather than replacing the argument above, because the argument above is
good and most of it survives; what changed is which of two true claims goes first.

The disagreement in one line: **a rebuildable keyboard is differentiated but is not
by itself a reason to switch keyboards, whereas Hebrew autocorrect that works is.**

Four reasons, in the order they carry weight.

**Installing a keyboard is a switching decision, and switching costs muscle memory.**
The thing that makes someone pay that cost is a daily irritation, not a capability
they did not know they wanted. For the audience this product is built for, the daily
irritation is that Hebrew autocorrect is bad: a hand that lands one key over could
not be repaired at all until `TypoChannel` and `TypoLexicon` landed, `לעבודה` is one
token no dictionary lists, and Apple's Hebrew checker calls `תדוה` and `שלמו`
perfectly good words. "Your keyboard finally fixes Hebrew" answers a complaint the
reader already has. "You can rearrange the rows" answers one they do not.

**Customisation is a second-session feature.** Nobody rebuilds a keyboard they have
not yet decided to keep. The layout editor is what makes someone stay and what they
tell a friend about; it is a poor argument for the first thirty seconds, when the
reader is deciding whether this is worth a Settings trip and a Full Access dialog.
Ordering the page Hebrew first, layout second matches the order in which those two
claims actually do their work.

**The two claims are not equally hard to copy.** A competitor can add a layout editor
in a release. Hebrew that reaches `לעבודה` from `לעבו` is `HebrewMorphology` splitting
the clitics ה ב ל מ ו ש כ, a frequency prior over 300,000 sentences, a typo channel
that prices a slip by *kind* rather than counting edits, and a wrong-plane rule that
turns `akuo` into `שלום`. Apple's own stack has no Hebrew in three places out of four
(Foundation Models, `SpeechTranscriber`, Vision's text recogniser; `UITextChecker` is
the exception and its Hebrew is weaker than it sounds). That is the moat, and it is
the one thing on the page a well-funded competitor cannot ship next quarter.

**The evidence is stronger on the Hebrew side, and it is the kind that matters.** The
editor's evidence is that it works: `LayoutEditorTests`, `CustomLayoutRenderingTests`,
nothing in README's "Not built". The Hebrew claim's evidence is that it works *better
than the alternative*, which is a different and more persuasive kind: 75/76 on
`Bar/typing/corpus.json` against 47/76, and 90 of 107 misspellings corrected against
61, with what ships (`AutocorrectLevel.shippedDefault`) reading 73/76 and 85 of 107
while cutting the wrong-word column from 10 to 3. Those numbers do not go on the
store page (see the last section of this document, which still stands), but they are
why the claim can be made at all.

**What survives from the argument above, unchanged.** The screenshot medium point is
correct and was not the thing being disputed: a still frame proves the editor and
does not prove an AI action. That is exactly why the layout editor keeps a prominent
slot with a visual rather than being demoted to a footnote, and why the landing page
sells Hebrew through a scrolling story and one legible chip (`akuo → שלום`, a
before/after nobody can mistake for stock autocorrect) rather than through a still
frame of a corrected word, which would indeed look like any other keyboard's
spell-check screenshot. Also unchanged: Reply stays out of the launch set (now for a
stronger reason, see `.claude/docs/screen-capture-v1-hold.md`), no `Bar/` number
appears in consumer copy, the 64-language claim stays scoped to typing and the
layout, and the AI-action claims stay scoped to Hebrew and English.

**What this changes concretely.** The keyword field above already leads with
`hebrew`, so it needs no edit. The subtitle "A keyboard shaped like you" was chosen
to mirror the landing page's old hero line ("A keyboard that writes with you"), and
that mirror is gone: the hero is now "Hebrew autocorrect that actually works." If the
subtitle is meant to keep mirroring the site, it wants a Hebrew-first phrasing within
the 30-character limit. The description's opening two sentences above still lead with
the editor; under this counter-argument they should lead with the Hebrew claim and
keep the editor as the second sentence. Neither edit is made here, because the store
listing is a separate deliverable from the landing page and should be changed
deliberately rather than as a side effect of a copy pass on the site.

**What would change this back.** If the store listing turns out to need a still image
that proves its headline claim, and no single frame can prove Hebrew autocorrect the
way one frame proves a dragged key, then the editor is the better *store* hero even
while Hebrew stays the better *site* hero. The two surfaces are allowed to differ,
and this document governs the store.

## Screenshot sequence

Five screenshots, in order. Each is a real, capturable app state, not a composite.

1. **The layout editor, mid-drag.** A key lifted off the action row, hovering over
   the bottom row, the spare-keys tray visible above the keyboard.
   Caption: **"Rearrange it. This is the real keyboard, not a preview."**
   Grounds in `LayoutView`'s own documented invariant that the canvas is the live
   `KeyboardView`.
2. **The layout editor's "Size and rows" panel**, with the number row toggled on and
   the one-handed reach picker showing Left selected, keyboard visibly narrower and
   pushed to one side, and NIT-24's saved-pending-Full-Access state visible in frame.
   Caption: **"Build it your way. It's yours the moment Full Access is on."**
   Grounds in `LayoutGeometrySection` (key height per row band, row spacing, number
   row toggle, one-handed `Reach` picker) and the five named presets in
   `LayoutPresets.swift` (Default, Compact, Roomy, Power, AI first). The caption
   states the Full Access dependency as a fact rather than hiding it, which only
   reads honestly if NIT-24's on-screen state is what the screenshot actually shows.
3. **A live sentence mixing Hebrew and English**, the suggestion bar showing a
   loanword prediction tagged with its source language, one layout in use.
   Caption: **"One layout. Sixty-four languages, Hebrew and English side by side."**
   Grounds in the onboarding Welcome step's own claim ("Sixty-four keyboards, one
   swipe apart") and the code-switching prediction feature named in README's "What's
   built."
4. **Fix or Rewrite in progress**, the progress line above the suggestion bar, the
   undo control visible beside the result.
   Caption: **"Fix a sentence, or change its tone, in one tap. Undo is right there."**
   Grounds in README's "AI actions are small and reversible, never a chat box" design
   decision and the `Bar/ai-text/` corpus that scores Fix, Rewrite and Tone.
5. **Dictation mid-session**, live words appearing in the field, the microphone key
   red.
   Caption: **"Speak it. It types as you go, punctuated, in either language."**
   Grounds in `DictationService`/`SpeechGate`/`CloudDictation` being real and scored
   against `Bar/dictation/`'s 36 clips.

Reply and screen context are deliberately not in this set. See "What would have to
become true" below.

## Subtitle

**"A keyboard shaped like you"** (26 characters, well inside the App Store's 30
character limit). Mirrors the landing page's own hero line, "A keyboard that writes
with you," swapping the verb the way this issue asks the store page to: shaped, not
just written-with. Both are true of the shipped product.

## Keywords

100-character comma-separated field, no spaces after commas, no repeats of words
already indexed from the app name or the subtitle above (drop "keyboard" itself for
that reason):

```
hebrew,layout,custom,resize,rows,bilingual,onehanded,dictation,rewrite,dictionary,fix,tone,emoji
```

96 characters. Layout and customization terms lead, because that is this document's
story; "hebrew" is kept over a generic "translate" or "language learning" because it
is the real, specific differentiator README supports; "ai" and "keyboard" are dropped
as redundant with the app name and subtitle rather than spending characters on words
Apple already indexes for free.

## Description, opening lines

The visible-before-"more" portion on an iPhone product page is roughly the first two
sentences. They should not mention Reply, for the same reason it is out of the
screenshot set.

> Drag keys between rows, resize them, add a number row: build the keyboard your
> thumbs actually want, and it works that way across all 64 languages this keyboard
> types, Hebrew and English side by side. Turn on Full Access and it's the keyboard
> everywhere you write. Then let it fix a sentence or shift its tone in one tap, with
> the undo always one keystroke away.

The Full Access line sits in the second sentence rather than a footnote, the same way
the landing page already states it plainly for Hebrew AI features ("Reply, Rewrite,
and cloud dictation need it. Typing works without it.") instead of treating it as
something to apologize for. The rest of the description can go on to cover dictation
and Reply further down, where an overclaim does not set the reader's first
impression of what the app promises. Hebrew Fix, Rewrite and Reply need the same
Full Access line wherever they are mentioned in the body, because they need the
cloud path and Full Access is what gives the keyboard a network at all.

## Onboarding order

**NIT-15 landed on 2026-08-18, and it changes what two of the three options below
cost.** The flow is now three required screens (welcome, add-keyboard,
practice-writing) with five optional ones behind a "Show me more" button at the end:
palette, languages, microphone, practice-everyday, practice-smart-tools. There is no
Full Access step anywhere in it. The paragraph below that treats NIT-15 as a proposal
was written before that, and its conclusion survives intact, since all three options
were chosen to be Full-Access-independent. What changes:

- **Option 1 gets stronger.** Welcome is now one of only three screens every user
  sees, so a fifth `InfoRow` there is a larger share of the whole flow than it was.
- **Option 2 gets weaker, and its premise is gone.** Palette is no longer step 1; it
  is optional, reached only by a user who asks for more at the end. A pointer into
  the layout editor placed there is seen by the subset who opted in, which is close
  to the deferral the option was written to fix. If the editor is worth pointing at
  early, Welcome is now the only screen early enough.
- **Option 3 is unchanged**, and still costs what it said it costs: `.writing` is on
  the required path while `.everyday` and `.smartTools` are optional, so a new stage
  would have to choose a side, and that choice is the estimate rather than a detail
  of it.

The issue asks where the editor should sit so a user meets it early rather than
finds it in a tab. Two moves below are genuinely "not new engineering," matching how
the issue scopes this document; a third, stronger move is not, and is flagged as
such rather than folded in as if it were free. None of the three depends on Full
Access being granted, or even asked for, which matters because NIT-15 proposes
removing the upfront Full Access step from onboarding entirely and raising it at the
first moment it buys something. An onboarding order that only works if Full Access
has already happened breaks the moment NIT-15 ships, whatever NIT-15 decides.

1. **Zero engineering: add a fifth bullet to the Welcome step.** `WelcomeStep` already
   lists four `InfoRow`s before any setup begins ("Types in both languages at once,"
   "Fix and rewrite in one tap," and so on). A fifth, stating the differentiator
   directly ("Build your own layout: move keys, resize rows, add a number row"), is a
   string added to an existing list, in the first screen every user sees, before the
   first tap of setup.
2. **Low engineering: turn the Palette step's throwaway line into a pointer.** Palette
   (`OnboardingPaletteStep.swift`, step 1, already themed "Make it yours") currently
   ends with "You can change this later in Keys," which is exactly the deferral this
   issue argues against: it tells the user the editor exists and then points them
   away from it. Replacing that caption with an explicit link into the layout editor
   is a small addition to a step that already exists for personalization, not a new
   step.
3. **Real engineering, not scoped here: give the editor its own practice stage.**
   `OnboardingPracticeStage` already runs three guided stages
   (`.writing`, `.everyday`, `.smartTools`) on a `MockTextTarget`-backed
   `KeyboardController`, so adding a stage ahead of those three would stay
   Full-Access-independent the same way options 1 and 2 do. But those stages embed
   `KeyboardPreview`, a keyboard a user *types into*; `LayoutView`'s own canvas is a
   different and heavier piece of UI, built around `GeometryReader`-tracked key
   frames, a spare-key tray, and drag and resize gestures, currently reached only by
   a pushed `NavigationLink` from the Keys tab. Making that canvas run inside the
   TabView-paged onboarding flow is an integration task, not a copy edit, and this
   document does not claim otherwise. If this is worth doing, it is worth its own
   estimate rather than being waved through under "not new engineering."

## Where the strongest line would overclaim

**Without NIT-24, this entire story overclaims, and two specific assets are the
worst of it.** Every screenshot and caption above is written assuming NIT-24's
visible "saved, applies once Full Access is on" state ships in the layout editor and
language picker. If it does not land before this story ships, name these two
explicitly rather than shipping the story as written:

- **Screenshot 2's caption, "Build it your way. It's yours the moment Full Access is
  on,"** becomes false rather than merely incomplete: without NIT-24 there is nothing
  on that screen saying so, the editor's Done button behaves identically whether or
  not Full Access is granted, and a user who has not granted it sees no distinction
  between "saved" and "saved and live." Revert this caption to something that does
  not claim persistence at all, for example "Taller keys, a number row, one thumb's
  reach," and drop the Full Access sentence.
- **The description's second sentence, "Turn on Full Access and it's the keyboard
  everywhere you write,"** implies the first sentence's promise ("build the keyboard
  your thumbs actually want") is conditional and known to the reader as such. Without
  NIT-24 that condition exists in the code but not on any screen the user sees while
  editing, so the honest opening drops the whole build-your-own-keyboard framing down
  to a single caveated sentence, which is a materially weaker opening than the one
  above, and is exactly why this document treats NIT-24 as a dependency rather than a
  footnote.

**"Reply reads your screen and drafts an answer," as a headline claim: overclaims
today.** Nothing about the ReplayKit capture path has ever executed on any device,
simulator or hardware: "None of the ReplayKit half has ever run, because the iOS
Simulator ships no `replayd`." What would have to become true before this belongs on
the store page or in a screenshot: a real device confirms a broadcast session
actually starts from the keyboard's picker, `SampleHandler` is actually invoked,
frames actually reach `RoutedScreenReader`, and the whole loop is exercised by a
person other than the one who wrote it. Until then, the honest line is that Reply
exists as a feature you can turn on, tested down to the keyboard reading a shared
status file, but not yet proven end to end, and that line does not belong in a launch
screenshot.

**"AI actions work in all 64 languages," alongside the 64-language typing claim:
overclaims.** The typing and layout claim is real for all 64 (see above); the AI
actions are not scored anywhere near that breadth. `Bar/ai-text/corpus.json` covers
exactly three configurations: English only, Hebrew only, and Hebrew with English
loanwords, the case the product is built for. Foundation Models on device covers
Apple's own supported-language list; the cloud path covers the rest, but "the rest"
has not been measured on this bar. Keep the 64-language claim scoped to typing and
the layout editor, where it is earned, and keep the AI-action claims scoped to
Hebrew and English, where they are scored.

**"Dictation keeps up when you switch language mid-sentence": already correctly kept
out of the app, and should stay out of the store page too.** `WelcomeStep.swift`'s
own comment explains why this line was removed from onboarding: code-switched speech
is measurably the weakest case, "the thing it is *worst* at." README's own numbers on
`Bar/dictation/`'s 36 clips put it at 23.5% word error rate, against 8.5% for English
alone and 10.7% for Hebrew alone, and both in-code comments now say the same
(`WelcomeStep.swift` and `CloudDictation.swift`, corrected 2026-08-16). Until that
date they carried a set built around 17.7%, and the sentence here called it "an
earlier run of the same corpus" — which was the charitable reading and the wrong one.
`harness/score.py` over every committed outputs file reproduces
`Bar/dictation/README.md` exactly and produces 17.7% nowhere, and that set was
committed in `d023520f` alongside the scorer itself, so it predates the scoring rule
that ships and came from code that never landed. The lesson is not the usual "one
corpus run is not evidence" — it is that a number nobody can re-derive from the
committed harness is not a reading at all, and the fix is to score the corpus rather
than to quote a comment. Do not reintroduce this claim on the store page
after the app's own code already decided against it. The safe claim is that
dictation is real, live, and works in either language, which is true and already in
the screenshot sequence above; the seamless-switching claim is not, and should wait
for the number the in-app comment is waiting for.

**Any WER, accuracy, or benchmark number from `Bar/`: does not belong in App Store
copy at all, in either direction.** These are internal, dated readings taken for
engineering decisions, not consumer-facing marketing claims, and `AGENTS.md`'s own
rule that "one corpus run is not evidence" and that numbers move meaningfully between
runs makes them a poor fit for a store listing that cannot be dated or caveated the
way this repository's own docs are. The screenshot captions above describe what the
features do, not how well, for this reason.
