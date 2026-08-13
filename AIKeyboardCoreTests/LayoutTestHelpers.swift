import CoreGraphics
import XCTest

@testable import AIKeyboardCore

/// Sums the unit width of every key in `row`.
///
/// Flexible, pinned and slot keys count as 1 unit each, the minimum that lets
/// them stand in the row. Shared by `CustomLayoutTests` and `LayoutValidatorTests`.
func totalUnits(of row: KeyRow) -> CGFloat {
    row.keys.reduce(CGFloat(0)) { total, key in
        switch key.width {
        case .unit(let value): return total + value
        case .slot: return total + 1
        case .flexible, .pinned: return total + 1
        }
    }
}
