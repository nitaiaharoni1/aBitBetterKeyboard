import XCTest

/// **Where this keyboard actually draws each key, against where Apple draws it.**
///
/// `LayoutProvenanceTests` compares the shipped rows against Apple's data
/// position by position and passed for the whole time every right-to-left
/// keyboard was mirrored, because the rows were never wrong: `KeyboardView` put
/// an RTL `layoutDirection` on the letter rows and an RTL `HStack` draws its
/// first element last. Hebrew's ק, which iOS puts at the left of the top row,
/// came out at the right — and the same for Arabic, Persian, Urdu, Pashto and
/// Dhivehi. No test that reads `KeyboardLayout` can see that, because the data it
/// reads is the same either way.
///
/// So this one reads pixels. It drives the app's playground, measures the frame
/// of every key on screen, groups them into rows and sorts each row by x — the
/// order a person sees — and compares that against
/// `Bar/layouts/stock-rendered-rows.json`, which `Bar/layouts/capture-rendered.sh`
/// measured the same way off Apple's own keyboard.
///
/// English is here as the control: a "fix" that flipped every layout rather than
/// stopping the flip cannot pass.
final class RenderedRowOrderTests: XCTestCase {

    private var app: XCUIApplication!
    private var shotDirectory: URL!

    /// The committed measurement of Apple's own keyboard. Read from the checkout
    /// the way `LayoutProvenanceTests` reads `Bar/layouts/apple-layouts.json`:
    /// this runs in the simulator, but the file system it sees is this Mac's.
    private static let stockURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Bar/layouts/stock-rendered-rows.json")

