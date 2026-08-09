import ReplayKit
import SwiftUI

/// Apple's own button for starting a screen broadcast, and the reason it is in
/// this package rather than only in the app.
///
/// **It is the one system affordance a keyboard extension can host, and the
/// disassembly says why.** The standing constraint on this keyboard is that it
/// has no `UIApplication`: it cannot `openURL`, cannot open Settings, cannot
/// launch the containing app, and the responder-chain workaround is disallowed.
/// The obvious reading is that starting a broadcast belongs in the same bucket.
/// It does not, and the difference is structural rather than a loophole. Read out
/// of `ReplayKit` in the iOS 26.2 simulator runtime on 2026-08-09,
/// `-[RPSystemBroadcastPickerView buttonPressed:]` does exactly two things:
///
///     [[RPDaemonProxy daemonProxy] setBroadcastPickerPreferredExt:showsMicButton:]
///     [[RPDaemonProxy daemonProxy] openControlCenterSystemRecordingView]
///
/// Two XPC calls to `replayd`, asking *Control Center* to present its own
/// recording view. No `UIApplication`, no view controller presented into our own
/// hierarchy, no window scene, nothing that a process without an application
/// object can be missing. `-[RPSystemBroadcastPickerView addBroadcastPickerButton]`
/// is likewise a plain `UIButton` with an image from ReplayKit's bundle added as a
/// subview. The class is `API_AVAILABLE(ios(12.0))` on `UIView` and no header in
/// `ReplayKit.framework` carries an `NS_EXTENSION_UNAVAILABLE` annotation of any
/// kind.
///
/// **What that argument does not establish, and nothing here can:** whether
/// `replayd` accepts the request from a keyboard extension's process, and whether
/// Control Center's sheet actually appears over a keyboard. Both are device
/// questions and both are unmeasured — the simulator runtime ships no `replayd`,
/// so the button renders and nothing happens, here and in the app equally. The
/// UI around this therefore never claims a broadcast will start; it says what
/// pressing it asks for, and every caller keeps the words that send the user to
/// the app if nothing happens.
///
/// It is also the *only* supported way in: the button inside the picker is
/// system-vended, so no app can press it, and there is no API that starts a
/// session directly.
///
/// **The glyph's colour belongs to the system, and every call site has to design
/// around it rather than set it.** `-[RPSystemBroadcastPickerView
/// screenCaptureChanged]` runs at construction and again on every capture-state
/// change; it dispatches to the main queue and assigns the inner button's
/// `tintColor` from `UIScreen.main.isCaptured` — **black normally, red while the
/// screen is being captured**. Because the button's own tint is assigned
/// explicitly it never inherits, so a tint set on the picker view is ignored.
/// That behaviour is worth keeping: it is the system telling the truth about
/// recording. What it costs is that the background underneath has to be light in
/// *both* appearances or the glyph vanishes in dark mode, which is why each call
/// site fills white first and puts the brand tint over it.
public struct BroadcastPickerButton: UIViewRepresentable {

    /// The broadcast upload extension's bundle identifier, which is
    /// `PRODUCT_BUNDLE_IDENTIFIER` of the `AIKeyboardBroadcast` target. With it
    /// set, iOS shows our extension alone rather than every broadcast service
    /// installed on the phone.
    public static let extensionBundleID = "com.nitai.aikeyboard.broadcast"

    /// **The size is the tap target, and not by much.** `addBroadcastPickerButton`
    /// insets its `UIButton` by 5 points on every edge, so the pressable area is
    /// this size minus 10 in each dimension; everything outside it is an inert
    /// `UIView`. A 26-point square would leave a 16-point target. Callers pass the
    /// largest rectangle their layout allows.
    private let size: CGSize

    public init(width: CGFloat = 60, height: CGFloat = 60) {
        self.size = CGSize(width: width, height: height)
    }

    public func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(origin: .zero, size: size))
        picker.preferredExtension = Self.extensionBundleID
        // The capture path reads pixels and never audio: `SampleHandler` drops
        // `.audioApp` and `.audioMic` without looking at them.
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear
        // No `tintColor` here. See the type's note: the picker overwrites its
        // button's tint from `UIScreen.main.isCaptured`, so setting one would be a
        // line that reads as if it did something.
        return picker
    }

    public func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {}

    @MainActor
    public func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: RPSystemBroadcastPickerView, context: Context
    ) -> CGSize? {
        size
    }
}

/// The row above the suggestion bar, shown whenever screen context has something
/// to say.
///
/// It does two jobs at once. It is the visible capture indicator Apple requires,
/// and it is the entry point to Reply. Those belong together: the moment the user
/// benefits from the screen being read is the moment they should be reminded it
/// is being read.
///
/// **It never names the app.** There is no live signal for which app is on
/// screen: `broadcastAnnotatedWithApplicationInfo:` names the *first* app of a
/// session and only from a Control Center start, and a stale app name beside a
/// fresh message is worse than no app name at all. The sender is the thing the
/// user cares about anyway.
public struct ScreenContextStrip: View {

