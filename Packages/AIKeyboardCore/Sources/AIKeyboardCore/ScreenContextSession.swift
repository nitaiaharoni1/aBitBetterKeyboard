import Combine
import CoreGraphics
import Foundation

/// The screen capture session, faked.
///
/// In the real product this wraps a **ReplayKit broadcast upload extension**: the
/// main app presents `RPSystemBroadcastPickerView`, the user starts a broadcast,
/// and `RPBroadcastSampleHandler` receives frames system-wide — including while
/// the user is in WhatsApp. The handler runs Vision OCR on each frame and writes
/// only the resulting text into the App Group container for the keyboard to read.
///
/// Which API to use is a deployment-target decision, not a preference, and on
/// this machine it is not yet a live choice. Measured 2026-08-08 against the
/// installed toolchain (Xcode 26.2, build 17C52):
///
/// | SDK | `ScreenCaptureKit.framework` |
/// |---|---|
/// | `iPhoneOS26.2.sdk` | absent |
/// | `iPhoneSimulator26.2.sdk` | absent |
/// | `MacOSX26.2.sdk` | present |
///
/// `ReplayKit.framework` is present in the iOS SDK, which is the control that
/// makes the absence meaningful. So `import ScreenCaptureKit` does not compile
/// for iOS here at all: the path below needs an Xcode carrying the iOS 27 SDK
/// before a line of it can be written, let alone verified.
///
/// **iOS 27+ — `SCContentSharingPicker` + `SCStream`.** ScreenCaptureKit is
/// `iOS 27.0+ Beta` / `iPadOS 27.0+ Beta`. Apple's framework page states plainly:
/// *"ScreenCaptureKit replaces ReplayKit for screen streaming and mirroring. A
/// broadcast extension is no longer necessary."* The picker is the recommended
/// way to let the user choose a source, and the user can pick an entire display.
/// Apple's "Capturing screen content on iOS" sample declares two background modes
/// *"so ScreenCaptureKit continues to run while the app isn't frontmost"* —
/// `screen-capture` (*"so the stream survives backgrounding for full-display
/// capture"*) and `audio`. Also needs `NSScreenCaptureUsageDescription`.
///
/// This is a materially better fit than ReplayKit for this product: no broadcast
/// extension, frames arrive in the app, and the stream survives the user
/// switching to WhatsApp — which is the entire feature.
///
/// **iOS ≤ 26 — ReplayKit.** ScreenCaptureKit is genuinely absent from the iOS
/// 26.2 SDK (measured, device and simulator). Keep this path for as long as the
/// deployment target reaches back that far.
///
/// One inconsistency to be aware of before shipping: the `UIBackgroundModes`
/// reference page does **not** list `screen-capture` among its possible values,
/// while the ScreenCaptureKit sample tells you to use it. Beta docs disagreeing
/// with each other is normal, but validation tooling sometimes follows the older
/// list, so verify an App Store Connect upload accepts it rather than assuming.
///
/// Three constraints from that design are modelled here rather than glossed over,
/// because they shape the UI:
///
/// 1. The user starts a session explicitly. Apple's persistent capture
///    entitlement is meant for remote-desktop apps, so "allow once, works
///    forever" is not something to build on.
/// 2. A session ends. It has to be restartable from the keyboard as well as the
///    app, or the feature dies the first time iOS tears the stream down.
/// 3. Capture is visible while it runs. Apple requires a clear indication, and
///    the product is better for it anyway.
@MainActor
public final class ScreenContextSession: ObservableObject {

    public static let shared = ScreenContextSession()

    @Published public private(set) var state: ScreenContextState = .off

    /// Frames seen this session. Shown in the app as proof that nothing is kept:
    /// the count goes up while the stored frame count stays at one.
    @Published public private(set) var framesRead = 0

    /// When the session started, for the running-time label.
    @Published public private(set) var startedAt: Date?

    private var sampleIndex = 0
    private var task: Task<Void, Never>?

    /// Reads frames once a capture backend is attached. Nil leaves the session
    /// on the scripted timeline below, which is what the in-app playground and
    /// the UI tests drive.
    public var reader: (any ScreenReader)?

    private init() {}

    public var isLive: Bool { state.isLive }

    // MARK: - Real frames

    /// Hands one captured frame to the reader.
    ///
    /// Deliberately takes a `CGImage` and nothing else: this is the seam the
    /// capture API plugs into, and which API delivered the pixels — ReplayKit
    /// today, ScreenCaptureKit once the deployment target allows it — changes
    /// nothing above this line. The frame is read and dropped; only the text
    /// survives the call, which is the promise the Screen Context screen makes.
    public func submit(_ frame: CGImage, appName: String, appIcon: String) async {
        guard let reader, state.isLive else { return }
        framesRead += 1

        do {
            let output = try await reader.read(frame)
            guard let reading = output.value else {
                // A screen with nothing to reply to is a real answer. The strip
                // goes back to watching rather than offering a stale reply.
                if state.context != nil { state = .watching }
                return
            }
            state = .ready(
                ScreenContext(
                    appName: appName,
                    appIcon: appIcon,
                    sender: reading.sender,
                    message: reading.message,
                    language: reading.language))
        } catch {
            // A frame that could not be read is not worth telling the user
            // about: another one arrives in a moment. Only a session that never
            // reads anything is worth surfacing, and that shows as `.watching`.
            state = state.context == nil ? .watching : state
        }
    }

    /// Mirrors the real flow: picker and stream start-up, then frames arriving,
    /// then the first frame that actually contains something worth replying to.
    ///
    /// Still scripted. Reading a frame is real and measured — see
    /// `RoutedScreenReader` and `submit(_:appName:appIcon:)` — but *getting* one
    /// is not implemented, because neither capture API is available to this
    /// build. ScreenCaptureKit is `iOS 27.0+` and absent from the iOS 26.2 SDK
    /// this project compiles against; ReplayKit is present but needs a broadcast
    /// upload extension target that does not exist yet.
    public func start() {
        guard !state.isLive else { return }
        Feedback.actionPress()
        startedAt = Date()
        framesRead = 0
        state = .starting

        task?.cancel()
        task = nil

        // A capture backend is attached, so frames arrive through
        // `submit(_:appName:appIcon:)` and the session waits for them. Running
        // the scripted timeline alongside a real reader would drop the sample
        // context on top of a real reading two seconds in, which is exactly what
        // `ScreenContextBarTests` drives.
        guard reader == nil else {
            state = .watching
            return
        }

        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: MockScreenContext.startupDelay)
            guard !Task.isCancelled, let self else { return }
            state = .watching

            try? await Task.sleep(for: MockScreenContext.firstReadDelay)
            guard !Task.isCancelled else { return }
            framesRead = 34
            state = .ready(MockScreenContext.sample(at: sampleIndex))

            // Keep the frame counter moving so the session reads as live.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                framesRead += 30
            }
        }
    }

    public func stop() {
        Feedback.modifierPress()
        task?.cancel()
        task = nil
        state = .off
        startedAt = nil
        framesRead = 0
    }

    /// Stands in for the user moving to a different conversation.
    public func advanceToNextSample() {
        guard state.isLive else { return }
        sampleIndex += 1
        state = .ready(MockScreenContext.sample(at: sampleIndex))
    }
}
