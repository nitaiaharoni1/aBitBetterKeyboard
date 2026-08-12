import SwiftUI

/// The hairline directly above the suggestion bar that says a model call is
/// running.
///
/// **It replaced a 69pt strip, and the strip was the problem rather than the
/// shimmer in it.** Fix, Rewrite and Reply write their answer straight into the
/// field (see `KeyboardController.applyDirectly`), so for the whole length of a
/// call the banner existed to say one thing — *working* — and it said it by
/// appearing, pushing the three candidates and every key row down by 69 points,
/// and then leaving again when the answer landed. Two full-keyboard relayouts per
/// tap, on the two actions a user runs most.
///
/// **So its height is spent whether or not anything is running.** A progress bar
/// that appears is a progress bar that moves the thing underneath it; this one is
/// three points of nothing while the keyboard is idle, and the same three points
/// with a segment sweeping through them while a call is in flight. Nothing on
/// screen moves in either direction.
///
/// **Indeterminate, because there is nothing to determine.** A cloud call answers
/// when it answers; the shimmer this replaces was indeterminate for the same
/// reason, and a bar that filled to a percentage would be inventing one.
public struct WorkingProgressBar: View {

    @ObservedObject var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    /// How much of the width the moving segment covers.
    static let segmentFraction: CGFloat = 0.32

    /// Whether this strip is showing a voice rather than a model call.
    ///
    /// A recording wins if both are somehow true, which they should not be:
    /// `run(_:)` and `runTone(_:)` both refuse while one is open.
    var isRecording: Bool { controller.dictationKeyState.isRecording }

    /// **The same three points, showing sound instead of progress.** A recording
    /// has nothing to say about how far along it is — it ends when the speaker
    /// stops — so a sweeping segment would be inventing a measurement. What it
    /// does have is loudness, which is the one honest thing to draw and the thing
    /// that tells somebody the microphone is actually hearing them. It is
    /// deliberately tiny: this strip exists because it costs nothing when nothing
    /// is happening, and a waveform tall enough to admire would cost the keys.
    private func waveform(width: CGFloat) -> some View {
        let levels = controller.dictationLevels
        let count = max(1, KeyboardController.dictationLevelHistory)
        let barWidth = max(1, (width - CGFloat(count - 1) * Self.waveGap) / CGFloat(count))
        let full = Theme.Metrics.progressBarHeight

        return HStack(alignment: .center, spacing: Self.waveGap) {
            ForEach(0..<count, id: \.self) { slot in
                // Right-aligned: the newest reading is at the trailing edge and the
                // history scrolls away from it, so a fresh recording fills in from
                // the right rather than starting as a full row of flat bars.
                let index = slot - (count - levels.count)
                let level = levels.indices.contains(index) ? levels[index] : 0
                Capsule(style: .continuous)
                    .fill(Theme.Semantic.record)
                    .frame(
                        width: barWidth,
                        // Never quite zero: a silent moment is a thin line rather
                        // than a gap, or the strip looks broken between words.
                        height: max(full * 0.28, min(full, full * CGFloat(level) * 2.2)))
            }
        }
        .frame(width: width, height: full)
    }

    /// The gap between two bars of the waveform.
    static let waveGap: CGFloat = 1.5

    /// The indeterminate sweep a model call draws.
    private func sweep(width: CGFloat) -> some View {
        let segment = width * Self.segmentFraction
        // `workingPhase` grows without bound — `beginWork` drives it at
        // 0.03 per 16ms and never wraps it — so the wrap happens here, the
        // same way `ActionBanner` wrapped it for the shimmer it fed.
        let phase = controller.workingPhase.truncatingRemainder(dividingBy: 1)

        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(Theme.Brand.solid.opacity(0.14))

            Capsule(style: .continuous)
                .fill(Theme.Brand.solid)
                .frame(width: segment)
                // Out of sight on both sides at the ends of a cycle, so the
                // segment enters and leaves rather than being clipped in
                // place at either edge.
                .offset(x: CGFloat(phase) * (width + segment) - segment)
        }
        .frame(height: Theme.Metrics.progressBarHeight)
        .clipShape(Capsule(style: .continuous))
    }

    public var body: some View {
        GeometryReader { geo in
            if isRecording {
                waveform(width: geo.size.width)
            } else {
                sweep(width: geo.size.width)
            }
        }
        .frame(height: Theme.Metrics.progressBarHeight)
        // Reserved, never removed. See the note above and
        // `Theme.Metrics.progressBarHeight`.
        .opacity(controller.isWorking || isRecording ? 1 : 0)
        .padding(.horizontal, Theme.Space.sm)
        // Pinned like every other control row in this keyboard: a slide along the
        // space bar changes language mid-call, and a bar that swept the other way
        // when it did would read as the call having restarted.
        // See `.claude/rules/keyboard-layout.md`.
        .environment(\.layoutDirection, .leftToRight)
        .animation(Theme.Motion.quick, value: controller.isWorking)
        .animation(Theme.Motion.quick, value: isRecording)
        // **The one thing a VoiceOver user lost with the strip.** The banner said
        // "Fix, working" out loud; a sweeping capsule says nothing at all, and the
        // lit key beside it is a colour.
        //
        // `accessibilityElement(children: .ignore)` is not decoration: the content
        // is two `Capsule`s, which carry no accessibility of their own, so a label
        // on the container alone has nothing to attach to and the row stays absent
        // from the tree — the same silence it is here to fix.
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(!controller.isWorking && !isRecording)
        .accessibilityLabel(
            isRecording ? "Recording" : "\(controller.runningAction?.title ?? "Working"), working"
        )
        .accessibilityIdentifier("bar-working")
    }
}

// MARK: - Previews

#if DEBUG

/// Holds the controller in a `@StateObject` for the reason every other preview
/// host in this package does: the bar takes an `@ObservedObject`, so something
/// outside the view has to own it or a canvas re-render throws the state away.
private struct WorkingProgressBarPreviewHost: View {

    @StateObject private var controller: KeyboardController

    init() {
        let preview = KeyboardController.preview(language: .english, text: "hi mami")
        preview.isWorking = true
        preview.runningAction = .fix
        preview.workingPhase = 0.35
        _controller = StateObject(wrappedValue: preview)
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkingProgressBar(controller: controller)
            SuggestionBar(controller: controller)
        }
        .background(Theme.Keys.background)
    }
}

#Preview("Working") {
    WorkingProgressBarPreviewHost()
}

#endif
