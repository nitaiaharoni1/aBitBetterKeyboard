import AIKeyboardCore
import SwiftUI

/// The icon, headline and subhead at the top of `ScreenContextView`.
///
/// The idle tile is a quiet inset well with a graphite glyph — the feature's
/// state colour is red, and it belongs to the one state that is actually
/// recording. Orange stays off this hero: it marks actions, not status.
struct ScreenContextHeroSection: View {
    @ObservedObject var session: ScreenContextSession
    let isCapturing: Bool

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle()
                    .fill(
                        isCapturing
                            ? Theme.Semantic.record.opacity(0.16)
                            : Theme.Surface.raised
                    )
                    .frame(width: 104, height: 104)
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.Surface.separator, lineWidth: 1)
                            .opacity(isCapturing ? 0 : 1)
                    )

                Image(systemName: heroIcon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(isCapturing ? Theme.Semantic.record : Theme.Text.primary)
            }
            .padding(.top, Theme.Space.sm)
            .animation(Theme.Motion.quick, value: isCapturing)

            if let badge {
                StatusCapsule(text: badge.text, colour: badge.colour)
            }

            Text(headline)
                .font(Theme.Fonts.display)
                .tracking(-0.5)
                .foregroundStyle(Theme.Text.primary)
                .multilineTextAlignment(.center)

            Text(subhead)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Text.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The same two badges the home card wears: SAMPLE over the scripted demo,
    /// LIVE only while a capture session is running. Anything else gets none,
    /// because a badge over "Not watching anything" would be noise.
    private var badge: (text: String, colour: Color)? {
        if session.source == .scripted { return ("SAMPLE", Theme.Text.tertiary) }
        if isCapturing { return ("LIVE", Theme.Semantic.record) }
        return nil
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
            // Word for word what the keyboard's strip and ScreenContextPrompt
            // print, separated by a newline to match both.
            return "\(reason.explanation)\n\(reason.recovery)"
        }
    }
}
