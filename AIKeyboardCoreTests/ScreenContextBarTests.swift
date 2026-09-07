import CoreGraphics
import Foundation
import ImageIO
import XCTest

@testable import AIKeyboardCore
@testable import AIKeyboardShared

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

        let shippingScore = ShippingScore()
        for entry in entries {
            try await score(
                entry, recorded: recorded, harness: harness, session: session, into: shippingScore)
        }

        session.stop()
        try assertShippingResults(
            rows: shippingScore.rows, byEngine: shippingScore.byEngine,
            byLanguage: shippingScore.byLanguage, silent: shippingScore.silent,
            disagreesWithHarness: shippingScore.disagreesWithHarness,
            returnedATrap: shippingScore.returnedATrap)
    }

    private func score(
        _ entry: ScreenBar.Entry, recorded: [String: [String: String]],
        harness: [String: ScreenBar.ReaderRow], session: ScreenContextSession, into score: ShippingScore
    ) async throws {
        let result = try await read(entry, recorded: recorded, session: session)
        verify(result, for: entry, score: score)
        record(result, for: entry, harness: harness, score: score)
    }

    private func read(
        _ entry: ScreenBar.Entry, recorded: [String: [String: String]], session: ScreenContextSession
    ) async throws -> ShippingRead {
        let frame = try ScreenBar.frame(entry.file)
        let fields = try XCTUnwrap(recorded[entry.id], "no recorded cloud answer for \(entry.id)")
        let transport = ReplayTransport(fields)
        let reader = RecordingReader(RoutedScreenReader(
            onDevice: VisionScreenReader(), cloud: CloudScreenReader(transport: transport)))
        // One session for all thirty frames, started once, exactly as a capture
        // stream would drive it. Swapping the reader only attaches this frame's
        // recorded answer.
        session.reader = reader
        if !session.isLive {
            session.start()
            XCTAssertEqual(session.state, .watching)
        }
        let started = Date()
        await session.submit(frame, appName: entry.app, appIcon: "message.fill")
        return ShippingRead(reader: reader, transport: transport, context: session.state.context,
                            seconds: Date().timeIntervalSince(started))
    }

    private func verify(_ result: ShippingRead, for entry: ScreenBar.Entry, score: ShippingScore) {
        XCTAssertNil(result.reader.error, "\(entry.id) failed outright: \(String(describing: result.reader.error))")
        // The session is the thing under test, so score what the strip would
        // render, not the reader's return value.
        if let reading = result.reader.output?.value {
            XCTAssertEqual(result.context?.sender, reading.sender, "\(entry.id) lost the sender")
            XCTAssertEqual(result.context?.message, reading.message, "\(entry.id) lost the message")
            XCTAssertEqual(result.context?.language, reading.language, "\(entry.id) lost the language")
            XCTAssertEqual(result.context?.appName, entry.app)
        } else {
            XCTAssertNil(result.context, "\(entry.id) read nothing but left a reply on screen")
            score.silent.append(entry.id)
        }
        let engine = result.transport.requests.isEmpty ? "vision" : "cloud"
        XCTAssertEqual(result.reader.output?.provenance, engine == "cloud" ? .cloud : .onDevice,
                       "\(entry.id): the transport and the provenance disagree about which engine answered")
        verifyRequest(result.transport, score: score)
    }

    private func verifyRequest(_ transport: ReplayTransport, score: ShippingScore) {
        // Recorded answers were bought with this prompt, so check the wire shape
        // once before using them as the score's baseline.
        guard let request = transport.requests.first, !score.checkedRequest else { return }
        score.checkedRequest = true
        XCTAssertEqual(request.instructions, ScreenPrompt.instructions)
        XCTAssertEqual(request.prompt, ScreenPrompt.task)
        XCTAssertEqual(request.fields.map(\.name), ["messages", "sender", "message", "script", "language"])
        guard case .screenJPEG(let jpeg) = request.payload else {
            XCTFail("screen corpus must use the screen JPEG payload")
            return
        }
        XCTAssertGreaterThan(jpeg.count, 1000)
    }

    private func record(
        _ result: ShippingRead, for entry: ScreenBar.Entry, harness: [String: ScreenBar.ReaderRow],
        score: ShippingScore
    ) {
        let reading = result.reader.output?.value
        let engine = result.transport.requests.isEmpty ? "vision" : "cloud"
        // The ground truth uses these lowercase identifiers. Keep the third
        // script case distinct, rather than collapsing it into English.
        let script = reading.map { $0.scripts.contains(.hebrew) && $0.scripts.contains(.latin) ? "mixed" : ($0.scripts.contains(.hebrew) ? "hebrew" : "latin") }
        let language = result.context.map(\.language.rawValue)
        let tally = BarScorer.score(
            entry, sender: result.context?.sender, message: result.context?.message,
            script: script, language: language)
        score.byEngine[engine] = (score.byEngine[engine] ?? BarScorer.Tally()) + tally
        score.byLanguage[entry.language] = (score.byLanguage[entry.language] ?? BarScorer.Tally()) + tally
        recordHarnessDifference(result, entry: entry, engine: engine, harness: harness, score: score)
        recordTrap(entry, message: result.context?.message, score: score)
        score.rows.append(RoutedRow(
            id: entry.id, language: entry.language, config: "routed-session", engine: engine,
            sender: result.context?.sender, message: result.context?.message, detectedScript: script,
            detectedLanguage: language, seconds: (result.seconds * 100).rounded() / 100))
    }

    private func recordHarnessDifference(
        _ result: ShippingRead, entry: ScreenBar.Entry, engine: String,
        harness: [String: ScreenBar.ReaderRow], score: ShippingScore
    ) {
        guard let row = harness[entry.id] else { return }
        // The macOS reader harness measures the same sources on a different
        // platform. Collect differences here, then name the whole set below.
        let sameGate = (engine == "vision") == row.gated
        let sameAnswer = BarScorer.normalise(result.context?.sender) == BarScorer.normalise(row.sender)
            && BarScorer.normalise(result.context?.message) == BarScorer.normalise(row.message)
        if !sameGate || (row.gated && !sameAnswer) { score.disagreesWithHarness.append(entry.id) }
    }

    private func recordTrap(_ entry: ScreenBar.Entry, message: String?, score: ShippingScore) {
        let normalised = BarScorer.normalise(message)
        // The bar's counter is exact-string matching; containment separately
        // catches a trap returned with surrounding bubble chrome.
        guard !normalised.isEmpty, entry.traps.contains(where: { trap in
            let text = BarScorer.normalise(trap.text)
            return text.count >= 8 && normalised.contains(text)
        }) else { return }
        score.returnedATrap.append(entry.id)
    }

    private final class ShippingScore {
        var rows: [RoutedRow] = []
        var byEngine: [String: BarScorer.Tally] = [:]
        var byLanguage: [String: BarScorer.Tally] = [:]
        var silent: [String] = []
        var disagreesWithHarness: [String] = []
        var returnedATrap: [String] = []
        var checkedRequest = false
    }

    private struct ShippingRead {
        let reader: RecordingReader
        let transport: ReplayTransport
        let context: ScreenContext?
        let seconds: TimeInterval
    }

    private func assertShippingResults(
        rows: [RoutedRow], byEngine: [String: BarScorer.Tally], byLanguage: [String: BarScorer.Tally],
        silent: [String], disagreesWithHarness: [String], returnedATrap: [String]
    ) throws {
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
