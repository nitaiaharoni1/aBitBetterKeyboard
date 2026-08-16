import UIKit
import SwiftUI
import Combine
import os
import AIKeyboardCore

/// Thin host. Everything visible lives in `AIKeyboardCore` so the companion app
/// can render the same keyboard during onboarding.
final class KeyboardViewController: UIInputViewController {

    private let handoffLogger = Logger(subsystem: "com.nitai.aikeyboard", category: "handoff")

    private var controller: KeyboardController!
    /// Held here as well as by the controller. Belt and braces on the bug that
    /// made this keyboard type nothing on a real device for its whole life: the
    /// target used to be created inline in the call below and referenced only
    /// weakly on the other side, so it died between `viewDidLoad` and the first
    /// tap. See `KeyboardController.target`.
    private var textTarget: ProxyTextTarget!
    private var heightConstraint: NSLayoutConstraint?
    private var cancellables = Set<AnyCancellable>()
    /// Last banner presence we sized the host for. `objectWillChange` fires on
    /// every keystroke; this is what keeps those from touching the constraint.
    private var lastShowsActionBanner: Bool?
    /// Latched only once the shared container has actually taken the record, so a
    /// keyboard that starts without Full Access and is granted it mid-process
    /// still gets to leave one. See `recordPresence()`.
    private var hasRecordedPresence = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // `store.load()` is what puts the palette into `Theme` at launch, through
        // `brandPalette`'s `didSet` — so there is deliberately no
        // `applyBrandPalette()` here. It is `viewWillAppear` that needs it, for
        // the instance iOS kept alive across a change made in the app.
        let store = SharedStore.shared
        store.load()

        // Resolved per call, so a host swapping the focused field cannot leave us
        // typing into the old one. `weak` rather than `unowned`: `KeyView`'s
        // key-repeat task is cancelled from `DragGesture.onEnded`, so a gesture
        // interrupted by teardown can call back in after this controller has
        // gone, and against `unowned` that is a crash rather than a no-op.
        textTarget = ProxyTextTarget { [weak self] in self?.textDocumentProxy }

        controller = KeyboardController(
            target: textTarget,
            store: store,
            language: store.enabledLanguages.first ?? .english,
            // **The one caller that says this is the real keyboard**, and the two
            // things it turns on are both things only a real keyboard should do:
            // ask a model for a better suggestion on a typing pause, and remember
            // the words the person typed. The app's playground and all 57 test
            // constructions leave it off, so neither spends a model call on a
            // screenshot run nor writes scripted demo words into somebody's
            // vocabulary — which the test suite did, teaching the store `Handi` ten
            // times before `KeyboardController.personal` existed.
            isSystemKeyboard: true
        )
        controller.showsGlobeKey = needsInputModeSwitchKey
        // Construction uses the in-app default (no iOS handoff key). Reapply
        // after this real host supplies the device's answer.
        controller.reloadCustomization()
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
        // `UIApplication` is unavailable in extensions, so the package cannot
        // open a URL itself. The host handles it here with two best-effort
        // paths; see `openContainingApp(_:)` for the caveats on each.
        controller.onOpenContainingApp = { [weak self] url in
            self?.openContainingApp(url)
        }

        // Inject a custom URL opener so `Link` elements inside the keyboard
        // (e.g. the "Open aBitBetterKeyboard" chip) route through `openContainingApp`
        // rather than through SwiftUI's default, which silently fails inside an
        // extension because `UIApplication.shared` is unavailable there.
        install(
            KeyboardView(controller: controller)
                .environment(
                    \.openURL,
                    OpenURLAction { [weak self] url in
                        self?.openContainingApp(url)
                        return .handled
                    })
        )

