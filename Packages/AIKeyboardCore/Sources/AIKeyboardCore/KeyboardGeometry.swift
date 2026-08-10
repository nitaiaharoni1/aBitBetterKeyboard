import SwiftUI

// MARK: - Where our own keyboard is on the screen

/// How much of the screen our own keyboard covers, which is the one thing the
/// capture process cannot work out for itself.
///
/// It needs it because our own UI must not be part of the frame fingerprint.
/// `AIResultPanel.loading` repaints three shimmer lines at 60 Hz for the whole
/// five seconds of a read, and the keyboard is a third of the fingerprint band on
/// an iPhone 17 Pro, so with it left in the freshness gate retired the answer to
/// the very tap that paid for it. `CaptureIntent.ownUIHeightPermille` carries
/// this across; `FrameReduction.bottomCrop(ownUI:)` is what acts on it.
public enum KeyboardGeometry {

    /// iPhone 17 Pro in portrait: the device every number under
    /// `Bar/screen-context/` is measured on, and the fallback when there is no
    /// window to measure.
    public static let referenceScreenHeight: CGFloat = 874

    /// The bottom fraction of a `screenHeight`-tall screen our keyboard covers.
    ///
    /// **Always the tallest form, never the current one.** The context strip
    /// appears and disappears with the capture session, including in the middle
    /// of a read, and the crop it feeds decides the fingerprint's band: a band
    /// that moves mid-read retires the reading exactly as a conversation switch
    /// does, because the gate's only content condition is exact equality. Over-
    /// reporting by the height of the strip costs nothing — those rows are ours
    /// whether or not the strip is drawn in them.
    ///
    /// `gapBelow` is the strip of screen between the bottom of our view and the
    /// bottom edge of the display, where the system draws the home indicator over
    /// the keyboard. Only the runtime knows it, and it is bounded here rather
    /// than trusted: a bad measurement that grew the crop without limit would
    /// start removing the host's newest message from the fingerprint, which is
    /// the 23-of-29 failure the band measurement found.
    /// **The layout has to be passed in, because the keyboard stopped having one
    /// height.** This read `Theme.Metrics.totalHeight()` — the *default* layout —
    /// which was exactly right while that was the only height there was. With the
    /// layout editor a user can turn on a number row, turn on an action row and
    /// choose 52pt keys, and the keyboard then covers about 0.55 of an iPhone 17
    /// Pro while this went on publishing 0.43. The difference is roughly 120pt of
    /// our own keyboard left inside the fingerprint band, which is the 30-of-30
    /// defect `.claude/rules/screen-context.md` records: our UI animating inside
    /// the band gives every frame a fresh identity and the freshness gate then
    /// retires the reading the user's own tap paid a cloud call for.
    ///
    /// Still the height the keyboard *can* occupy rather than a live measurement,
    /// which is the rule this has to keep: a layout changes only when the user
    /// edits it in the app, never mid-read, so it does not move the band under a
    /// reading in flight the way the old appearing-and-disappearing context strip
    /// did.
    public static func ownUIHeightFraction(
        screenHeight: CGFloat, gapBelow: CGFloat = 0,
        layout: KeyboardCustomization = .default
    ) -> Double {
        guard screenHeight > 0 else { return 0 }
        let gap = min(max(0, gapBelow), Theme.Metrics.minTouchTarget)
        let covered = Theme.Metrics.totalHeight(for: layout) + gap
        return Double(min(covered, screenHeight) / screenHeight)
    }
}
