# What the test suite actually reports

NIT-92 exists because nobody knew. This file is the answer, with a date and a
commit on it, so the next person can tell a new failure from one that was
already there. **Re-run it and update this table rather than trusting it**: every
number here is a reading, not a property of the code.

## The run

| | |
|---|---|
| Date | 2026-08-17 |
| Commit | Working tree over `50c8bf87`, after the row-height transfer and the two stale assertions below. |
| Destination | iPhone 17 Pro, iOS 26.2 simulator, uncontended |
| Command | `xcodebuild test -project AIKeyboard.xcodeproj -scheme AIKeyboard -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:AIKeyboardCoreTests` |

**`AIKeyboardCoreTests`: 1386 executed, 2 failed, 3 skipped.**

Both are `EmojiModeTests` **ranking**, which is the one genuine product decision
left; the section below carries the measurement that says why it must not be
tuned by hand. The 3 skipped are what the earlier run's "1257 declared, 1252
executed" gap actually was; `xcodebuild` reports them, so read the skip count
rather than subtracting.

### Since that run: the emoji tone strip, checked without a simulator

`EmojiModeTests` gained 10 tests with the skin-tone picker and **the suite has not
been re-run on a simulator since**, so the count above is still the count above.
What *was* done instead is worth recording, because it costs nothing and answers
most of the question:

- A Linux Swift toolchain compiles `EmojiCatalog.swift`, `EmojiSkinTone.swift`
  and `EmojiSearch.swift` — the three the fidelity check already treats as
  Foundation-only — against the shipping `EmojiCatalog.json`. Every assertion in
  the four catalogue tone tests and in the two pre-existing catalogue tests was
  run that way and passes. So did `Bar/emoji/harness/swift-check.sh`'s own
  comparison, ported to that toolchain: **147/147 result lists identical** to
  `rank.py`.
- `EmojiTonePicker`'s geometry is pure arithmetic over `CGRect`, which Linux
  Foundation has, so the placement sweep runs there too: 55 configurations, all
  green.
- **The two known ranking failures were re-confirmed, and confirmed unchanged.**
  Running the four ranking tests' bodies against the *new* catalogue and against
  `main`'s gives the identical pair — `לב` → 🫀 and `car` at index 5 — which is
  what says the catalogue regeneration (see `pack()` in the generator) moved no
  ranking at all.

What none of this covers is SwiftUI: `EmojiTonePicker.swift`'s view and gesture,
and `EmojiPanel`'s wiring to them, parse and format clean and have not been
compiled. **Re-run the suite on a simulator before trusting the number at the top
of this file again.**

### The previous reading, and the two that were red for a reason nobody had checked

2026-08-16 at `45fe74c8`: **1302 executed, 1296 passed, 3 failed, 3 skipped**,
recorded above as "all three are `EmojiModeTests` ranking". That was true of that
run and had stopped being true by `6a7dbd31`: two *different* tests were red and
one of the three emoji ones had gone green, so the count matched while the
contents did not. Both were confirmed on a pristine `git archive 6a7dbd31`
export before anything was touched — the method this file already recommends, and
the reason it is worth the ten minutes — and both turned out to be **stale
assertions rather than product questions**, the same category the four below fell
into.

`CustomLayoutTests.testNoActionAppearsInTwoRowsOfAnyPreset` was reporting a real
defect in the shipped presets: `ad5356e4` moved Rewrite and dictation into the
default `cursorRow`, and "AI first" writes its own `barTrailing` and `bottomRow`
carrying copies of both, so anybody who picked that preset got two Rewrites and
two microphones with `LayoutValidator` silent — it only looks for a repeat
*inside* one row. `LayoutPresets` filters Rewrite out of the row it inherits and
no longer seats the microphone in the bottom row. This is the third time that
file's own note about presets not inheriting the default's seating has been
proved right.

