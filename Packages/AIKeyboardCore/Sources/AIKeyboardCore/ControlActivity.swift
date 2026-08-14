import SwiftUI

/// What a control is doing right now, if it is the live one.
///
/// **One value rather than `isWorking` and `isDictating` read in every view.**
/// The reserved strip above the candidates used to answer both questions for
/// the whole keyboard. Status now lives on the control that started the work,
/// and that control asks one thing: am I the live one? AI keys already have
/// `isActionKeyActive`. The waveform follows `isDictating`, not the key's
/// `isRecording`, which stays true through `.finishing` so the cap does not
/// flash Record.
public enum KeyActivity: Equatable, Sendable {
    case idle
    /// A model call. `phase` is `KeyboardController.workingPhase`.
    case working(phase: Double)
    /// The microphone is open. Empty levels are still a recording that just
    /// started; finishing is `.idle` here even though the key stays red.
    case recording(levels: [Double])
}

extension KeyActivity {

    /// Caps that wear the working sweep: the three text actions, not emoji
    /// and not the microphone.
    static func hostsWorkingSweep(_ cap: KeyCap) -> Bool {
        switch cap {
        case .aiFix, .aiReply, .quickTone: return true
        default: return false
        }
    }

    /// Resolves activity for one cap. Callers pass this only to the live
    /// control so a 60 Hz `workingPhase` tick does not rebuild every key.
    static func resolve(
        cap: KeyCap,
        isDictating: Bool,
        dictationLevels: [Double] = [],
        isActionActive: Bool,
        isWorking: Bool,
        workingPhase: Double = 0
    ) -> KeyActivity {
        if cap == .dictation {
            return isDictating ? .recording(levels: dictationLevels) : .idle
        }
        if isActionActive, isWorking, hostsWorkingSweep(cap) {
            return .working(phase: workingPhase)
        }
        return .idle
    }

    /// Same questions, read off the controller. `workingPhase` and
    /// `dictationLevels` are touched only on the live branch.
    @MainActor
    static func resolve(for cap: KeyCap, controller: KeyboardController) -> KeyActivity {
        resolve(
            cap: cap,
            isDictating: controller.isDictating,
            dictationLevels: controller.isDictating ? controller.dictationLevels : [],
            isActionActive: controller.isActionKeyActive(cap),
            isWorking: controller.isWorking,
            workingPhase: controller.isWorking ? controller.workingPhase : 0)
    }

    /// The bar's rewrite button. Fix and Reply light their own keys; this
    /// one used to spin for every call.
    static func resolveTone(
        runningAction: AIAction?,
        isWorking: Bool,
        workingPhase: Double
    ) -> KeyActivity {
        guard isWorking else { return .idle }
        switch runningAction {
        case .rewrite, .tone: return .working(phase: workingPhase)
        default: return .idle
        }
    }
}

// MARK: - Sweep

/// The indeterminate segment a model call draws, clipped by the caller to
/// the key or chip.
///
/// **The same math the reserved hairline used.** `workingPhase` grows without
/// bound — `beginWork` drives it at 0.03 per 16 ms and never wraps it — so
/// the wrap happens here. Pinned left-to-right: a language swipe mid-call
/// must not reverse the sweep and read as the call having restarted.
struct ControlSweep: View {
    let phase: Double

    static let segmentFraction: CGFloat = 0.32
    /// White on a filled brand cap, not a second hue.
    static let fillOpacity: Double = 0.4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let segment = width * Self.segmentFraction
            // Reduced motion freezes a visible slice. Travel is the thing
            // that reads as progress; a parked segment still says "this one".
            let shown = reduceMotion ? 0.35 : phase.truncatingRemainder(dividingBy: 1)
            Capsule(style: .continuous)
                .fill(Theme.Text.onBrand.opacity(Self.fillOpacity))
                .frame(width: segment)
                .offset(x: CGFloat(shown) * (width + segment) - segment)
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
    }
}

// MARK: - Waveform

