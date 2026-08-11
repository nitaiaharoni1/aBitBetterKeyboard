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
            AmbientBackground()

            ScrollView {
                VStack(spacing: Theme.Space.md) {
                    ScreenContextHeroSection(session: session, isCapturing: isCapturing)
                    if session.source == .capture { ScreenContextLiveDetailCard(session: session) }
                    // Above `starter`, because a broadcast started without this
                    // set ends inside a second with `.notConfigured`. Putting the
                    // fix below the thing it blocks would be a screen that lets
                    // the user fail first.
                    backend
                    ScreenContextStarterSection(source: session.source)
                    ScreenContextDemoSection(session: session)
                    ScreenContextExplanationSection()
                    ScreenContextLimitsSection()
                    // Last, because it is for whoever is developing this rather
                    // than for whoever is using it — and on a device with no Mac
                    // attached it is the only way to find out whether ReplayKit
                    // delivers anything at all. See `CaptureDiagnosticsView`.
                    CaptureDiagnosticsView(session: session)
                }
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xl)
                .animation(Theme.Motion.quick, value: session.source)
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
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    CloudModelRow()
                }
            }
        }
    }

    // MARK: Capturing state

    /// Nothing on this screen goes red for the sample conversation. A recording
    /// colour over a session that is not capturing anything is the same lie as a
    /// red dot on the strip, and this is the screen that has to be checkable
    /// against what the user observes.
    private var isCapturing: Bool { session.source == .capture && session.isLive }
}
