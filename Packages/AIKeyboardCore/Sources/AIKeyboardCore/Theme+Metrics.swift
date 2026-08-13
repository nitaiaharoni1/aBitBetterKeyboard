import CoreGraphics

extension Theme {

    // MARK: Keyboard metrics
    //
    // Matched to the system keyboard on a standard-width iPhone in portrait.
    // Getting these wrong is the fastest way to make a custom keyboard feel cheap.

    public enum Metrics {
        public static let suggestionBarHeight: CGFloat = 36

        /// The hairline above the suggestion bar that says a model call is
        /// running. See `WorkingProgressBar`.
        ///
        /// **Its height is spent whether or not anything is running, and that is
        /// the whole point of it.** A strip that appeared with the call would move
        /// the three candidates and the whole key grid under the thumb twice per
        /// tap — which is exactly what the banner did while it carried the
        /// shimmer, and why it is not carrying it any more.
        ///
        /// **The three points came out of the banner rather than out of the
        /// total.** `FrameReduction.Band.maximumOwnUI` is `368/874`: 368 is the
        /// measured cliff past which the frame fingerprint stops telling two
        /// conversations apart, so a row that is added has to be paid for by a row
        /// that shrinks. See `bannerHeight` below.
        public static let progressBarHeight: CGFloat = 3

        /// How tall the recording waveform is allowed to grow.
        ///
        /// **The hairline above cannot show loudness.** Three points with a floor
        /// is a dashed line; speech needs vertical room or every frame looks the
        /// same. 24 is the `WaveformView` in the companion app at a size that
        /// still fits under the fingerprint cliff.
        ///
        /// **Spent whenever the banner is down, not only while the microphone is
        /// on.** Swapping 3 for 24 at the start of a recording moved every key
        /// under the thumb, and swapping back at stop moved them again. The
        /// banner-off live height therefore always includes this slot; a model
        /// call keeps the three-point sweep centred inside it. The fingerprint
        /// crop still reads the tallest form (banner on, three-point hairline),
        /// which this reserved slot does not exceed: 24 sits 37 points under
        /// `bannerHeight + progressBarHeight`.
        public static let recordingWaveformHeight: CGFloat = 24

        /// The strip above the suggestion bar: what the keyboard is doing, and the
        /// answer when it has one. See `ActionBanner`.
        ///
        /// **Constant while shown, omitted for everything the keys and the
        /// progress bar can say themselves.** A running call is the bar above; a
        /// live recording is the microphone key, drawn in record red. What is left
        /// is a live screen reading, a refusal and a failure — sentences with
        /// nowhere else to go. See `BannerState.isPresented`. The fingerprint crop
        /// does not follow it: `KeyboardGeometry.ownUIHeightFraction` still reports
        /// the tallest form so a mid-read resize cannot move the band.
        ///
        /// **58, paid down from 69 so the letter keys could grow.** Title plus
        /// two lines of detail still fit. The total may not move, because the
        /// cliff between 368 and 370 (`FrameReduction.Band.maximumOwnUI`) is
        /// measured rather than chosen.
        ///
        /// The height of this keyboard is a constraint now, not a taste: another
        /// row, or a taller banner, costs a conversation switch on every screen
        /// read.
        public static let bannerHeight: CGFloat = 58
        public static let keyHeight: CGFloat = 43
        /// Points the numbers row gives the space row.
        ///
        /// **A transfer, not a growth.** The shipped total sits on the 368 pt
        /// fingerprint cliff, so the space bar can only get taller if another row
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
        public static func keyAreaHeight(for layout: KeyboardCustomization) -> CGFloat {
            let rows = CGFloat(layout.rowCount)
            return layout.geometry.keyHeight * rows
                + layout.geometry.rowSpacing * (rows - 1)
                + topInset + bottomInset
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

        /// Height the keyboard extension asks the host app for right now.
        ///
        /// The banner is omitted for everything the keys can say themselves
        /// (`showsBanner: false`). Ordinary typing, a running model call, and a
        /// live recording all use that form. The progress slot is in every form
        /// of this: `progressBarHeight` under a banner, and
        /// `recordingWaveformHeight` whenever the banner is down, recording or
        /// not, so opening the microphone cannot move the keys. The fingerprint
        /// crop still reads the tallest form (banner on, hairline).
        public static func totalHeight(
            for layout: KeyboardCustomization, showsBanner: Bool
        ) -> CGFloat {
            let progress = showsBanner ? progressBarHeight : recordingWaveformHeight
            return (showsBanner ? bannerHeight : 0) + progress + suggestionBarHeight
                + keyAreaHeight(for: layout)
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