`CustomKeyActionTests.testAControllerDoesNotInventAnIOSGlobeBeforeItsHostAnswers`
was the reverse: no product defect at all, a control assertion left behind. It
asked that the default bottom row contain `.settings`, which NIT-98 traded into
the action row's narrow centre, so the test had been red since that trade and had
stopped saying anything about globes. It asks for `.emoji` now, which is the seat
the gear gave up and is what makes "no globe in this row" mean something other
than "this row is empty".

### The reading before that, and how the eight became three

2026-08-16 at `aaca58d2`: **1271 executed, 1260 passed, 8 failed, 3 skipped**,
the same reading taken at `45fe74c8`. Five of those eight were the emoji search
box inheriting the document's shift and are now fixed (see below). A ninth
failure appeared and went in between, `LayoutStoreTests
.testAnEditedLayoutMigratesTheOldInternalGlobeToSettings`: the Emoji/gear seat
swap (NIT-98) moved `.settings` from `cursorRow` to `bottomRow`, and the test
built its "old" layout by rewriting `.settings` inside `cursorRow` alone — so it
tripped **its own precondition** and had stopped exercising the migration at all.
It rewrites all four collections now, the way `SharedStore.replacingInternalGlobe`
already reads them.

`xcodebuild build` does **not** compile these targets, so a compile check needs
`build-for-testing`.

**The UI bundle is excluded from that command and from the numbers above**, on
purpose. See "The UI tests" at the bottom: it is unproven rather than passing or
failing, and folding it in would turn one honest number into a misleading one.

### The previous reading, for comparison

2026-08-15 on `fd2a480c`: 1274 executed across both bundles, 1238 passed, 36
failed, of which 17 were core. Core went 17 failures to 8 by fixing nine of
them, and gained 19 tests (the landscape geometry).

## How the failures were separated from our own changes

A pristine `git archive HEAD` was exported to a temp directory (not a worktree)
and the suspect classes were run there against the same simulator. That is the
only way to answer "was this already red", and it is worth the ten minutes: it
moved twelve failures out of the "we broke it" column and found two bugs nobody
was looking for.

## Pre-existing failures, confirmed identical on committed `main`

Twelve were found. **Four of them turned out to be stale assertions rather than
product questions, and calling all twelve "product questions" was wrong.** They
are listed under "Fixed" below. What is left is eight, and these eight really are
decisions somebody has to make.

| Test | What it reports |
|---|---|
| ~~`EmojiSearchTypingTests` (5 tests)~~ | **Fixed.** The emoji search box inherited the document's shift. See the section below. |
| `EmojiModeTests` (2 tests) | Search ranking. `לב` returns 🫀 rather than ❤️, and `car` puts 🚗 at index 5 behind 🚕 and 🚙. **Still open, deliberately.** It was 3 at `45fe74c8`; the English `heart` half now passes on its own, which is worth knowing before reading a count as a verdict. |

**The `לב` one is not a data gap, and a data fix was tried and reverted.**
Giving 🫀 a distinct Hebrew name (`לב אנטומי` rather than the bare `לב` it shares
with the query) moves 🫀 out of the way and then **💏 wins instead**, and it
breaks `testRecentsWinACloseCallAndLoseToAName`, which deliberately relies on
🫀's Hebrew name being exactly `לב`. So the ranker, not the catalogue, is what
puts a kiss above a red heart for the word "heart". Do not repeat that fix.

`car` is the same shape: 🚗, 🚕 and 🚙 all carry `car` as an exact keyword, and
🚗's own CLDR name is `automobile`, not `car`, so no name-match tiebreak favours
it either. Both want a ranking decision, and there is no measured harness for
emoji search the way there is for typing, so a ranker change cannot currently be
scored.

**The mechanism is now known exactly, and knowing it did not make it fixable.**
`EmojiSearch.score`'s exact-keyword branch scores `length` as `shortest(names)`,
which is the shortest **across both locales**, so an English query is decided by
a Hebrew name: `heart` reaches ❤️ and 🫀 identically (rung 1, coverage −1.0) and
the tiebreak is ❤️'s `min("red heart", "לב אדום") = 7` against 🫀's
`min("anatomical heart", "לב") = 2`. That is precisely what `Match.length`'s own
comment forbids — the repair was applied to the two name branches and this branch
was left behind.

