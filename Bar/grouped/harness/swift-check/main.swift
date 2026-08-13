// Does the Swift port group and decode exactly as the Python did?
//
// `Bar/grouped/` measured the design in Python and the keyboard implements it in
// Swift. A port is precisely the thing that can be faithful in design and wrong
// in a detail — an off-by-one in the rounding, the extra letter going to the
// wrong end — and every such detail is a different keyboard that still compiles.
//
// Emits JSON on stdout; `swift-check.sh` diffs it against the Python's answer for
// the same questions.

import Foundation

// MARK: The rows, out of the file make-rows.py extracted from LetterLayouts.swift

struct RowsPayload: Decodable {
    struct Language: Decodable { let rows: [String] }
    let languages: [String: Language]
}

let environment = ProcessInfo.processInfo.environment
let rowsPath = environment["ROWS_JSON"] ?? "data/rows.json"

guard let rowsData = FileManager.default.contents(atPath: rowsPath),
    let payload = try? JSONDecoder().decode(RowsPayload.self, from: rowsData)
else {
    FileHandle.standardError.write(Data("cannot read \(rowsPath)\n".utf8))
    exit(1)
}

let rowsByLanguage: [String: [[String]]] = payload.languages.mapValues { language in
    language.rows.map { $0.map(String.init) }
}

// **Install them, or every answer below is silently empty.** `GroupedDecoder`'s
// language-based `letterToKey` reads `KeyboardLayout.letterLayouts`, which in the
// shim starts empty — so without this the decoder codes no word, indexes nothing
// and returns [] for every query, which reads like a broken port rather than a
// harness that forgot to load its data. It did exactly that once.
for (tag, rows) in rowsByLanguage {
    let language: KeyboardLanguage = tag == "he" ? .hebrew : .english
    KeyboardLayout.letterLayouts[language] = KeyboardLayout.LetterLayout(keys: rows)
}

/// Hebrew keeps its clitics apart; English has nothing to keep apart.
func clitics(_ tag: String) -> Set<String> {
    tag == "he" ? GroupedKeys.hebrewClitics : []
}

// MARK: The questions

var report: [String: Any] = [:]

for (tag, rows) in rowsByLanguage {
    var perLevel: [[String: Any]] = []
    for level in [GroupedKeys.Level.pairs, .l1, .l2, .l3] {
        let groups = GroupedKeys.groups(for: rows, keepingApart: clitics(tag), level: level)
        let flat = groups.flatMap { $0 }.map { $0.joined() }
        let collisions = flat.filter { cap in
            cap.map(String.init).filter(clitics(tag).contains).count > 1
        }
        // Plain adjacency too, so the harness can see the separation working
        // rather than only its result.
        let adjacent = GroupedKeys.groups(for: rows, keepingApart: [], level: level)
            .flatMap { $0 }.map { $0.joined() }
        perLevel.append([
            "k": level.rawValue,
            "keys": flat.count,
            "groups": flat,
            "adjacentGroups": adjacent,
            "cliticCollisions": collisions
        ])
    }
    report[tag] = perLevel
}

// MARK: The decoder, on a fixed vocabulary so both sides rank the same list

let vocabulary: [String: [String]] = [
    "en": ["the", "to", "and", "of", "a", "in", "is", "it", "that", "for", "cat", "car", "cab", "bat"],
    "he": ["את", "של", "לא", "על", "זה", "הוא", "אני", "כל", "שלום", "תודה", "מה", "בסדר"]
]

var decoded: [String: Any] = [:]
for (tag, words) in vocabulary {
    guard let rows = rowsByLanguage[tag] else { continue }
    var perLevel: [[String: Any]] = []
    for level in [GroupedKeys.Level.pairs, .l1, .l2, .l3] {
        let map = GroupedDecoder.letterToKey(
            rows: rows, keepingApart: clitics(tag), level: level)
        // The code as a list of key indices, which is comparable across languages
        // where a raw scalar string would not be readable in a diff.
        var codes: [String: [Int]] = [:]
        for word in words {
            guard let code = GroupedDecoder.code(for: word, map: map) else { continue }
            codes[word] = code.unicodeScalars.map { Int($0.value) - 0xE000 }
        }
        let language: KeyboardLanguage = tag == "he" ? .hebrew : .english
        let decoder = GroupedDecoder(language: language, level: level, words: words)
        var answers: [String: [String]] = [:]
        for word in words {
            guard let code = GroupedDecoder.code(for: word, map: map) else { continue }
            // Every prefix of the word, which is what the bar actually asks for.
            var prefix = ""
            for scalar in code.unicodeScalars {
                prefix.unicodeScalars.append(scalar)
                answers["\(word)|\(prefix.unicodeScalars.count)"] =
                    decoder.candidates(startingWith: prefix, limit: 3)
            }
        }
        perLevel.append(["k": level.rawValue, "codes": codes, "candidates": answers])
    }
    decoded[tag] = perLevel
}

// MARK: Tap location as a soft pin, the same cases Python `letter_at` answers

let tapCases: [(lines: [[String]], x: Double, y: Double)] = [
    ([["q", "w"], ["a", "s"]], 0.2, 0.2),
    ([["q", "w"], ["a", "s"]], 0.8, 0.2),
    ([["q", "w"], ["a", "s"]], 0.2, 0.8),
    ([["q", "w"], ["a", "s"]], 0.8, 0.8),
    ([["q", "w"], ["a", "s"]], 0.5, 0.5),
    ([["q", "w"], ["a", "s"]], 0.5, 0.2),
    ([[], ["ך", "ף"]], 0.5, 0.2),
    ([[], ["ך", "ף"]], 0.2, 0.8),
    ([[], ["ך", "ף"]], 0.8, 0.8)
]
var taps: [[String: Any]] = []
for tap in tapCases {
    taps.append([
        "lines": tap.lines,
        "x": tap.x,
        "y": tap.y,
        "letter": GroupedKeys.letter(atX: tap.x, y: tap.y, in: tap.lines) ?? ""
    ])
}

let output: [String: Any] = ["grouping": report, "decoding": decoded, "taps": taps]
let json = try! JSONSerialization.data(
    withJSONObject: output, options: [.sortedKeys, .prettyPrinted])
FileHandle.standardOutput.write(json)
FileHandle.standardOutput.write(Data("\n".utf8))