        // The action banner appears for a live reading, a refusal or a failure,
        // so the height we ask the host for has to follow it. A model call and a
        // recording do not: they report on the control, so the host height stays
        // at the banner-off total. `objectWillChange` fires before the property
        // lands; defer one turn so the read sees the new state. Presence is
        // compared only after that turn: every keystroke and every loudness tick
        // publishes, and the constraint must not move unless the strip actually
        // appeared.
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, let controller = self.controller else { return }
                    let shows = controller.showsActionBanner
                    guard shows != self.lastShowsActionBanner else { return }
                    self.lastShowsActionBanner = shows
                    self.updateKeyboardHeight()
                }
            }
            .store(in: &cancellables)

        // The layout is edited in the companion app, which is another process, so
        // the height changes without anything in here having asked for it.
        controller.$customization
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateKeyboardHeight()
            }
            .store(in: &cancellables)

        // The value in the sink is the new host language. `@Published` emits from
        // `willSet`, so reading `controller.hostLanguage` here would still be the
        // old one. Dictation and Reply write this without moving the keys.
        // Synchronous on purpose: `.receive(on: RunLoop.main)` defers even when
        // we are already on main, and the insert would land in a field that still
        // thought it was English.
        controller.$hostLanguage
            .sink { [weak self] language in self?.publishInputLanguage(language) }
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

    /// Puts the user's accent into `Theme` for this process, and repaints if it
    /// moved.
    ///
    /// **Read through `storedBrandPalette`, not the `@Published` copy**, for the
    /// reason that accessor documents: the palette is written in the app and
    /// every key it recolours is drawn here, and `load()` fills the published
    /// copy once per process launch.
    ///
    /// The nudge is the extension's half of the invalidation the app does with
    /// `.id(store.brandPalette)`. `KeyboardView` observes the controller and
    /// nothing else, so a global that changed while this keyboard sat in the
    /// background would otherwise not reach the keys until something unrelated
    /// published. Guarded on an actual change, because `viewWillAppear` runs
    /// every time the keyboard comes up and a rebuild of every key is not free.
    private func applyBrandPalette() {
        let palette = SharedStore.shared.storedBrandPalette
        guard palette != Theme.palette else { return }
        Theme.palette = palette
        controller?.objectWillChange.send()
    }

    private func install<Content: View>(_ root: Content) {
        let host = UIHostingController(rootView: root)
        // SwiftUI was applying the home-indicator safe area inside a view
        // whose height already is the keyboard, which left an empty band
        // under the space row.
        host.safeAreaRegions = []
        host.view.insetsLayoutMarginsFromSafeArea = false
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        // Letter callouts still grow up through the suggestion bar, the way
        // a system key preview does. The default clip cuts them off at the
        // keyboard's top edge. Fix and Rewrite stacks grow down over the
        // letters and do not need this, but sharing the flag keeps one rule.
        view.clipsToBounds = false
        host.view.clipsToBounds = false

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
        // **Re-read the suite before measuring, and both before the keyboard is
        // on screen.** Settings live in the companion app; iOS keeps this process
        // alive in the background. The space bar and Return already read
        // UserDefaults through `stored*`; `load()` is what puts a language list
        // or an auto-capitalise toggle the user just flipped into the published
        // copies the rest of the chrome draws from — and what
        // `reloadCustomization` below then draws. Reading only the layout left
        // those two on the launch-time copy.
        SharedStore.shared.load()
        // Forget lives in the app. This process stays alive, so without a
        // re-read the bar would keep ranking words the user just wiped.
        PersonalLanguageModel.shared.reload()
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
        controller?.refreshCopyClip()
        // Re-read for exactly the reason above: the picker is in the companion
        // app, iOS keeps this process alive in the background, and the first
        // appearance after the user changed palette is the one that has to be
        // right. `viewDidLoad` alone would leave a live instance drawing the old
        // accent for as long as iOS chose to keep it.
        applyBrandPalette()
        // **The field this keyboard is coming up over, not the one it last saw.**
        // iOS keeps one extension instance alive across fields and across host
        // apps, so Fix and Rewrite — which are drawn disabled on an empty field —
        // would otherwise open showing whatever the previous field's state was
        // until something else moved. `refreshDocumentState()` rather than
        // `refreshSuggestions()`: the full refresh starts `PredictiveRefiner`'s
        // clock, and paying for a model call every time the keyboard appears, for
        // a word nobody has started typing, is not what this line is for.
        controller?.refreshDocumentState()
        // Empty field: follow the keys, so Notes does not inherit Hebrew from
        // a WhatsApp reply. Field that already has Hebrew: keep telling the
        // host that — resetting here flipped an in-progress draft LTR.
        controller?.prepareForNewDocument()
        // The Recent emoji order is frozen while the grid is open so it cannot
        // re-sort under the thumb that is picking from it, and nothing resets
        // `overlay` on the way out — so an instance iOS kept alive comes back
        // with the grid still open and yesterday's order in it. Arriving on
        // screen is a fresh visit, which is the moment that freeze is allowed to
        // lift. See `KeyboardController.visibleRecentEmoji`.
        controller?.settleRecentEmoji()
        publishInputLanguage()
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
    /// user is waiting for is silently thrown away. The host height constraint
    /// republishes here too, unconditionally: unlike the fingerprint crop it has
    /// no reading in flight to protect, and a landscape keyboard left standing in
    /// a portrait-tall reservation is a visible gap under the keys, not a subtle
    /// one.
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
            // The host height follows rotation immediately: the device has
            // physically turned, and `KeyboardView`'s own `verticalSizeClass`
            // read already redrew the grid at the new orientation's height, so
            // the constraint has to catch up or a landscape keyboard sits inside
            // a portrait-sized reservation.
            self.updateKeyboardHeight()
            // A band that moves while Reply is waiting for a frame retires that
            // reading as a conversation switch. Hold the crop until the read
            // lands; the next appearance or the next rotation after that
            // republishes the real height.
            guard !ScreenContextSession.shared.isAwaitingRead else { return }
            ScreenContextSession.shared.updateOwnUIHeightFraction(self.ownUIHeightFraction())
        }
    }

    /// Portrait or landscape, read from the window rather than
    /// `UIScreen.bounds`: `UIScreen.bounds` is documented to stay fixed across
    /// rotation on iOS, while the window's own bounds are exactly what UIKit lays
    /// autolayout out against, so they are the one source that is guaranteed to
    /// track the device's actual current orientation. No window (not yet in a
    /// hierarchy) falls back to portrait, matching `ownUIHeightFraction()`'s own
    /// fallback.
    private var currentOrientation: KeyboardGeometry.Orientation {
        guard let size = view.window?.bounds.size else { return .portrait }
        return KeyboardGeometry.Orientation(width: size.width, height: size.height)
    }

    /// How much of the screen we are covering, for the capture process to leave
    /// out of the frame fingerprint. See `KeyboardGeometry`.
    ///
    /// The height itself comes from `Theme.Metrics`, because that is what this
    /// class asks the host for and it is a constant per orientation. The two
    /// things only the runtime knows are the gap underneath us — the strip where
    /// the system draws the home indicator over the keyboard — and which
    /// orientation we are actually in, so both are measured here and nothing
    /// else is.
    private func ownUIHeightFraction() -> Double {
        // The layout, because a Roomy keyboard with both optional rows on covers
        // half again what the default does, and the band has to leave all of it
        // out. See `KeyboardGeometry.ownUIHeightFraction`.
        let layout = controller?.customization ?? .default
        guard let window = view.window else {
            return KeyboardGeometry.ownUIHeightFraction(
                screenHeight: KeyboardGeometry.referenceScreenHeight, layout: layout)
        }
        // `window.bounds`, not `window.screen.bounds` — see `currentOrientation`.
        // Mixing the two here would compare a rotation-aware `ourBottom` against
        // a `screenHeight` that never rotates, which is wrong in both directions:
        // right in portrait by coincidence, silently wrong the moment the device
        // turns.
        let screenSize = window.bounds.size
        let orientation = KeyboardGeometry.Orientation(width: screenSize.width, height: screenSize.height)
        let screenHeight = screenSize.height
        let ourBottom = window.frame.minY + view.convert(view.bounds, to: window).maxY
        return KeyboardGeometry.ownUIHeightFraction(
            screenHeight: screenHeight, gapBelow: screenHeight - ourBottom, layout: layout,
            orientation: orientation)
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
        // An answer that arrives after the keyboard has gone would land in whatever
        // document comes next, which is a different person's message.
        controller?.cancelRefinement()
        // A Send button that never presses space or Return still finishes the
        // word under the cursor. Learning here, before the save, is what makes
        // a one-word message count; a trailing space already learned it and
        // this is a no-op.
        controller?.learnWordJustCommitted()
        // The only moment it is certain there is a keyboard to save from.
        // `PersonalLanguageModel` writes every twenty-fifth word on its own, so
        // this bounds the loss to the tail rather than being the whole mechanism —
        // iOS tears a keyboard extension down without warning and there is no
        // callback that reliably fires when it does.
        PersonalLanguageModel.shared.save()
    }

    /// How WhatsApp, Notes and every other host decide writing direction.
    ///
    /// The extension's Info.plist is `PrimaryLanguage=en-US` and
    /// `PrefersRightToLeft=false` because this keyboard is bilingual, and those
    /// keys cannot change at runtime. `primaryLanguage` can, and it supersedes
    /// them. Leaving it unset is a Hebrew (Arabic, Persian, …) keyboard whose
    /// letters go into a left-aligned field: the host never learned the language
    /// moved.
    ///
    /// Pass the language when you have it. `$hostLanguage` fires from `willSet`,
    /// so the sink must use the emitted value. Appear calls
    /// `prepareForNewDocument` first, then publishes `hostLanguage`.
    private func publishInputLanguage(_ language: KeyboardLanguage? = nil) {
        guard let language = language ?? controller?.hostLanguage else { return }
        primaryLanguage = language.inputModeTag
    }

    /// The host app decides how tall the keyboard is only if we tell it. The
    /// priority is below required so the constraint never fights the system
    /// during rotation.
    private func updateKeyboardHeight() {
        guard let controller else { return }
        // Banner presence plus the layout. The fingerprint crop still uses the
        // tallest form — see `ownUIHeightFraction()` — so a mid-read resize
        // cannot move the band even though the host height follows the strip.
        // A recording or a model call does not change this: neither reserves a
        // row.
        let showsBanner = controller.showsActionBanner
        lastShowsActionBanner = showsBanner
        let height = Theme.Metrics.totalHeight(
            for: controller.customization, showsBanner: showsBanner, orientation: currentOrientation)

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

    /// Opens the containing app at the given URL on behalf of the keyboard.
    ///
    /// Both paths here are best-effort. `NSExtensionContext.open(_:)` is
    /// documented for specific extension points (Today, Action, Share) and is
    /// **not** documented for keyboard extensions — it may work, may report
    /// failure without opening, or may be silently ignored depending on the OS
    /// version and hosting configuration. The responder-chain `UIApplication`
    /// path is **explicitly unsupported**: it relies on walking UIKit internals
    /// that Apple does not document for extensions and may stop working without
    /// notice. Both are isolated here, in the extension host; the package never
    /// calls either.
    ///
    /// `UIApplication.shared` is not used — it is unavailable in extensions.
    private func openContainingApp(_ url: URL) {
        guard let ctx = extensionContext else {
            handoffLogger.info(
                "extensionContext nil — attempting responder-chain fallback for \(url.scheme ?? "unknown", privacy: .public)"
            )
            openViaResponderChain(url)
            return
        }
        ctx.open(url) { [weak self] success in
            if success {
                self?.handoffLogger.info(
                    "extensionContext.open succeeded for \(url.scheme ?? "unknown", privacy: .public)"
                )
            } else {
                self?.handoffLogger.warning(
                    "extensionContext.open failed — attempting responder-chain fallback for \(url.scheme ?? "unknown", privacy: .public)"
                )
                // The completion may arrive on any thread; UIKit responder traversal
                // and UIApplication.open(_:) must run on main.
                DispatchQueue.main.async { self?.openViaResponderChain(url) }
            }
        }
    }

    /// Walks the UIKit responder chain looking for a `UIApplication` instance
    /// and asks it to open the URL. **Unsupported and best-effort** — see the
    /// caller's doc comment. `UIApplication.shared` cannot be used here because
    /// it is unavailable in extensions; this is the only way to reach an
    /// instance without it.
    ///
    /// All UIKit responder traversal and `UIApplication.open` must run on main.
    private func openViaResponderChain(_ url: URL) {
        var responder: UIResponder? = view
        while let r = responder {
            if let app = r as? UIApplication {
                handoffLogger.info(
                    "UIApplication found in responder chain — opening \(url.scheme ?? "unknown", privacy: .public)"
                )
                app.open(url, options: [:]) { [weak self] success in
                    if success {
                        self?.handoffLogger.info(
                            "UIApplication.open succeeded for \(url.scheme ?? "unknown", privacy: .public)"
                        )
                    } else {
                        self?.handoffLogger.warning(
                            "UIApplication.open failed for \(url.scheme ?? "unknown", privacy: .public)"
                        )
                    }
                }
                return
            }
            responder = r.next
        }
        handoffLogger.warning(
            "no UIApplication found in responder chain for \(url.scheme ?? "unknown", privacy: .public)"
        )
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

    /// A tap in the host field moves the caret without changing any characters,
    /// so `textDidChange` never runs. `UIInputViewController` is a
    /// `UITextInputDelegate`, and this is the callback that tap fires.
    ///
    /// **Refresh only.** Clearing `revertibleEdit` here would delete the undo on
    /// the same turn as the insert that created it, because this keyboard's own
    /// insertions move the caret too. `deletedWordPrefix` expires by itself when
    /// the word under the caret no longer starts with it.
    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        guard let controller else { return }
        controller.refreshSuggestions()
    }
}
