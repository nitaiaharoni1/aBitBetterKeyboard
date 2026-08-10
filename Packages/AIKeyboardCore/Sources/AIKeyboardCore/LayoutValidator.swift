import CoreGraphics
import Foundation

/// One thing wrong with a layout.
public struct LayoutIssue: Equatable, Identifiable, Sendable {

    public enum Severity: Sendable { case error, warning }

    public enum Kind: String, Equatable, Sendable {
        case missingSpace
        case missingReturn
        case missingPlaneSwitch
        case missingGlobe
        case duplicateSpace
        case rowTooWide
        case geometryOutOfRange
        case costsScreenContext
        case snippetTooLong
        case duplicateAction
    }

    public var id: String { "\(kind.rawValue)-\(message)" }
    public let kind: Kind
    public let severity: Severity
    /// Written for the user, not for a log. It appears under the canvas.
    public let message: String

    public init(kind: Kind, severity: Severity, message: String) {
        self.kind = kind
        self.severity = severity
        self.message = message
    }
}

/// The rails.
///
/// A keyboard the user can break is a keyboard the user cannot type on, and the
/// person who breaks it will not connect the crash to the screen where they
/// broke it — they will be in somebody else's app with no way back.
///
/// **Errors block Done, warnings do not**, and that split is the whole design: a
/// second comma on a row is a taste the user is allowed to have, and a layout
/// with no return key is not a keyboard.
public enum LayoutValidator {

    /// How many key widths a custom row may occupy before it runs off the screen.
    ///
    /// **Ten, the *narrowest* `KeyboardLayout.columns`, and it was written as
    /// twelve — the widest — which is the same rail pointing the wrong way.** The
    /// unit is inversely proportional to the column count: `unitWidth` divides the
    /// available width by `columns`, so a twelve-column language (Russian, Arabic,
    /// Turkish, Persian) gets a *smaller* key and a ten-column one gets a bigger
    /// one. Twelve units therefore fits Russian exactly and overruns English by a
    /// fifth of the screen. Since one layout is shared by all sixty-four
    /// languages, the budget has to be the tightest of them, and
    /// `columns(for:plane:)` never returns less than ten.
    ///
    /// This is the Bulgarian overrun again, inverted: the first version of this
    /// rail under-protected the fifty-nine common languages instead of the five
    /// rare ones. `testARowThatFitsRussianButNotEnglishIsRejected` is what holds
    /// it, and it fails against a budget of twelve.
    public static let widthBudget: CGFloat = 10

    /// **There is deliberately no "this row is crowded" warning.**
    ///
    /// One was written and it could never fire. `SlotWidth.minimumUnits` is a
    /// whole key, so a row of more than twelve keys is necessarily more than
    /// twelve units, which `rowTooWide` already rejects as an error with a better
    /// message. The only layout that could have reached the warning was one
    /// hand-written into the JSON with sub-unit widths, and the warning read as a
    /// rail while being unreachable.
    static let longestSnippet = 20

    /// The tallest the keyboard can be before it starts costing screen context.
    ///
    /// Derived from the measured cliff rather than restated: `maximumOwnUI` is the
    /// fraction of the reference screen the fingerprint crop is capped at, swept
    /// over the corpus, and past it the band eats the host's own message lines.
    /// Reading it from the constant means the two cannot drift when the next
    /// measurement moves it.
    static var screenContextHeightLimit: CGFloat {
        CGFloat(FrameReduction.Band.maximumOwnUI) * KeyboardGeometry.referenceScreenHeight
    }

