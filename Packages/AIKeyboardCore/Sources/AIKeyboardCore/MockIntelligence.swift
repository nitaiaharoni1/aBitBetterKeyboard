import Foundation

// MARK: - Screen context
//
// Stands in for the ReplayKit broadcast session that runs in the main app and
// hands OCR'd text to the keyboard through the App Group. Nothing here captures
// anything; these are the messages a session would have read off the screen.
// (Capture API depends on deployment target: ReplayKit on iOS <=26, reportedly
// ScreenCaptureKit on iOS 27+. See ScreenContextSession.swift.)

public enum MockScreenContext {

    private static let samples: [ScreenContext] = [
        ScreenContext(
            appName: "WhatsApp",
            appIcon: "message.fill",
            sender: "שרה",
            message: "היי, אתה פנוי לארוחת ערב הערב? חשבתי על המקום החדש ביפו",
            language: .hebrew
        ),
        ScreenContext(
            appName: "Slack",
            appIcon: "number",
            sender: "Daniel",
            message: "Can you take the standup tomorrow? I have a conflict at 9.",
            language: .english
        ),
        ScreenContext(
            appName: "Messages",
            appIcon: "bubble.left.fill",
            sender: "Maya",
            message: "שלחתי לך את ה-deck, אפשר feedback עד מחר בצהריים?",
            language: .hebrew
        )
    ]

    public static func sample(at index: Int) -> ScreenContext {
        samples[index % samples.count]
    }

    public static var sampleCount: Int { samples.count }

    /// How long the picker plus stream start-up takes before frames arrive.
    public static let startupDelay: Duration = .milliseconds(900)
    /// How long the session watches before it reads something repliable.
    public static let firstReadDelay: Duration = .milliseconds(1400)
}
