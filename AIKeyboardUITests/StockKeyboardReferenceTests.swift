import XCTest

/// Photographs the **stock iOS keyboard's** suggestion bar for the sequences in
/// `Bar/typing/corpus.json`, so the AIKeyboard bar has something real to be judged
/// against. It drives Apple's own Reminders app, not this project's app.
///
/// Not part of the normal test run: it skips in well under a second unless
/// `STOCK_CAPTURE` is set, because a full capture takes tens of minutes, needs the
/// simulator prepared by `Bar/typing/setup-simulator.sh`, and depends on Apple
/// software this repo does not control. Run it through `Bar/typing/capture.sh`.
///
/// Every character is a real tap on the system keyboard, which is slow and is the
/// only thing that works. iOS keeps its own typing session; text that arrives any
/// other way never joins it. Pasting the context is not possible in Reminders at
/// all (long-pressing a row opens its context menu, never Paste), and `typeText`
/// does insert the text but leaves the suggestion bar answering for whatever was
/// tapped afterwards in isolation.
///
/// Three keys are off limits: `more` (the numbers plane), the globe (layout), and
/// shift (case). Each rebuilds the keyboard view, and on this simulator that kills
/// the test runner mid-tap and loses the rest of the run. So punctuation, digits and
/// mid-sentence capitals are unreachable, and only the code-switch retry pass sets
/// `ALLOW_LAYOUT_SWITCH` to try the globe — one entry per invocation, so a death
/// costs one entry. Every entry is claimed on disk before it is typed, so a death
/// cannot make the retry loop butt against the same entry forever.
///
/// `Bar/typing/README.md` has the rest, including why the software keyboard sits
/// off-screen unless the simulator is prepared first.
final class StockKeyboardReferenceTests: XCTestCase {

    private var app: XCUIApplication!
    private var refDir: URL!
    private var keyPoints: [String: CGPoint] = [:]

