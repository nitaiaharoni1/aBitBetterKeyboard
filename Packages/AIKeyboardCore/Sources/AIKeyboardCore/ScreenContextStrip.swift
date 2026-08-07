import SwiftUI

/// The row above the suggestion bar, shown only while a capture session is live.
///
/// It does two jobs at once. It is the visible capture indicator Apple requires,
/// and it is the entry point to Reply. Those belong together: the moment the user
/// benefits from the screen being read is the moment they should be reminded it
/// is being read.
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
                status("Watching for a message")
            case .ready(let context):
                contextLabel(context)
                Spacer(minLength: Theme.Space.xxs)
                replyButton
            }

            if controller.screenContext.context == nil {
                Spacer(minLength: 0)
            }

            stopButton
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

    private var liveDot: some View {
        Circle()
            .fill(Theme.Semantic.record)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.Keys.secondaryLabel)
            .lineLimit(1)
    }

    /// Names the app and the sender so it is obvious what was read, and shows the
    /// message itself so nothing is happening off-screen.
    private func contextLabel(_ context: ScreenContext) -> some View {
        HStack(spacing: 4) {
            Image(systemName: context.appIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.Keys.secondaryLabel)

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
        .accessibilityLabel("Message from \(context.sender) in \(context.appName): \(context.message)")
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
