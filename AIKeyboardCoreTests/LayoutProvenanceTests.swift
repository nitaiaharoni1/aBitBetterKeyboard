import XCTest

@testable import AIKeyboardCore

/// **Every shipped letter row, against Apple's own data, key by key and in
/// order.**
///
/// `LanguageCatalogueTests` asks whether every letter of an alphabet is
/// *reachable*, which is the right question for a keyboard with three rows and
/// no shift plane, and it is blind to the failure that actually shipped: Czech,
/// Slovak and Hungarian went out with y and z transposed, taken from Apple's
/// `Czech – QWERTY` rather than its `Czech`. Both letters were reachable either
/// way, no identifier collided, no row overflowed, no key was in the wrong
/// script — so every check this repository had went green while a Czech speaker
/// typing `zítra` got `yítra`.
///
/// So this file compares *positions*, against an artifact rather than a memory.
/// `Bar/layouts/apple-layouts.json` is written by `Bar/layouts/harness/run.sh`
/// out of `TISCreateInputSourceList` + `UCKeyTranslate` and the iOS Simulator's
/// own `InputMode_<tag>.plist`. The claim "extracted from Apple's data" is a
/// file on disk here, not a sentence in a doc comment.
///
/// Regenerating needs macOS with the input sources installed; the harness names
/// anything it could not find rather than writing a short file quietly.
final class LayoutProvenanceTests: XCTestCase {

    // MARK: The artifact

    /// Read from the checkout, the way `ScreenContextBarTests` reads
    /// `Bar/screen-context/`: this target runs in the simulator, but the file
    /// system it sees is this Mac's.
    private static let artifactURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Bar/layouts/apple-layouts.json")

    private struct AppleLayout: Decodable {
        let id: String
        let macSource: String
        let base: [String]
        let adjacent: [String: String]
        let iosSoftwareLayouts: [String]?
        let iosHardwareLayout: String?
    }

    private struct Artifact: Decodable {
        let missing: [String]
        let languages: [AppleLayout]
    }

    private func artifact() throws -> [String: AppleLayout] {
        let data = try Data(contentsOf: Self.artifactURL)
        let decoded = try JSONDecoder().decode(Artifact.self, from: data)
        XCTAssertEqual(decoded.missing, [], "the harness could not read some layouts")
        return Dictionary(uniqueKeysWithValues: decoded.languages.map { ($0.id, $0) })
    }

    /// The snapshot covers the catalogue and nothing was skipped when it was
    /// taken. A harness that quietly wrote fewer languages than it was asked for
    /// would make everything below vacuous for the ones it dropped.
    func testTheSnapshotCoversEveryShippedLanguage() throws {
        let byID = try artifact()
        XCTAssertEqual(
            Set(byID.keys), Set(KeyboardLanguage.allCases.map(\.rawValue)),
            "the snapshot and the catalogue have drifted apart")
        for (id, entry) in byID {
            XCTAssertEqual(entry.base.count, 3, "\(id) has \(entry.base.count) rows")
            XCTAssertFalse(entry.macSource.isEmpty, "\(id) names no macOS input source")
        }
    }

    // MARK: The rows, in order

    /// **The test the transposition needed.** Take Apple's rows, remove the keys
    /// this layout deliberately drops; take the shipped rows, remove the keys it
    /// deliberately borrows; what is left has to be equal *and in the same
    /// order*. A transposition survives every set-shaped check and dies here.
    func testEveryRowMatchesApplesLayoutPositionally() throws {
        for (id, entry) in try artifact() {
            guard let language = KeyboardLanguage(rawValue: id) else {
                XCTFail("\(id) is in the snapshot and not in the catalogue")
                continue
            }
            let departure = Self.departures[id] ?? Departure(removed: [], added: [], reason: "")
            let apple = entry.base.map { strip(departure.removed, from: $0) }
            let shipped = shippedRows(language).map { strip(departure.added, from: $0) }

            XCTAssertEqual(
                shipped, apple,
                "\(id) does not match Apple's “\(entry.macSource)”: shipped \(shipped), "
                    + "Apple \(apple)"
                    + (departure.reason.isEmpty ? "" : " (allowing: \(departure.reason))"))
        }
    }

