import SwiftUI
import UIKit

/// Wraps `UIPasteControl`, iOS 16's system paste button, for the one
/// generation `refreshCopyClip(_:)` left pending rather than read.
///
/// **This is the only route in the package that resolves pasteboard text
/// without calling `UIPasteboard.general.string`.** The control's own tap is
/// the user's consent; the text arrives through `paste(itemProviders:)` on
/// `Coordinator`, which iOS calls directly — nothing here ever names
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

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = Theme.Radius.key
        configuration.baseBackgroundColor = UIColor(Theme.Brand.solid)
        configuration.baseForegroundColor = UIColor(Theme.Text.onBrand)
        let control = UIPasteControl(configuration: configuration)
        control.target = context.coordinator
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onCapture = onCapture
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    /// **Owns `pasteConfiguration`, not the control.** `UIPasteControl` has
    /// no such property of its own (see the header): it reads its target's,
    /// which is also how it knows to enable or hide itself — a copied image
    /// never satisfies `NSString`'s own registered type identifiers, so the
    /// button goes quiet on its own for exactly the generation
    /// `PasteboardReader.holdsText` could not rule out at panel-open. Nothing
    /// here has to guess.
    final class Coordinator: NSObject, UIPasteConfigurationSupporting {
        var onCapture: (String) -> Void
        var pasteConfiguration: UIPasteConfiguration?

        init(onCapture: @escaping (String) -> Void) {
            self.onCapture = onCapture
            super.init()
            let configuration = UIPasteConfiguration()
            configuration.addAcceptableTypeIdentifiers(
                NSString.readableTypeIdentifiersForItemProvider)
            self.pasteConfiguration = configuration
        }

        func canPaste(itemProviders: [NSItemProvider]) -> Bool {
            itemProviders.contains { $0.canLoadObject(ofClass: NSString.self) }
        }

        /// **Delivered through item providers, never through
        /// `UIPasteboard.general.string`.** This is what makes the whole
        /// control alert-free: the text is handed to the app by iOS as the
        /// direct result of the tap, rather than fetched by the app calling
        /// a pasteboard accessor of its own.
        func paste(itemProviders: [NSItemProvider]) {
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
}
