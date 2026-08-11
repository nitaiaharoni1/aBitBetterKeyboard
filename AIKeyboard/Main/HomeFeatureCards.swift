import AIKeyboardCore
import SwiftUI

// MARK: - HomeFeatureCard

/// Shared shell for one feature row in the home screen's graphite features card
/// (Screen Context, Dictation). Handles the 38pt icon chip (flat orange with a
/// white glyph, the direction's feature-card mark; red when a session is live),
/// title + optional status capsule, detail text, and chevron. The grouping card
/// itself lives in `HomeView`, so rows sit flush against each other with a
/// hairline between.
///
/// The labels ride on `Theme.Keys.labelOnFunction`, the token the keyboard
/// pairs with its graphite function keys — it is exactly this pairing, white
/// copy on graphite, so the card needs no local colours of its own.
private struct HomeFeatureCard<Destination: View>: View {
    let icon: String
    let activeIcon: String
    let isActive: Bool
    let title: String
    let detail: String
    var badge: (text: String, colour: Color)?
    let accessibilityID: String
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Theme.Space.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(isActive ? Theme.Semantic.record : Theme.Brand.action)
                        .frame(width: 38, height: 38)

                    Image(systemName: isActive ? activeIcon : icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Text.onBrand)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Space.xxs) {
                        Text(title)
                            .font(Theme.Fonts.headline)
                            .foregroundStyle(Theme.Keys.labelOnFunction)

                        if let badge {
                            StatusCapsule(text: badge.text, colour: badge.colour)
                        }
                    }

                    Text(detail)
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Keys.labelOnFunction.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Keys.labelOnFunction.opacity(0.45))
            }
            .padding(.vertical, Theme.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }
}

// MARK: - HomeScreenContextCard

/// Navigation card linking to `ScreenContextView`. Shows LIVE when a capture
/// session is running and SAMPLE over the scripted demo.
struct HomeScreenContextCard: View {
    @StateObject private var session = ScreenContextSession.shared

    var body: some View {
        HomeFeatureCard(
            icon: "eye",
            activeIcon: "eye.fill",
            isActive: isCapturing,
            title: "Screen Context",
            detail: screenContextDetail,
            badge: badge,
            accessibilityID: "home-screen-context"
        ) {
            ScreenContextView()
        }
    }

    /// LIVE means a capture session is running, and only that. The sample
    /// conversation gets its own badge; a red LIVE over a scripted demo says the
    /// screen is being watched when nothing is.
    private var isCapturing: Bool { session.source == .capture && session.isLive }

    private var badge: (text: String, colour: Color)? {
        if isCapturing { return ("LIVE", Theme.Semantic.record) }
        if session.source == .scripted { return ("SAMPLE", Theme.Text.tertiary) }
        return nil
    }

    private var screenContextDetail: String {
        switch session.source {
        case .capture: return "The keyboard can reply to what's on screen"
        case .scripted: return "Playing a sample conversation"
        case .none: return "Let the keyboard answer the message you're looking at"
        }
    }
}

// MARK: - HomeDictationCard

/// Navigation card linking to `DictationView`. Shows LIVE while a dictation
/// session is running in the app.
struct HomeDictationCard: View {
    @StateObject private var dictation = DictationService.shared

    var body: some View {
        HomeFeatureCard(
            icon: "mic",
            activeIcon: "mic.fill",
            isActive: dictation.isRunning,
            title: "Dictation",
            detail: dictation.isRunning
                ? "The keyboard's microphone button works now"
                : "Start a session here to dictate from the keyboard",
            badge: dictation.isRunning ? ("LIVE", Theme.Semantic.record) : nil,
            accessibilityID: "home-dictation"
        ) {
            DictationView()
        }
    }
}
