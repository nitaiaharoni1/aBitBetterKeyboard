import AIKeyboardCore
import SwiftUI

/// Session stats card: live/stopped status dot, counters, and the last read
/// context. Only shown when `session.source == .capture`.
///
/// Exposes what the session has done *for the user* (screens sent, answers
/// back, pictures kept). The raw frame counters live in `CaptureDiagnosticsView`
/// where they are labelled as developer numbers.
struct ScreenContextLiveDetailCard: View {
    @ObservedObject var session: ScreenContextSession

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                HStack(spacing: Theme.Space.xs) {
                    Circle()
                        .fill(session.isLive ? Theme.Semantic.record : Theme.Text.tertiary)
                        .frame(width: 8, height: 8)
                    Text(statusLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Text.primary)
                    Spacer()
                    // Reachable: `MemoryGovernor` writes `degraded` when the
                    // capture process's own `phys_footprint` goes above its
                    // watermark, and reads are refused for as long as it stays
                    // there.
                    if session.status?.isDegraded == true {
                        StatusCapsule(text: "LOW MEMORY", colour: Theme.Semantic.record)
                    }
                }

                Divider().overlay(Theme.Surface.separator)

                HStack(spacing: 0) {
                    metric(value: "\(session.status?.readsStarted ?? 0)", label: "Screens sent")
                    metric(value: "\(session.status?.readsCompleted ?? 0)", label: "Answers back")
                    metric(value: "0", label: "Pictures kept")
                }

                if let context = session.state.context {
                    Divider().overlay(Theme.Surface.separator)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("LAST READ")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Theme.Text.tertiary)

                        // No app name: this design has no live signal for which
                        // app is on screen, and a stale one beside a fresh
                        // message is worse than none.
                        Text(context.sender)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Text.primary)

                        Text(context.message)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .environment(\.layoutDirection, context.language.layoutDirection)
                            .frame(
                                maxWidth: .infinity,
                                alignment: context.language.isRightToLeft ? .trailing : .leading)
                    }
                }
            }
        }
    }

    private var statusLabel: String {
        switch session.state {
        case .off: return "Off"
        case .starting: return "Starting"
        case .watching: return "Watching"
        case .ready: return "Read the screen"
        case .paused: return "Paused"
        case .ended: return "Stopped"
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.Text.primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.Text.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