/// Loudness bars for a live microphone, sized to the icon slot.
///
/// **The same lift the reserved strip used, drawn smaller.** Speech RMS lives
/// around 0.02–0.2; the square root pulls quiet speech off the floor, and a
/// standing sine across the slots keeps a held note from marching as a wall.
/// Bar count follows the control's width, not the old full-width 30.
struct ControlWaveform: View {
    let levels: [Double]
    var full: CGFloat = iconSlotHeight
    var color: Color = Theme.Text.onBrand

    static let iconSlotHeight: CGFloat = 20
    static let waveGap: CGFloat = 1.5
    /// Speech RMS that fills the slot. The quietest corpus clip peaks at 0.208
    /// (`SpeechGate.peakFloor` is 0.01); typical frames sit well below that.
    static let waveFullLevel: Double = 0.12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let drawn = reduceMotion ? Self.reducedMotionLevels : levels
            let count = min(12, max(5, Int(geo.size.width / 5)))
            let barWidth = max(
                1, (geo.size.width - CGFloat(count - 1) * Self.waveGap) / CGFloat(count))
            HStack(alignment: .center, spacing: Self.waveGap) {
                ForEach(0..<count, id: \.self) { slot in
                    // Right-aligned: newest reading at the trailing edge, so a
                    // fresh recording fills in from the right rather than
                    // starting as a full row of flat bars.
                    let index = slot - (count - drawn.count)
                    let level = drawn.indices.contains(index) ? drawn[index] : 0
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(
                            width: barWidth,
                            height: Self.waveHeight(level: level, full: full, slot: slot))
                }
            }
            .frame(width: geo.size.width, height: full)
        }
        .frame(height: full)
        .environment(\.layoutDirection, .leftToRight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: levels)
        .allowsHitTesting(false)
    }

    /// A short static shape. Live levels at 10 Hz are the dance Reduce Motion
    /// is asking us not to do.
    private static let reducedMotionLevels: [Double] = [0.06, 0.11, 0.08, 0.12, 0.07, 0.10]

    /// How tall one sliver is.
    ///
    /// Drawn into three points this was a dashed line that never moved. The
    /// icon slot is ~20 pt so a quiet spoken frame is taller than silence and
    /// taller than that hairline.
    static func waveHeight(level: Double, full: CGFloat, slot: Int = 0) -> CGFloat {
        let visual = min(1, sqrt(max(0, level) / waveFullLevel))
        let freq = 0.62 + 0.38 * sin(Double(slot) * 1.37)
        return max(full * 0.12, full * CGFloat(visual * freq))
    }
}

// MARK: - Cap chrome

/// The working sweep, clipped to a key or chip. Recording draws in the icon
/// slot instead: a sweep under a waveform would be two progress languages.
struct ControlActivityChrome: View {
    let activity: KeyActivity
    let cornerRadius: CGFloat

    var body: some View {
        if case .working(let phase) = activity {
            ControlSweep(phase: phase)
                .clipShape(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - Previews

#if DEBUG

private struct ControlActivityPreview: View {
    var body: some View {
        HStack(spacing: 12) {
            previewCap(title: "Fix", activity: .working(phase: 0.35))
            previewCap(
                title: "Pause",
                activity: .recording(levels: [0.04, 0.09, 0.06, 0.11, 0.08]),
                fill: Theme.Semantic.record)
        }
        .padding()
        .background(Theme.Keys.background)
    }

    private func previewCap(
        title: String, activity: KeyActivity, fill: Color = Theme.Brand.action
    )
        -> some View
    {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.key, style: .continuous)
                .fill(fill)
            ControlActivityChrome(activity: activity, cornerRadius: Theme.Radius.key)
            VStack(spacing: 1) {
                if case .recording(let levels) = activity {
                    ControlWaveform(levels: levels)
                        .frame(maxWidth: 36)
                } else {
                    Image(systemName: "checkmark.circle")
                        .font(Theme.Glyph.medium(15))
                }
                Text(title)
                    .font(Font(SuggestionBar.toneLabelFont))
            }
            .foregroundStyle(Theme.Text.onBrand)
        }
        .frame(width: 74, height: 43)
    }
}

#Preview("In-key activity") {
    ControlActivityPreview()
}

#endif
