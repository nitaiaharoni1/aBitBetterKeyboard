import SwiftUI
import UIKit

/// Wraps `UIPasteControl`, iOS 16's system paste button, for the one
/// generation `refreshCopyClip(_:)` left pending rather than read.
///
/// **This is the only route in the package that resolves pasteboard text
/// without calling `UIPasteboard.general.string`.** The control's own tap is
/// the user's consent; the text arrives through `paste(itemProviders:)` on
/// `PasteControlHost`, which iOS calls directly — nothing here ever names
/// `.string`, so there is no alert to raise. See `PasteboardReader` and
/// `KeyboardController.captureFromPasteControl(_:)`.
///
/// **Styling is what `UIPasteControlConfiguration` exposes and nothing
/// more.** It is a system button: no card fill, no press animation to match
/// the letter-key cards around it, and Apple supplies its own label text
/// ("Paste"), which cannot be replaced with CopyClip's own words. The four
/// properties below are tuned to `Theme`'s palette so it reads as this
/// product's orange rather than iOS blue, but it will never disappear into
/// the panel the way a `CopyClipCard` does — it is a system control sitting
/// in a custom list, and it looks like one.
struct CopyClipPasteControl: UIViewRepresentable {
    let onCapture: (String) -> Void

    func makeUIView(context: Context) -> PasteControlHost {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = Theme.Radius.key
        // `action`, not `solid`: this is a filled surface under
        // `Text.onBrand` white, which is the split `BrandPalette.Role`
        // exists to make. `solid` is 2.91:1 under white and is for tint,
        // icons and accent text on the app's own surfaces.
        configuration.baseBackgroundColor = UIColor(Theme.Brand.action)
        configuration.baseForegroundColor = UIColor(Theme.Text.onBrand)

        let host = PasteControlHost(onCapture: onCapture)
        let control = UIPasteControl(configuration: configuration)
        control.target = host
        control.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(control)
        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            control.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            control.topAnchor.constraint(equalTo: host.topAnchor),
            control.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        return host
    }

    func updateUIView(_ uiView: PasteControlHost, context: Context) {
        uiView.onCapture = onCapture
    }
}

/// The responder a `UIPasteControl` pastes into, and the control's `target`.
///
/// **A `UIPasteControl` whose target is not a `UIResponder` draws dimmed and
/// never fires, and the first version of this file shipped exactly that.**
/// `UIPasteControl.target` is typed `id<UIPasteConfigurationSupporting>`, so
/// a bare `NSObject` coordinator satisfies the compiler; Apple's own example
/// sets `pasteButton.target = textView` and adds the button as a *subview* of
/// that view, and both halves of that arrangement are reproduced here because
/// the failure mode is silent. The control asks its target whether it can
/// paste what is on the board before it enables itself, and
/// `canPasteItemProviders:` is an **optional** protocol requirement whose
/// only default implementation — the one that matches the board against
/// `pasteConfiguration` — lives on `UIResponder`. A target that is not one
/// answers nothing, and "nothing" is read as "cannot paste": the button is
/// drawn at reduced opacity, a tap does nothing, and CopyClip's *only* route
/// from a fresh copy into the ledger is dead while the panel says "Paste adds
/// it here. No prompt."
///
/// **The second half was a name.** The Swift spelling of
/// `canPasteItemProviders:` is `canPaste(_:)`, with no argument label. The
/// coordinator declared `canPaste(itemProviders:)`, which the compiler
/// reports as *nearly* matching the optional requirement and then exports
/// under a selector of its own — so even a target that had been a responder
/// would have had that method ignored. Overriding it here is belt and
/// braces: `UIResponder`'s default already answers from
/// `pasteConfiguration`, and this says the same thing in the one form the
/// panel actually needs, that a clip is text.
final class PasteControlHost: UIView {
    var onCapture: (String) -> Void

    init(onCapture: @escaping (String) -> Void) {
        self.onCapture = onCapture
        super.init(frame: .zero)
        // Set on the responder, not on the control: `UIPasteControl` has no
        // `pasteConfiguration` of its own and reads its target's.
        pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A copied image never satisfies `NSString`'s readable type
    /// identifiers, so the button goes quiet on its own for exactly the
    /// generation `PasteboardReader.holdsText` could not rule out at
    /// panel-open. Nothing here has to guess.
    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
    }

    /// **Delivered through item providers, never through
    /// `UIPasteboard.general.string`.** This is what makes the whole control
    /// alert-free: the text is handed to the app by iOS as the direct result
    /// of the tap, rather than fetched by the app calling a pasteboard
    /// accessor of its own.
    override func paste(itemProviders: [NSItemProvider]) {
        guard
            let provider = itemProviders.first(where: {
                $0.canLoadObject(ofClass: NSString.self)
            })
        else { return }
        provider.loadObject(ofClass: NSString.self) { [onCapture] reading, _ in
            guard let text = reading as? String else { return }
            DispatchQueue.main.async { onCapture(text) }
        }
    }
}
