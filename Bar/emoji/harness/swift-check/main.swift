// Does `rank.py` rank exactly as `EmojiSearch.swift` ranks?
//
// The corpus is scored by a Python port, and a port is precisely the thing that
// can be faithful in design and wrong in a detail. Here the details that would
// not show up as a crash are: which rung a query lands on, whether `length` is
// counted in grapheme clusters or code points, whether an empty name survives
// the split, and the exact order of the four sort keys. Each of those is a
// different ranker that still runs.
//
// Reads the questions from `EMOJI_QUERIES`, writes the answers as JSON on
// stdout. `python_side.py` asks the same questions and diffs.

import Foundation

struct Question: Decodable {
    let id: String
    let query: String
    let recent: [String]
    let limit: Int
}

struct Explain: Decodable {
    let query: String
    let emoji: [String]
    let recent: [String]
}

struct Questions: Decodable {
    let queries: [Question]
    let explain: [Explain]
}

let environment = ProcessInfo.processInfo.environment
guard let path = environment["EMOJI_QUERIES"],
    let data = FileManager.default.contents(atPath: path),
    let questions = try? JSONDecoder().decode(Questions.self, from: data)
else {
    FileHandle.standardError.write(Data("cannot read EMOJI_QUERIES\n".utf8))
    exit(1)
}

// **Said out loud, because an empty catalogue would agree with an empty
// catalogue.** If the resource bundle did not assemble, both sides would rank
// nothing and every list would match — a green check over a harness that
// measured neither implementation.
if let failure = EmojiCatalog.loadFailure {
    FileHandle.standardError.write(Data("catalogue did not load: \(failure)\n".utf8))
    exit(1)
}

var results: [String: [String]] = [:]
for question in questions.queries {
    results[question.id] = EmojiSearch.results(
        for: question.query, recent: question.recent, limit: question.limit)
}

// The `Match` behind a handful of answers, so a disagreement says *where*
// rather than only that the two lists differ.
// The raw `Match`, before the recents boost — that boost is one `max` and it
// is already covered by the result lists of the four `recents` entries.
var explained: [String: [String: Any]] = [:]
for item in questions.explain {
    let needle = EmojiSearch.normalise(item.query)
    for emoji in item.emoji {
        let match = EmojiSearch.score(
            needle: needle,
            names: EmojiCatalog.names(for: emoji),
            keywords: EmojiCatalog.keywords(for: emoji))
        explained["\(item.query)|\(emoji)"] = [
            "rung": match.rung,
            "coverage": match.coverage,
            "length": match.length,
            "order": EmojiCatalog.order(of: emoji),
            "names": EmojiCatalog.names(for: emoji),
            "keywords": EmojiCatalog.keywords(for: emoji)
        ]
    }
}

let output: [String: Any] = [
    "results": results,
    "explain": explained,
    "catalogue": [
        "count": EmojiCatalog.all.count,
        "first": EmojiCatalog.all.first ?? "",
        "last": EmojiCatalog.all.last ?? "",
        "categories": EmojiCatalog.categories.map(\.id)
    ]
]
let json = try! JSONSerialization.data(
    withJSONObject: output, options: [.sortedKeys, .prettyPrinted])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write(Data("\n".utf8))
