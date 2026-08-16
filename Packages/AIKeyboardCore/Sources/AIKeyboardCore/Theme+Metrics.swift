import CoreGraphics

extension Theme {

    // MARK: Keyboard metrics
    //
    // Matched to the system keyboard on a standard-width iPhone in portrait.
    // Getting these wrong is the fastest way to make a custom keyboard feel cheap.

    public enum Metrics {
        public static let suggestionBarHeight: CGFloat = 36

        /// The strip above the suggestion bar: what the keyboard is doing, and the
        /// answer when it has one. See `ActionBanner`.
        ///
        /// **Constant while shown, omitted for everything the keys can say
        /// themselves.** A running call is a sweep on the key that started it; a
        /// live recording is a waveform on the microphone. What is left is a live
        /// screen reading, a refusal and a failure — sentences with nowhere else
        /// to go. See `BannerState.isPresented`. The fingerprint crop does not
        /// follow it: `KeyboardGeometry.ownUIHeightFraction` still reports the
        /// tallest form so a mid-read resize cannot move the band.
        ///
        /// **58, paid down from 69 so the letter keys could grow.** Title plus
        /// two lines of detail still fit. The total may not grow, because the
        /// cliff between 368 and 370 (`FrameReduction.Band.maximumOwnUI`) is
        /// measured rather than chosen. Deleting the reserved progress slot
        /// shrinks the tallest form by 3 pt; that space is not spent on taller
        /// keys.
        ///
        /// The height of this keyboard is a constraint now, not a taste: another
        /// row, or a taller banner, costs a conversation switch on every screen
        /// read.
        public static let bannerHeight: CGFloat = 58
        public static let keyHeight: CGFloat = 43
        /// Points the numbers row gives the space row.
        ///
        /// **A transfer, not a growth.** The shipped total sits 3 pt under the
        /// 368 pt fingerprint cliff, so the space bar can only get taller if another row
        /// in the same grid gets shorter by the same amount. Applied when the
        /// digits are on screen: the optional number row, and the top row of the
        /// 123 / `#+=` planes. Letter rows stay at `keyHeight`.
        public static let rowHeightBias: CGFloat = 3

        /// The space row's share of `rowHeightBias`, or zero when there is no
        /// numbers row in this grid to pay for it.
        public static func spaceRowHeightBias(
            plane: KeyboardPlane, showsNumberRow: Bool
        ) -> CGFloat {
            (plane != .letters || showsNumberRow) ? rowHeightBias : 0
        }

        public static let rowSpacing: CGFloat = 12
        /// Gap between keys in a row. Raised from 5 so the caps breathe. Do not
        /// raise further without re-checking
        /// `LanguageCatalogueTests.testNoRowOverflowsTheKeyboard` on 320pt —
        /// Bulgarian's thirteen columns are the ones that run out first.
        public static let keySpacing: CGFloat = 6
        public static let sideInset: CGFloat = 3
        public static let topInset: CGFloat = 4
        public static let bottomInset: CGFloat = 4

        /// Height of the four key rows plus their insets, at the shipped size.
        ///
        /// The default-layout answer. Everything that can be resized asks
        /// `keyAreaHeight(for:)` instead; this stays because the capture band and
        /// several call sites want the constant, not the current setting.
        public static var keyAreaHeight: CGFloat {
            keyAreaHeight(for: .default)
        }

