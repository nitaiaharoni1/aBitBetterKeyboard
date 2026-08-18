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
///
/// **Not in the v1 build, and not deleted.** This is the only screen in the app
/// that can start a ReplayKit broadcast, so it is the surface
/// `FeatureFlags.screenCaptureReply` turns off: `HomeView` draws it only while
/// that flag is true, and `AppSearch` withholds the row that lands on it. The
/// flag's own comment carries the reason and the condition — NIT-6 passing on a
/// physical phone, because nothing in this path has ever executed on a
/// Simulator that ships no `replayd`.
///
/// **The scripted sample needed no gate, because nothing offers it.**
/// `ScreenContextSession.start()` — the fake conversation, `source ==
/// .scripted` — has no call site outside `AIKeyboardCoreTests`: the button that
/// played it is already gone, and `SharedStore.screenContextAllowed`, the only
/// other way in, has no control that writes it. That matters now rather than as
/// trivia, because v1 Reply reads the pasteboard rather than the screen: a
/// sample that acted out "Reply reads the conversation on your screen" would be
/// demonstrating a capability this build does not have, which is the one thing
/// the app may not do. It is a test fixture in `AIKeyboardCore` and stays there.
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
///
/// **The session this starts has no end, and that is a decision rather than an
/// oversight.** It opens with `DictationService.noSessionLimit`, so `expiresAt`
/// stays nil in this process and the shared page carries `0`, which
/// `DictationSessionState.isAlive` reads as "alive for as long as the heartbeat
/// keeps coming". Dictation runs until the user stops it.
///
/// A bound was added here on 2026-08-18 and taken back out the same day. The
/// argument for it was real and is worth keeping written down, because it is the
/// argument anyone will re-derive from the code: the microphone stays open in
/// the one app whose `audio` background mode keeps it recording after the user
/// switches away, and a `SharedStore.dictationSessionMinutes` setting offered 5,
/// 15 and 60 while saying it deliberately had no "never". The owner's answer was
/// that dictation is not to be bounded at all: a
/// session is something you start and stop, and cutting somebody off mid-sentence
/// is the worse failure.
///
/// The setting is deleted, because with the bound gone nothing read it and a
/// stored setting nothing consults invites somebody to wire it back up without
/// re-taking the decision. Worth knowing if a bound is ever revisited: it never
/// had a control the user could reach, so bounding sessions would have meant a
/// fixed length for everyone until a picker was built.
///
/// What this decision does change is `Info.plist`'s background-mode comment,
/// which used to justify the entitlement by saying the session closes itself;
/// that comment now says what is actually true, and it is the place to start if
/// App Review ever asks.
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
                        await dictation.start(minutes: DictationService.noSessionLimit)
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
        // **Names no length, because a session has none.** A bound was briefly
        // added here and taken back out: dictation runs until the user stops it.
        // Promising a number this screen would then have to keep is the reason
        // the sentence says what the session is for instead.
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
