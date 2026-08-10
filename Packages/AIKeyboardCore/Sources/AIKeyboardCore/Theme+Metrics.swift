import CoreGraphics

extension Theme {

    // MARK: Keyboard metrics
    //
    // Matched to the system keyboard on a standard-width iPhone in portrait.
    // Getting these wrong is the fastest way to make a custom keyboard feel cheap.

    public enum Metrics {
        public static let suggestionBarHeight: CGFloat = 46

        /// The strip above the suggestion bar: what the keyboard is doing, and the
        /// answer when it has one. See `ActionBanner`.
        ///
        /// **Constant, and always counted.** It replaced `contextStripHeight`,
        /// which was added to the total only while a capture session was live —
        /// so the keyboard changed height when a session started, when it ended,
        /// and again for every panel that opened over the keys. A strip that
        /// appears is a keyboard that resizes under the user's thumb mid-sentence,
        /// and it is also a moving fingerprint band: `KeyboardGeometry
        /// .ownUIHeightFraction` feeds the crop that decides whether a reading is
        /// still fresh, and a band that moves mid-read retires the answer the
        /// user's own tap just paid a cloud call for.
        ///
        /// **48, and the last 8 points were taken back by a measurement rather
        /// than a preference.** Two lines of 13pt under a label wants 56, and at 56
        /// the keyboard totals 372 pt — 0.4256 of an iPhone 17 Pro, which is past
        /// the point where the frame fingerprint stops telling two conversations
        /// apart. `FrameReduction.Band.maximumOwnUI` carries the swept table; the
        /// cliff is between 368 and 370 pt and it is sharp. 48 puts the total at
        /// 364 with 6 points of margin.
        ///
        /// The height of this keyboard is a constraint now, not a taste: another
        /// row, or a taller banner, costs a conversation switch on every screen
        /// read.
        public static let bannerHeight: CGFloat = 48
        public static let keyHeight: CGFloat = 42
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

        /// Total height the keyboard extension asks the host app for.
        ///
        /// **No conditional term any more.** It used to add the context strip only
        /// while a capture session was live; the banner that replaced that strip is
        /// always drawn, so the keyboard is one height for a given layout and
        /// changes only when the user changes the layout. `KeyboardViewController`
        /// republishes the constraint from `controller.$customization`, which is
        /// now the only thing that can move it.
        public static func totalHeight() -> CGFloat {
            totalHeight(for: .default)
        }

        public static func totalHeight(for layout: KeyboardCustomization) -> CGFloat {
            bannerHeight + suggestionBarHeight + keyAreaHeight(for: layout)
        }

        /// Apple's minimum comfortable target. Anything smaller gets mistapped.
        public static let minTouchTarget: CGFloat = 44
    }
}
