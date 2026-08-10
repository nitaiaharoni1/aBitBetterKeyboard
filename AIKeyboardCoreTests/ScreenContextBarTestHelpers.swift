import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

// MARK: - The bar, as data

/// `Bar/screen-context/`, read from the repository rather than from a bundle.
///
/// The test target has no resources phase and the images are 7.4MB, so copying
/// them into the bundle would double them for no gain: an iOS Simulator process
/// reads the host filesystem directly, and `#filePath` points at the checkout
/// this build came from.
enum ScreenBar {

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Bar/screen-context")

    struct Expected: Decodable {
        let sender: String?
        let message: String?
        let language: String?
        let script: String?
    }

    struct Trap: Decodable {
        let text: String
        let why: String
    }

    struct Ghost: Decodable {
        let text: String
    }

    struct Entry: Decodable {
        let id: String
        let file: String
        let app: String
        /// `english`, `mixed` or `hebrew` — the bar's own bucket for the screen.
        let language: String
        /// Nil on the screen that has nothing worth replying to, where silence
        /// is the correct answer.
        let expected: Expected?
        let traps: [Trap]
        let notOnScreen: [Ghost]
    }

    private struct Truth: Decodable {
        let images: [Entry]
    }

    static func entries() throws -> [Entry] {
        try JSONDecoder()
            .decode(Truth.self, from: Data(contentsOf: root.appendingPathComponent("ground-truth.json")))
            .images
    }

    static func frame(_ file: String) throws -> CGImage {
        let url = root.appendingPathComponent(file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ScreenReadError.failed("could not decode \(file)") }
        return image
    }

    /// The recorded cloud answers, keyed by image id, in the shape the transport
    /// hands back: the model's own field names, with a null field absent rather
    /// than empty. `vertex_vision.py` renames `script`/`language` to
    /// `detectedScript`/`detectedLanguage` on the way into the file, so this
    /// undoes exactly that and nothing else.
    static func recordedCloudFields() throws -> [String: [String: String]] {
        let data = try Data(contentsOf: root.appendingPathComponent("cloud_outputs.json"))
        let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []

        var byID: [String: [String: String]] = [:]
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            var fields: [String: String] = [:]
            for (recorded, wire) in [
                ("sender", "sender"), ("message", "message"),
                ("detectedScript", "script"), ("detectedLanguage", "language")
            ] where row[recorded] is String {
                fields[wire] = row[recorded] as? String
            }
            if let messages = row["messages"],
                let encoded = try? JSONSerialization.data(
                    withJSONObject: messages, options: [.fragmentsAllowed])
            {
                fields["messages"] = String(decoding: encoded, as: UTF8.self)
            }
            byID[id] = fields
        }
        return byID
    }

    /// The `VisionScreenReader`-only numbers `harness/run-reader.sh` last wrote,
    /// so the on-device half of the routed run can be compared against the
    /// harness it is supposed to agree with.
    struct ReaderRow: Decodable {
        let id: String
        let gated: Bool
        let sender: String?
        let message: String?
    }

    static func recordedReaderRows() throws -> [String: ReaderRow] {
        let data = try Data(contentsOf: root.appendingPathComponent("reader_outputs.json"))
        let rows = try JSONDecoder().decode([ReaderRow].self, from: data)
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    }
}

// MARK: - Doubles

/// The cloud half of the router, replaying one recorded answer.
///
/// The reader, the prompt, the JPEG encoding and the parsing are all the
/// shipping ones; only the wire is replaced. It keeps every request it is handed
/// so the test can check that what the shipping path *would have sent* is the
/// same call the harness recorded these answers from.
final class ReplayTransport: CloudTransport, @unchecked Sendable {

    private let fields: [String: String]
    private let lock = NSLock()
    private var received: [CloudRequest] = []

    init(_ fields: [String: String]) {
        self.fields = fields
    }

    var requests: [CloudRequest] {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    func send(_ request: CloudRequest) async throws -> [String: String] {
        lock.lock()
        received.append(request)
        lock.unlock()
        return fields
    }
}

/// Sits between the session and the router and keeps what came back.
///
/// `ScreenContextSession` reads `AIOutput.value` and drops the provenance, so
/// this is the only place the answer to "which engine answered this frame" is
/// visible from outside the router.
final class RecordingReader: ScreenReader, @unchecked Sendable {

    private let wrapped: any ScreenReader
    private let lock = NSLock()
    private var lastOutput: AIOutput<ScreenReading?>?
    private var lastError: (any Error)?

    init(_ wrapped: any ScreenReader) {
        self.wrapped = wrapped
    }

    var output: AIOutput<ScreenReading?>? {
        lock.lock()
        defer { lock.unlock() }
        return lastOutput
    }

    var error: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return lastError
    }

    func read(_ frame: CGImage) async throws -> AIOutput<ScreenReading?> {
        do {
            let output = try await wrapped.read(frame)
            lock.lock()
            lastOutput = output
            lastError = nil
            lock.unlock()
            return output
        } catch {
            lock.lock()
            lastOutput = nil
            lastError = error
            lock.unlock()
            throw error
        }
    }
}

// MARK: - Scoring

/// The scorer `harness/score_cloud.py` runs, ported so the shipping path is
/// graded by the same rules inside the test that produces its numbers.
///
/// `ratio` is a faithful port of Python's
/// `difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()` and not a
/// stand-in for it: the bar's headline "within 90%" figure is that number, and a
/// different similarity would quietly move the line. The test cross-checks its
/// own table against `score_cloud.py` by writing `routed_outputs.json`, which
/// that script grades unchanged.
enum BarScorer {

