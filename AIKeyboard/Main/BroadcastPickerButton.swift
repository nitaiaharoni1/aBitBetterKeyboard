import ReplayKit
import SwiftUI

/// Apple's own button for starting a screen broadcast.
///
/// `RPSystemBroadcastPickerView` is present and **not** deprecated in
/// `iPhoneOS26.2.sdk` (`API_AVAILABLE(ios(12.0))`, `RPBroadcast.h:177-186`), and
/// both properties set below are declared there. It is also the *only* supported
/// way to start a broadcast: the button inside it is system-vended, so no app can
/// press it, and there is no API that starts a session directly. Everything the
/// UI can do is put the button where the user will find it and say what happens
/// when they press it.
///
/// **Nothing here can be verified on this machine.** The iOS 26.2 simulator
/// runtime ships no `replayd`, so the view renders and the button does nothing.
/// Whether the picker lists `AIKeyboardBroadcast`, and what the session does
/// afterwards, is a device measurement.
struct BroadcastPickerButton: UIViewRepresentable {

    /// The broadcast upload extension's bundle identifier, which is
    /// `PRODUCT_BUNDLE_IDENTIFIER` of the `AIKeyboardBroadcast` target. With it
    /// set, iOS shows our extension alone rather than every broadcast service
    /// installed on the phone.
    static let extensionBundleID = "com.nitai.aikeyboard.broadcast"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = Self.extensionBundleID
        // The capture path reads pixels and never audio: `SampleHandler` drops
        // `.audioApp` and `.audioMic` without looking at them.
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {}

    @MainActor
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: RPSystemBroadcastPickerView, context: Context
    ) -> CGSize? {
        CGSize(width: 60, height: 60)
    }
}
