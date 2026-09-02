import SwiftUI
import UIKit

/// Where each key ended up, keyed by `KeySpec.id`, in `KeyboardView.frameSpace`.
///
/// Published only so the layout editor can put a selection ring and a drop target
/// over the *real* keyboard rather than over a drawing of one. Nothing in the
/// keyboard itself reads this, and it costs one `GeometryReader` per key in a
/// background that draws nothing.
public struct KeyFramesKey: PreferenceKey {
    public static var defaultValue: [String: CGRect] { [:] }
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Drawing order between the action row and the letter block.
///
/// **A permanent `zIndex(1)` on the action row hid every QWERTY callout.** The
/// balloon grows up into Reply / Fix / Rewrite, and that row was painted after
/// the letters on purpose so a Fix / Rewrite / CopyClip stack could cover
/// QWERTY. Letters now sit above that rest layer; the action row climbs over
/// them only while one of those stacks is open. The climb is a callback from
/// the held key, not a preference, so the menu is already in front on the
/// first frame it appears.
enum KeyPopupLayer {
    static let letters: Double = 2
    static func actionRow(raised: Bool) -> Double { raised ? 3 : 1 }
}

/// The whole keyboard: suggestion strip, key grid, and whatever panel is covering
/// the grid right now.
public struct KeyboardView: View {

    /// The coordinate space `KeyFramesKey` reports in. It is this view's own
    /// bounds, so an `.overlay` on a `KeyboardView` shares it exactly.
    public static let frameSpace = "aikeyboard-frames"

    // Internal so `KeyboardView+Keys` (and any later split) can read it. Private
    // would compile only while the keys lived in this same file.
    @ObservedObject var controller: KeyboardController
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.verticalSizeClass) var verticalSizeClass
    var isEditingLayout: Bool
    @State var actionPopupRaised = false
    @StateObject private var touchContactMonitor = TouchContactMonitor()

    public init(controller: KeyboardController, isEditingLayout: Bool = false) {
        self.controller = controller
        self.isEditingLayout = isEditingLayout
    }

    /// iPhone only: `.compact` is exactly how UIKit reports "this device is in
    /// landscape" for a phone, and it is the same test
    /// `KeyboardGeometry.Orientation.init(width:height:)` runs over the numbers
    /// `KeyboardViewController` measures from the window — one definition of
    /// landscape rather than two that can disagree. iPad and Slide Over/Split
    /// View can also report `.compact` for reasons that have nothing to do with
    /// rotation, which is exactly why iPad needs its own answer; see NIT-177.
    var orientation: KeyboardGeometry.Orientation {
        verticalSizeClass == .compact ? .landscape : .portrait
    }

