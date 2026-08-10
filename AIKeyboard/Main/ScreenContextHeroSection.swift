import AIKeyboardCore
import SwiftUI

/// The icon, headline and subhead at the top of `ScreenContextView`.
///
/// `isCapturing` is passed in rather than computed here because the parent
/// also uses it for `AmbientBackground`'s intensity.
struct ScreenContextHeroSection: View {
    @ObservedObject var session: ScreenContextSession
    let isCapturing: Bool

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle()
                    .fill(
                        isCapturing
                            ? AnyShapeStyle(Theme.Semantic.record.opacity(0.16))
                            : AnyShapeStyle(Theme.Brand.softGradient)
                    )
                    .frame(width: 104, height: 104)

                Image(systemName: heroIcon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        isCapturing
                            ? AnyShapeStyle(Theme.Semantic.record) : AnyShapeStyle(Theme.Brand.gradient))
            }
            .padding(.top, Theme.Space.sm)

            Text(headline)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.Text.primary)
                .multilineTextAlignment(.center)

            Text(subhead)
                .font(.system(size: 15))
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var heroIcon: String {
        if session.source == .scripted { return "play.circle" }
        return isCapturing ? "eye.fill" : "eye.slash"
    }

    /// Deliberately not "Reading your screen". A live session watches; it reads
    /// only when the user taps Reply, and the difference is the whole privacy
    /// story.
    private var headline: String {
        if session.source == .scripted { return "Sample conversation" }
        switch session.state {
        case .off: return "Not watching anything"
        case .starting: return "Starting"
        case .watching, .ready: return "Watching your screen"
        case .paused: return "Paused"
        case .ended(let reason):
            return reason.canRestart ? "Screen context stopped" : "Screen context can't run yet"
        }
    }

    private var subhead: String {
        if session.source == .scripted {
            return
                "Nothing is being captured. This is a message we wrote, so you can see what Reply does before starting anything."
        }
        switch session.state {
        case .off:
            return "Start this and the keyboard can answer the message in front of you, in any app."
        case .starting:
            return "Waiting for the first frame from iOS."
        case .watching, .ready:
            return "Nothing is sent anywhere until you tap Reply on the keyboard."
        case .paused:
            return "iOS paused the broadcast. It usually resumes on its own."
        case .ended(let reason):
            // Word for word what the keyboard's strip prints, because it is the
            // same two strings off the same reason.
            return "\(reason.explanation) \(reason.recovery)"
        }
    }
}
