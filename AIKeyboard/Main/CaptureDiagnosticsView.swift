import AIKeyboardCore
import SwiftUI

/// What only a phone can answer, shown on the phone.
///
/// **Why this screen exists.** Every statement this project makes about ReplayKit
/// is a prediction. The iOS Simulator ships no `replayd`, so `processSampleBuffer`
/// has never executed anywhere: the frame's size, its pixel format, whether
/// rotation ever reaches us, and what a read costs against a ~50 MB jetsam ceiling
/// are all guesses written down carefully. The capture process logs every one of
/// them, but reading a device log means a cable and a Mac, and needing a cable to
/// learn whether the feature works at all is a bad reason not to learn it.
///
/// So the same facts cross the App Group in `CaptureStatus`'s device-facts block,
/// and this renders them. Install the app any way you like — a cable, TestFlight,
/// anything — start a broadcast, and read the answers here.
///
/// **Everything on this screen is observation, and nothing on it gates anything.**
/// A row that says "not yet" is not a failure; it means no frame has carried that
/// fact yet, which for a session that has never started is the correct answer.
///
/// **It is collapsed, and that is the whole of the change this section needed.**
/// The first row is "Frames delivered: 1,283, 320 sampled" and a phone's owner
/// reads that as "this app is photographing my screen sixty times a second" — a
/// reasonable reading of a number that is, in fact, about a counter incrementing
/// inside a process that keeps nothing. Deleting the rows was the other option and
/// it is the wrong one: ten of this design's open questions can only be answered
/// on hardware, six of them (R1, R2, R3, R7, R11, R17) are answered by exactly
/// these rows, and no device has ever run this pipeline. So the numbers stay, in
/// full, one tap away, under a label that says whose numbers they are. Nobody
/// opens it by accident and nobody who needs it has to go looking for a cable.
struct CaptureDiagnosticsView: View {

    @ObservedObject var session: ScreenContextSession

    /// Collapsed on every appearance, deliberately not remembered. A developer
    /// disclosure that stays open is a developer disclosure the next person to
    /// pick up the phone reads as the product.
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                Divider().overlay(Theme.Surface.separator)
                    .padding(.top, 8)

                preamble

                if let status = session.status, status.sessionID != nil {
                    rows(for: status)
                } else {
                    waiting
                }
            }
        } label: {
            header
        }
        .tint(Theme.Text.secondary)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Surface.raised)
        )
        .accessibilityIdentifier("screen-context-developer-details")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("DEVELOPER DETAILS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Text.tertiary)
            Text("Raw capture counters. Not something you need to read.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preamble: some View {
        Text(
            "These are the capture process's own counters, for whoever is building this. "
                + "They describe a counter going up, not pictures being kept: no screenshot is "
                + "stored anywhere, and one only leaves the device when you tap Reply. Nothing "
                + "here changes how the keyboard behaves."
        )
        .font(.system(size: 12))
        .foregroundStyle(Theme.Text.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 12)
    }

    private var waiting: some View {
        Text(
            "No broadcast has run on this device yet. Start screen context above, "
                + "use the keyboard for a moment, and these fill in."
        )
        .font(.system(size: 13))
        .foregroundStyle(Theme.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func rows(for status: CaptureStatus) -> some View {
        VStack(spacing: 0) {
            // R1. The first question, and the one everything else depends on:
            // does ReplayKit hand this process anything at all?
            row(
                "Frames delivered",
                status.framesDelivered == 0
                    ? "none yet" : "\(status.framesDelivered), \(status.framesSampled) sampled",
                warn: status.framesDelivered == 0)

            row(
                "Frame size",
                status.frameWidth == 0
                    ? "not yet" : "\(status.frameWidth) x \(status.frameHeight)")

            row("Pixel format", status.pixelFormatCode ?? "not yet")

            // R17. A session that only ever reports `up` cannot tell us whether
            // the quarter turns are mapped the right way round — so the set
            // matters more than the current value.
            row(
                "Orientations seen",
                status.orientationsSeen == 0
                    ? "not yet"
                    : status.orientationsDelivered.map(\.name).joined(separator: ", "))

            // R2c / R2 / R3 / R7. The headroom against a ceiling nothing here has
            // ever actually hit.
            row(
                "Memory at start",
                status.baselineFootprintMB.map { String(format: "%.1f MB", $0) } ?? "not yet")

            row(
                "Memory peak",
                status.peakFootprintMB.map { peak in
                    String(format: "%.1f MB  (%.1f MB under 50)", peak, 50 - peak)
                } ?? "not yet",
                warn: (status.peakFootprintMB ?? 0) > 40)

            // R11. Whether locking the screen ends the broadcast or pauses it.
            row(
                "Paused / resumed",
                status.pauseCount == 0 && status.resumeCount == 0
                    ? "never paused" : "\(status.pauseCount) / \(status.resumeCount)")

            row(
                "Reads",
                "\(status.readsRequested) asked, \(status.readsStarted) sent, "
                    + "\(status.readsCompleted) answered")

            // Non-zero means the freshness gate was blind for those frames.
            if status.fingerprintFailures > 0 {
                row(
                    "Frames not fingerprinted", "\(status.fingerprintFailures)",
                    warn: true)
            }

            if status.refusedMemory > 0 {
                row("Reads refused for memory", "\(status.refusedMemory)", warn: true)
            }
        }
        .padding(.top, 4)
    }

    private func row(_ label: String, _ value: String, warn: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Text.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(warn ? Theme.Semantic.record : Theme.Text.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)
    }
}
