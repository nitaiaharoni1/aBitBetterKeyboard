import ReplayKit
import SwiftUI

/// Apple's own button for starting a screen broadcast, and the reason it is in
/// this package rather than only in the app.
///
/// **It is the one system affordance a keyboard extension can host, and the
/// disassembly says why.** The standing constraint on this keyboard is that it
/// has no `UIApplication`: it cannot `openURL`, cannot open Settings, cannot
/// launch the containing app, and the responder-chain workaround is disallowed.
/// The obvious reading is that starting a broadcast belongs in the same bucket.
/// It does not, and the difference is structural rather than a loophole. Read out
/// of `ReplayKit` in the iOS 26.2 simulator runtime on 2026-08-09,
/// `-[RPSystemBroadcastPickerView buttonPressed:]` does exactly two things:
///
///     [[RPDaemonProxy daemonProxy] setBroadcastPickerPreferredExt:showsMicButton:]
///     [[RPDaemonProxy daemonProxy] openControlCenterSystemRecordingView]
///
/// Two XPC calls to `replayd`, asking *Control Center* to present its own
/// recording view. No `UIApplication`, no view controller presented into our own
/// hierarchy, no window scene, nothing that a process without an application
/// object can be missing. `-[RPSystemBroadcastPickerView addBroadcastPickerButton]`
/// is likewise a plain `UIButton` with an image from ReplayKit's bundle added as a
/// subview. The class is `API_AVAILABLE(ios(12.0))` on `UIView` and no header in
/// `ReplayKit.framework` carries an `NS_EXTENSION_UNAVAILABLE` annotation of any
/// kind.
///
/// **What that argument does not establish, and nothing here can:** whether
/// `replayd` accepts the request from a keyboard extension's process, and whether
/// Control Center's sheet actually appears over a keyboard. Both are device
/// questions and both are unmeasured — the simulator runtime ships no `replayd`,
/// so the button renders and nothing happens, here and in the app equally. The
/// UI around this therefore never claims a broadcast will start; it says what
/// pressing it asks for, and every caller keeps the words that send the user to
/// the app if nothing happens.
///
/// It is also the *only* supported way in: the button inside the picker is
/// system-vended, so no app can press it, and there is no API that starts a
/// session directly.
///
/// **The glyph's colour belongs to the system, and every call site has to design
/// around it rather than set it.** `-[RPSystemBroadcastPickerView
/// screenCaptureChanged]` runs at construction and again on every capture-state
/// change; it dispatches to the main queue and assigns the inner button's
/// `tintColor` from `UIScreen.main.isCaptured` — **black normally, red while the
/// screen is being captured**. Because the button's own tint is assigned
/// explicitly it never inherits, so a tint set on the picker view is ignored.
/// That behaviour is worth keeping: it is the system telling the truth about
/// recording. What it costs is that the background underneath has to be light in
/// *both* appearances or the glyph vanishes in dark mode, which is why each call
/// site fills white first and puts the brand tint over it.
public struct BroadcastPickerButton: UIViewRepresentable {

    /// The broadcast upload extension's bundle identifier, which is
    /// `PRODUCT_BUNDLE_IDENTIFIER` of the `AIKeyboardBroadcast` target. With it
    /// set, iOS shows our extension alone rather than every broadcast service
    /// installed on the phone.
    public static let extensionBundleID = "com.nitai.aikeyboard.broadcast"

    /// **The size is the tap target, and not by much.** `addBroadcastPickerButton`
    /// insets its `UIButton` by 5 points on every edge, so the pressable area is
    /// this size minus 10 in each dimension; everything outside it is an inert
    /// `UIView`. A 26-point square would leave a 16-point target. Callers pass the
    /// largest rectangle their layout allows.
    private let size: CGSize

    public init(width: CGFloat = 60, height: CGFloat = 60) {
        self.size = CGSize(width: width, height: height)
    }

    public func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(origin: .zero, size: size))
        picker.preferredExtension = Self.extensionBundleID
        // The capture path reads pixels and never audio: `SampleHandler` drops
        // `.audioApp` and `.audioMic` without looking at them.
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear
        // No `tintColor` here. See the type's note: the picker overwrites its
        // button's tint from `UIScreen.main.isCaptured`, so setting one would be a
        // line that reads as if it did something.
        return picker
    }

    public func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {}

    @MainActor
    public func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: RPSystemBroadcastPickerView, context: Context
    ) -> CGSize? {
        size
    }
}
