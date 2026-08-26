import Foundation

/// One pass through the suggestion pipeline, with every layer a judge needs.
///
/// `ranked` is what `SuggestionEngine.suggestions` has always returned.
/// `generated` is every source text before `rank` cuts the list.
/// `visible` is the three drawn slots after `SuggestionSlotOrder.centeredSlots`.
/// `commits` is what `KeyboardController.insertSpace` inserts: the first
/// `isDefault` in `ranked`, not whichever word sits in the middle of the bar.
public struct SuggestionEvaluation: Sendable {
    public let generated: [String]
    public let ranked: [Suggestion]
    public let visible: [String?]
    public let defaultIndex: Int
    public let commits: String
}
