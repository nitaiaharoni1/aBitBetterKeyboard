import UIKit
import SwiftUI
import Combine
import AIKeyboardCore

/// Thin host. Everything visible lives in `AIKeyboardCore` so the companion app
/// can render the same keyboard during onboarding.
final class KeyboardViewController: UIInputViewController {

    private var controller: KeyboardController!
    private var heightConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()

        let store = SharedStore.shared
        store.load()

        Feedback.hapticsEnabled = store.haptics
        // Key clicks need Full Access. Without it the call is a silent no-op, so
        // there is nothing to guard against here beyond the user's own setting.
        Feedback.soundEnabled = store.keySounds

        controller = KeyboardController(
            target: ProxyTextTarget(textDocumentProxy),
            store: store,
            language: store.enabledLanguages.first ?? .english
        )
        controller.showsGlobeKey = needsInputModeSwitchKey
        controller.onAdvanceToNextKeyboard = { [weak self] in
            self?.advanceToNextInputMode()
        }

        install(KeyboardView(controller: controller))

        // The context strip appears and disappears with the capture session, so
        // the height we ask the host app for has to follow it.
        controller.$screenContext
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateKeyboardHeight() }
            .store(in: &cancellables)

        // Names and text replacements the user already has, so `SuggestionEngine`
        // can offer "Nitai" without waiting for it to appear in a sentence
        // first. "Will not provide a complete repository of a language's
        // vocabulary" per Apple's own doc comment on this method — it is a
        // supplement, not a dictionary, and on the Simulator it answers empty.
        requestSupplementaryLexicon { [weak self] lexicon in
            let words = lexicon.entries.map(\.documentText)
            Task { @MainActor [weak self] in
                self?.controller.updateSupplementaryLexicon(words)
            }
        }
    }

    private func install<Content: View>(_ root: Content) {
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateKeyboardHeight()
    }

    /// The keyboard is the consuming end of the capture channel, and it only
    /// consumes while it is on screen: polling a shared page from a keyboard the
    /// user cannot see would cost battery to learn something nobody is looking
    /// at, and `intent.keyboardVisible` would be a lie.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        ScreenContextSession.shared.startConsuming(
            .shared, as: .keyboard, ownUIHeightFraction: ownUIHeightFraction())
    }

    /// A rotation changes the screen height, so it changes the fraction of the
    /// screen we cover, so it changes where the capture process cuts the band it
    /// fingerprints. Republishing it is not cosmetic: the freshness gate's only
    /// content condition is exact equality of the frame identity, so a band that
    /// moves between the frame a reading was taken from and the frame it is
    /// confirmed against retires that reading exactly as a real conversation
    /// switch would. Rotate the phone while a read is in flight and the answer the
    /// user is waiting for is silently thrown away.
    ///
    /// `viewWillTransition` rather than `traitCollectionDidChange`, because the
    /// size is what matters and the traits do not always move with it — an iPad
    /// keyboard resizing inside a split view changes neither trait. Published
    /// after the transition rather than before it, so the height describes where
    /// we actually ended up.
    override func viewWillTransition(
        to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            ScreenContextSession.shared.updateOwnUIHeightFraction(ownUIHeightFraction())
        }
    }

    /// How much of the screen we are covering, for the capture process to leave
    /// out of the frame fingerprint. See `KeyboardGeometry`.
    ///
    /// The height itself comes from `Theme.Metrics`, because that is what this
    /// class asks the host for and it is a constant. The one thing only the
    /// runtime knows is the gap underneath us — the strip where the system draws
    /// the home indicator over the keyboard — so that is measured and everything
    /// else is not.
    private func ownUIHeightFraction() -> Double {
        guard let window = view.window else {
            return KeyboardGeometry.ownUIHeightFraction(
                screenHeight: KeyboardGeometry.referenceScreenHeight)
        }
        let screenHeight = window.screen.bounds.height
        let ourBottom = window.frame.minY + view.convert(view.bounds, to: window).maxY
        return KeyboardGeometry.ownUIHeightFraction(
            screenHeight: screenHeight, gapBelow: screenHeight - ourBottom)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ScreenContextSession.shared.stopConsuming()
    }

    /// The host app decides how tall the keyboard is only if we tell it. The
    /// priority is below required so the constraint never fights the system
    /// during rotation.
    private func updateKeyboardHeight() {
        guard controller != nil else { return }
        let height = Theme.Metrics.totalHeight(withContextStrip: controller.showsScreenContextStrip)

        guard let heightConstraint else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            self.heightConstraint = constraint
            return
        }
        guard heightConstraint.constant != height else { return }
        heightConstraint.constant = height
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        controller.refreshSuggestions()
    }
}
