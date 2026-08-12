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
        /// **69, so a title plus three lines of detail still fit without an
        /// ellipsis.** It was 72 until the progress bar above needed three points;
        /// the total may not move, because the cliff between 368 and 370
        /// (`FrameReduction.Band.maximumOwnUI`) is measured rather than chosen.
        ///
        /// The height of this keyboard is a constraint now, not a taste: another
        /// row, or a taller banner, costs a conversation switch on every screen
        /// read.
        public static let bannerHeight: CGFloat = 69
        public static let keyHeight: CGFloat = 40
        public static let rowSpacing: CGFloat = 12
        public static let keySpacing: CGFloat = 6
        public static let sideInset: CGFloat = 3
        public static let topInset: CGFloat = 8
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
        /// longer a constant either.
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
        /// (`showsBanner: false`), so ordinary typing — and a running model call,
        /// and a live recording — is `bannerHeight` shorter. The progress bar is
        /// in every form of this, running or not: see `progressBarHeight`.
        public static func totalHeight(
            for layout: KeyboardCustomization, showsBanner: Bool
        ) -> CGFloat {
            (showsBanner ? bannerHeight : 0) + progressBarHeight + suggestionBarHeight
                + keyAreaHeight(for: layout)
        }

        /// Apple's minimum comfortable target. Anything smaller gets mistapped.
        public static let minTouchTarget: CGFloat = 44
    }
}
