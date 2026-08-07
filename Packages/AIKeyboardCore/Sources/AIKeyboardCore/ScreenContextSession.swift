import Foundation
import Combine

/// The screen capture session, faked.
///
/// In the real product this wraps `SCStream`: the main app puts up Apple's
/// `SCContentSharingPicker`, starts a full-display capture, declares the
/// `screen-capture` background mode so frames keep arriving after the user
/// switches to WhatsApp, runs OCR on each frame, and writes only the resulting
/// text into the App Group container for the keyboard to read.
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

    private init() {}

    public var isLive: Bool { state.isLive }

    /// Mirrors the real flow: picker and stream start-up, then frames arriving,
    /// then the first frame that actually contains something worth replying to.
    public func start() {
        guard !state.isLive else { return }
        Feedback.actionPress()
        startedAt = Date()
        framesRead = 0
        state = .starting

        task?.cancel()
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