    public var body: some View {
        VStack(spacing: 0) {
            // **One strip when there is something to say, nothing the rest of the
            // time — and "the rest of the time" includes the two states it was
            // most often up for.** `ScreenContextStrip` occupied a 30pt row only
            // while a capture session was live, and every AI answer arrived in a
            // panel over the keys; the banner was both. A running call is a sweep
            // on the key that started it, and a live recording is a waveform on
            // the microphone, so what is left here is a live reading, a refusal
            // and a failure. See `BannerState.isPresented`.
            // **Landscape never shows it.** The banner's 58pt is more than a
            // third of landscape's whole ≈169pt budget under the fingerprint
            // cap — see `Theme.Metrics.totalHeight(for:showsBanner:orientation:)`.
            // Height and drawing have to agree on this or the published crop
            // stops matching what is actually on screen.
            if controller.showsActionBanner, orientation == .portrait {
                ActionBanner(controller: controller)
                    .transition(.opacity)
            }

            // **The bar is told which orientation it is in, and that is what
            // pays for the action row landscape sheds.** Its row is already in
            // the published height, so the controls that row carried can stand
            // in it for nothing — see `SuggestionBar.landscapeActionStrip`.
            // Handed down rather than read again there, for the same reason the
            // panel above is closed from here: one definition of landscape.
            SuggestionBar(controller: controller, orientation: orientation)

            // **Nothing covers the whole key area any more.** This was a `ZStack`
            // with a `fullKeyAreaPanel` over it, and the three panels that used it —
            // the AI menu, the AI result and dictation — are deleted: every one of
            // them existed to say something the strip above now says, and they said
            // it with the keyboard hidden. What is left of overlays lives inside
            // `keyGrid`: emoji and CopyClip replace the letters and leave the
            // action row above them, and search hands the letters back and
            // takes only that row.
            keyGrid
                .frame(
                    height: Theme.Metrics.keyAreaHeight(
                        for: controller.customization, orientation: orientation)
                )
                .environment(\.touchContactMonitor, touchContactMonitor)
        }
        .background(Theme.Keys.background)
        .environment(\.layoutDirection, controller.language.layoutDirection)
        .coordinateSpace(name: Self.frameSpace)
        .animation(Theme.Motion.quick, value: controller.showsActionBanner)
        .background(FeedbackAnchor(monitor: touchContactMonitor))
        .onAppear {
            Feedback.prepare()
            controller.refreshCopyClip()
        }
        // **The same `orientation` that sheds the action row below decides this**,
        // rather than a second read in the extension, because the two disagreeing
        // is the whole defect: landscape drops the row holding the only key that
        // closes the emoji grid or the CopyClip panel, and those panels hide every
        // letter — so a panel rotated into left a keyboard nothing could type on
        // or close. `.task(id:)` and not `.onChange`, so a keyboard that *appears*
        // in landscape with a panel still open from last time is caught too:
        // `overlay` survives the extension being reused across fields.
        // See `KeyboardController.closeOverlayForLandscape`.
        .task(id: orientation) {
            guard orientation == .landscape else { return }
            controller.closeOverlayForLandscape()
        }
    }

    /// How the emoji grid arrives. Still needed by `KeyboardView+Keys`, which is the
    /// one place left that puts anything over the keys.
    var panelTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
    }
}

/// Binds `Feedback` to a real view once this keyboard is in a window.
///
/// A generator created with only a style is a free-floating motor. In the
/// extension that is why the first taps of a session are late or missing.
/// `didMoveToWindow` is the moment we have a view UIKit will actually drive.
private struct FeedbackAnchor: UIViewRepresentable {
    let monitor: TouchContactMonitor

    func makeUIView(context: Context) -> AnchorView { AnchorView(monitor: monitor) }
    func updateUIView(_ uiView: AnchorView, context: Context) { uiView.monitor = monitor }

    static func dismantleUIView(_ uiView: AnchorView, coordinator: ()) {
        uiView.detachTouchObserver()
    }

    final class AnchorView: UIView {
        var monitor: TouchContactMonitor {
            didSet { touchObserver.monitor = monitor }
        }

        private let touchObserver: TouchContactGestureRecognizer

        init(monitor: TouchContactMonitor) {
            self.monitor = monitor
            touchObserver = TouchContactGestureRecognizer(monitor: monitor)
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("storyboard") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detachTouchObserver()
            guard let window else { return }
            Feedback.attach(to: self)
            window.addGestureRecognizer(touchObserver)
        }

        func detachTouchObserver() {
            touchObserver.view?.removeGestureRecognizer(touchObserver)
            monitor.reset()
        }
    }
}

/// UIKit's touch object is richer than SwiftUI's `DragGesture.Value`: UIKit
/// also reports an approximate contact radius and its error band. This monitor
/// observes the same touches without cancelling or delaying the key gestures.
final class TouchContactMonitor: ObservableObject {
    struct Contact {
        let id: UInt64
        let location: CGPoint
        let radius: CGFloat
        let radiusTolerance: CGFloat
        let startedAt: TimeInterval
        let timestamp: TimeInterval
    }

    private struct TrackedContact {
        let id: UInt64
        let initialLocation: CGPoint
        let startedAt: TimeInterval
        var radius: CGFloat
        var radiusTolerance: CGFloat
        var timestamp: TimeInterval

        var contact: Contact {
            Contact(
                id: id,
                location: initialLocation,
                radius: radius,
                radiusTolerance: radiusTolerance,
                startedAt: startedAt,
                timestamp: timestamp)
        }
    }

    private var active: [ObjectIdentifier: TrackedContact] = [:]
    private var recent: [TrackedContact] = []
    private var claimedIDs: Set<UInt64> = []
    private var nextID: UInt64 = 0

