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
private final class ReplayTransport: CloudTransport, @unchecked Sendable {

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
private final class RecordingReader: ScreenReader, @unchecked Sendable {

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
private struct RoutedRow: Encodable {
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

/// Drives all thirty bar frames through the shipping path.
///
/// Not through a copy of it: the frame goes into
/// `ScreenContextSession.submit(_:appName:appIcon:)`, which hands it to
/// `RoutedScreenReader`, which tries the real `VisionScreenReader` and falls
/// back to the real `CloudScreenReader` — real prompt, real JPEG encoding, real
/// parsing. Only the network is replaced, by a transport replaying the answers
/// `harness/vertex_vision.py` recorded in `cloud_outputs.json`.
///
/// The number this produces does not exist anywhere else. `run-reader.sh` scores
/// Vision alone, `vertex_vision.py` scores the cloud alone, and the product
/// ships the composition of the two.
@MainActor
final class ScreenContextBarTests: XCTestCase {

    override func tearDown() async throws {
        ScreenContextSession.shared.stop()
        ScreenContextSession.shared.reader = nil
    }

    func testTheShippingPathScoresTheBar() async throws {
        let entries = try ScreenBar.entries()
        let recorded = try ScreenBar.recordedCloudFields()
        let harness = try ScreenBar.recordedReaderRows()
        XCTAssertEqual(entries.count, 30)

        let session = ScreenContextSession.shared
        session.stop()

        var rows: [RoutedRow] = []
        var byEngine: [String: BarScorer.Tally] = [:]
        var byLanguage: [String: BarScorer.Tally] = [:]
        var silent: [String] = []
        var disagreesWithHarness: [String] = []
        var returnedATrap: [String] = []
        var checkedRequest = false

        for entry in entries {
            let frame = try ScreenBar.frame(entry.file)
            let fields = try XCTUnwrap(recorded[entry.id], "no recorded cloud answer for \(entry.id)")
            let transport = ReplayTransport(fields)
            let reader = RecordingReader(
                RoutedScreenReader(
                    onDevice: VisionScreenReader(),
                    cloud: CloudScreenReader(transport: transport)))

            // One session for all thirty frames, started once, exactly as a
            // capture stream would drive it. Swapping the reader between frames
            // is only how the recorded answer for this frame is attached.
            session.reader = reader
            if !session.isLive {
                session.start()
                XCTAssertEqual(session.state, .watching)
            }

            let started = Date()
            await session.submit(frame, appName: entry.app, appIcon: "message.fill")
            let seconds = Date().timeIntervalSince(started)

            XCTAssertNil(reader.error, "\(entry.id) failed outright: \(String(describing: reader.error))")
            let reading = reader.output?.value
            let provenance = reader.output?.provenance

            // The session is the thing under test, so the score is read off the
            // state the strip would render, not off the reader's return value.
            let context = session.state.context
            if let reading {
                XCTAssertEqual(context?.sender, reading.sender, "\(entry.id) lost the sender")
                XCTAssertEqual(context?.message, reading.message, "\(entry.id) lost the message")
                XCTAssertEqual(context?.language, reading.language, "\(entry.id) lost the language")
                XCTAssertEqual(context?.appName, entry.app)
            } else {
                XCTAssertNil(context, "\(entry.id) read nothing but left a reply on screen")
                silent.append(entry.id)
            }

            let engine = transport.requests.isEmpty ? "vision" : "cloud"
            XCTAssertEqual(
                provenance, engine == "cloud" ? .cloud : .onDevice,
                "\(entry.id): the transport and the provenance disagree about which engine answered")

            // What the shipping path would put on the wire, checked once: the
            // recorded answers were bought with this prompt, so a drift here
            // would make every number below a number for a different call.
            if let request = transport.requests.first, !checkedRequest {
                checkedRequest = true
                XCTAssertEqual(request.instructions, ScreenPrompt.instructions)
                XCTAssertEqual(request.prompt, ScreenPrompt.task)
                XCTAssertEqual(
                    request.fields.map(\.name), ["messages", "sender", "message", "script", "language"])
                XCTAssertEqual(request.image?.mimeType, "image/jpeg")
                XCTAssertGreaterThan(request.image?.data.count ?? 0, 1000)
            }

            let script = reading.map {
                $0.scripts.contains(.hebrew) && $0.scripts.contains(.latin)
                    ? "mixed" : ($0.scripts.contains(.hebrew) ? "hebrew" : "latin")
            }
            let detectedLanguage = context.map { $0.language == .hebrew ? "hebrew" : "english" }

            let tally = BarScorer.score(
                entry, sender: context?.sender, message: context?.message,
                script: script, language: detectedLanguage)
            byEngine[engine] = (byEngine[engine] ?? BarScorer.Tally()) + tally
            byLanguage[entry.language] = (byLanguage[entry.language] ?? BarScorer.Tally()) + tally

            // The on-device half has recorded numbers of its own, written by
            // `harness/run-reader.sh` from the same sources — on macOS. Where
            // this run disagrees with that file, the two are not measuring the
            // same product, and the difference is collected rather than asserted
            // per frame so the whole set can be named at the end.
            if let harnessRow = harness[entry.id] {
                let sameGate = (engine == "vision") == harnessRow.gated
                let sameAnswer =
                    BarScorer.normalise(context?.sender) == BarScorer.normalise(harnessRow.sender)
                    && BarScorer.normalise(context?.message) == BarScorer.normalise(harnessRow.message)
                if !sameGate || (harnessRow.gated && !sameAnswer) {
                    disagreesWithHarness.append(entry.id)
                }
            }

            // The bar's own trap counter is an exact-string check, so a trap
            // returned with a bubble timestamp glued to it scores as a plain
            // near-miss. Containment is counted alongside it, because "returned
            // the trap plus chrome" is the same failure as "returned the trap".
            let normalised = BarScorer.normalise(context?.message)
            if !normalised.isEmpty,
                entry.traps.contains(where: {
                    let text = BarScorer.normalise($0.text)
                    return text.count >= 8 && normalised.contains(text)
                })
            {
                returnedATrap.append(entry.id)
            }

            rows.append(
                RoutedRow(
                    id: entry.id, language: entry.language, config: "routed-session",
                    engine: engine, sender: context?.sender, message: context?.message,
                    detectedScript: script, detectedLanguage: detectedLanguage,
                    seconds: (seconds * 100).rounded() / 100))
        }

        session.stop()
        XCTAssertEqual(rows.count, 30)

        try write(rows)
        report(
            rows: rows, byEngine: byEngine, byLanguage: byLanguage, silent: silent,
            disagreesWithHarness: disagreesWithHarness, returnedATrap: returnedATrap)

        let total = byLanguage.values.reduce(BarScorer.Tally(), +)

        // The routed score, measured on the simulator, which is the only place
        // the on-device half runs the way a phone runs it. Lower bounds rather
        // than equalities so an improvement does not read as a break.
        //
        // Every one of these is still *below* the cloud reader alone (30/30
        // sender, 30/30 language, 18/30 exact, 25/30 near against the same
        // recording), and that is the headline finding of this file rather than a
        // rounding error: on iOS, routing through `VisionScreenReader` costs 3
        // points of sender and 2 of exact message against simply asking the
        // cloud. Both sides replay one recording, so the comparison survives the
        // model drift the absolute numbers do not. The eight screens it
        // still answers include three it answers wrongly. See `disagreesWithHarness`.
        XCTAssertGreaterThanOrEqual(total.sender, 26, "sender fell below the measured routed score")
        XCTAssertGreaterThanOrEqual(
            total.language, 28, "keyboard language fell below the measured routed score")
        XCTAssertGreaterThanOrEqual(total.message, 16, "exact message fell below the measured routed score")
        XCTAssertGreaterThanOrEqual(
            total.message + total.near, 24, "message-within-90% fell below the measured routed score")

        // The bar's own trap and off-screen counters, ported exactly. They stay
        // at zero — and that is not the whole story, see `returnedATrap` below.
        XCTAssertEqual(total.traps, 0, "the shipping path returned a chrome string listed under traps")
        XCTAssertEqual(total.ghosts, 0, "the shipping path returned text the bar measured as off screen")

        // **Deviation 1: iOS and the macOS harness do not read the same screens
        // the same way.** `harness/run-reader.sh` compiles the very same reader
        // sources, and on macOS it accepts 9 of 30 and answers 5, all 5 right.
        // Run on the simulator it accepts 10 and answers 8, and the two extra
        // answers plus `ml-01` are wrong. `ml-01` is a gate difference (macOS
        // measures mean confidence 0.896, just under the 0.90 threshold; the
        // simulator clears it); `wa-07` and `sl-05` pass the gate on both and
        // differ in what the recogniser put on the page. Vision does not ship
        // the same behaviour on both platforms, which is the assumption
        // `run-reader.sh` is written on.
        XCTAssertEqual(
            disagreesWithHarness, ["wa-07", "sl-01", "sl-03", "sl-05", "ml-01"],
            "the set of screens where iOS and the macOS harness disagree has moved")

        // **Deviation 2: the zero above is an exact-match zero.** Three answers
        // contain one of the bar's named traps with something else glued on, so
        // `score_cloud.py` files them as ordinary near-misses:
        //
        //   wa-07  "hey are you around? 13:40" — the trap "hey are you around?"
        //          (a message the user already answered) plus the bubble
        //          timestamp, on the one screen whose correct answer is silence
        //   ml-01  the quoted history the user wrote themselves
        //   ml-02  the correct message with the signature block appended — a
        //          cloud answer, so this one is in `cloud_outputs.json` too and
        //          the published "no traps" applies to it as well
        //
        // `sl-05`'s "X n m C V Z" is keyboard key caps but not the *same* key
        // caps the trap lists, so containment misses it. Widening the bar's own
        // check is a decision for the bar, not for this test, which ports it
        // exactly and counts the containment separately.
        XCTAssertEqual(
            returnedATrap, ["wa-07", "ml-01", "ml-02"],
            "the set of answers that contain one of the bar's traps has moved")

        XCTAssertEqual(
            byEngine["vision"]?.n, 8, "the on-device gate accepted a different number of screens")
        XCTAssertEqual(byEngine["cloud"]?.n, 22)
        XCTAssertEqual(ScreenContextSession.shared.framesRead, 0, "stop() resets the counter")
    }

