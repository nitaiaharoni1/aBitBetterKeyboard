import AIKeyboardCore
import SwiftUI

/// Where the capture session is started, watched, and restarted.
///
/// This screen carries the honesty burden for the whole feature. It has to say
/// what is read, what leaves the device, what is kept, and when it stops, in
/// language someone can check against what they observe. Two claims on it used to
/// fail that test and are gone: that the reading happens on device (in the
/// ReplayKit flow it is cloud-only), and that a switch could keep it on device.
struct ScreenContextView: View {
    @EnvironmentObject private var store: SharedStore
    @StateObject private var session = ScreenContextSession.shared

    var body: some View {
        ZStack {
            AmbientBackground(intensity: isCapturing ? 1 : 0.5)

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    hero
                    if session.source == .capture { liveDetail }
                    // Above `starter`, because a broadcast started without this
                    // set ends inside a second with `.notConfigured`. Putting the
                    // fix below the thing it blocks would be a screen that lets
                    // the user fail first.
                    backend
                    starter
                    demo
                    explanation
                    limits
                    // Last, because it is for whoever is developing this rather
                    // than for whoever is using it — and on a device with no Mac
                    // attached it is the only way to find out whether ReplayKit
                    // delivers anything at all. See `CaptureDiagnosticsView`.
                    CaptureDiagnosticsView(session: session)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
            }
        }
        .navigationTitle("Screen Context")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: The backend