    func record(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            // For a finger this may equal `location(in:)`; when the hardware
            // has a finer sample UIKit gives it to us here at no extra cost.
            let location = touch.preciseLocation(in: nil)
            let trackedID: UInt64
            if let existing = active[id] {
                trackedID = existing.id
            } else {
                nextID &+= 1
                trackedID = nextID
            }
            let initial = active[id]?.initialLocation ?? location
            let startedAt = active[id]?.startedAt ?? touch.timestamp
            active[id] = TrackedContact(
                id: trackedID,
                initialLocation: initial,
                startedAt: startedAt,
                radius: touch.majorRadius,
                radiusTolerance: touch.majorRadiusTolerance,
                timestamp: touch.timestamp)
        }
    }

    func finish(_ touches: Set<UITouch>) {
        record(touches)
        for touch in touches {
            guard let contact = active.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            recent.append(contact)
        }
        pruneRecent()
    }

    func reset() {
        active.removeAll(keepingCapacity: true)
        recent.removeAll(keepingCapacity: true)
        claimedIDs.removeAll(keepingCapacity: true)
    }

    /// The raw and SwiftUI callbacks are delivered during the same event but
    /// their order is not promised. Recently-ended contacts stay available for
    /// one beat so a lift can still recover its radius.
    func contact(
        near point: CGPoint, matching id: UInt64?, includesRecent: Bool,
        startedNear gestureStart: TimeInterval?
    ) -> Contact? {
        pruneRecent()
        if let id {
            if let live = active.values.first(where: { $0.id == id }) { return live.contact }
            guard includesRecent else { return nil }
            return recent.last(where: { $0.id == id })?.contact
        }

        let recentContacts =
            includesRecent
            ? recent.filter { contact in
                gestureStart.map {
                    abs(contact.startedAt - $0) <= Self.startTimeTolerance
                } ?? true
            }.map(\.contact)
            : []
        let contacts = (active.values.map(\.contact) + recentContacts)
            .filter { !claimedIDs.contains($0.id) }
            .filter { contact in
                gestureStart.map {
                    abs(contact.startedAt - $0) <= Self.startTimeTolerance
                } ?? true
            }
        let contact =
            contacts
            .map { contact in
                (
                    contact: contact,
                    distance: hypot(contact.location.x - point.x, contact.location.y - point.y)
                )
            }
            .filter { $0.distance <= Self.matchDistance }
            .min {
                if $0.distance != $1.distance { return $0.distance < $1.distance }
                return $0.contact.timestamp > $1.contact.timestamp
            }?
            .contact
        if let contact { claimedIDs.insert(contact.id) }
        return contact
    }

    private func pruneRecent() {
        let cutoff = ProcessInfo.processInfo.systemUptime - Self.recentLifetime
        recent.removeAll { $0.timestamp < cutoff }
        let retained = Set(active.values.map(\.id) + recent.map(\.id))
        claimedIDs.formIntersection(retained)
    }

    private static let matchDistance: CGFloat = 24
    private static let recentLifetime: TimeInterval = 0.25
    private static let startTimeTolerance: TimeInterval = 0.1
}

/// A passive recognizer: it sees the touch objects but never wins ownership of
/// a sequence, so SwiftUI's press, long-press and multi-touch handling stays in
/// charge of behaviour.
private final class TouchContactGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    weak var monitor: TouchContactMonitor?
    private var activeTouches = Set<ObjectIdentifier>()

    init(monitor: TouchContactMonitor) {
        self.monitor = monitor
        super.init(target: nil, action: nil)
        delegate = self
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        monitor?.record(touches)
        activeTouches.formUnion(touches.map(ObjectIdentifier.init))
        state = state == .possible ? .began : .changed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        monitor?.record(touches)
        if state == .began || state == .changed { state = .changed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, cancelled: true)
    }

    override func reset() {
        super.reset()
        activeTouches.removeAll(keepingCapacity: true)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        monitor?.finish(touches)
        activeTouches.subtract(touches.map(ObjectIdentifier.init))
        guard activeTouches.isEmpty else {
            state = .changed
            return
        }
        state = cancelled ? .cancelled : .ended
    }
}

