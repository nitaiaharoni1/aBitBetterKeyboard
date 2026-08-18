---
paths:
  - "**/EmojiCatalog.swift"
  - "**/EmojiPanel.swift"
  - "**/EmojiSearch.swift"
  - "**/EmojiSearchViews.swift"
  - "**/EmojiSkinTone.swift"
  - "**/EmojiTonePicker.swift"
  - "**/Resources/EmojiCatalog.json"
  - "Scripts/generate-emoji-catalog.py"
  - "AIKeyboardCoreTests/EmojiModeTests.swift"
  - "AIKeyboardCoreTests/EmojiSearchTypingTests.swift"
  - "Bar/emoji/**"
---

# The emoji grid, its catalogue and the tone strip

- **A toned emoji you can spell is not a toned emoji that exists, and building
  one puts tofu on the grid.** The rule for applying a skin tone — insert the
  modifier after each `Emoji_Modifier_Base` codepoint, swallowing a U+FE0F that
  followed it — is exact as *spelling*, and says nothing about whether Unicode
  fully-qualifies the result at or below `MAX_EMOJI_VERSION`. 👋 takes all five
  tones; 👨‍👩‍👦 has three modifier bases in it and takes none at all below Emoji
  16, and so do the other 39 family sequences and 🧑‍🤝‍🧑. So
  `Scripts/generate-emoji-catalog.py` derives only the *candidate* and then
  **looks it up in `emoji-test.txt`**, dropping the whole strip unless all five
  come back (`tone_variants`). Measured over the 1,870 in the grid: 304 take all
  five, 1,566 take none, and there is no partial case — so a partial one appearing
  is upstream news, not something to trim silently. A derived-instead-of-looked-up
  build looks perfectly fine in the editor and shows dotted boxes under half the
  People tab on a phone.

- **The strip stores plain spellings and the tone goes on at the last moment,
  twice.** `EmojiCatalog.all`, `EmojiCatalog.categories`, `recentEmoji` and the
  search index are all untoned; `EmojiCatalog.toned(_:_:)` is called once when a
  cell is *drawn* and once when it is *inserted*. That is what makes changing the
  tone free — `EmojiPanel.sections`, the cell ids, the column counts and the seams
  are all computed from the plain spellings, so a new tone repaints 304 cells and
  rebuilds nothing — and it is what keeps `EmojiSearch` matching, because a query
  is scored against `EmojiCatalog.all`. **Recents record `untoned(_:)` of what was
  inserted**, not what was inserted: storing the toned string leaves five
  spellings of the same wave in a twenty-slot tab, and strands somebody else's
  tone there the moment the user goes back to plain. `EmojiModeTests
  .testSkinTonedVariantsAreNotInTheGrid` is what stops the strip itself growing
  back to 9,000 cells.

- **Flipping a popup below the cell and clamping it into the panel is not enough,
  and the bottom row is why.** The emoji panel draws its own tone strip, so unlike
  a letter's accent strip it cannot hang over the suggestion bar — the top row has
  no room above it and has to flip under. Clamping the flipped strip into the
  panel then drags it *back onto the cell the finger is holding* for the bottom
  row, which has nothing below it: the picker ends up under the thumb that opened
  it. `EmojiTonePicker.origin` takes the roomier side when neither fits, so that
  case crosses the cell's *top* edge instead. Swept over every geometry
  `LayoutGeometry` can describe (55 configurations, `EmojiModeTests
  .testTheToneStripStaysInsideThePanelAndOffTheFingerHoldingIt`): portrait clears
  the cell outright everywhere, and landscape's bottom row is the only overlap in
  the whole space — 4.5 points of the cell's top, well clear of its centre. There
  is no corpus for a popup, so the sweep is the measurement.

- **A tap inside a `ScrollView` is not the same event as a tap on a key, so the
  emoji cell keeps its `Button`.** A scroll view in flight swallows the first tap
  to stop itself; a raw `DragGesture` does not know that, and would type an emoji
  every time somebody halted a flicking strip. `EmojiPickCell` therefore leaves
  the tap to the `Button` and adds the hold as a `simultaneousGesture`, with
  `.scrollDisabled` going on only once the strip is up — a moment the finger has
  by definition not moved, so no pan is in flight to cut short. The one touch both
  want is hold-then-lift-in-place, and **`pickerTookTouch` is deliberately not
  cleared when the strip commits**: SwiftUI does not say whether the button's
  action runs before or after the gesture's `onEnded`, so it is cleared at the
  start of the *next* touch, where the order cannot matter.

- **A picker keyed by its emoji is open on two cells at once.** The same emoji is
  in Recents *and* in its category, so both cells would answer the lift and both
  would insert. `EmojiTonePicker.owner` holds `EmojiPanel.Cell.id`, which is
  unique by construction (`"\(category)-\(index)"`).

- **`pack()` in the generator must not deduplicate names against each other, and
  the reason is positional.** `EmojiCatalog.names(for:)` hands the list back in
  `LOCALES` order and slot 1 is read as the Hebrew one, so collapsing two locales
  that happen to agree does not shorten a list — it moves Hebrew into slot 0 and
  leaves the emoji looking as though CLDR had never named it. This is not
  hypothetical: CLDR now gives 📀 the Hebrew `tts` "dvd", the same string as
  English's. Keywords are still deduplicated against the names, where the list is
  a bag of words and position means nothing.

- **The tone strip has no home in the search results band, and that is a room
  problem rather than a decision.** `EmojiResultsStrip` is one key tall with the
  search box directly above it and the letter rows directly below; a 34 pt strip
  has nowhere to stand that is not on top of the row it came from. The band
  follows `KeyboardController.emojiSkinTone` for what it draws and what it
  inserts, and the grid is where a tone is picked.

- **`Bar/emoji/harness/swift-check.sh` compiles the real `EmojiSearch.swift`,
  `EmojiCatalog.swift` and `EmojiSkinTone.swift` and nothing else**, so those
  three must stay Foundation-only; the script says so before the compiler does.
  Anything that needs UIKit or SwiftUI belongs in `EmojiPanel.swift`,
  `EmojiSearchViews.swift` or `EmojiTonePicker.swift`. A new file that
  `EmojiCatalog` names has to be added to that `cp` line or the fidelity check
  stops compiling — which reads as a broken toolchain rather than as a rule being
  broken.
