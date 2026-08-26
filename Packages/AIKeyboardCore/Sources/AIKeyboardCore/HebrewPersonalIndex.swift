import Foundation

/// In-memory grouping of persisted Hebrew surfaces that share a vouched stem.
///
/// The on-disk store stays exact. This is rebuilt after a mutation and thrown
/// away on the next one, so a keystroke never walks the bigram table.
struct HebrewPersonalIndex {
    private let exactUnigrams: [String: Int]
    private let persisted: Set<String>
    private let surfacesByStem: [String: Set<String>]
    private let stemsBySurface: [String: Set<String>]
    private let followersByPrevious: [String: [(String, Int)]]

    init(unigrams: [String: Int], bigrams: [String: Int], pairSeparator: Character) {
        exactUnigrams = unigrams
        let persisted = Set(unigrams.keys)
        self.persisted = persisted

        var byStem: [String: Set<String>] = [:]
        var bySurface: [String: Set<String>] = [:]
        for surface in persisted {
            for stem in Self.vouchedStems(of: surface, persisted: persisted) {
                byStem[stem, default: []].insert(surface)
                bySurface[surface, default: []].insert(stem)
            }
        }
        surfacesByStem = byStem
        stemsBySurface = bySurface

        var byPrevious: [String: [(String, Int)]] = [:]
        for (pair, count) in bigrams {
            guard let separator = pair.firstIndex(of: pairSeparator) else { continue }
            let previous = String(pair[..<separator])
            let follower = String(pair[pair.index(after: separator)...])
            byPrevious[previous, default: []].append((follower, count))
        }
        for previous in byPrevious.keys {
            byPrevious[previous]?.sort {
                $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1
            }
        }
        followersByPrevious = byPrevious
    }

    func rankingCount(of folded: String) -> Int {
        relatedSurfaces(of: folded).reduce(0) { $0 + (exactUnigrams[$1] ?? 0) }
    }

    /// Exact previous-word pairs first, then followers of related attested
    /// surfaces. Every spelling comes from a stored pair. Nothing is glued.
    func followers(after folded: String, limit: Int, minimumCount: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []

        func take(_ matches: [(String, Int)]) {
            for (follower, count) in matches {
                guard count >= minimumCount, seen.insert(follower).inserted else { continue }
                out.append(follower)
                if out.count == limit { return }
            }
        }

        take(followersByPrevious[folded] ?? [])
        if out.count == limit { return out }

        var inherited: [String: Int] = [:]
        for previous in relatedSurfaces(of: folded) {
            for (follower, count) in followersByPrevious[previous] ?? [] {
                guard !seen.contains(follower) else { continue }
                inherited[follower, default: 0] += count
            }
        }
        take(
            inherited
                .map { ($0.key, $0.value) }
                .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 })
        return out
    }

    private func relatedSurfaces(of folded: String) -> Set<String> {
        var related: Set<String> = [folded]
        for stem in acceptedStems(for: folded) {
            related.formUnion(surfacesByStem[stem] ?? [])
            if exactUnigrams[stem] != nil { related.insert(stem) }
        }
        return related
    }

    private func acceptedStems(for surface: String) -> Set<String> {
        var stems = stemsBySurface[surface] ?? []
        if surfacesByStem[surface] != nil {
            stems.insert(surface)
        }
        stems.formUnion(Self.vouchedStems(of: surface, persisted: persisted))
        return stems
    }

    /// Only a stripped stem that seed, the typo list, or the store itself
    /// already stands behind. An empty prefix is the surface, not a grouping.
    private static func vouchedStems(of surface: String, persisted: Set<String>) -> Set<String> {
        var stems = Set<String>()
        for reading in HebrewMorphology.splits(of: surface) where !reading.prefix.isEmpty {
            guard isVouched(reading.stem, persisted: persisted) else { continue }
            stems.insert(reading.stem)
        }
        return stems
    }

    private static func isVouched(_ stem: String, persisted: Set<String>) -> Bool {
        persisted.contains(stem)
            || SeedLanguageModel.knows(stem, in: .hebrew)
            || TypoLexicon.isWord(stem, in: .hebrew)
    }
}
