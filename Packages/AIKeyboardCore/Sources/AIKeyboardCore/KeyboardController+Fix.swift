import Foundation
import SwiftUI

extension KeyboardController {

    // MARK: Fix styles

    /// The passes a long press on Fix offers, in the order the popup draws them.
    ///
    /// **Proofread leads, because index 0 of an alternates popup is the no-op.**
    /// `KeyView` treats lifting on the first item as "the long press changed
    /// nothing", which for a letter means the character it already inserted and
    /// for Rewrite means the default register a tap would have run. The same
    /// rule has to hold here or a user who holds Fix, looks, and lifts without
    /// moving gets Spelling they did not pick.
    public var fixAlternates: [String] { FixStyle.allCases.map(\.title) }

    /// Runs one of `fixAlternates` by the name the popup drew.
    ///
    /// By title rather than by index, for the same reason `selectTone(named:)`
    /// does: the popup and the controller would otherwise have to agree about
    /// an order. The same two refusals as a tap: nothing to fix is a key that
    /// should not have fired, and a call in flight must not be thrown away.
    public func selectFix(named title: String) {
        guard !isWorking else { return }
        guard hasTextToWorkWith else {
            refuseForEmptyField(.fix)
            return
        }
        guard let style = FixStyle.allCases.first(where: { $0.title == title }) else { return }
        Feedback.modifierPress()
        aiSourceText = aiSourceText.isEmpty ? aiTargetText : aiSourceText
        runFix(style)
    }

    /// One Fix call, however the pass was chosen.
    ///
    /// Reached from `run(.fix)` (the tap, always proofread) and from the
    /// long-press popup. Dictation is refused here as well as in `run(_:)`,
    /// because the popup never goes through `run(_:)` — the same split
    /// `runTone` exists for.
    func runFix(_ style: FixStyle) {
        guard !isDictationActive else { return }
        let source = aiSourceText
        beginWork(.fix, showing: .none) { [engine] in
            try await engine.fix(source, style: style)
        } apply: { controller, text in
            // **Straight into the field, with no Use button in front of it.**
            // See `applyDirectly`. `aiResultText` is still set on the way past,
            // because it is what `BannerState.resolve` reads to tell "the model
            // answered" from "the model answered with nothing" — and an empty
            // answer is the one case that still has to reach the strip.
            controller.aiResultText = text
            controller.applyDirectly(text, for: .fix)
        }
    }
}
