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
        ScreenContextChannel.shared.startWatching()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ScreenContextChannel.shared.stopWatching()
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
