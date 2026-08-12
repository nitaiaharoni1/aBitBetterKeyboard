import CoreGraphics
import Foundation

// MARK: - Customization into rows

/// **Customization is a source of `KeyRow`s, not a second rendering path.**
///
/// Everything the user arranges is compiled into the same `KeySpec` and `KeyRow`
/// types the measured letter layouts produce, before it reaches any view. The
/// width solver, `KeyView`, hit testing, the alternates popup and the
/// left-to-right pinning therefore need no knowledge that this feature exists,
/// and `RenderedRowOrderTests` keeps measuring exactly what it always measured.
extension KeyboardLayout {

    /// Row ids.
    ///
    /// `KeyRow` is `Identifiable` by `Int` and `KeyboardView` runs a `ForEach`
    /// over them, so two rows with one id is a `ForEach` with duplicate identity.
    /// The letter rows own 0, 1 and 2 and the bottom row owns 3, which is what
    /// shipped; the two new rows take numbers outside that range rather than
    /// renumbering anything that already works.
    public enum RowID {
        public static let numbers = -1
        public static let bottom = 3
        public static let cursor = 4
    }

    /// Every row the keyboard draws, in the order it draws them.
    public static func rows(
        for language: KeyboardLanguage,
        plane: KeyboardPlane,
        showsGlobe: Bool,
        customization: KeyboardCustomization,
        grouping: GroupedKeys.Level = .off
    ) -> [KeyRow] {
        var rows: [KeyRow] = []
        let columns = columns(for: language, plane: plane, grouping: grouping)

        // The number row is a letters-plane affordance. On the numbers plane the
        // digits are already the top row, and drawing them twice is not a feature.
        if customization.showsNumberRow, plane == .letters {
            rows.append(numberRow(for: language, columns: columns))
        }

        // `Self.` because the local `rows` shadows the static one from the line it
        // is declared on, so the bare call does not compile.
        rows += Self.rows(for: language, plane: plane, grouping: grouping)

        rows.append(
            compile(
                customization.bottomRow, id: RowID.bottom, language: language, plane: plane,
                showsGlobe: showsGlobe))

        if !customization.cursorRow.isEmpty {
            rows.append(
                compile(
                    customization.cursorRow, id: RowID.cursor, language: language, plane: plane,
                    showsGlobe: showsGlobe))
        }

        return rows
    }

    /// The optional digits row, in the language's own numerals.
    private static func numberRow(for language: KeyboardLanguage, columns: Int) -> KeyRow {
        let digits = language.digits.map { KeySpec(.character(String($0))) }
        return KeyRow(
            id: RowID.numbers,
            keys: digits,
            // Centred the way a short letter row is, so a twelve-column layout does
            // not stretch ten digits across the whole width and break the columns
            // the rest of the keyboard lines up on.
            sideInsetUnits: max(0, (CGFloat(columns) - CGFloat(digits.count)) / 2))
    }

    /// One editable row.
    ///
    /// **The plane keys are resolved here, not stored.** A stored
    /// `SlotAction.numbersPlane` means "the key that switches planes", and what it
    /// says depends on where the keyboard is standing: `123` on the letters plane,
    /// the language's own letters label everywhere else. Storing the resolved cap
    /// would freeze a Hebrew keyboard's bottom row saying `123` while it was
    /// already showing numbers.
    static func compile(
        _ slots: [SlotSpec],
        id: Int,
        language: KeyboardLanguage,
        plane: KeyboardPlane,
        showsGlobe: Bool
    ) -> KeyRow {
        let keys: [KeySpec] = slots.compactMap { slot in
            // iOS owns this one. The layout stores it, the system decides whether
            // it is drawn, and a keyboard on a device with nothing else installed
            // gets the width back rather than a dead key.
            if slot.action == .globe, !showsGlobe { return nil }

            // **Built whole, not from a cap.** Its long-press marks live on the
            // `KeySpec`, and `KeyView` finds them by recognising
            // `punctuationKeyID`. Drawn on all three planes (same rule as
            // `KeyboardLayout.bottomRow`): the five marks on the numbers plane
            // are not a replacement for the one key a thumb finds without
            // looking. The ids do not collide — this one is `punctuation`, that
            // one is `char-.`.
            if slot.action == .punctuation {
                let key = punctuationKey(for: language)
                return KeySpec(
                    key.cap, width: keyWidth(slot.width),
                    id: "\(punctuationKeyID)#\(slot.id.uuidString.prefix(8))",
                    alternates: key.alternates)
            }

            guard let cap = resolvedCap(slot.action, language: language, plane: plane) else {
                return nil
            }
            return KeySpec(cap, width: keyWidth(slot.width), id: identifier(for: cap, slot: slot))
        }
        return KeyRow(id: id, keys: keys, sideInsetUnits: 0)
    }

    /// **Two parts, and both are load-bearing.**
    ///
    /// The cap's own derived id is what a UI test and an accessibility identifier
    /// address — `char-,` rather than a raw UUID, so `key-char-,` still finds the
    /// key. The slot's id is what keeps two commas on one row from resolving to
    /// one `ForEach` identity, which is undefined behaviour rather than a cosmetic
    /// clash. `KeyView` strips everything from the `#` when it builds its
    /// accessibility identifier.
    static func identifier(for cap: KeyCap, slot: SlotSpec) -> String {
        "\(KeySpec(cap).id)#\(slot.id.uuidString.prefix(8))"
    }

    /// The plane key answers to where the keyboard is standing; everything else
    /// answers to itself.
    private static func resolvedCap(
        _ action: SlotAction, language: KeyboardLanguage, plane: KeyboardPlane
    ) -> KeyCap? {
        switch (action, plane) {
        // **Every plane key goes somewhere it is not, on every plane.** The first
        // version of this sent `.symbolsPlane` to `.letters` from the letters
        // plane and to `.symbols` from the symbols plane, so a symbols key the
        // user had placed themselves was a dead button on two planes out of
        // three: it drew, it pressed, and it switched to the plane already
        // showing. Only the route from `.numbers` worked. The rule now is simply
        // "not where you are".
        case (.numbersPlane, .letters):
            return .plane(.numbers, label: "123")
        case (.numbersPlane, _):
            return .plane(.letters, label: language.lettersPlaneLabel)
        case (.symbolsPlane, .symbols):
            return .plane(.letters, label: language.lettersPlaneLabel)
        case (.symbolsPlane, _):
            return .plane(.symbols, label: "#+=")
        default:
            return action.keyCap(language: language)
        }
    }

    private static func keyWidth(_ width: SlotWidth) -> KeyWidth {
        switch width {
        case .units(let value): return .unit(value)
        case .fill: return .flexible
        }
    }
}
