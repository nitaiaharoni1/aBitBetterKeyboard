import Foundation

extension TypoChannel {
    static func cost(
        typed rawTyped: [Character], candidate rawCandidate: [Character],
        language: KeyboardLanguage, budget: Int
    ) -> EditCost? {
        let typed = rawTyped.map(fold)
        let candidate = rawCandidate.map(fold)
        let band = max(0, budget / minimumIndelCost)
        guard abs(candidate.count - typed.count) <= band else { return nil }
        let insertions = packedInsertionCosts(for: typed, language: language)
        let deletions = packedDeletionCosts(for: candidate, language: language)
        return bandedCost(
            typed: typed, candidate: candidate, language: language, budget: budget,
            band: band, insertions: insertions, deletions: deletions)
    }

    private static func packedInsertionCosts(for typed: [Character], language: KeyboardLanguage) -> [Int] {
        typed.indices.map { index in
            packEdit(
                insertionCost(
                    typed[index],
                    leftNeighbor: index >= 1 ? typed[index - 1] : nil,
                    rightNeighbor: index + 1 < typed.count ? typed[index + 1] : nil,
                    language: language))
        }
    }

    private static func packedDeletionCosts(for candidate: [Character], language: KeyboardLanguage) -> [Int] {
        candidate.indices.map { index in
            packEdit(
                deletionCost(
                    candidate[index],
                    leftNeighbor: index >= 1 ? candidate[index - 1] : nil,
                    rightNeighbor: index + 1 < candidate.count ? candidate[index + 1] : nil,
                    isTrailing: index == candidate.count - 1,
                    language: language))
        }
    }

    private static func bandedCost(
        typed: [Character], candidate: [Character], language: KeyboardLanguage, budget: Int,
        band: Int, insertions: [Int], deletions: [Int]
    ) -> EditCost? {
        let unreachable = Int.max / 2
        let width = 2 * band + 1
        var rowBeforeLast = [Int](repeating: unreachable, count: width)
        var previousRow = initialBandedRow(
            band: band, typedCount: typed.count, insertions: insertions, unreachable: unreachable)
        var currentRow = [Int](repeating: unreachable, count: width)

        if !candidate.isEmpty {
            for candidateIndex in candidate.indices {
                let i = candidateIndex + 1
                reset(&currentRow, to: unreachable)
                let bounds = (max(-band, -i), min(band, typed.count - i))
                guard bounds.0 <= bounds.1 else { return nil }
                var rowMinimum = unreachable
                for d in bounds.0...bounds.1 {
                    let j = i + d
                    let cell = cheapestCell(
                        i: i, j: j, d: d, band: band,
                        typed: typed, candidate: candidate, language: language,
                        rowBeforeLast: rowBeforeLast, previousRow: previousRow, currentRow: currentRow,
                        insertions: insertions, deletions: deletions, unreachable: unreachable)
                    currentRow[d + band] = cell
                    rowMinimum = min(rowMinimum, cell)
                }
                if (rowMinimum >> 4) > budget { return nil }
                rowBeforeLast = previousRow
                previousRow = currentRow
            }
        }
        return unpackResult(
            previousRow[typed.count - candidate.count + band], budget: budget, unreachable: unreachable)
    }

    private static func initialBandedRow(
        band: Int, typedCount: Int, insertions: [Int], unreachable: Int
    ) -> [Int] {
        var row = [Int](repeating: unreachable, count: 2 * band + 1)
        var running = 0
        for d in 0...band where d <= typedCount {
            if d == 0 {
                row[band] = 0
            } else {
                running += insertions[d - 1]
                row[d + band] = running
            }
        }
        return row
    }

    private static func reset(_ row: inout [Int], to value: Int) {
        for index in row.indices { row[index] = value }
    }

    private static func cheapestCell(
        i: Int, j: Int, d: Int, band: Int,
        typed: [Character], candidate: [Character], language: KeyboardLanguage,
        rowBeforeLast: [Int], previousRow: [Int], currentRow: [Int],
        insertions: [Int], deletions: [Int], unreachable: Int
    ) -> Int {
        var best = unreachable
        considerDeletion(
            &best, i: i, d: d, band: band, previousRow: previousRow, deletion: deletions[i - 1],
            unreachable: unreachable)
        considerInsertionAndSubstitution(
            &best, i: i, j: j, d: d, band: band, typed: typed, candidate: candidate,
            language: language, previousRow: previousRow, currentRow: currentRow,
            insertion: insertions, unreachable: unreachable)
        considerTransposition(
            &best, i: i, j: j, d: d, band: band, typed: typed, candidate: candidate,
            rowBeforeLast: rowBeforeLast, unreachable: unreachable)
        return best
    }

    private static func considerDeletion(
        _ best: inout Int, i: Int, d: Int, band: Int, previousRow: [Int], deletion: Int, unreachable: Int
    ) {
        let offset = d + 1
        guard offset <= band else { return }
        let value = previousRow[offset + band]
        if value < unreachable { best = min(best, value + deletion) }
    }

    private static func considerInsertionAndSubstitution(
        _ best: inout Int, i: Int, j: Int, d: Int, band: Int,
        typed: [Character], candidate: [Character], language: KeyboardLanguage,
        previousRow: [Int], currentRow: [Int], insertion: [Int], unreachable: Int
    ) {
        guard j >= 1 else { return }
        let insertionOffset = d - 1
        if insertionOffset >= -band {
            let value = currentRow[insertionOffset + band]
            if value < unreachable { best = min(best, value + insertion[j - 1]) }
        }
        let diagonal = previousRow[d + band]
        if diagonal < unreachable {
            best = min(
                best,
                diagonal + packEdit(substitutionCost(candidate[i - 1], typed[j - 1], language: language)))
        }
    }

    private static func considerTransposition(
        _ best: inout Int, i: Int, j: Int, d: Int, band: Int,
        typed: [Character], candidate: [Character], rowBeforeLast: [Int], unreachable: Int
    ) {
        guard i >= 2, j >= 2 else { return }
        let value = rowBeforeLast[d + band]
        guard value < unreachable else { return }
        if candidate[i - 1] == typed[j - 2], candidate[i - 2] == typed[j - 1] {
            best = min(best, value + packEdit(transpositionCost))
        } else if shapeFold(candidate[i - 1]) == shapeFold(typed[j - 2]),
            shapeFold(candidate[i - 2]) == shapeFold(typed[j - 1])
        {
            best = min(best, value + packEdit(transpositionCost + 20))
        }
    }

    private static func unpackResult(_ packed: Int, budget: Int, unreachable: Int) -> EditCost? {
        guard packed < unreachable else { return nil }
        let cost = packed >> 4
        guard cost <= budget else { return nil }
        return EditCost(cost: cost, count: packed & 0xF)
    }
}