    /// Every declared departure has to be real. Without this the escape hatch is
    /// a way to make the test above pass by declaring the drift instead of
    /// fixing it: a language that no longer differs from Apple's rows must lose
    /// its entry.
    func testEveryDeclaredDepartureIsStillOneAndSaysWhy() throws {
        let byID = try artifact()
        XCTAssertEqual(
            Set(Self.departures.keys),
            [
                "french", "hindi", "italian", "macedonian", "marathi", "nepali", "portuguese",
                "serbian", "tongan", "ukrainian", "urdu"
            ],
            "the set of layouts allowed to depart from Apple's rows changed")

        for (id, departure) in Self.departures {
            guard let entry = byID[id], let language = KeyboardLanguage(rawValue: id) else {
                XCTFail("\(id) departs from a layout that is not in the snapshot")
                continue
            }
            XCTAssertFalse(departure.reason.isEmpty, "\(id) departs without saying why")
            XCTAssertNotEqual(
                shippedRows(language), entry.base,
                "\(id) no longer departs from Apple's rows; delete its entry")

            let apple = entry.base.joined()
            let shipped = shippedRows(language).joined()
            for character in departure.removed {
                XCTAssertTrue(
                    has(character, in: apple),
                    "\(id) claims to drop \(character), which Apple does not put on its rows")
                XCTAssertFalse(
                    has(character, in: shipped), "\(id) still has \(character) on a key")
            }
            for character in departure.added {
                XCTAssertTrue(has(character, in: shipped), "\(id) never picked \(character) up")
                XCTAssertFalse(
                    has(character, in: apple),
                    "\(character) is already on Apple's rows for \(id), so nothing was borrowed")
            }
        }
    }

    /// A borrowed letter says which key Apple keeps it on, and the snapshot has
    /// to actually have it there — which is what stops "Apple puts it on key 42"
    /// from being a story. On an ISO keyboard 42 closes the home row and 50 opens
    /// the bottom one, which is where these letters land.
    func testABorrowedLetterIsOnTheKeyTheSnapshotSaysItIsOn() throws {
        let byID = try artifact()
        for (id, letter, key) in [
            ("ukrainian", "ʼ", "42"), ("serbian", "ж", "42"), ("macedonian", "ж", "42"),
            ("tongan", "ʻ", "50")
        ] {
            guard let entry = byID[id] else {
                XCTFail("\(id) is missing from the snapshot")
                continue
            }
            XCTAssertEqual(
                entry.adjacent[key]?.lowercased(), letter,
                "\(id) claims \(letter) comes from key \(key); Apple has "
                    + "“\(entry.adjacent[key] ?? "nothing")” there")
        }
    }

    // MARK: What a phone does, which is not always what a Mac does

    /// **The check that settles Czech, Slovak, Hungarian and Slovene at once.**
    /// `InputMode_<tag>.plist` inside the iOS runtime says which software layout
    /// a phone uses for a language, and it is the only source here that is about
    /// phones at all.
    ///
    /// Slovene is why it is read: its file gives `Hardware.Layout = "Slovenian"`,
    /// which is QWERTY, and `SWLayouts[0] = "QWERTZ"` beside it. Apple ships one
    /// arrangement for a Mac and another for a phone, and this is a phone.
    /// Serbian in Latin script is the control — same region, same alphabet, and
    /// iOS gives it QWERTY, so the rule is not "the Balkans are QWERTZ".
    func testTheRowArrangementIsTheOneIOSUsesOnAPhone() throws {
        var checked: [String] = []
        for (id, entry) in try artifact() {
            guard let language = KeyboardLanguage(rawValue: id),
                let declared = entry.iosSoftwareLayouts?.first,
                let expected = Self.arrangement(named: declared),
                let actual = arrangement(of: shippedRows(language))
            else { continue }
            checked.append(id)
            XCTAssertEqual(
                actual, expected,
                "iOS calls \(id) “\(declared)” and this keyboard is laid out \(actual)")
        }
        XCTAssertGreaterThan(checked.count, 20, "only \(checked.count) languages were checked")
        XCTAssertTrue(checked.contains("czech"))
        XCTAssertTrue(checked.contains("slovenian"))

        // Slovene's two sources disagree in Apple's own file, so pin both halves:
        // the hardware layout it names, and the software one this follows.
        let slovene = try artifact()["slovenian"]
        XCTAssertEqual(slovene?.iosHardwareLayout, "Slovenian")
        XCTAssertEqual(slovene?.iosSoftwareLayouts?.first, "QWERTZ")
    }

    /// The transposition in isolation, on the two keys it costs. Nothing above
    /// can pass while `zítra` types as `yítra`.
    func testTheLettersACentralEuropeanTypesAreUnderTheirOwnKeys() {
        for language in [KeyboardLanguage.czech, .slovak, .hungarian, .slovenian] {
            let rows = shippedRows(language)
            let top = Array(rows[0].map(String.init))
            XCTAssertEqual(
                top.count > 5 ? top[5] : "",
                "z", "\(language.rawValue) has \(top.count > 5 ? top[5] : "nothing") where z belongs")
            XCTAssertEqual(
                rows[2].map(String.init).first, "y",
                "\(language.rawValue) starts its bottom row with "
                    + "\(rows[2].map(String.init).first ?? "nothing")")
        }
        // The families that were always right, so a fix that flipped everything
        // could not pass either.
        XCTAssertEqual(arrangement(of: shippedRows(.english)), .qwerty)
        XCTAssertEqual(arrangement(of: shippedRows(.german)), .qwertz)
        XCTAssertEqual(arrangement(of: shippedRows(.french)), .azerty)
        XCTAssertEqual(arrangement(of: shippedRows(.serbianLatin)), .qwerty)
    }

