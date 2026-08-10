import CoreGraphics

extension KeyboardLayout {

    // MARK: Width solving

    /// Resolved widths for one row, given the space available.
    ///
    /// The top row of equal keys sets the unit; everything else is expressed
    /// in that unit so the columns line up down the whole keyboard.
    ///
    /// **Three widths, resolved in that order: pinned, then unit, then flexible.**
    /// A pinned key is answered first and never moves, a unit key is a multiple of
    /// the language's own letter key, and a flexible key takes whatever is left.
    /// The last step is the one that pays for the first: when the pinned keys plus
    /// the letters do not fit, **everything that is not pinned shrinks together**
    /// rather than the pinned key giving ground. Hebrew is the layout that shows
    /// it — nine letters and a delete key want 359.1pt of a 342pt row on an iPhone
    /// 17 Pro — so its bottom-row letters come out 32.3pt against the 34.2pt of
    /// the rows above. That misalignment is the visible price of a delete key that
    /// does not move when the language does, and it is deliberate.
    ///
    /// **The space row is the exception: its unit is the ten-column reference,
    /// not the language.** `123`, punctuation and return are declared in units so
    /// the editor can resize them, but they must not inherit Arabic's twelve-column
    /// letter key or English's ten-column one — that is what made the same phone
    /// draw a 60pt return on Arabic and a 75pt return on English. The space bar
    /// is `.flexible` and absorbs whatever those three leave, so locking their
    /// unit locks the whole row. Letter rows still take the caller's `unitWidth`.
    ///
    /// The `1.15` tappability floor that used to live here is gone with
    /// `remainderShare`: it existed to stop a leftover-sized shift or delete
    /// becoming unusably narrow, and a pinned key cannot.
    public static func widths(
        for row: KeyRow,
        totalWidth: CGFloat,
        unitWidth: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        let count = CGFloat(row.keys.count)
        guard count > 0 else { return [] }

        // `totalWidth` is already the row's usable width (side insets stripped by
        // the caller), so the reference unit is asked with `sideInset: 0`.
        let unit =
            row.id == RowID.bottom
            ? Self.unitWidth(
                totalWidth: totalWidth, spacing: spacing, sideInset: 0,
                columns: referenceColumns)
            : unitWidth

        let gaps = spacing * (count - 1)
        let inset = row.sideInsetUnits * (unit + spacing) * 2
        let available = max(0, totalWidth - gaps - inset)

        let pinned = pinnedWidth(totalWidth: totalWidth, spacing: spacing)
        let pinnedTotal = pinned * CGFloat(row.keys.filter { $0.width == .pinned }.count)
        // What the row has to spend on everything else. Never negative, so a
        // degenerate width cannot produce a negative frame.
        let room = max(0, available - pinnedTotal)

        let fixedTotal = row.keys.reduce(CGFloat(0)) { partial, key in
            switch key.width {
            case .unit(let multiple): return partial + unit * multiple
            case .flexible, .pinned: return partial
            }
        }

        let flexibleCount = row.keys.filter { $0.width == .flexible }.count
        let flexibleWidth =
            flexibleCount > 0 ? max(0, room - fixedTotal) / CGFloat(flexibleCount) : 0

        // A row with a flexible key has already absorbed the difference into it,
        // so this only bites on rows of fixed keys: the three letter rows and the
        // punctuation row of the numbers and symbols planes.
        let unpinnedTotal = fixedTotal + flexibleWidth * CGFloat(flexibleCount)
        let scale = unpinnedTotal > room && unpinnedTotal > 0 ? room / unpinnedTotal : 1

        return row.keys.map { key in
            switch key.width {
            case .pinned: return pinned
            case .unit(let multiple): return unit * multiple * scale
            case .flexible: return flexibleWidth * scale
            }
        }
    }

    /// The width of a pinned key, in points.
    ///
    /// **Derived from the screen, not from the language.** `unitWidth` divides the
    /// available width by the language's own column count, so a twelve-column
    /// Russian keyboard gets a smaller key than a ten-column English one — and a
    /// delete key expressed in *those* units would be a different size on every
    /// keyboard, which is the thing this exists to stop. So the reference is
    /// always ten columns, whatever the language is, and the answer is the same
    /// 51.3pt on a 402pt screen for all sixty-four of them and on all three planes.
    ///
    /// 1.5 units because that is what English's shift and delete already worked
    /// out to when they took the leftover, so the language nobody complained about
    /// keeps the key it had.
    public static func pinnedWidth(totalWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        let columns = CGFloat(referenceColumns)
        return functionKeyUnits * max(1, (totalWidth - spacing * (columns - 1)) / columns)
    }

    /// The column count a pinned key is measured against. The narrowest any
    /// language gets, and the width `LayoutValidator.widthBudget` is also the
    /// floor of, so the two cannot drift.
    public static let referenceColumns = 10

    /// Width of a standard letter key for a keyboard of this width.
    ///
    /// **The floor here is a guard against a degenerate width, not a minimum key
    /// size, and it used to be both.** At `max(20, …)` a thirteen-column layout on
    /// a 320pt screen — which is what Display Zoom gives a modern iPhone — asked
    /// for 20pt keys where there was room for 18.6, and Bulgarian's top two rows
    /// ran 18pt off the side. A key that is a little narrow is worse than a key
    /// the right size and better than a key that is not on the screen, so the
    /// division wins and the floor only stops a zero-width `GeometryReader` pass
    /// producing zero or negative frames.
    public static func unitWidth(
        totalWidth: CGFloat, spacing: CGFloat, sideInset: CGFloat, columns: Int = 10
    ) -> CGFloat {
        let columns = CGFloat(max(1, columns))
        let usable = totalWidth - sideInset * 2 - spacing * (columns - 1)
        return max(1, usable / columns)
    }
}
