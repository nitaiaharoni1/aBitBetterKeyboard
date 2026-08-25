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
    /// A model call. The orbit keeps its own clock — see `ControlOrbit`.
    case working
    /// The half-second after an answer lands: the rim completes and lets go.
    /// Success only; a failure returns straight to idle and the banner
    /// explains, so the celebration can never sit on top of an error.
    case arriving
    /// The microphone is open. Empty levels are still a recording that just
    /// started; finishing is `.idle` here even though the key stays red.
    case recording(levels: [Double])
}

extension KeyActivity {

    /// Caps that wear the working orbit: the three text actions, not emoji
    /// and not the microphone.
    static func hostsWorkingOrbit(_ cap: KeyCap) -> Bool {
        switch cap {
        case .aiFix, .aiReply, .quickTone: return true
        default: return false
        }
    }

    /// Resolves activity for one cap. Callers pass this only to the live
    /// control so the other keys never rebuild for another key's call.
    static func resolve(
        cap: KeyCap,
        isDictating: Bool,
        dictationLevels: [Double] = [],
        isActionActive: Bool,
        isWorking: Bool,
        isArriving: Bool = false
    ) -> KeyActivity {
        if cap == .dictation {
            return isDictating ? .recording(levels: dictationLevels) : .idle
        }
        guard isActionActive, hostsWorkingOrbit(cap) else { return .idle }
        // Work outranks arrival: `beginWork` clears the arrival state, but a
        // resolve racing that clear must not flash a finished rim over a call
        // that has already started again.
        if isWorking { return .working }
        if isArriving { return .arriving }
        return .idle
    }

    /// Same questions, read off the controller. `dictationLevels` are touched
    /// only on the live branch.
    @MainActor
    static func resolve(for cap: KeyCap, controller: KeyboardController) -> KeyActivity {
        resolve(
            cap: cap,
            isDictating: controller.isDictating,
            dictationLevels: controller.isDictating ? controller.dictationLevels : [],
            isActionActive: controller.isActionKeyActive(cap),
            isWorking: controller.isWorking,
            isArriving: controller.arrivingAction != nil)
    }

    /// The bar's rewrite button. Fix and Reply light their own keys; this
    /// one used to spin for every call. The arrival is matched the same way:
    /// only its own two actions close a rim here.
    static func resolveTone(
        runningAction: AIAction?,
        isWorking: Bool,
        arrivingAction: AIAction? = nil
    ) -> KeyActivity {
        if isWorking {
            switch runningAction {
            case .rewrite, .tone: return .working
            default: return .idle
            }
        }
        switch arrivingAction {
        case .rewrite, .tone: return .arriving
        default: return .idle
        }
    }
}

// MARK: - Orbit

/// The indeterminate signal a model call draws: a white highlight circling
/// the cap's rim over a breathing interior wash.
///
/// **It keeps its own clock.** The sweep this replaces was driven by a
/// published `workingPhase` ticked every 16 ms in `beginWork`, which
/// invalidated the controller for every observer for the length of every call
/// — `KeyView`'s `Equatable` conformance exists to survive that.
/// `TimelineView(.animation)` redraws this one small view instead. The phase
/// is derived from the wall clock, so it is monotonic by construction and a
/// language swipe mid-call cannot reverse it — the same rule the sweep's
/// left-to-right pin enforced, inherited here as the layout-direction pin on
/// the gradient's angle.
///
/// The rim rather than the interior, because the signal has to survive a
/// resting thumb: the perimeter is the one part of a 39 pt cap a finger
/// cannot fully cover.
struct ControlOrbit: View {
    let cornerRadius: CGFloat

    /// One lap. Slower than the old 0.53 s sweep on purpose: a typical call
    /// watched that band race past seven times, and fast repetition reads as
    /// stuck rather than busy.
    static let orbitPeriod: TimeInterval = 1.6
    static let rimWidth: CGFloat = 2
    /// White on a filled brand cap, not a second hue — the sweep's own rule.
    static let headOpacity: Double = 0.95
    static let tailOpacity: Double = 0.55
    /// The interior wash at the deepest point of its breath.
    static let breathOpacity: Double = 0.10

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            // Reduced motion parks a visible arc and a faint wash. Presence is
            // what reads as "this one is live"; travel is what Reduce Motion
            // asks us not to do.
            let lap = reduceMotion ? 0.42 : Self.phase(at: context.date)
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                shape.fill(
                    Theme.Text.onBrand.opacity(
                        reduceMotion ? Self.breathOpacity * 0.6 : Self.breath(lap)))
                shape.strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.69),
                            .init(
                                color: Theme.Text.onBrand.opacity(Self.tailOpacity),
                                location: 0.85),
                            .init(
                                color: Theme.Text.onBrand.opacity(Self.headOpacity),
                                location: 0.94),
                            .init(color: .clear, location: 1)
                        ]),
                        center: .center,
                        angle: .degrees(lap * 360)),
                    lineWidth: Self.rimWidth)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
    }

    /// Where the highlight is in its lap, 0 to 1, monotonic across views: the
    /// key and the chip derive it from the same clock, so two surfaces can
    /// never disagree about the orbit.
    static func phase(at date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate / orbitPeriod)
            .truncatingRemainder(dividingBy: 1)
    }

    /// The interior wash, in step with the orbit so the cap inhales once per
    /// lap rather than on a second rhythm.
    static func breath(_ lap: Double) -> Double {
        breathOpacity * (0.5 - 0.5 * cos(lap * 2 * .pi))
    }
}

// MARK: - Arrival

/// The one-shot close: the rim completes the moment the answer lands, then
/// lets go. Paired with the `Feedback.success()` haptic at the call sites
/// that enter `.arriving`, so the eye gets the beat the hand already does.
///
/// Opacity only, which is why Reduce Motion keeps it: a fade is not spatial
/// motion, and the arrival is feedback that confirms an action.
struct ControlArrivalRim: View {
    let cornerRadius: CGFloat

    static let fadeDuration: TimeInterval = 0.45
    static let fullOpacity: Double = 0.9

    @State private var faded = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                Theme.Text.onBrand.opacity(Self.fullOpacity),
                lineWidth: ControlOrbit.rimWidth
            )
            .opacity(faded ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: Self.fadeDuration)) { faded = true }
            }
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

/// The working orbit and its arrival close, drawn on a key or chip.
/// Recording draws in the icon slot instead: an orbit under a waveform would
/// be two progress languages.
struct ControlActivityChrome: View {
    let activity: KeyActivity
    let cornerRadius: CGFloat

    var body: some View {
        switch activity {
        case .working:
            ControlOrbit(cornerRadius: cornerRadius)
        case .arriving:
            ControlArrivalRim(cornerRadius: cornerRadius)
        case .idle, .recording:
            EmptyView()
        }
    }
}

// MARK: - Previews

#if DEBUG

private struct ControlActivityPreview: View {
    var body: some View {
        HStack(spacing: 12) {
            previewCap(title: "Fix", activity: .working)
            previewCap(title: "Fix", activity: .arriving)
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
        // The action row's own height, read rather than restated: this preview
        // is of a control that only ever lives in that row.
        .frame(width: 74, height: Theme.Metrics.actionRowHeight)
    }
}

#Preview("In-key activity") {
    ControlActivityPreview()
}

#endif