Both repairs for it were measured over 60 English and Hebrew queries and **both
make the product worse**, which is the finding worth keeping:

| Repair | Top-five moved | Effect on the cases in question |
|---|---|---|
| keyword scored by its own length | **51 / 60** | `heart` loses ❤️ from the top five entirely; `moon` answers 🥮; `car` loses 🚗 |
| keyword scored by the shortest name in the **query's own script** | **30 / 60** | 💏 still above ❤️ for `heart`; 🌑 above 🌙 for `moon` |

So `shortest(names)` is carrying a crude centrality prior — a short CLDR name
tends to belong to the primary emoji for a concept — and losing it costs more
than the locale bug does. What is missing is a frequency signal, the same gap
`SeedLanguageModel` fills for words, and CLDR has none. **Do not tune this until
`Bar/emoji/` exists.** Two notes for whoever builds it: the two `לב` assertions
in `EmojiModeTests` contradict each other today (`testHebrewFindsWhatEnglishFinds`
wants ❤️, `testRecentsWinACloseCallAndLoseToAName` pins 🫀 in a comment), so
deciding which is right is part of the same job; and the ranker ports faithfully
to ~40 lines of Python over `EmojiCatalog.json` — a port matched the shipping
engine byte for byte on `car`, `heart` and `לב` — so that corpus needs no
simulator and would be the cheapest harness in the repo.

### The emoji search shift question, with the line

All five `EmojiSearchTypingTests` failures reduce to one fact.
`KeyboardController+Typing.consumeForEmojiSearch` already does the right thing:

```swift
setEmojiQuery(emojiQuery + (shift.isUppercase ? language.uppercased(value) : value))
if shift == .on { shift = .off }
```

Shift applies to the query as a one-shot, which is a deliberate design and is
what `testShiftDoesNotBreakTheSearch` expects. The bug is only that shift is
**inherited from the document** when the box opens: an empty field arms shift at
focus, so `cat` is typed as `Cat`, and a shift press from that inherited `.on`
gives `.locked` where the test expects `.on`.

**The fix is save-and-restore around the search session, and it is not a
one-liner, which is why it was left.** Setting `shift = .off` on entry without
restoring it would leave shift off after the box closes, losing the capital at a
sentence start, which is worse than the cosmetic problem it fixes. A correct fix
has to catch **four** exit paths that write `overlay` directly:
`show(_:)`, `dismissOverlay()`, `KeyboardController+AI.swift:213`, and
`KeyboardController+Dictation.swift:416`. Miss one and shift is stuck `.off` in
the core typing path.

**Fixed, and the four paths are why it is a `didSet` rather than four edits.**
`KeyboardController.overlay` observes itself into `adoptSearchShift(from:)`, so a
fifth writer added later cannot miss it — which is the failure mode the paragraph
above describes, written as a rule the compiler enforces instead of a note. It
acts only on a genuine crossing of the new `KeyboardOverlay.isSearch`, so
`.emojiSearch` → `.copyclipSearch` keeps the document's shift parked rather than
restoring and re-taking it, and a shift pressed inside the box belongs to the
query and is discarded with it. `testTheDocumentsShiftIsParkedForSearchAndGivenBack`
asserts through `dismissOverlay()` as well as `show(_:)`, and
`testAShiftPressedInsideTheQueryDoesNotLeakIntoTheDocument` is what fails a
restore that puts the query's own shift into the user's message.

## Fixed in this pass