    override func setUpWithError() throws {
        continueAfterFailure = true
        let path =
            ProcessInfo.processInfo.environment["SHOT_DIR"]
            ?? NSTemporaryDirectory().appending("aikeyboard-rtl")
        shotDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)

        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSkipOnboarding"]
    }

    // MARK: The test

    func testLetterRowsRenderInTheOrderAppleDrawsThem() throws {
        let stock = try stockRows()

        app.launch()
        skipOnboardingIfPresent()
        openPlayground()

        // English first, and not only as a control: it is the one layout whose
        // rendered order and data order have always agreed, so if it disagrees
        // here the measurement itself is wrong and nothing below means anything.
        capture("english")
        assertRendersLikeStock(stock["en_US"], "English", rowForRow: true)
        XCTAssertTrue(
            deleteIsOnTheRight(), "English draws delete on the left of the keyboard")
        assertCandidatesRunLeftToRight("English")

        // The globe cycles the enabled languages, which start as English, Hebrew.
        cycleLanguage()
        capture("hebrew")
        assertRendersLikeStock(stock["he_IL"], "Hebrew", rowForRow: true)
        assertCandidatesRunLeftToRight("Hebrew")
        // The claim `KeyboardLayout` used to carry was that delete "sits at the
        // trailing edge, which mirrors to the left of the screen". Apple's own
        // Hebrew keyboard puts it at the *right*, and so does its Arabic one.
        XCTAssertTrue(
            deleteIsOnTheRight(),
            "Hebrew draws delete on the left; Apple's Hebrew keyboard puts it on the right")

        try enableArabic()
        openPlayground()
        cycleLanguage(until: "key-char-ض")
        capture("arabic")
        // ة is the one key the two Arabic layouts disagree about: iOS closes its
        // home row with it, macOS closes its top row, and this keyboard follows
        // macOS. A difference in which row a key is on, not in which direction the
        // row runs — see `assertRendersLikeStock`.
        assertRendersLikeStock(stock["ar"], "Arabic", rowForRow: false, ignoring: ["ة"])
        XCTAssertTrue(
            deleteIsOnTheRight(),
            "Arabic draws delete on the left; Apple's Arabic keyboard puts it on the right")
    }

    // MARK: Measuring what is on screen

    /// Every key on screen, grouped into rows by centre y and ordered by minimum
    /// x. Identifiers rather than labels, because a shifted key relabels itself
    /// and `key-char-q` does not.
    private func renderedRows() -> [[String]] {
        let keys = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'key-'"))
            .allElementsBoundByIndex
            .map { (name: $0.identifier, frame: $0.frame) }
            .filter { $0.frame.height > 4 && $0.frame.width > 4 }
            .sorted { $0.frame.midY < $1.frame.midY }

        var rows: [[(name: String, frame: CGRect)]] = []
        for key in keys {
            if let first = rows.last?.first, abs(first.frame.midY - key.frame.midY) > key.frame.height / 2 {
                rows.append([key])
            } else if rows.isEmpty {
                rows.append([key])
            } else {
                rows[rows.count - 1].append(key)
            }
        }
        return rows.map { $0.sorted { $0.frame.minX < $1.frame.minX }.map(\.name) }
    }

    /// The three letter rows, characters only, left to right.
    ///
    /// **Not `prefix(3)`.** The action row is drawn above the letters, so the first
    /// visual row of `key-` identifiers is Emoji / Reply / Fix, which has no
    /// `key-char-` keys. Taking the first three rows would compare Apple's letters
    /// against an empty row plus two letter rows and pass a mirrored keyboard.
    /// Skip rows with no letters (the action row, the space row) and skip a
    /// digits-only number row if one is on.
    private func renderedLetterRows() -> [[String]] {
        renderedRows().compactMap { row -> [String]? in
            let letters = row.compactMap { name -> String? in
                name.hasPrefix("key-char-") ? String(name.dropFirst("key-char-".count)) : nil
            }
            guard !letters.isEmpty else { return nil }
            let digitsOnly = letters.allSatisfy { $0.count == 1 && $0.first?.isNumber == true }
            return digitsOnly ? nil : letters
        }.prefix(3).map { $0 }
    }

    /// The three suggestion slots are drawn in the same three places whatever the
    /// language is.
    ///
    /// **Measured on screen for the same reason the letter rows are.** The bar
    /// used to hand the candidates the language's own `layoutDirection`, so slot 0
    /// was drawn last on Hebrew and the three words swapped ends the instant a
    /// slide along the space bar changed language — with the word a thumb was
    /// travelling towards now at the other end of the bar. Nothing that reads
    /// `controller.suggestions` can see that: the array is in the same order
    /// either way, which is exactly the trap `RenderedRowOrderTests` exists for.
    private func assertCandidatesRunLeftToRight(_ name: String) {
        let centres = (0..<3).compactMap { slot -> CGFloat? in
            let element = element("suggestion-\(slot)")
            return element.exists ? element.frame.midX : nil
        }
        guard centres.count == 3 else {
            XCTFail("\(name) shows \(centres.count) suggestions, not three")
            return
        }
        XCTAssertEqual(
            centres, centres.sorted(),
            "\(name) draws the suggestions in reverse: slot 0 is not the leftmost")
    }

    /// True when delete is drawn on the right half of the keyboard, which is where
    /// Apple puts it in every layout measured — English, Hebrew and Arabic alike.
    private func deleteIsOnTheRight() -> Bool {
        let delete = app.descendants(matching: .any).matching(identifier: "key-backspace").firstMatch
        guard delete.exists else {
            XCTFail("no delete key on screen")
            return false
        }
        return delete.frame.midX > app.windows.firstMatch.frame.midX
    }

    // MARK: Comparing against Apple

    /// Compares what is on screen against what Apple draws.
    ///
    /// **Relative order always, row for row only where the two keyboards carry the
    /// same keys.** Mirroring is a reversal, so the assertion that catches it is
    /// about *order*, and order survives the one place these layouts genuinely
    /// differ: this keyboard's Arabic rows come from Apple's macOS `Arabic` source
    /// and are 12 / 10 / 7, while its iOS keyboard is 11 / 11 / 9 — ة sits at the
    /// end of a different row, and ء and ى are keys there rather than long
    /// presses. That is a fidelity gap of its own and it predates this; it is not
    /// a reversal, and a test that could not tell the two apart would be no use
    /// for either.
    ///
    /// `ignoring` is for keys the two keyboards put on different *rows*. It is
    /// deliberately narrow: everything not named still has to be in Apple's order,
    /// so a reversal cannot hide behind it.
    private func assertRendersLikeStock(
        _ stock: [[String]]?, _ name: String, rowForRow: Bool, ignoring moved: Set<String> = []
    ) {
        guard let stock else {
            XCTFail("\(name) is not in \(Self.stockURL.lastPathComponent)")
            return
        }
        // Apple's letters only. Its rows carry delete too, and not always on the
        // row this keyboard puts it on.
        let apple = stock.prefix(3).map { row in
            row.filter { $0.count == 1 }.map { $0.lowercased() }
        }
        let measured = renderedLetterRows()

        let shared = Set(apple.joined()).intersection(measured.joined()).subtracting(moved)
        XCTAssertGreaterThan(shared.count, 6, "\(name) shares almost no letters with Apple's rows")
        XCTAssertEqual(
            measured.joined().filter(shared.contains), apple.joined().filter(shared.contains),
            "\(name) draws the letters it shares with the stock iOS keyboard in a different order")

        if rowForRow {
            XCTAssertEqual(
                measured, apple,
                "\(name) draws its letters in a different order from the stock iOS keyboard")
        }
    }

    private func stockRows() throws -> [String: [[String]]] {
        let data = try Data(contentsOf: Self.stockURL)
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(Self.stockURL.path) is not a JSON object")
        let layouts = try XCTUnwrap(root["layouts"] as? [String: [String: Any]])
        return layouts.compactMapValues { $0["rows"] as? [[String]] }
    }

    // MARK: Driving the app

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openPlayground() {
        let card = element("home-playground")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "playground card never appeared")
        card.tap()
        XCTAssertTrue(
            element("key-space").waitForExistence(timeout: 10), "the keyboard never appeared")
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Taps the globe until the wanted key is on screen. The globe cycles the
    /// enabled languages in order, so this terminates as long as the language is
    /// enabled at all.
    private func cycleLanguage(until key: String? = nil, taps: Int = 1) {
        for _ in 0..<max(taps, 1) {
            element("key-globe").tap()
            Thread.sleep(forTimeInterval: 0.6)
            guard let key else { return }
            if element(key).exists { return }
        }
        guard let key else { return }
        for _ in 0..<8 where !element(key).exists {
            element("key-globe").tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertTrue(element(key).exists, "the globe never reached \(key)")
    }

    /// Turns Arabic on through the Languages screen, then comes back to Home.
    /// Searching first is what makes the row reachable: the catalogue is
    /// sixty-four rows grouped by script and Arabic is a long scroll down.
    private func enableArabic() throws {
        let dismiss = app.buttons["Close and go back to the keyboard"]
        if dismiss.exists { dismiss.tap() }
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 0.8)

        let tab = app.tabBars.buttons["Languages"]
        guard tab.waitForExistence(timeout: 10) else { throw XCTSkip("no Languages tab") }
        tab.tap()

        let search = element("language-search")
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the language search field is missing")
        search.tap()
        search.typeText("Arabic")
        Thread.sleep(forTimeInterval: 1.0)

        let row = app.switches["Arabic"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "no Arabic row after searching")
        if (row.value as? String) != "1" {
            // The row is one combined accessibility element, so its centre is the
            // label. The switch is at the trailing edge.
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTAssertEqual(app.switches["Arabic"].firstMatch.value as? String, "1", "Arabic is still off")

        // The search field left the system keyboard up, and it covers the tab bar.
        // This screen's scroll view dismisses it on any scroll.
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 0.8)
        app.tabBars.buttons["Home"].tap()
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func skipOnboardingIfPresent() {
        let start = app.buttons["Start typing"]
        let cont = app.buttons["Continue"]
        // Ten onboarding steps, so the bound clears ten taps rather than equalling them.
        for _ in 0..<14 {
            Thread.sleep(forTimeInterval: 0.5)
            if start.exists {
                start.tap()
                Thread.sleep(forTimeInterval: 1.0)
                return
            }
            guard cont.exists else { return }
            cont.tap()
        }
    }

    private func capture(_ name: String) {
        let url = shotDirectory.appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        print("SHOT \(url.path)")
    }
}