    private struct Entry {
        let id: String
        let keyboard: String
        let context: String
        let prefix: String
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        let path = ProcessInfo.processInfo.environment["REF_DIR"] ?? NSTemporaryDirectory()
        refDir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: refDir, withIntermediateDirectories: true)
        app = XCUIApplication(bundleIdentifier: "com.apple.reminders")
    }

    func testCaptureStockSuggestionBar() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipIf(
            env["STOCK_CAPTURE"] == nil,
            "Stock-keyboard capture. Run Bar/typing/capture.sh."
        )
        let corpusPath = try XCTUnwrap(env["CORPUS_PATH"], "CORPUS_PATH is required")

        var entries = try loadCorpus(corpusPath)
        if let only = env["ONLY_IDS"], !only.isEmpty {
            let wanted = Set(only.split(separator: ",").map(String.init))
            entries = entries.filter { wanted.contains($0.id) }
        }
        // A crashed runner loses the rest of the run, so a re-run picks up where the
        // last one stopped. RETRY_FAILED re-attempts entries that were recorded as
        // uncaptured; without it, only entries never reached at all are attempted,
        // which is what stops one entry that kills the runner from being retried
        // forever while the rest of the corpus waits behind it.
        let retryFailed = env["RETRY_FAILED"] == "1"
        entries = entries.filter { retryFailed ? !isCaptured($0.id) : !hasRecord($0.id) }
        print("CAPTURE-PLAN entries=\(entries.count)")
        guard !entries.isEmpty else { return }

        try openEmptyReminder()

        for entry in entries {
            // Claim the entry before touching the keyboard. If the runner dies
            // mid-entry this record survives, the next run steps over it, and the
            // manifest says plainly that nobody ever saw an answer for it.
            write(
                [
                    "id": entry.id, "status": "uncaptured",
                    "reason": "the test runner exited while this entry was being typed"
                ], for: entry.id)
            let result = capture(entry)
            write(result, for: entry.id)
            print("CAPTURE-DONE \(entry.id) \(result["status"] ?? "?") \(result["suggestions"] ?? [])")
            clearField((entry.context + entry.prefix).count)
        }
    }

    // MARK: One entry

    private func capture(_ entry: Entry) -> [String: Any] {
        var result: [String: Any] = ["id": entry.id]

        guard waitForKeyboard() else {
            return fail(&result, "the keyboard never became interactive")
        }
        // The sequence starts in whatever script its first character belongs to,
        // which for a code-switch entry is not the layout the prefix needs.
        let opening =
            (entry.context + entry.prefix).first(where: { layout(for: $0) != nil })
            .flatMap(layout(for:)) ?? entry.keyboard
        if currentKeyboard() != opening {
            guard allowLayoutSwitch, switchLayout(to: opening) == opening else {
                return fail(
                    &result,
                    "this entry opens in \(opening) but the \(currentKeyboard() ?? "no") keyboard "
                        + "is on screen, and the globe key crashes the test runner here")
            }
        }
        refreshKeyMap()
        let full = entry.context + entry.prefix
        guard !full.isEmpty else { return fail(&result, "the entry is empty") }

        // Every character is tapped. Staging the head with typeText and tapping only
        // the last character is roughly forty times faster and was tried; it is
        // wrong. iOS keeps its own typing session, and text that arrives any other
        // way never joins it — after typeText("…ten min") plus a tapped "u" the bar
        // offered “u” · unfortunately · unless, answering for a one-letter word in
        // an empty field. Tapping the whole thing gives “minu” · minutes · minute,
        // which is the question the corpus is asking.
        var skipped = ""
        for ch in full {
            switch tapKey(for: ch) {
            case .typed: continue
            case .skipped: skipped.append(ch)
            case .unavailable: return fail(&result, reasonNoKey(for: ch))
            }
        }
        Thread.sleep(forTimeInterval: 1.3)
        if !skipped.isEmpty { result["skippedCharacters"] = skipped }

        // Refuse to record a screenshot of a sequence that is not the one the corpus
        // asked for. A reference that is subtly wrong is worse than one that is
        // missing, because nothing downstream can tell.
        // Curly quotes and the corpus's straight ones are the same apostrophe here.
        let onScreen = titleField.value as? String ?? ""
        guard straighten(onScreen).hasPrefix(straighten(full)) else {
            return fail(
                &result,
                "the field ended up holding '\(onScreen)', which does not start with the "
                    + "sequence this entry asked for ('\(full)')")
        }

        let file = "\(entry.id).png"
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: refDir.appendingPathComponent(file))

        // Save the screenshot before reading anything else. Walking the keyboard's
        // accessibility tree is the most expensive thing here and the likeliest
        // place for the runner to die, and a picture with no transcription still
        // shows what the stock keyboard offered.
        result["status"] = "captured"
        result["screenshot"] = file
        result["keyboardActual"] = currentKeyboard() ?? "none"
        result["suggestions"] = [String]()
        result["note"] = "the suggestion bar was photographed but not transcribed"
        write(result, for: entry.id)

        result["fieldText"] = titleField.value as? String ?? ""
        result["suggestions"] = readSuggestionBar()
        result["note"] = nil
        return result
    }

    private func fail(_ result: inout [String: Any], _ reason: String) -> [String: Any] {
        result["status"] = "uncaptured"
        result["reason"] = reason
        // A screenshot of the failure says more than the reason string alone.
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: refDir.appendingPathComponent("\(result["id"] as? String ?? "x")-failed.png"))
        return result
    }

    // MARK: The suggestion bar

    /// The three QuickType slots, left to right on screen. iOS exposes them as
    /// unlabelled containers under one element labelled 'Typing Predictions'.
    private func readSuggestionBar() -> [String] {
        let bar = app.otherElements["Typing Predictions"].firstMatch
        guard bar.exists else { return [] }
        let width = bar.frame.width
        return
            bar.descendants(matching: .other).allElementsBoundByIndex
            .filter { !$0.label.isEmpty && $0.frame.width > 1 && $0.frame.width < width - 1 }
            .sorted { $0.frame.minX < $1.frame.minX }
            .map(\.label)
    }

    // MARK: Driving Reminders

    /// The row being typed into. Reminders keeps every row's title field in the
    /// tree, so `app.textFields["Title"]` matches several at once and throws the
    /// moment it is resolved; keyboard focus is what actually identifies ours.
    private var titleField: XCUIElement {
        let focused = app.textFields.matching(NSPredicate(format: "hasKeyboardFocus == true"))
            .firstMatch
        return focused.exists ? focused : app.textFields.matching(identifier: "Title").firstMatch
    }

    private func openEmptyReminder() throws {
        // A previous run can leave Reminders sitting on a context menu it restores on
        // activate, and then nothing is tappable. Start it from cold every time.
        app.terminate()
        Thread.sleep(forTimeInterval: 2)
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        for label in ["Not Now", "OK", "Continue"] where app.buttons[label].exists {
            app.buttons[label].tap()
            Thread.sleep(forTimeInterval: 1)
        }
        let newReminder = app.buttons["New Reminder"].firstMatch
        guard newReminder.waitForExistence(timeout: 15) else {
            throw XCTSkip("Reminders never showed its New Reminder button")
        }
        newReminder.tap()

        var top = CGFloat.greatestFiniteMagnitude
        let deadline = Date().addingTimeInterval(10)
        repeat {
            Thread.sleep(forTimeInterval: 0.5)
            top =
                app.keys.allElementsBoundByIndex
                .map(\.frame).filter { $0.height > 0 }.map(\.minY).min()
                ?? .greatestFiniteMagnitude
        } while top >= app.windows.firstMatch.frame.height && Date() < deadline

        guard top < app.windows.firstMatch.frame.height else {
            throw XCTSkip(
                "The software keyboard never came on screen (top y=\(top)). Run "
                    + "Bar/typing/setup-simulator.sh, then reboot the device if it persists.")
        }
    }

    /// Empties the field with the delete key, one coordinate tap per character.
    private func clearField(_ typed: Int) {
        guard let delete = keyPoints["delete"] else { return }
        for _ in 0..<(typed + 4) { tap(delete) }
    }

    /// True once a key is on screen and tappable — which is also how we know the
    /// paste menu has gone.
    private func waitForKeyboard(timeout: TimeInterval = 6) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let space = app.keys["space"]
            if space.exists && space.isHittable && !app.buttons["Paste"].exists { return true }
            Thread.sleep(forTimeInterval: 0.4)
        } while Date() < deadline
        return app.keys["space"].exists && app.keys["space"].isHittable
    }

    // MARK: Keys

    /// Which layout is on screen, told by a letter only that layout has.
    private func currentKeyboard() -> String? {
        if app.keys["ק"].exists { return "he_IL" }
        if app.keys["q"].exists || app.keys["Q"].exists { return "en_US" }
        return nil
    }

    private enum KeyResult {
        case typed
        /// The apostrophe, which lives on the numbers plane. iOS puts it back on the
        /// next space, which is what a person relies on: nobody opens the numbers
        /// plane to type "I'll".
        case skipped
        case unavailable
    }

    /// Taps the key for `ch`, switching layout first if the code-switch pass allows
    /// it. Keys that rebuild the keyboard view — `more`, shift, and the globe — take
    /// the test runner down with them on this simulator, so `more` and shift are
    /// never touched and the globe only under `ALLOW_LAYOUT_SWITCH`. A capital is
    /// therefore only reachable where iOS produces one itself, at the start of an
    /// empty field.
    private func tapKey(for ch: Character) -> KeyResult {
        if let point = keyPoints[keyName(for: ch)] {
            tap(point)
            return .typed
        }
        if ch == "'" { return .skipped }
        guard allowLayoutSwitch, let target = layout(for: ch), target != currentKeyboard(),
            switchLayout(to: target) == target
        else { return .unavailable }
        refreshKeyMap()
        guard let point = keyPoints[keyName(for: ch)] else { return .unavailable }
        tap(point)
        return .typed
    }

    private func straighten(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
    }

    private func keyName(for ch: Character) -> String {
        ch == " " ? "space" : String(ch).lowercased()
    }

    /// One snapshot of the whole keyboard, turned into a label-to-centre map. Every
    /// keystroke after this is a coordinate tap, which needs no element lookup —
    /// the difference between roughly three seconds per key and a fifth of a second.
    private func refreshKeyMap() {
        var points: [String: CGPoint] = [:]
        for key in app.keys.allElementsBoundByIndex where key.frame.height > 0 {
            let name = key.identifier.isEmpty ? key.label : key.identifier
            guard !name.isEmpty else { continue }
            points[name.lowercased()] = CGPoint(x: key.frame.midX, y: key.frame.midY)
        }
        keyPoints = points
    }

    private func tap(_ point: CGPoint) {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x, dy: point.y))
            .tap()
    }

    /// Only ever asked about the final character, the one that has to be a real
    /// keystroke.
    private func reasonNoKey(for ch: Character) -> String {
        if layout(for: ch) != nil {
            return "the sequence ends in '\(ch)', which is not on the \(currentKeyboard() ?? "no") "
                + "layout, and the globe key crashes the test runner on this simulator"
        }
        return "the sequence ends in '\(ch)', which lives on the numbers plane, and tapping "
            + "'more' to reach it crashes the test runner on this simulator"
    }

    private var allowLayoutSwitch: Bool {
        ProcessInfo.processInfo.environment["ALLOW_LAYOUT_SWITCH"] == "1"
    }

    private func layout(for ch: Character) -> String? {
        guard let scalar = ch.unicodeScalars.first else { return nil }
        if (0x0590...0x05FF).contains(Int(scalar.value)) { return "he_IL" }
        if String(ch).rangeOfCharacter(from: .letters) != nil { return "en_US" }
        return nil
    }

    /// Long-presses the globe and picks a layout by name. Returns what is on screen
    /// afterwards, which is not always what was asked for.
    private func switchLayout(to wanted: String) -> String? {
        let globe = app.buttons["Next keyboard"]
        guard globe.exists, globe.isHittable else { return currentKeyboard() }
        globe.press(forDuration: 1.4)
        Thread.sleep(forTimeInterval: 1.6)
        let cell = app.cells[wanted == "he_IL" ? "עברית" : "English (US)"]
        if cell.exists && cell.isHittable { cell.tap() }
        Thread.sleep(forTimeInterval: 1.8)
        return currentKeyboard()
    }

    // MARK: Output

    /// One file per entry, written as it happens, so a crash halfway through still
    /// leaves everything captured up to that point.
    private func write(_ result: [String: Any], for id: String) {
        let dir = refDir.appendingPathComponent("raw", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        else { return }
        try? data.write(to: dir.appendingPathComponent("\(id).json"))
    }

    private func record(_ id: String) -> [String: Any]? {
        let url = refDir.appendingPathComponent("raw/\(id).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func hasRecord(_ id: String) -> Bool { record(id) != nil }

    private func isCaptured(_ id: String) -> Bool {
        record(id)?["status"] as? String == "captured"
    }

    private func loadCorpus(_ path: String) throws -> [Entry] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let raw = root?["entries"] as? [[String: Any]] ?? []
        return raw.compactMap { item in
            guard let id = item["id"] as? String,
                let keyboard = item["keyboard"] as? String,
                let context = item["context"] as? String,
                let prefix = item["prefix"] as? String
            else { return nil }
            return Entry(id: id, keyboard: keyboard, context: context, prefix: prefix)
        }
    }
}
