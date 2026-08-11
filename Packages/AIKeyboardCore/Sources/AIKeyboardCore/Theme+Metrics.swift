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
        /// **Constant while shown, omitted when idle.** The idle instruction is
        /// gone — the action row is the affordance — so the host height follows
        /// `BannerState.isPresented`. The fingerprint crop does not: see
        /// `KeyboardGeometry.ownUIHeightFraction`, which still reports the tallest
        /// form so a mid-read resize cannot move the band.
        ///
        /// **72, so a title plus three lines of detail fit without an ellipsis.**
        /// Growing the strip alone would blow past the fingerprint cliff between
        /// 368 and 370 (`FrameReduction.Band.maximumOwnUI`); the 16 pt comes from
        /// a 36 pt suggestion bar and 40 pt keys, keeping the total at 368.
        ///
        /// The height of this keyboard is a constraint now, not a taste: another
        /// row, or a taller banner, costs a conversation switch on every screen
        /// read.
        public static let bannerHeight: CGFloat = 72
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
        /// The banner is omitted while idle (`showsBanner: false`), so ordinary
        /// typing is `bannerHeight` shorter. Presence still follows the strip
        /// rather than the capture session alone — a Fix answer and a live reading
        /// both show it, and the idle instruction does not.
        public static func totalHeight(
            for layout: KeyboardCustomization, showsBanner: Bool
        ) -> CGFloat {
            (showsBanner ? bannerHeight : 0) + suggestionBarHeight + keyAreaHeight(for: layout)
        }

        /// Apple's minimum comfortable target. Anything smaller gets mistapped.
        public static let minTouchTarget: CGFloat = 44
    }
}