        /// Height of the key rows plus their insets, for one layout.
        ///
        /// **The old spelling hardcoded four rows** — `keyHeight * 4 + rowSpacing
        /// * 3` — which was right for exactly as long as the grid could only be
        /// three letter rows and a bottom row. With an optional number row and an
        /// optional cursor row it is four, five or six, and the key height is no
        /// longer a constant either. The numbers/space `rowHeightBias` pair does
        /// not appear here because it cancels;
        /// `testTheHostHeightMatchesWhatTheGridDraws` fails if it stops.
        ///
        /// **`rowCount` is still the gap count, and is no longer the height
        /// multiplier.** Three bands can each carry their own key height now, so
        /// this sums the bands the layout actually draws rather than multiplying
        /// one number by a row count. Miss that and the extension asks the host
        /// for a height the grid does not fill: a short action row leaves a strip
        /// of host app showing under the keys, and a tall one clips the space
        /// bar. `testTheHostHeightMatchesWhatTheGridDraws` is what fails.
        public static func keyAreaHeight(
            for layout: KeyboardCustomization,
            orientation: KeyboardGeometry.Orientation = .portrait
        ) -> CGFloat {
            let layout = orientation == .landscape ? landscapeLayout(basedOn: layout) : layout
            let geometry = layout.geometry
            let letterRows = 3 + (layout.showsNumberRow ? 1 : 0)
            let stacked =
                geometry.height(.letters) * CGFloat(letterRows)
                + geometry.height(.bottom)
                + (layout.cursorRow.isEmpty ? 0 : geometry.height(.action))
            return stacked
                + geometry.rowSpacing * CGFloat(layout.rowCount - 1)
                + topInset + bottomInset
        }

        /// **Landscape is a separate branch of the geometry, not a scaled-down
        /// portrait.** iPhone 17 Pro portrait is 874pt tall; rotated, it is 402 —
        /// and `FrameReduction.Band.maximumOwnUI` (368/874, ≈0.4211) is a fraction
        /// of screen height, not a point budget, so the same fraction of 402pt
        /// leaves only ≈169pt for the *whole* keyboard, against 368pt in
        /// portrait. Scaling every portrait row down by that same ~46% would put
        /// keys under 20pt tall. Shedding rows instead: no number row, no action
        /// row (`cursorRow`), and no banner — see `KeyboardView`.
        ///
        /// That still leaves three letter rows and the bottom row at
        /// `Landscape.keyHeight` (26pt) and a `Landscape.suggestionBarHeight`
        /// (30pt) candidate strip:
        ///
        /// | | height |
        /// |---|---|
        /// | 3 letter rows + bottom row | `26 × 4 = 104` |
        /// | 3 row gaps at `Landscape.rowSpacing` (4) | `12` |
        /// | top + bottom inset (unchanged from portrait) | `8` |
        /// | **key area** | **124** |
        /// | suggestion bar | `30` |
        /// | **total** | **154** |
        ///
        /// **The number that has to be satisfied is 375, not 402, and reading it
        /// off the reference phone is what left a live defect standing for the
        /// whole of NIT-18 and NIT-101.** The cap is a fraction of the *landscape
        /// screen height*, which is the phone's portrait width, so the budget is
        /// a different number of points on every phone and the narrowest one
        /// binds. Break-even is `total / 0.4210526`; at the previous 166 pt that
        /// is **394.25 pt**, above five shipping widths. The 166 pt keyboard was
        /// therefore over the cap on the iPhone SE 2/3, XS, 11 Pro, 12 mini and
        /// 13 mini (`H = 375`, 8.1 pt over), the 12 / 13 / 14 (390, 1.8 over) and
        /// the 14 Pro / 15 / 16 / 16e (393, 0.5 over). Over the cap
        /// `FrameReduction.bottomCrop(ownUI:)` clamps, and the rows it then
        /// refuses to crop are rows of **our own keyboard** — at 375 that reaches
        /// the Reply chip, whose `ControlSweep` runs for the whole of a read, and
        /// `Bar/screen-context/harness/run-fingerprint-landscape.sh` measured
        /// **30 of 30** frames taking a fresh identity from it. That is the same
        /// defect `FrameReduction` was rewritten to remove, arriving in an
        /// orientation nobody had swept.
        ///
        /// **The 12 pt came out of the row gap, and out of nothing else, because
        /// the row gap is the only vertical dimension in landscape that is not a
        /// touch target.** A landscape key is about 81 × 26, so every mistap risk
        /// is vertical and the key height is the whole of it; `KeyView` puts
        /// `.contentShape(Rectangle())` on the cap's own frame, so the gap
        /// between two rows is dead space a touch lands in and nothing happens.
        /// Cutting 8 → 4 therefore pays the entire overspend without shrinking a
        /// single target by a point, and it keeps the cap idiom: the crisp part
        /// of `KeyView`'s depth recipe is a 2 pt contact line (`restContactY`),
        /// which still clears, and what is lost is part of an ambient lift its
        /// own comment calls "barely there" (6% black). The other candidates all
        /// cost something a user can feel — the bar is 30 pt around a 26 pt chip
        /// and hosts the whole shed action row, and 26 pt keys are already under
        /// `minTouchTarget` and under `LayoutGeometry.keyHeightRange`'s own 36 pt
        /// floor.
        ///
        /// **One geometry for every phone, rather than a budget per device.** The
        /// obvious alternative is to keep 166 where it fits and shorten only the
        /// narrow phones, which means the geometry takes a measured screen height
        /// — and that height would have to be obtained and agreed on in four
        /// places (`KeyboardGeometry.ownUIHeightFraction`, the host constraint in
        /// `KeyboardViewController`, `KeyboardView`'s grid frame and
        /// `KeyboardView+Keys`), one of which already falls back to a reference
        /// height when there is no window. A keyboard drawn from a measured
        /// screen and a fraction published from a fallback is the band moving
        /// under a reading in flight, which is the failure `landscapeLayout`
        /// exists to make impossible. Since the 12 pt comes entirely out of dead
        /// space, spending it on every phone costs no phone a target, so the
        /// plumbing buys nothing worth that risk.
        ///
        /// 154 / 375 = 0.4107 against the 0.4211 cap, so the margin on the phone
        /// that binds is **3.9 pt** and it grows with the screen: 10.2 at 390,
        /// 11.5 at 393, 15.3 at 402, 31.3 at 440.
        /// `LandscapeGeometryTests.testTheLandscapeKeyboardFitsUnderTheCapOnEveryWidthItShipsTo`
        /// asserts every one of them, and 375 is the row that fails against the
        /// 166 pt build.
        ///
        /// 26pt keys are shorter than `Theme.Metrics.minTouchTarget` (44) and
        /// `LayoutGeometry.keyHeightRange`'s own 36pt floor — both portrait
        /// numbers for a portrait thumb. Landscape's constraint is the
        /// fingerprint cap over an iPhone's short axis, not a preference, and the
        /// cap does not leave room for Apple's comfortable target here.
        public enum Landscape {
            public static let suggestionBarHeight: CGFloat = 30
            public static let keyHeight: CGFloat = 26
            /// **4, paid down from 8 so the keyboard fits the narrowest phone it
            /// ships to.** See the table above: this is the one vertical
            /// dimension landscape spends that no thumb ever aims at.
            public static let rowSpacing: CGFloat = 4