private struct TouchContactMonitorKey: EnvironmentKey {
    static let defaultValue: TouchContactMonitor? = nil
}

extension EnvironmentValues {
    var touchContactMonitor: TouchContactMonitor? {
        get { self[TouchContactMonitorKey.self] }
        set { self[TouchContactMonitorKey.self] = newValue }
    }
}

/// Width of the key grid, so a long-press strip can stay on screen.
///
/// Paired with `keyboardCanvasOriginX`. Both come from the same
/// `GeometryReader` in screen coordinates, not `frameSpace`. Hebrew sets
/// `layoutDirection` on `KeyboardView`, and a named space on that view can
/// report the punctuation key as `minX == 0` (its leading edge). The clamp
/// then treats a right-edge key as a left-edge one and shifts the strip off
/// the screen.
private struct KeyboardCanvasWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct KeyboardCanvasOriginXKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var keyboardCanvasWidth: CGFloat {
        get { self[KeyboardCanvasWidthKey.self] }
        set { self[KeyboardCanvasWidthKey.self] = newValue }
    }

    var keyboardCanvasOriginX: CGFloat {
        get { self[KeyboardCanvasOriginXKey.self] }
        set { self[KeyboardCanvasOriginXKey.self] = newValue }
    }
}

extension View {
    /// Side inset, optional one-handed width, and the left-to-right pin every key
    /// row needs. Shared by the letter block and the action row; the emoji panel
    /// below the action row uses the same width and reach, without the key inset.
    func keyboardGridChrome(width: CGFloat, reach: Reach) -> some View {
        // **Every row is drawn in the order its keys are listed, in every
        // language, and the letters plane is not an exception.** It was, and
        // that shipped all six right-to-left keyboards mirrored: the rows come
        // out of Apple's own layout data in physical key order, which is
        // already the order Apple draws them on screen — ק at the left of the
        // Hebrew top row, ض at the left of the Arabic one — and an RTL `HStack`
        // draws its first element last, so it reversed rows that were right.
        // `Bar/layouts/stock-rendered-rows.json` is the measurement and
        // `RenderedRowOrderTests` is what holds this to it.
        padding(.horizontal, Theme.Metrics.sideInset)
            .frame(width: width)
            // Which edge a narrowed grid hugs.
            .frame(maxWidth: .infinity, alignment: reachAlignment(reach))
            // **Applied last, so it covers the frame above as well as the rows.**
            // `.leading` and `.trailing` resolve against the layout direction in
            // force *where the modifier sits*, so with this pinned only around the
            // `VStack` a one-handed Hebrew keyboard hugged the wrong side — the
            // rows were right and the box holding them was mirrored. One-handed is
            // about which thumb is holding the phone, and that does not swap with
            // the script.
            .environment(\.layoutDirection, .leftToRight)
    }

    /// Where the grid sits when it has been narrowed for one hand. Physical
    /// sides, guaranteed by the `.leftToRight` pin this is resolved inside.
    func reachAlignment(_ reach: Reach) -> Alignment {
        switch reach {
        case .full: return .center
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

// MARK: - Previews

#if DEBUG

/// Holds the controller in a `@StateObject` for the same reason the in-app
/// playground does: `KeyboardView` takes its controller as an
/// `@ObservedObject`, so something outside the view has to own it or a canvas
/// re-render rebuilds the keyboard's entire state mid-edit.
///
/// What a preview cannot show is the extension talking to a *host* app, which is
/// the half that broke on the first real install — see
/// `KeyboardController.preview(language:text:)`.
private struct KeyboardPreviewHost: View {

    @StateObject private var controller: KeyboardController

    init(language: KeyboardLanguage, text: String) {
        _controller = StateObject(
            wrappedValue: .preview(language: language, text: text))
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            KeyboardView(controller: controller)
        }
        .task { controller.refreshSuggestions() }
    }
}

#Preview("English") {
    KeyboardPreviewHost(language: .english, text: "the quick brown fo")
}

/// Hebrew is here because right-to-left rows are **not** mirrored, and a
/// preview is the cheapest place to see that they are not. See
/// `.claude/rules/keyboard-layout.md`.
#Preview("Hebrew") {
    KeyboardPreviewHost(language: .hebrew, text: "שלו")
}

#endif
