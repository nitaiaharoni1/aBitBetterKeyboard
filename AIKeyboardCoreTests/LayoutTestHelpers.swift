import CoreGraphics
import XCTest

@testable import AIKeyboardCore

/// Sums the unit width of every key in `row`.
///
/// Flexible and pinned keys count as 1 unit each — the minimum that lets them
/// stand in the row. A share counts as the columns it stands over, which is what
/// it was built from. Shared by `CustomLayoutTests` and `LayoutValidatorTests`.
func totalUnits(of row: KeyRow) -> CGFloat {
    row.keys.reduce(CGFloat(0)) { total, key in
        switch key.width {
        case .unit(let value), .share(let value): return total + value
        case .flexible, .pinned: return total + 1
        }
    }
}