| Test | Why it failed |
|---|---|
| `AutocapitalizationTests` (2 tests) | `target.autocapitalizationType = .none` assigns **`Optional.none`, which is nil**, not `UITextAutocapitalizationType.none`. The tests were setting "the host declared nothing", correctly getting `.sentences`, and reporting a bug in code that was right. Spelled out as `UITextAutocapitalizationType.none`. |
| `FieldKeyboardTypeTests.testAnEmailFieldDoesNotArriveWithShiftArmed` | The same assignment, the same way. |
| `FieldKeyboardTypeTests.testEveryLatinWantingFieldTypeMovesOffHebrew` | It asserted `.webSearch` moves off Hebrew while `testASearchFieldLeavesAHebrewKeyboardAlone`, two screens down, asserted it stays. One of the pair had to be red whatever the code did. `latinFieldTypes` deliberately excludes `.webSearch`, so the list was wrong and `.webSearch` came out of it. |
| `CustomKeyActionTests.testTheQuickToneKeySaysWhyWithNothingToRewrite` | `XCTAssertEqual(controller.block?.remedy, .none)` compares against nil, but the block correctly carries `Remedy.none`. Its own message ("there is no button that would help") describes the enum case it failed to assert. |
| `SparkleReachabilityTests.testReplyDoesNotOpenTheAppWhenThePromptWithholdsTheStart` | The same trap twice more, at `AIButtonTests.swift:211` and `:221`. `refuseForScreenContext` builds its block as `remedy: prompt.offersPicker ? .broadcastPicker : .none`, and `offersPicker` is asserted false one line above, so `Remedy.none` is exactly what was meant. **This was first filed as a product question and it was not one.** |
| `LanguageReachabilityTests.testAnAlternateIsNeverTheKeyItSitsOn` | The blanket rule "no alternate is ever the key it sits on" has one deliberate exception the test did not carry. `.claude/rules/keyboard-layout.md` records that the period popup is SwiftKey's order `! @ # , . ?` **including the period**, aligned so it sits over the key it came from, with `alternateRestIndex` naming the period so lifting without sliding still types a full stop. Removing it would move every other mark. The key is exempted by `punctuationKeyID`; every other key still has to obey. |
| `SpaceBarGestureOrderTests.testADeleteRollingOverAnOpenSpaceTouchLandsAfterTheSpace` | It asserted the corrected word, which is what a delete that removed only the trailing space would leave. The space commits the swap and arms `pendingAutocorrectUndo`, so the delete landing after it is the delete that **takes the swap back**, exactly as `insertSpace` documents. The answer is the original word, and that is the ordering working. The assertion predates the undo. |
| `EmojiModeTests.testEveryEmojiHasAHebrewNameAndAnEnglishOne` | A real one-entry data gap, not a test bug. 📀 was `"dvd"` with no Hebrew half while all 1869 of its neighbours are `english\|hebrew`. Now `"dvd\|דיסק DVD"`. Every entry in the catalogue was rescanned; this was the only one, in either direction. |

## `.none` in an optional position is the trap this repo keeps falling into

Four of the fixes above are the same mistake, across three files, and `AGENTS.md`
already records a fifth: `FrameIdentity` is spelled `.absent` precisely because
`FrameIdentity.none` in an optional position silently resolves to
`Optional.none`. When the type of the expression is `T?` and `T` has a case
called `none`, Swift picks `Optional.none` and says nothing.

**Write the type out.** `UITextAutocapitalizationType.none`, not `.none`. It is
four extra words and it is the difference between a test that measures the code
and a test that measures Swift's overload resolution.

## The UI tests

19 of 22 failed. They are excluded from the "green" claim above and they are
**not** evidence of a regression: they drive the real Settings app to enable the
keyboard and grant Full Access, and most fail with the app's TabBar never
appearing after that excursion. `AGENTS.md` already warns that these need an
uncontended simulator; what this run shows is that an uncontended simulator is
necessary and not sufficient. Treat the UI bundle as unproven rather than as
passing or failing until somebody sits with it.

**One UI-adjacent finding is real and was fixed by accident.**
`CustomKeyActionTests.testCopyclipKeyTogglesThePanel` **hangs indefinitely** on
committed `main`: toggling the CopyClip panel reads `UIPasteboard.general.string`,
which blocks the main thread until the "Allow Paste?" alert is answered, and
nothing answers it under `xcodebuild test`. That is NIT-23's defect, stated in
its own words, reproducing as a hung test rather than a failing one. The
`UIPasteControl` work removed that read, so the test now runs and passes. A
hanging test is worse than a failing one, because it looks like a slow suite.
