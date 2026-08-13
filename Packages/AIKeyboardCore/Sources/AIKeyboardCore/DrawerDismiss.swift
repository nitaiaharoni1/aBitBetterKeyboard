import SwiftUI

/// Whether a downward slide over the keyboard chrome is a dismiss, or just a
/// finger wandering.
///
/// **Arithmetic rather than a gesture, because a `DragGesture` cannot be asked
/// anything afterwards.** Every rule here is one a keyboard gets wrong in a way
/// the user reads as the keyboard being broken — a swipe that dismisses on the
/// ordinary wobble of a tap, a diagonal that meant to pick Rewrite, an upward
/// flick that hid the keyboard nobody asked to close. So the rules live in a
/// type a test can drive, and the view only forwards translations into it.
///
/// **The keys are not in this region, because they commit on finger-down.** A
/// letter is already in the document by the time the finger has travelled far
/// enough to look like a dismiss. Wrapping the grid would type `q` and then hide
/// the keyboard, which is two things the user did not ask for from one touch.
/// Chrome does not insert. The progress bar and the suggestion strip are the
/// band a downward swipe can mean dismiss without a letter already being owed.
///
/// **The banner is not in this file's call site either.** `ActionBanner` hosts
/// `RPSystemBroadcastPickerView`, whose pressable area is the system `UIButton`
/// ReplayKit insets inside it. A parent drag over that view would win the touch
/// the picker needs to ask Control Center to present, and there is no other
/// supported way to start a broadcast from a keyboard extension. Leave the
/// banner outside the wrap.
///
/// **Travel is taller than the strip, so a tap cannot also be a dismiss.** The
/// suggestion bar is `Theme.Metrics.suggestionBarHeight` (36). A drag that has
/// not yet left that frame is still a tap on a candidate, the emoji search box,
/// or a Rewrite chip. `minimumTravel` is `minTouchTarget` (44), one comparison a
/// test can reject. The gesture is high-priority so a qualifying pull owns the
/// touch before a child button can commit on lift; its `minimumDistance` is that
/// same 44, so an ordinary tap never recognises and still lands.
enum DrawerDismiss {

    struct Policy: Equatable, Sendable {
        let minimumTravel: CGFloat
        let minimumVerticalDominance: CGFloat
        static let standard = Policy(
            minimumTravel: Theme.Metrics.minTouchTarget,
            minimumVerticalDominance: 1.25)
    }

    enum Outcome: Equatable, Sendable {
        case ignored
        case dismiss
    }

    static func outcome(for translation: CGSize, policy: Policy = .standard) -> Outcome {
        let down = translation.height
        guard down >= policy.minimumTravel else { return .ignored }
        guard down >= abs(translation.width) * policy.minimumVerticalDominance else {
            return .ignored
        }
        return .dismiss
    }
}

extension View {
    func drawerDismiss(perform action: @escaping () -> Void) -> some View {
        highPriorityGesture(
            DragGesture(
                minimumDistance: DrawerDismiss.Policy.standard.minimumTravel,
                coordinateSpace: .local
            )
            .onEnded { value in
                if DrawerDismiss.outcome(for: value.translation) == .dismiss {
                    action()
                }
            },
            including: .all)
    }
}