            /// The landscape screen height every number here has to satisfy: the
            /// portrait *width* of the narrowest iPhone this package's iOS 17
            /// floor still reaches (SE 2/3, XS, 11 Pro, 12 mini, 13 mini).
            ///
            /// `KeyboardGeometry.referenceLandscapeScreenHeight` (402) is the
            /// device every other number under `Bar/screen-context/` is measured
            /// on; this is the device the *cap* is decided on, and they are not
            /// the same phone. Checking only the reference one is exactly how a
            /// 30-of-30 defect survived two tickets.
            public static let narrowestScreenHeight: CGFloat = 375
        }

        /// The layout landscape actually draws: the caller's rows and reach, with
        /// the two that do not fit removed and the compact key height and row
        /// spacing substituted. Shared by `keyAreaHeight(for:orientation:)` and
        /// `KeyboardView+Keys`'s `keyGrid`, so the height this publishes and the
        /// grid that is actually drawn cannot drift apart.
        ///
        /// **Emptying `cursorRow` sheds the row, not the controls.** It is a
        /// height decision and only a height decision: the five things that row
        /// carries — CopyClip, Fix, Emoji, Rewrite and dictation in the shipped
        /// arrangement — are drawn as chips on the suggestion bar instead, whose
        /// own row is already inside the number this function feeds. See
        /// `SuggestionBar.landscapeActions(for:)`, which reads the *unmodified*
        /// layout for exactly that reason. So nothing here may be read as "the
        /// user does not get these in landscape"; what they do not get is a
        /// second band of keyboard to put them in.
        static func landscapeLayout(basedOn layout: KeyboardCustomization) -> KeyboardCustomization {
            var compact = layout
            compact.showsNumberRow = false
            compact.cursorRow = []
            compact.geometry = LayoutGeometry(
                keyHeight: Landscape.keyHeight, rowSpacing: Landscape.rowSpacing,
                reach: layout.geometry.reach)
            return compact
        }