    // MARK: Helpers

    private enum Arrangement: String {
        case qwerty, qwertz, azerty
    }

    /// Which of the three families a layout belongs to, read off the two keys
    /// that separate them.
    private func arrangement(of rows: [String]) -> Arrangement? {
        let top = rows[0].map(String.init)
        guard top.count >= 6 else { return nil }
        if top[0] == "a", top[1] == "z" { return .azerty }
        guard top[0] == "q", top[1] == "w", top[4] == "t" else { return nil }
        if top[5] == "z" { return .qwertz }
        if top[5] == "y" { return .qwerty }
        return nil
    }

    /// The arrangement an iOS `SWLayouts` name stands for, or nil for the names
    /// that describe a script rather than a family (`Hebrew`, `Russian`,
    /// `Georgian-Phonetic`). `Czech-Slovak` is QWERTZ by the `QWERTY-Czech-Slovak`
    /// sitting beside it in the same list.
    private static func arrangement(named declared: String) -> Arrangement? {
        switch declared {
        case "QWERTZ", "QWERTZ-German", "QWERTZ-Albanian", "Czech-Slovak": return .qwertz
        case "AZERTY", "AZERTY-French": return .azerty
        case let name where name.hasPrefix("QWERTY"): return .qwerty
        default: return nil
        }
    }

    /// The character keys of the letters plane, one string per row, in order.
    private func shippedRows(_ language: KeyboardLanguage) -> [String] {
        KeyboardLayout.rows(for: language, plane: .letters).map { row in
            row.keys.compactMap { key -> String? in
                guard case .character(let value) = key.cap else { return nil }
                return value
            }.joined()
        }
    }

    /// Whether a row carries this character. Scalar by scalar for the same reason
    /// `strip` is: `"\u{0949}\u{0902}मनवलसय".contains("\u{0949}")` is **false**, because ॉ and
    /// the anusvara after it are one `Character`, and a membership test written
    /// the obvious way silently answers no for every Devanagari key.
    private func has(_ character: String, in text: String) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return text.unicodeScalars.contains(scalar)
    }

    /// Removes named characters from a row. Scalar by scalar, not `Character` by
    /// `Character`: a Devanagari row is mostly combining marks and `"ोे"` is one
    /// `Character`, so iterating clusters would compare the wrong things.
    private func strip(_ characters: [String], from row: String) -> String {
        guard !characters.isEmpty else { return row }
        let unwanted = Set(characters.compactMap { $0.unicodeScalars.first })
        var out = String.UnicodeScalarView()
        for scalar in row.unicodeScalars where !unwanted.contains(scalar) { out.append(scalar) }
        return String(out)
    }

    /// A layout that deliberately differs from Apple's three letter rows: what it
    /// dropped, what it borrowed from elsewhere on the same layout, and why.
    private struct Departure {
        let removed: [String]
        let added: [String]
        let reason: String
    }

    private static let departures: [String: Departure] = [
        "french": Departure(
            removed: ["ù"], added: [],
            reason: "ù closes Apple's home row and is a long press of u here, as it is on iOS"),
        "hindi": Departure(
            removed: ["\u{093C}"], added: ["\u{0949}", "\u{0943}"],
            reason:
                "the nukta closes Apple's top row and rides on ड here; ॉ and ृ are on keys a "
                + "phone has no column for and earn their own, because कृपया needs ृ"),
        "marathi": Departure(
            removed: ["\u{093C}"], added: ["\u{0949}", "\u{0943}"],
            reason: "the Devanagari InScript layout, shared with Hindi"),
        "nepali": Departure(
            removed: ["\u{093C}"], added: ["\u{0949}", "\u{0943}"],
            reason: "the Devanagari InScript layout, shared with Hindi"),
        "ukrainian": Departure(
            removed: [], added: ["ʼ"],
            reason: "ʼ is a letter of the alphabet and Apple keeps it on key 42"),
        "serbian": Departure(
            removed: [], added: ["ж"],
            reason: "ж is on key 42, which on an ISO keyboard closes the home row"),
        "macedonian": Departure(
            removed: [], added: ["ж"],
            reason: "ж is on key 42, which on an ISO keyboard closes the home row"),
        "tongan": Departure(
            removed: [], added: ["ʻ"],
            reason: "ʻ is on key 50, which on an ISO keyboard opens the bottom row"),
        "italian": Departure(
            removed: ["è", "ò", "à"], added: [],
            reason:
                "Apple's Italian layout gives the three accented vowels keys of their own; iOS "
                + "does not, and neither does this — they are long presses of e, o and a"),
        "portuguese": Departure(
            removed: ["º"], added: [],
            reason:
                "º is the masculine ordinal indicator, which Unicode files as a letter and "
                + "Portuguese does not spell with"),
        "urdu": Departure(
            removed: ["\u{064E}", "\u{064F}"], added: [],
            reason: "Apple's last two top-row keys are bare harakat, which Urdu does not write")
    ]
}