    /// A pointer, not a field, and **the move is the point.**
    ///
    /// `BackendTransport.configured()` is the only thing that turns a captured
    /// frame into text, and it returns nil unless `cloudBackendURL` is in the
    /// shared store. This screen used to be the one place in the whole app that
    /// wrote that key, under a heading about screen reading — which made the
    /// *other* three readers of it invisible. The same key is what every Hebrew
    /// Fix, Rewrite, Tone and Reply needs, and a user whose keyboard failed at all
    /// four had no reason on earth to look for the fix inside a screen-recording
    /// feature they had never turned on. The editor now lives in Settings › AI and
    /// this points at it; see `CloudModelView` for why that direction and not the
    /// other one.
    ///
    /// Still above `starter`, unchanged: a broadcast started with no cloud model
    /// ends inside a second with `.notConfigured`, so the fix has to be reachable
    /// before the button that fails.
    private var backend: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            // Not "Where the screen is read" any more. That title was true of one
            // of the four things this setting switches on, and it is what made the
            // other three impossible to find.
            SectionHeader(title: "Before you start: the cloud model")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(
                        "Reading a screen needs a server to send it to, and it is the same one the keyboard's AI actions use. Until it is set, screen context will not start."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    CloudModelRow()
                }
            }
        }
    }

    // MARK: Hero

    /// Nothing on this screen goes red for the sample conversation. A recording
    /// colour over a session that is not capturing anything is the same lie as a
    /// red dot on the strip, and this is the screen that has to be checkable
    /// against what the user observes.
    private var isCapturing: Bool { session.source == .capture && session.isLive }

    private var hero: some View {
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
            // same two strings off the same reason. This screen used to append its
            // own "Start it again below." to `explanation` while the strip appended
            // "Restart it in AI Keyboard.", so one page in the shared container
            // produced two different pieces of advice — and both were wrong for an
            // ending a restart cannot fix. See `ScreenContextEndReason.recovery`.
            return "\(reason.explanation) \(reason.recovery)"
        }
    }

    // MARK: Live detail

    /// What this session has done *for the user*, and nothing about frames.
    ///
    /// **A frame count is the wrong unit to put in front of somebody.** This card
    /// used to lead with "Frames seen: 1,283", read straight out of
    /// `CaptureStatus.framesSampled`, which is true and reads as "this app is
    /// photographing my phone sixty times a second". It is not a privacy fact at
    /// all: a sampled frame is reduced to 2,048 greyscale samples inside the
    /// capture process, hashed, and discarded inside the callback it arrived in —
    /// nothing about it ever leaves, and nothing about it is stored. The number
    /// that *is* a privacy fact is how many screenshots left the device, which is
    /// one per Reply tap, and how many pictures are kept, which is none.
    ///
    /// The frame counters are not deleted; they moved to `CaptureDiagnosticsView`,
    /// which is now behind a disclosure that says whose numbers they are. They are
    /// the only answer this project has to R1 and nobody has run it yet.
    private var liveDetail: some View {
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
                        Text("LOW MEMORY")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.Text.onBrand)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Semantic.record))
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

    // MARK: Starting, and restarting

    /// The only way in, and it is Apple's button.
    ///
    /// `RPSystemBroadcastPickerView` cannot be triggered programmatically, so
    /// there is no "Start" button here that does the work — the three steps say
    /// what the user has to do, and the button below them is the system's own.
    private var starter: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: session.source == .capture ? "Start it again" : "Start screen context")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    step(
                        number: 1, title: "Tap the button below",
                        detail: "iOS opens its own list of what can record the screen.")
                    step(
                        number: 2, title: "Pick AI Keyboard, then Start Broadcast",
                        detail: "iOS counts down from three before anything starts.")
                    step(
                        number: 3, title: "Go back to your conversation",
                        detail:
                            "A red indicator stays in the status bar for as long as this runs. Tap it to stop."
                    )

                    HStack {
                        Spacer()
                        BroadcastPickerButton()
                            .frame(width: 60, height: 60)
                            // White under the soft gradient, which is 18% opacity
                            // and therefore takes on whatever is behind it. The
                            // system draws the glyph black — see
                            // `BroadcastPickerButton` — so over `Surface.raised` in
                            // dark mode the button was a black glyph on a near-black
                            // circle.
                            .background(
                                Circle()
                                    .fill(Theme.Text.onBrand)
                                    .overlay(Circle().fill(Theme.Brand.softGradient))
                            )
                            .accessibilityLabel("Start a screen broadcast")
                            .accessibilityIdentifier("screen-context-start-broadcast")
                        Spacer()
                    }

                    Text("Only iOS can start this. No app can press that button for you, including this one.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Text.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Explanation

    private var explanation: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "What actually happens")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    step(
                        number: 1,
                        title: "iOS captures the screen",
                        detail:
                            "The broadcast keeps running when you switch to WhatsApp or Slack. Nothing is sent anywhere while it just runs."
                    )
                    // "Half the size" is the measurement, not a hedge: the
                    // capture process uploads 602x1310 rather than the full
                    // 1206x2622, and `Bar/screen-context/` §"Size and format"
                    // scores both. It costs no accuracy and saves 74% of the
                    // bytes. Saying the size here is what stops this screen
                    // quoting a full-resolution bar for a half-resolution
                    // pipeline.
                    step(
                        number: 2,
                        title: "Tapping Reply sends one screenshot",
                        detail:
                            "The screen is read in the cloud, because on-device text recognition has no Hebrew and reads the rest less accurately. One picture goes out per tap, shrunk to half the screen's width and height, and nothing else does."
                    )
                    step(
                        number: 3,
                        title: "Only text reaches the keyboard",
                        detail:
                            "What comes back is the sender, the message and its language. The picture is never saved — not on disk, not in the shared container, not in a backup. That text is handed over in a file the keyboard deletes as soon as the broadcast it came from has stopped."
                    )

                    Divider().overlay(Theme.Surface.separator)

                    // All three steps are built now. What is still missing is a
                    // measurement, not code, and the honest thing is to say which
                    // it is rather than let a Reply tap fail with a reason it
                    // invented.
                    Text(
                        "All three steps are built, and none of them has run on a phone yet: a broadcast cannot start in the simulator, so no frame has ever reached the capture process here. Reply may not work on your device, and if it does not, the reason it gives you is the real one."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Text.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func step(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.Text.onBrand)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.Brand.gradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Text.primary)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Limits

    private var limits: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "What it will not do")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    limit(
                        "Run forever. Apple reserves permanent capture for remote-desktop apps, so every session is one you started, and iOS can end it for a phone call, the lock button or its own memory limit. This screen tells you it stopped. It cannot tell you which of those did it: iOS says only that the broadcast finished, and never why."
                    )
                    limit(
                        "Read anything by itself. A screenshot leaves the device only when you tap Reply, and never on a timer, a screen change or because the keyboard is open."
                    )
                    limit(
                        "Promise that protected content is hidden. Apps can exclude themselves from a recording and banking and video apps usually do, but we have not verified that on a device, so do not rely on it."
                    )
                    limit(
                        "Work in the background silently. iOS shows a recording indicator the entire time, and the keyboard shows a strip whenever it is up."
                    )
                }
            }
        }
    }

    private func limit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.xs) {
            Image(systemName: "minus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Text.tertiary)
                .frame(width: 14, height: 18)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Demo

    /// The scripted sample, labelled as one.
    ///
    /// It reads no screen and starts no broadcast — it plays a fixed
    /// conversation through the same strip and the same Reply panel, which is
    /// what the in-app playground and the UI walkthrough drive. A real session
    /// takes the screen back from it the moment one appears.
    private var demo: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Not sure yet?")

            Card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text(
                        "See it with a sample conversation. Nothing is captured, nothing is sent, and the message is one we wrote."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if session.source == .scripted {
                        SecondaryButton(title: "Stop the sample") {
                            session.stop()
                        }
                    } else if session.canPlaySample {
                        PrimaryButton(title: "Play a sample conversation", icon: "play.fill") {
                            store.screenContextAllowed = true
                            session.start()
                        }
                    } else {
                        // Words rather than a button that does nothing. The sample
                        // would have to paint a message nobody sent over a session
                        // that is watching the real screen, so it is refused — and
                        // the one thing the user can do about it is named.
                        Text(
                            "Not while screen context is running: the strip is showing your real screen, and a made-up message on top of it would be the one thing this feature must never do. Stop the broadcast from the red indicator in the status bar first."
                        )
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
