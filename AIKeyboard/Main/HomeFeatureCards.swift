import AIKeyboardCore
import SwiftUI

// MARK: - HomeFeatureCard

/// Shared shell for one feature row in the home screen's graphite features card
/// (Screen Context, Dictation). Handles the 38pt icon chip (flat orange with a
/// white glyph, the direction's feature-card mark; red when a session is live),
/// title + optional status capsule, detail text, and a trailing control. The
/// grouping card itself lives in `HomeView`, so rows sit flush against each
/// other with a hairline between.
///
/// The labels ride on `Theme.Keys.labelOnFunction`, the token the keyboard
/// pairs with its graphite function keys — it is exactly this pairing, white
/// copy on graphite, so the card needs no local colours of its own.
private struct HomeFeatureCard<Trailing: View>: View {
    let icon: String
    let activeIcon: String
    let isActive: Bool
    let title: String
    let detail: String
    var badge: (text: String, colour: Color)?
    let accessibilityID: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
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
                        .accessibilityIdentifier(accessibilityID)

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

            trailing()
        }
        .padding(.vertical, Theme.Space.xs)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - HomeScreenContextCard

/// Starts a broadcast from Home. The record icon is paint. The tap
/// target is `RPSystemBroadcastPickerView` stretched over the whole
/// row, the same way the Reply banner hosts it: a 38pt chip left
/// "Share the screen" inert. A SwiftUI button cannot open that sheet.
struct HomeScreenContextCard: View {
    @StateObject private var session = ScreenContextSession.shared

    var body: some View {
        HomeFeatureCard(
            icon: "eye",
            activeIcon: "eye.fill",
            isActive: isCapturing,
            title: "Screen Context",
            detail: screenContextDetail,
            badge: isCapturing ? ("LIVE", Theme.Semantic.record) : nil,
            accessibilityID: "home-screen-context"
        ) {
            HomeSessionLabel(icon: "record.circle", isStop: isCapturing)
        }
        .accessibilityHidden(!isCapturing)
        .overlay {
            if !isCapturing {
                BroadcastPickerButton.overlay(
                    label: "Start a screen broadcast",
                    hint: "Opens the iOS screen broadcast picker.",
                    identifier: "screen-context-start-broadcast")
            }
        }
        .searchTarget(.screenContext)
    }

    private var isCapturing: Bool { session.source == .capture && session.isLive }

    private var screenContextDetail: String {
        if isCapturing { return "Sharing. The keyboard can reply to what's on screen." }
        return "Share the screen so Reply can read it"
    }
}

// MARK: - HomeDictationCard

/// Starts and stops a dictation session from Home. The microphone can only
/// open in this process, which is why the control lives here and not on the
/// keyboard.
struct HomeDictationCard: View {
    @ObservedObject private var dictation = DictationService.shared
    @State private var starting = false

    var body: some View {
        HomeFeatureCard(
            icon: "mic",
            activeIcon: "mic.fill",
            isActive: dictation.isRunning,
            title: "Dictation",
            detail: dictationDetail,
            badge: dictation.isRunning ? ("LIVE", Theme.Semantic.record) : nil,
            accessibilityID: "home-dictation"
        ) {
            HomeSessionButton(
                icon: dictation.isRunning ? "stop.fill" : "mic.fill",
                isStop: dictation.isRunning,
                isEnabled: !starting
            ) {
                if dictation.isRunning {
                    dictation.stop()
                } else {
                    starting = true
                    Task {
                        await dictation.start(minutes: 0)
                        starting = false
                    }
                }
            }
            .accessibilityLabel(dictation.isRunning ? "Stop dictation" : "Start dictation")
            .accessibilityIdentifier(dictation.isRunning ? "dictation-stop" : "dictation-start")
        }
        .searchTarget(.dictation)
    }

    private var dictationDetail: String {
        if dictation.isRunning {
            return "The mic key works now. Switch to the app you're writing in."
        }
        if !dictation.lastError.isEmpty { return dictation.lastError }
        return "Start a session to dictate from the keyboard"
    }
}

// MARK: - HomeSessionButton

private struct HomeSessionLabel: View {
    let icon: String
    let isStop: Bool

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isStop ? Theme.Semantic.record : Theme.Brand.action)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Theme.Text.onBrand))
    }
}

private struct HomeSessionButton: View {
    let icon: String
    let isStop: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeSessionLabel(icon: icon, isStop: isStop)
        }
        .pressable()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