    /// Bidi controls are invisible and the corpus is half right-to-left, so they
    /// are stripped before anything is compared. Same set as `score_cloud.py`.
    private static let bidi: Set<UInt32> = [
        0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069
    ]

    static func normalise(_ text: String?) -> String {
        let stripped = String(
            String.UnicodeScalarView((text ?? "").unicodeScalars.filter { !bidi.contains($0.value) }))
        return
            stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func similarity(_ a: String?, _ b: String?) -> Double {
        let left = Array(normalise(a).unicodeScalars)
        let right = Array(normalise(b).unicodeScalars)
        if left.isEmpty && right.isEmpty { return 1 }
        if left.isEmpty || right.isEmpty { return 0 }

        var indices: [UInt32: [Int]] = [:]
        for (j, scalar) in right.enumerated() { indices[scalar.value, default: []].append(j) }

        func longestMatch(_ alo: Int, _ ahi: Int, _ blo: Int, _ bhi: Int) -> (a: Int, b: Int, size: Int) {
            var best = (a: alo, b: blo, size: 0)
            var runs: [Int: Int] = [:]
            for i in alo..<ahi {
                var next: [Int: Int] = [:]
                for j in indices[left[i].value] ?? [] {
                    if j < blo { continue }
                    if j >= bhi { break }
                    let length = (runs[j - 1] ?? 0) + 1
                    next[j] = length
                    if length > best.size { best = (i - length + 1, j - length + 1, length) }
                }
                runs = next
            }
            return best
        }

        var matched = 0
        var pending = [(0, left.count, 0, right.count)]
        while let (alo, ahi, blo, bhi) = pending.popLast() {
            let block = longestMatch(alo, ahi, blo, bhi)
            guard block.size > 0 else { continue }
            matched += block.size
            if alo < block.a && blo < block.b { pending.append((alo, block.a, blo, block.b)) }
            if block.a + block.size < ahi && block.b + block.size < bhi {
                pending.append((block.a + block.size, ahi, block.b + block.size, bhi))
            }
        }
        return 2 * Double(matched) / Double(left.count + right.count)
    }

    struct Tally {
        var n = 0
        var message = 0
        var near = 0
        var sender = 0
        var language = 0
        var script = 0
        var traps = 0
        var ghosts = 0

        static func + (lhs: Tally, rhs: Tally) -> Tally {
            Tally(
                n: lhs.n + rhs.n, message: lhs.message + rhs.message, near: lhs.near + rhs.near,
                sender: lhs.sender + rhs.sender, language: lhs.language + rhs.language,
                script: lhs.script + rhs.script, traps: lhs.traps + rhs.traps,
                ghosts: lhs.ghosts + rhs.ghosts)
        }
    }

    static func score(
        _ entry: ScreenBar.Entry, sender: String?, message: String?, script: String?, language: String?
    )
        -> Tally
    {
        var tally = Tally()
        tally.n = 1
        let gotMessage = normalise(message)

        guard let expected = entry.expected else {
            // The deliberate nothing-to-reply-to screen: silence is the answer.
            let ok = gotMessage.isEmpty ? 1 : 0
            tally.message = ok
            tally.sender = ok
            tally.language = ok
            tally.script = ok
            return tally
        }

        let score = similarity(expected.message, message)
        if score == 1 {
            tally.message = 1
        } else if score >= 0.9 {
            tally.near = 1
        }
        if similarity(expected.sender, sender) == 1 { tally.sender = 1 }
        if language == expected.language { tally.language = 1 }
        if script == expected.script { tally.script = 1 }

        // The two failure modes the bar exists to catch, counted apart from
        // near-misses because they are not near anything.
        for trap in entry.traps where !normalise(trap.text).isEmpty && normalise(trap.text) == gotMessage {
            tally.traps += 1
        }
        for ghost in entry.notOnScreen {
            let text = normalise(ghost.text)
            // A short clipped fragment matches by accident inside any sentence;
            // only a run long enough to be evidence counts.
            if text.count >= 8 && gotMessage.contains(text) { tally.ghosts += 1 }
        }
        return tally
    }
}

// MARK: - The run

/// One row of `routed_outputs.json`. Same shape as `cloud_outputs.json` and
/// `reader_outputs.json` so `harness/score_cloud.py` grades all three unchanged,
/// plus `engine`, which is the question only this file can answer.
struct RoutedRow: Encodable {
    let id: String
    let language: String
    let config: String
    let engine: String
    let sender: String?
    let message: String?
    let detectedScript: String?
    let detectedLanguage: String?
    /// How long this frame took, for the timing line at the end of the run.
    /// **Not encoded** — see `CodingKeys`.
    let seconds: Double

    /// `seconds` is left out of the file on purpose. `routed_outputs.json` is
    /// checked in and `score_cloud.py` never reads a duration, so persisting one
    /// meant every unit-test run rewrote a tracked file with a wall-clock
    /// measurement and produced a diff that says nothing about the product. The
    /// number is still measured and still reported; it is just not a fact about
    /// the corpus.
    private enum CodingKeys: String, CodingKey {
        case id, language, config, engine, sender, message, detectedScript, detectedLanguage
    }
}
