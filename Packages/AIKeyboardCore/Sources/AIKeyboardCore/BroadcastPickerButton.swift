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
/// is likewise a plain `UIButton` with an image from ReplayKit's bundle added as
/// a subview. The class is `API_AVAILABLE(ios(12.0))` on `UIView` and no header in
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
/// session directly. A SwiftUI tap on the banner therefore cannot "open
/// screenshare" by calling anything — it can only host this view so the user's
/// tap lands on that system button. The overlay presentation stretches the
/// button across the message; the chip presentation leaves it as ReplayKit
/// draws it.
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
/// *both* appearances or the glyph vanishes in dark mode, which is why the chip
/// fills white first and puts the brand tint over it. The overlay hides the
/// glyph instead, because a record-dot on the banner reads as "already
/// recording" and the sentence underneath is the affordance.
public struct BroadcastPickerButton: View {

    /// The broadcast upload extension's bundle identifier, which is
    /// `PRODUCT_BUNDLE_IDENTIFIER` of the `AIKeyboardBroadcast` target. With it
    /// set, iOS shows our extension alone rather than every broadcast service
    /// installed on the phone.
    public static let extensionBundleID = "com.nitai.aikeyboard.broadcast"

    enum Presentation {
        /// Visible system glyph on a white-then-brand circle. `size` is the frame,
        /// and the pressable area is 10pt smaller: `addBroadcastPickerButton`
        /// insets its `UIButton` by 5 points on every edge.
        case chip(size: CGFloat)
        /// Invisible, fills the parent, inner button stretched to the bounds so a
        /// tap on the banner message is a tap on ReplayKit's button.
        case overlay(
            label: String, hint: String, identifier: String,
            onActivation: (@MainActor () -> Void)?)
    }

    private let presentation: Presentation

    /// **The size is the tap target, and not by much.** `addBroadcastPickerButton`
    /// insets its `UIButton` by 5 points on every edge, so the pressable area is
    /// this size minus 10 in each dimension; everything outside it is an inert
    /// `UIView`. A 26-point square would leave a 16-point target. Callers pass the
    /// largest square their layout allows.
    public init(size: CGFloat = 60) {
        self.presentation = .chip(size: size)
    }

    /// Hosts the system picker over a parent that already has a sentence, so the
    /// record glyph is not drawn and the inner button fills the parent.
    public static func overlay(
        label: String, hint: String, identifier: String,
        onActivation: (@MainActor () -> Void)? = nil
    ) -> BroadcastPickerButton {
        BroadcastPickerButton(
            presentation: .overlay(
                label: label, hint: hint, identifier: identifier, onActivation: onActivation))
    }

    private init(presentation: Presentation) {
        self.presentation = presentation
    }

    public var body: some View {
        switch presentation {
        case .chip(let size):
            BroadcastPickerUIView(presentation: presentation)
                .frame(width: size, height: size)
                // White first, brand tint over it: the system draws the glyph black.
                // Without the white underlay the glyph vanishes in dark mode over a
                // near-black surface.
                .background(
                    Circle()
                        .fill(Theme.Text.onBrand)
                        .overlay(Circle().fill(Theme.Brand.softGradient))
                )
        case .overlay:
            BroadcastPickerUIView(presentation: presentation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - UIKit wrapper

private struct BroadcastPickerUIView: UIViewRepresentable {
    let presentation: BroadcastPickerButton.Presentation

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker: RPSystemBroadcastPickerView
        switch presentation {
        case .chip(let size):
            picker = RPSystemBroadcastPickerView(
                frame: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
        case .overlay:
            let overlay = BroadcastPickerOverlayView(frame: .zero)
            overlay.hidesSystemGlyph = true
            overlay.onActivation = overlayActivation
            picker = overlay
        }
        configure(picker)
        applyAccessibility(to: picker)
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        if let overlay = picker as? BroadcastPickerOverlayView {
            overlay.onActivation = overlayActivation
        }
        applyAccessibility(to: picker)
        picker.setNeedsLayout()
    }

    @MainActor
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: RPSystemBroadcastPickerView, context: Context
    ) -> CGSize? {
        switch presentation {
        case .chip(let size):
            return CGSize(width: size, height: size)
        case .overlay:
            return CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
        }
    }

    private func configure(_ picker: RPSystemBroadcastPickerView) {
        picker.preferredExtension = BroadcastPickerButton.extensionBundleID
        // The capture path reads pixels and never audio: `SampleHandler` drops
        // `.audioApp` and `.audioMic` without looking at them.
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear
        // No `tintColor` here. See the type's note: the picker overwrites its
        // button's tint from `UIScreen.main.isCaptured`, so setting one would be a
        // line that reads as if it did something.
    }

    private var overlayActivation: (@MainActor () -> Void)? {
        if case .overlay(_, _, _, let onActivation) = presentation { return onActivation }
        return nil
    }

    private func applyAccessibility(to picker: RPSystemBroadcastPickerView) {
        guard case .overlay(let label, let hint, let identifier, _) = presentation else { return }
        picker.isAccessibilityElement = false
        for case let button as UIButton in picker.subviews {
            button.isAccessibilityElement = true
            button.accessibilityLabel = label
            button.accessibilityHint = hint
            button.accessibilityIdentifier = identifier
        }
    }
}

// MARK: - Overlay: one real button, the size of the sentence

/// `RPSystemBroadcastPickerView` with its system `UIButton` stretched to the
/// view's bounds and the record glyph hidden.
///
/// The class exists because a SwiftUI overlay of the stock picker does not make
/// the sentence tappable. `addBroadcastPickerButton` insets the real button 5pt
/// on every edge, so a picker laid out over the banner still has a 32pt chip of
/// hit area and a record-dot drawing. Stretching that button — not sending it
/// `sendActions`, which ReplayKit ignores from anyone but the user — is the
/// only way a tap on "Screen context is off" reaches `replayd`.
final class BroadcastPickerOverlayView: RPSystemBroadcastPickerView {

    var hidesSystemGlyph = false
    var onActivation: (@MainActor () -> Void)? {
        didSet { setNeedsLayout() }
    }

    override var intrinsicContentSize: CGSize { .zero }

    override func layoutSubviews() {
        super.layoutSubviews()
        stretchSystemButton()
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        stretchSystemButton()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard bounds.contains(point), isUserInteractionEnabled, !isHidden else {
            return super.hitTest(point, with: event)
        }
        return subviews.compactMap { $0 as? UIButton }.first
            ?? super.hitTest(point, with: event)
    }

    private func stretchSystemButton() {
        for case let button as UIButton in subviews {
            button.frame = bounds
            button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            button.backgroundColor = .clear
            // Remove then add: layoutSubviews runs often, and a second target
            // would fire the fallback twice. After the event, not during it —
            // growing the banner under a still-down finger misses the lift.
            // Skip the add when nobody is listening, so the banner overlay
            // does not put a no-op target on ReplayKit's button.
            button.removeTarget(
                self, action: #selector(handleBroadcastActivation), for: .touchUpInside)
            if onActivation != nil {
                button.addTarget(
                    self, action: #selector(handleBroadcastActivation), for: .touchUpInside)
            }
            guard hidesSystemGlyph else { continue }
            button.setImage(nil, for: .normal)
            button.setImage(nil, for: .highlighted)
            button.setImage(nil, for: .selected)
            for nested in button.subviews {
                nested.isHidden = true
                nested.isUserInteractionEnabled = false
            }
        }
    }

    @objc private func handleBroadcastActivation() {
        DispatchQueue.main.async { [onActivation] in
            onActivation?()
        }
    }
}
