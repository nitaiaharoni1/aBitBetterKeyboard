import SwiftUI

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
                // A first-class state with a reason and a way back. Restarting a
                // broadcast is Apple's picker's job and nothing here can do it,
                // so this says where the button is instead of pretending to be
                // one.
                status("\(reason.explanation) Restart it in AI Keyboard.")
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
