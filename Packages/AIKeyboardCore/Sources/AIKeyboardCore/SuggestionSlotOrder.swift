import Foundation

/// Visual order of the three suggestion-bar slots.
///
/// Mid-word the engine array is still `[typed, best, next, extra]` so the
/// refiner can find the keystrokes. Only the drawing order changes here:
/// default in the middle, the others on either side, a lone word centered.
///
/// **The word already in the field is drawn when the bar is completing it
/// and dropped when the bar is correcting it.** Being the default is not
/// enough on its own. A Hebrew typo such as `תדוה` keeps the default on the
/// keystrokes while offering `תודה`, and boldening the echo would endorse
/// the typo. The second question is whether anything on offer *continues*
/// the keystrokes, including a candidate that will not fit on the bar.
/// An empty prefix is next-word, so nothing is filtered.
///
/// Shared by `SuggestionBar` and `Bar/typing/harness`. A second spelling in
/// Python would drift from the one that draws the keyboard.
enum SuggestionSlotOrder {

    static func centeredSlots(_ items: [Suggestion], typed: String = "") -> [Suggestion?] {
        var slots: [Suggestion?] = Array(repeating: nil, count: SuggestionEngine.barSlots)
        let offers: [Suggestion]
        if typed.isEmpty {
            offers = items
        } else {
            let key = SuggestionEngine.comparable(typed)
            // "" is a prefix of every word, which would make every offer a
            // continuation as well as making equality meaningless — the same
            // trap `comparable`'s other callers already guard. A
            // punctuation-only echo is matched by the raw keystrokes instead.
            let isEcho: (Suggestion) -> Bool
            let continuesTyped: (Suggestion) -> Bool
            if key.isEmpty {
                isEcho = { $0.text == typed }
                continuesTyped = { $0.text.hasPrefix(typed) }
            } else {
                isEcho = { SuggestionEngine.comparable($0.text) == key }
                continuesTyped = { SuggestionEngine.comparable($0.text).hasPrefix(key) }
            }
            let offered = items.filter { !isEcho($0) }
            let echoKeepsItsSlot = offered.isEmpty || offered.contains(where: continuesTyped)
            offers = items.filter { !isEcho($0) || ($0.isDefault && echoKeepsItsSlot) }
        }
        guard !offers.isEmpty else { return slots }
        let defaultIndex = offers.firstIndex(where: \.isDefault) ?? 0
        slots[1] = offers[defaultIndex]
        let others = offers.indices.filter { $0 != defaultIndex }.map { offers[$0] }
        if others.count > 0 { slots[0] = others[0] }
        if others.count > 1 { slots[2] = others[1] }
        return slots
    }
}
