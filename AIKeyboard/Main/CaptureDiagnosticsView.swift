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
struct CaptureDiagnosticsView: View {

    @ObservedObject var session: ScreenContextSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().overlay(Theme.Surface.separator)

            if let status = session.status, status.sessionID != nil {
                rows(for: status)
            } else {
                waiting
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.Surface.raised)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WHAT THE PHONE SAYS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Text.tertiary)
            Text("Facts only a real device can answer. Nothing here changes how the keyboard behaves.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 12)
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
