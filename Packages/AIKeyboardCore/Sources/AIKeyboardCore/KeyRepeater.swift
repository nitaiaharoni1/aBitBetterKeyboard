import Foundation

// MARK: - Key repeat

/// The accelerating repeat behind a held delete key.
///
/// **Lifted out of `KeyView` because it is the most dangerous loop in the
/// product and a `@State` task inside a view body cannot be tested.** It was a
/// bare `Task` that ran `while !Task.isCancelled` with no bound and exactly one
/// cancellation site, `DragGesture.onEnded` — which SwiftUI does not call for a
/// *cancelled* touch. Until the typing fix that was inert, because
/// `KeyboardController.target` was `weak` and always nil on a device, so the loop
/// deleted from nothing. With a strong target and a proxy re-resolved per call,
/// the same loop deletes from whichever document is focused at that moment, 22
/// times a second, with a haptic each time, until iOS kills the extension.
///
/// Three things stop it, and none of them is enough alone. `KeyView` resets a
/// `@GestureState`, which fires on cancellation as well as on lift. `deinit`
/// cancels, so a discarded key cannot leave a task running — which is why `start`
/// copies its timings into locals rather than letting the task capture `self`; a
/// task holding the repeater alive would never let `deinit` run. And the loop
/// counts its own repeats: roughly nine seconds of continuous deletion, about two
/// hundred characters, which is longer than any message this keyboard is for.
/// A user who genuinely wants to delete more lifts and presses again, the way
/// every hardware key repeat that has ever shipped behaves after a timeout.
@MainActor
final class KeyRepeater {

    private var task: Task<Void, Never>?

    private let initialDelay: Duration
    private let firstInterval: Duration
    private let shortestInterval: Duration
    private let acceleration: Duration
    private let limit: Int

    /// Defaults are the shipping feel; the parameters exist so a test can run the
    /// whole loop, including its end, in a few milliseconds.
    init(
        initialDelay: Duration = .milliseconds(420),
        firstInterval: Duration = .milliseconds(110),
        shortestInterval: Duration = .milliseconds(45),
        acceleration: Duration = .milliseconds(8),
        limit: Int = 200
    ) {
        self.initialDelay = initialDelay
        self.firstInterval = firstInterval
        self.shortestInterval = shortestInterval
        self.acceleration = acceleration
        self.limit = limit
    }

    func start(_ tick: @escaping @MainActor () -> Void) {
        stop()
        // Copied out deliberately. A closure that reads `self.limit` captures the
        // repeater, the repeater then outlives the view that owned it, and the
        // `deinit` below never runs — which is the bug this type exists to close.
        let initialDelay = initialDelay
        let firstInterval = firstInterval
        let shortestInterval = shortestInterval
        let acceleration = acceleration
        let limit = limit

        task = Task { @MainActor in
            try? await Task.sleep(for: initialDelay)
            var interval = firstInterval
            var repeats = 0
            while !Task.isCancelled, repeats < limit {
                tick()
                repeats += 1
                try? await Task.sleep(for: interval)
                interval = max(shortestInterval, interval - acceleration)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