    /// **A reader that cannot see must not answer "nothing is there".**
    ///
    /// `sl-01` and `sl-03` are English Slack screens whose newest incoming
    /// message is plain, readable and answerable. `VisionScreenReader` passes
    /// its readability gate on both, then cannot place a sender because a
    /// one-sided layout leaves no geometry to say who sent what.
    ///
    /// It used to express that by returning nil, which `RoutedScreenReader`
    /// reads as a finished answer meaning "no message on this screen". The cloud
    /// was never asked, and the user was offered nothing on two screens the
    /// product could answer. The two refusals are now distinct: nil still means
    /// *nothing worth replying to* (a voice note), while a layout it cannot read
    /// throws `.notReadableOnDevice` and becomes a cloud call.
    ///
    /// Worth 2 points of sender, 2 of keyboard language and 2 of exact message
    /// on the bar, and two screens that went from silent to correct.
    func testAnUnreadableLayoutBecomesACloudCallRatherThanSilence() async throws {
        let entries = try ScreenBar.entries()
        let recorded = try ScreenBar.recordedCloudFields()
        let session = ScreenContextSession.shared

        for identifier in ["sl-01", "sl-03"] {
            let entry = try XCTUnwrap(entries.first { $0.id == identifier })
            let transport = ReplayTransport(try XCTUnwrap(recorded[identifier]))
            session.stop()
            session.reader = RoutedScreenReader(
                onDevice: VisionScreenReader(), cloud: CloudScreenReader(transport: transport))
            session.start()

            await session.submit(try ScreenBar.frame(entry.file), appName: entry.app, appIcon: "number")

            XCTAssertFalse(
                transport.requests.isEmpty,
                "\(identifier): a layout the on-device reader cannot read must reach the cloud")
            let context = try XCTUnwrap(
                session.state.context,
                "\(identifier) is answerable and the user must be offered something")
            XCTAssertEqual(context.message, recorded[identifier]?["message"])
            XCTAssertEqual(context.sender, recorded[identifier]?["sender"])
        }
        session.stop()
    }

