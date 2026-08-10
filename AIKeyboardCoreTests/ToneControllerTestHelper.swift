import XCTest

@testable import AIKeyboardCore

/// Builds a `KeyboardController` wired to a single on-device intelligence engine
/// and no cloud fallback, suitable for tone-rewrite tests.
///
/// Shared by `DefaultToneTests` and `DefaultToneSettingsTests`.
@MainActor
func makeToneController(text: String, engine: some TextIntelligence) -> KeyboardController {
    KeyboardController(
        target: MockTextTarget(text: text),
        engine: RoutedIntelligence(onDevice: engine, cloud: nil)
    )
}

/// Spin-waits until `controller.isWorking` is false or the timeout elapses.
///
/// Shared by `DefaultToneTests`, `DefaultToneSettingsTests`, and `ToneAlternatesTests`.
@MainActor
func settleToneController(_ controller: KeyboardController, timeout: TimeInterval = 8) async {
    let deadline = Date().addingTimeInterval(timeout)
    while controller.isWorking, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