        /// Tallest height the keyboard can ask the host for, for a given layout.
        ///
        /// **Always includes the banner.** The fingerprint crop and the layout
        /// editor's "this costs screen context" warning both need the ceiling, not
        /// the current form — see `KeyboardGeometry.ownUIHeightFraction`. The
        /// extension asks the host for the live height via
        /// `totalHeight(for:showsBanner:)`.
        public static func totalHeight() -> CGFloat {
            totalHeight(for: .default)
        }

        public static func totalHeight(for layout: KeyboardCustomization) -> CGFloat {
            totalHeight(for: layout, showsBanner: true)
        }

        /// Landscape's own tallest form. There is only one: see
        /// `totalHeight(for:showsBanner:orientation:)` — landscape never shows
        /// the banner, so `showsBanner` cannot change this answer.
        public static func totalHeight(
            for layout: KeyboardCustomization, orientation: KeyboardGeometry.Orientation
        ) -> CGFloat {
            totalHeight(for: layout, showsBanner: true, orientation: orientation)
        }

        /// Height the keyboard extension asks the host app for right now.
        ///
        /// The banner is omitted for everything the keys can say themselves
        /// (`showsBanner: false`). Ordinary typing, a running model call, and a
        /// live recording all use that form: status lives on the control, so
        /// none of those states reserve a row. The fingerprint crop still reads
        /// the tallest form (banner on).
        ///
        /// **Landscape never shows the banner, at any `showsBanner`.** A live
        /// reading, a refusal or a failure would cost the whole 58pt banner out
        /// of landscape's ≈169pt total budget, which is more than a third of it
        /// — see `Landscape`. Those three states are rare next to ordinary
        /// typing, and dropping them in landscape is a real gap, not a free
        /// choice; flagged for product to confirm rather than decided quietly.
        public static func totalHeight(
            for layout: KeyboardCustomization, showsBanner: Bool,
            orientation: KeyboardGeometry.Orientation = .portrait
        ) -> CGFloat {
            let banner = orientation == .landscape ? 0 : (showsBanner ? bannerHeight : 0)
            let suggestionBar =
                orientation == .landscape ? Landscape.suggestionBarHeight : suggestionBarHeight
            return banner + suggestionBar + keyAreaHeight(for: layout, orientation: orientation)
        }

        /// Apple's minimum comfortable target. Anything smaller gets mistapped.
        public static let minTouchTarget: CGFloat = 44

        /// How tall each sliding key is when a plane draws more rows than the
        /// letters plane paid for.
        ///
        /// SwiftKey's numbers and symbols pages are four rows. The letters plane
        /// is three, and `KeyboardCustomization.rowCount` follows the letters
        /// plane so the host height — and the 368 pt fingerprint cliff — does
        /// not move when the user taps 123. Four rows at the shipped 43 pt would
        /// be that move. This squeezes the extra row into the same block three
        /// letter rows already occupy; a layout that already turned the number
        /// row on has paid for the fourth slot and is left alone.
        public static func fittedKeyHeight(
            slidingRows: Int, referenceRows: Int, keyHeight: CGFloat, rowSpacing: CGFloat
        ) -> CGFloat {
            guard slidingRows > referenceRows, slidingRows > 0 else { return keyHeight }
            let block =
                CGFloat(referenceRows) * keyHeight
                + CGFloat(max(0, referenceRows - 1)) * rowSpacing
            let gaps = CGFloat(slidingRows - 1) * rowSpacing
            return max(0, (block - gaps) / CGFloat(slidingRows))
        }
    }
}
