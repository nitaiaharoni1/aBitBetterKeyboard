import UIKit
import SwiftUI
import Combine
import AIKeyboardCore

/// Thin host. Everything visible lives in `AIKeyboardCore` so the companion app
/// can render the same keyboard during onboarding.
final class KeyboardViewController: UIInputViewController {

    private var controller: KeyboardController!
    /// Held here as well as by the controller. Belt and braces on the bug that
    /// made this keyboard type nothing on a real device for its whole life: the
    /// target used to be created inline in the call below and referenced only
    /// weakly on the other side, so it died between `viewDidLoad` and the first
    /// tap. See `KeyboardController.target`.
    private var textTarget: ProxyTextTarget!
    private var heightConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()
    /// Latched only once the shared container has actually taken the record, so a
    /// keyboard that starts without Full Access and is granted it mid-process
    /// still gets to leave one. See `recordPresence()`.
    private var hasRecordedPresence = false

    override func viewDidLoad() {
        super.viewDidLoad()

        let store = SharedStore.shared
        store.load()

        Feedback.hapticsEnabled = store.haptics
        // Key clicks need Full Access. Without it the call is a silent no-op, so
        // there is nothing to guard against here beyond the user's own setting.
        Feedback.soundEnabled = store.keySounds

        // Resolved per call, so a host swapping the focused field cannot leave us
        // typing into the old one. `weak` rather than `unowned`: `KeyView`'s
        // key-repeat task is cancelled from `DragGesture.onEnded`, so a gesture
        // interrupted by teardown can call back in after this controller has
        // gone, and against `unowned` that is a crash rather than a no-op.
        textTarget = ProxyTextTarget { [weak self] in self?.textDocumentProxy }

        controller = KeyboardController(
            target: textTarget,
            store: store,
            language: store.enabledLanguages.first ?? .english
        )
        controller.showsGlobeKey = needsInputModeSwitchKey
        controller.onAdvanceToNextKeyboard = { [weak self] in
            self?.advanceToNextInputMode()
        }
        // Only a `UIInputViewController` can put the keyboard away, and the
        // package does not have one. Without this the Hide keyboard key a user
        // added in the layout editor would draw, animate, click and do nothing —
        // which is exactly the shape of the defect that made this whole keyboard
        // type nothing on a device for the length of its development.
        controller.onDismissKeyboard = { [weak self] in
            self?.dismissKeyboard()
        }

        install(KeyboardView(controller: controller))

        // The context strip appears and disappears with the capture session, so
        // the height we ask the host app for has to follow it.
        controller.$screenContext
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateKeyboardHeight() }
            .store(in: &cancellables)

        // The layout is edited in the companion app, which is another process, so
        // the height changes without anything in here having asked for it.
        controller.$customization
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
        // **Re-read before measuring, and both before the keyboard is on screen.**
        // The layout is edited in the companion app, and iOS keeps this process
        // alive in the background, so the first appearance after an edit is the
        // one that has to be right. Reading it in `viewDidAppear` instead left
        // `updateKeyboardHeight()` measuring the *previous* layout: a keyboard
        // that had just gained a number row came up at the old height, clipped
        // the new row, and jumped taller a runloop turn later when the
        // `$customization` sink landed — that sink is `.receive(on: RunLoop.main)`
        // and so is never synchronous with this.
        controller?.reloadCustomization()
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
        recordPresence()
    }

    /// Leaves the containing app the one piece of evidence it can have that this
    /// keyboard is installed and has Full Access. See `KeyboardPresence`.
    ///
    /// From `viewDidAppear` rather than `viewDidLoad` for two reasons. It is the
    /// moment the keyboard is genuinely in use, which is what the record claims;
    /// and it is off the path between the keyboard being asked for and the keys
    /// being drawn, which the write must not join. The file I/O itself goes to a
    /// background queue for the same reason — `hasFullAccess` is UIKit state and
    /// is read here, on the main actor, before anything is dispatched.
    private func recordPresence() {
        guard !hasRecordedPresence else { return }
        let fullAccess = hasFullAccess
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let recorded = KeyboardPresence.record(hasFullAccess: fullAccess)
            Task { @MainActor [weak self] in self?.hasRecordedPresence = recorded }
        }
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
        // The layout, because a Roomy keyboard with both optional rows on covers
        // half again what the default does, and the band has to leave all of it
        // out. See `KeyboardGeometry.ownUIHeightFraction`.
        let layout = controller?.customization ?? .default
        guard let window = view.window else {
            return KeyboardGeometry.ownUIHeightFraction(
                screenHeight: KeyboardGeometry.referenceScreenHeight, layout: layout)
        }
        let screenHeight = window.screen.bounds.height
        let ourBottom = window.frame.minY + view.convert(view.bounds, to: window).maxY
        return KeyboardGeometry.ownUIHeightFraction(
            screenHeight: screenHeight, gapBelow: screenHeight - ourBottom, layout: layout)
    }

    /// **Both channels stop here, and the dictation one is not optional.**
    ///
    /// Screen context stops for the reason `viewDidAppear` gives: polling a page
    /// from a keyboard nobody can see costs battery to learn nothing. Dictation
    /// stops for a stronger reason. `DictationRequest.keyboardAliveAt` is a
    /// dead-man's switch — the recorder abandons an open utterance whose keyboard
    /// has stopped writing it — and a `RunLoop` timer left running in a keyboard
    /// the user has dismissed goes on refreshing it, which is the one thing that
    /// defeats it. The microphone would then stay open, in another process, on
    /// nobody's behalf, until the sixty-second cap. Leaving it to the extension
    /// being killed is not good enough: iOS keeps the process around after the
    /// keyboard goes away, and how long for is not ours to decide.
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ScreenContextSession.shared.stopConsuming()
        // Withdraws the utterance and stops the poll. A no-op unless dictation
        // was actually up; see `KeyboardController.stopDictation`.
        controller?.stopDictation(insert: false)
    }

    /// The host app decides how tall the keyboard is only if we tell it. The
    /// priority is below required so the constraint never fights the system
    /// during rotation.
    private func updateKeyboardHeight() {
        guard let controller else { return }
        // The banner is a constant row that is always counted, so the only thing
        // that moves this number now is the layout. See `Theme.Metrics.bannerHeight`
        // for why a strip that appears and disappears was worse than one that is
        // always there.
        let height = Theme.Metrics.totalHeight(for: controller.customization)

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

    /// Guarded for the same reason `updateKeyboardHeight()` is, and the two are
    /// written the same way on purpose: `controller` is assigned in `viewDidLoad`,
    /// and both of these are host-driven callbacks that iOS is free to deliver
    /// before it has run. A missed suggestion refresh is nothing; an implicitly
    /// unwrapped nil is a crash on the first keystroke.
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        guard let controller else { return }
        controller.refreshSuggestions()
    }
}