    @ObservedObject private var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    public var body: some View {
        HStack(spacing: Theme.Space.xs) {
            liveDot

            switch controller.screenContext {
            case .off:
                EmptyView()
            case .starting:
                status("Starting screen context…")
            case .watching:
                // The offer, not a claim. Nothing has been read, because a read
                // only ever happens in answer to this button — and the offer is
                // withdrawn once a tap has proved it cannot be met. Reading
                // inside the capture process is not built, so on a device today
                // that is what every tap proves; the button stays, because the
                // user is the one who decides whether to try again.
                status(
                    controller.screenReadWentUnanswered
                        ? "Screen context isn't reading this screen"
                        : "Reply can read this screen")
                Spacer(minLength: Theme.Space.xxs)
                replyButton
            case .ready(let context):
                contextLabel(context)
                Spacer(minLength: Theme.Space.xxs)
                replyButton
            case .paused:
                status("Screen context is paused")
            case .ended(let reason):
                // A first-class state with a reason and a way back, and the way
                // back is now here rather than only a sentence pointing at the app.
                // Apple's picker is still the only thing that can start a
                // broadcast — but the picker is a `UIView` this process may host,
                // so the strip carries it.
                endedLabel(reason)
                if reason.canRestart {
                    Spacer(minLength: Theme.Space.xxs)
                    startButton
                }
            }

            if controller.screenContext.context == nil {
                Spacer(minLength: 0)
            }

            if controller.canStopScreenContext {
                stopButton
            }
        }
        .padding(.horizontal, Theme.Space.sm)
        .frame(height: Theme.Metrics.contextStripHeight)
        .background(Theme.Keys.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Keys.secondaryLabel.opacity(0.15))
                .frame(height: 0.5)
        }
    }

    // MARK: Pieces

    /// Red only while a capture session is running and looking. A recording dot
    /// over a paused session, a dead one, or the scripted sample is the one thing
    /// this indicator must never do — it is the capture indicator, not decoration.
    ///
    /// "Looking" rather than "sampling frames this instant", and the difference is
    /// `CaptureFreshness.Verdict.idle`: a live session on a screen that has not
    /// changed delivers no frames, and greying the dot for that would say the
    /// session had stopped watching when it had not. The three cases above are
    /// unaffected — a pause iOS reported is still `.paused`, a dead producer is
    /// still `.ended`, and the script is still not `.capture`.
    private var liveDot: some View {
        Circle()
            .fill(
                controller.isCapturingScreen
                    ? AnyShapeStyle(Theme.Semantic.record)
                    : AnyShapeStyle(Theme.Keys.secondaryLabel.opacity(0.5))
            )
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.Keys.secondaryLabel)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    /// Names the sender and shows the message itself, so nothing is happening
    /// off-screen.
    private func contextLabel(_ context: ScreenContext) -> some View {
        HStack(spacing: 4) {
            Text(context.sender)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.Keys.label)

            Text(context.message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .environment(\.layoutDirection, context.language.layoutDirection)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Message from \(context.sender): \(context.message)")
    }

    private var replyButton: some View {
        Button {
            controller.run(.reply)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("Reply")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.Text.onBrand)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Theme.Brand.gradient))
            .contentShape(Capsule())
        }
        .pressable()
        .accessibilityIdentifier("context-reply")
        .accessibilityLabel("Reply to this message")
    }

    /// An ending, in two lines: what happened, and what to do about it.
    ///
    /// **Two lines because the second one has to survive the button doing
    /// nothing.** `BroadcastPickerButton`'s own doc comment is honest that whether
    /// `replayd` answers a keyboard extension is unmeasured — no simulator ships
    /// it and no device has run this. A strip that replaced "Restart it in AI
    /// Keyboard." with a button would, in exactly the case where that button is
    /// inert, leave the user with a control that does nothing and no words telling
    /// them where it does work. So the button is the fast path and the app is
    /// named underneath it, and neither is dropped for the other.
    ///
    /// It fits: 11 and 10 points of text with no spacing is about 26 of the strip's
    /// 30. Where a restart would not help there is no button, and the second line
    /// is the reason's own recovery instead — the same string the app prints.
    private func endedLabel(_ reason: ScreenContextEndReason) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(reason.explanation)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.Keys.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(reason.canRestart ? "Start it again here, or in AI Keyboard." : reason.recovery)
                .font(.system(size: 10))
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reason.explanation) \(reason.recovery)")
    }

    /// Apple's picker, in the keyboard, sized to what a 30-point strip allows.
    ///
    /// **Not a `Button`, and it cannot be one.** The pressable thing is the
    /// system's own `UIButton` inside `RPSystemBroadcastPickerView`; no app can
    /// send it a touch, and nothing in this process may start a broadcast
    /// directly. So the capsule is decoration behind a system control, sized so
    /// that the control — inset by 5 points on each edge — is the larger part of
    /// what the user aims at.
    ///
    /// The sentence beside it carries the copy, because a system-vended button
    /// takes no title.
    private var startButton: some View {
        BroadcastPickerButton(width: 56, height: 26)
            .frame(width: 56, height: 26)
            // White first, brand tint over it. The system draws the glyph black
            // — see `BroadcastPickerButton` — so a background that goes dark in
            // dark mode makes it disappear.
            .background(
                Capsule()
                    .fill(Theme.Text.onBrand)
                    .overlay(Capsule().fill(Theme.Brand.softGradient))
                    .overlay(Capsule().strokeBorder(Theme.Brand.solid.opacity(0.35), lineWidth: 0.5))
            )
            .accessibilityLabel("Start screen context")
            .accessibilityHint("Opens the iOS screen broadcast picker")
            .accessibilityIdentifier("context-start-broadcast")
    }

    /// Only ever shown for the scripted demo. A real broadcast is stopped from
    /// iOS's own red pill or Control Center, and a stop button here that could
    /// not stop it would be a lie about who is in control.
    private var stopButton: some View {
        Button {
            ScreenContextSession.shared.stop()
        } label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Keys.secondaryLabel)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .pressable()
        .accessibilityLabel("Stop screen context")
    }
}