    public static func issues(
        in layout: KeyboardCustomization, showsGlobe: Bool
    ) -> [LayoutIssue] {
        var found: [LayoutIssue] = []
        let custom = layout.bottomRow + layout.cursorRow
        let everywhere = custom + layout.barLeading + layout.barTrailing
        let actions = custom.map(\.action)

        // MARK: The essentials
        //
        // Three, and not four. **Delete is deliberately not required here.**
        // `KeyboardLayout` closes the third letter row with it in all sixty-four
        // languages and on all three planes, at a `.pinned` width so the rect does
        // not move, and those rows are not editable — so it is reachable whatever
        // the user does down here. Requiring it in the custom rows would make the
        // shipped default invalid on its first launch.

        if !actions.contains(.space) {
            found.append(
                LayoutIssue(
                    kind: .missingSpace, severity: .error,
                    message: "Add a space bar. Without one there is no way to type a space."))
        }
        if !actions.contains(.ret) {
            found.append(
                LayoutIssue(
                    kind: .missingReturn, severity: .error,
                    message: "Add a return key. Without one you cannot send or start a new line."
                ))
        }
        if !actions.contains(.numbersPlane) {
            found.append(
                LayoutIssue(
                    kind: .missingPlaneSwitch, severity: .error,
                    message: "Add the 123 key. Without it the numbers are unreachable."))
        }
        if showsGlobe, !actions.contains(.globe) {
            found.append(
                LayoutIssue(kind: .missingGlobe, severity: .error, message: globeRefusal))
        }

        if actions.filter({ $0 == .space }).count > 1 {
            found.append(
                LayoutIssue(
                    kind: .duplicateSpace, severity: .error,
                    message: "Only one space bar. Two of them both try to fill the row."))
        }

        // MARK: Geometry

        if !LayoutGeometry.keyHeightRange.contains(layout.geometry.keyHeight)
            || !LayoutGeometry.rowSpacingRange.contains(layout.geometry.rowSpacing)
        {
            found.append(
                LayoutIssue(
                    kind: .geometryOutOfRange, severity: .error,
                    message: "The key size is outside what fits on screen."))
        }

        // MARK: Width
        //
        // This is the Bulgarian-class defect and it does not fail loudly: a row
        // over budget runs off the side of the screen. Apple's own Bulgarian
        // layout overran by 45pt that way, a whole key and a half.

        for (name, row) in [("bottom", layout.bottomRow), ("cursor", layout.cursorRow)] {
            guard !row.isEmpty else { continue }
            if fixedUnits(of: row) > widthBudget {
                found.append(
                    LayoutIssue(
                        kind: .rowTooWide, severity: .error,
                        message:
                            "The \(name) row is too wide to fit. Make a key narrower or remove one."
                    ))
            }
        }

        // MARK: A cost the user cannot otherwise see
        //
        // **A tall keyboard quietly degrades screen context, and until this
        // warning existed nothing said so where the choice was made.** The frame
        // fingerprint crops our own UI out before deciding whether the
        // conversation on screen is still the one that was read, and
        // `FrameReduction.Band.maximumOwnUI` caps that crop at a measured cliff:
        // past roughly 368pt the band starts eating the host's own message lines
        // and two different conversations collide. A user who turns on the number
        // row and picks 52pt keys is past it. That is a fair trade to offer — it
        // costs screen context and nothing else — but it has to be offered rather
        // than taken, which is the same principle as the globe key naming its
        // refusal. `FrameFingerprint.swift` carries the swept table.

        if Theme.Metrics.totalHeight(for: layout) > screenContextHeightLimit {
            found.append(
                LayoutIssue(
                    kind: .costsScreenContext, severity: .warning,
                    message:
                        "This keyboard is tall enough that screen context may miss a conversation switch. Typing and the AI actions are unaffected."
                ))
        }

        // MARK: Taste, not safety

        for slot in everywhere {
            if case .text(let value) = slot.action, value.count > longestSnippet {
                found.append(
                    LayoutIssue(
                        kind: .snippetTooLong, severity: .warning,
                        message: "\"\(value.prefix(12))…\" is too long to fit on a key cap."))
            }
        }

        for row in [layout.bottomRow, layout.cursorRow] {
            let repeated = Dictionary(grouping: row, by: \.action).filter { $0.value.count > 1 }
            for (action, _) in repeated where action != .space {
                found.append(
                    LayoutIssue(
                        kind: .duplicateAction, severity: .warning,
                        message: "\(action.title) appears twice on the same row."))
            }
        }

        return found
    }

    /// Whether Done is allowed.
    public static func isUsable(_ layout: KeyboardCustomization, showsGlobe: Bool) -> Bool {
        !issues(in: layout, showsGlobe: showsGlobe).contains { $0.severity == .error }
    }

    /// Whether one key may be taken out, and what to say if not.
    ///
    /// Asked by the editor's Remove button so a refusal can be shown *before* the
    /// tap rather than as an error afterwards. Implemented by removing the key and
    /// asking the same question the whole validator asks, so the button and the
    /// rails can never disagree about what is required.
    public static func canRemove(
        _ slot: SlotSpec, from layout: KeyboardCustomization, showsGlobe: Bool
    ) -> RemovalVerdict {
        var without = layout
        without.bottomRow.removeAll { $0.id == slot.id }
        without.cursorRow.removeAll { $0.id == slot.id }
        without.barLeading.removeAll { $0.id == slot.id }
        without.barTrailing.removeAll { $0.id == slot.id }

        let newErrors = issues(in: without, showsGlobe: showsGlobe)
            .filter { $0.severity == .error }
        // Only errors this removal *introduces* count. A layout that is already
        // broken must not refuse every further edit, which would be a corner the
        // user cannot get out of.
        let existing = Set(
            issues(in: layout, showsGlobe: showsGlobe)
                .filter { $0.severity == .error }.map(\.id))
        guard let blocker = newErrors.first(where: { !existing.contains($0.id) }) else {
            return RemovalVerdict(isAllowed: true, reason: "")
        }
        return RemovalVerdict(isAllowed: false, reason: blocker.message)
    }

    public struct RemovalVerdict: Equatable, Sendable {
        public let isAllowed: Bool
        /// Empty when allowed. Shown under the disabled Remove button otherwise.
        public let reason: String
    }

    /// **This is iOS's requirement, not a preference of ours.** `showsGlobe` is
    /// `UIInputViewController.needsInputModeSwitchKey`, which is the system saying
    /// the user has another keyboard installed and must be able to reach it. A
    /// layout without the key on such a device strands them in whatever app they
    /// are in.
    static let globeRefusal =
        "iOS requires the next-keyboard key on this device, so it cannot be removed."

    /// The units a row occupies before the `fill` keys take what is left. A `fill`
    /// key still needs somewhere to stand, so it counts as one.
    private static func fixedUnits(of row: [SlotSpec]) -> CGFloat {
        row.reduce(CGFloat(0)) { total, slot in
            switch slot.width {
            case .units(let value): return total + value
            case .fill: return total + 1
            }
        }
    }
}