    // MARK: - Reporting

    /// Writes the file `score_cloud.py` grades. Every field in it is a fact about
    /// the corpus, so a run that changes nothing rewrites the same bytes; see
    /// `RoutedRow.CodingKeys` for the one field that is deliberately absent.
    private func write(_ rows: [RoutedRow]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = ScreenBar.root.appendingPathComponent("routed_outputs.json")
        try encoder.encode(rows).write(to: url)
        print("wrote \(rows.count) routed results to \(url.path)")
    }

    private func report(
        rows: [RoutedRow], byEngine: [String: BarScorer.Tally],
        byLanguage: [String: BarScorer.Tally], silent: [String],
        disagreesWithHarness: [String], returnedATrap: [String]
    ) {
        func line(_ label: String, _ t: BarScorer.Tally) -> String {
            String(
                format: "%-9@ %3d  %3d/%-3d %5d  %3d/%-3d %3d/%-3d %5d %6d",
                label as NSString, t.n, t.message, t.n, t.near, t.sender, t.n, t.language, t.n, t.traps,
                t.ghosts)
        }

        print("\nROUTED — ScreenContextSession + RoutedScreenReader over Bar/screen-context/")
        print("bucket      n  message  +near  sender    lang traps ghosts")
        print(String(repeating: "-", count: 58))
        for bucket in ["english", "mixed", "hebrew"] where byLanguage[bucket] != nil {
            print(line(bucket, byLanguage[bucket]!))
        }
        print(String(repeating: "-", count: 58))
        print(line("ALL", byLanguage.values.reduce(BarScorer.Tally(), +)))

        print("\nby engine")
        for engine in ["vision", "cloud"] where byEngine[engine] != nil {
            print(line(engine, byEngine[engine]!))
        }

        let onDevice = rows.filter { $0.engine == "vision" }
        print("\nanswered on device:  \(onDevice.map(\.id).joined(separator: " "))")
        print("no reply offered:    \(silent.joined(separator: " "))")
        print("disagrees with the macOS harness: \(disagreesWithHarness.joined(separator: " "))")
        print("answer contains a trap:           \(returnedATrap.joined(separator: " "))")

        let seconds = onDevice.map(\.seconds).sorted()
        print(
            String(
                format: "on-device read time over %d frames: median %.2fs  p90 %.2fs  max %.2fs",
                seconds.count, seconds[seconds.count / 2],
                seconds[min(seconds.count - 1, Int(Double(seconds.count) * 0.9))], seconds.last ?? 0))
    }
}
