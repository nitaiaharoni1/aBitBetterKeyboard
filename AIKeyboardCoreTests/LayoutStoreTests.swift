import XCTest

@testable import AIKeyboardCore

// MARK: - Persistence

/// Drives the decode path against a scratch suite. The singleton's own defaults
/// are the App Group plist and are nobody's fixture.
final class LayoutStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "LayoutStoreTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testAnAbsentKeyIsTheShippedDefault() {
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    func testGarbageDecodesToTheDefaultRatherThanCrashing() {
        defaults.set(Data("not json".utf8), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    /// A build that adds a new required key must not brick a keyboard saved by the
    /// build before it. The user cannot fix a keyboard that will not draw from
    /// inside the keyboard.
    func testAnInvalidStoredLayoutFallsBackToTheDefault() throws {
        var broken = KeyboardCustomization.default
        // Reach validation rather than the named-preset refresh branch.
        broken.preset = nil
        broken.bottomRow.removeAll { $0.action == .space }
        defaults.set(try JSONEncoder().encode(broken), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    /// A named preset stores identity, not a permanent snapshot. This fixture is
    /// deliberately stale but valid: the old decoder returns it unchanged, while
    /// the migration path has to replace it with today's Roomy definition.
    func testANamedPresetReloadsItsCurrentDefinition() throws {
        let current = LayoutPreset.named("roomy")!.customization
        var stale = current
        stale.geometry = .default
        XCTAssertNotEqual(stale, current, "the fixture must differ from the current preset")

        defaults.set(try JSONEncoder().encode(stale), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), current)
    }

    /// An edited layout has no preset identity and remains the user's snapshot.
    func testAValidEditedLayoutComesBackUnchanged() throws {
        var edited = LayoutPreset.named("roomy")!.customization
        edited.preset = nil
        edited.geometry = .default
        defaults.set(try JSONEncoder().encode(edited), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), edited)
    }

    /// **The gear is found wherever it sits, not in the row it used to sit in.**
    /// This rewrote `.settings` inside `cursorRow` alone, which was the whole of
    /// the truth while the action row carried the gear. Emoji and the gear then
    /// traded seats (`KeyboardCustomization.actionRow`), so the map matched
    /// nothing, the layout still held a `.settings` in `bottomRow`, and the setup
    /// tripped its own precondition — the assertion below is the one that failed,
    /// before `decodeLayout` was ever called. `replacingInternalGlobe` already
    /// runs over all four collections, so building the "old" layout the same way
    /// is what keeps this test about the migration rather than about the seating.
    /// They have since traded back, which this survived untouched: that is the
    /// whole point of asking all four rather than the one the gear happened to be
    /// in.
    func testAnEditedLayoutMigratesTheOldInternalGlobeToSettings() throws {
        var old = KeyboardCustomization.default
        old.preset = nil
        let asInternalGlobe: ([SlotSpec]) -> [SlotSpec] = { slots in
            slots.map { slot in
                guard slot.action == .settings else { return slot }
                var migrated = slot
                migrated.action = .globe
                return migrated
            }
        }
        old.barLeading = asInternalGlobe(old.barLeading)
        old.barTrailing = asInternalGlobe(old.barTrailing)
        old.bottomRow = asInternalGlobe(old.bottomRow)
        old.cursorRow = asInternalGlobe(old.cursorRow)
        let encoded =
            old.barLeading + old.barTrailing + old.bottomRow + old.cursorRow
        XCTAssertTrue(
            encoded.contains { $0.action == .globe },
            "the layout under test has to carry an internal globe, or the migration "
                + "has nothing to migrate and the assertions below pass for free")
        XCTAssertFalse(encoded.contains { $0.action == .settings })
        defaults.set(try JSONEncoder().encode(old), forKey: SharedStore.layoutKey)

        let decoded = SharedStore.decodeLayout(from: defaults)
        let slots =
            decoded.barLeading + decoded.barTrailing + decoded.bottomRow + decoded.cursorRow

        XCTAssertTrue(slots.contains { $0.action == .settings })
        XCTAssertFalse(slots.contains { $0.action == .globe })
    }

    /// **A layout missing the globe decodes fine, and that is deliberate.**
    /// Whether the key is required belongs to the device, not to the store, and
    /// `KeyboardController.apply(_:)` puts it back where that answer is known. The
    /// store used to say so by validating with `showsGlobe: false`; the validator
    /// has no globe rule left to opt out of, so there is nothing to pass.
    func testAGlobelessLayoutSurvivesTheStore() throws {
        var without = KeyboardCustomization.default
        without.preset = nil
        without.bottomRow.removeAll { $0.action == .globe }
        defaults.set(try JSONEncoder().encode(without), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), without)
    }

    /// **A layout stored before per-row heights existed keeps the keyboard it
    /// described.**
    ///
    /// The JSON here is what every shipped build wrote: one `keyHeight`, no
    /// `actionRowHeight`, no `bottomRowHeight`. Both failure modes are real and
    /// silent in opposite directions — decoding the missing keys as required
    /// throws, which drops a tuned layout back to the shipped default on the
    /// next launch, and defaulting them to `Theme.Metrics.keyHeight` reshapes a
    /// Compact keyboard's action and space rows to 43 pt behind the user's back.
    /// The rule is that a missing key means "this row matched the letters",
    /// because that is the only keyboard the old model could describe.
    ///
    /// The fixture is today's encoding with the two new keys *deleted* rather
    /// than a hand-written blob: `SlotAction` and `SlotWidth` each carry their
    /// own nested representation, so spelling a whole layout out by hand would
    /// be a second copy of the schema that goes stale on the next unrelated
    /// field. Deleting the keys reproduces exactly what an old build wrote.
    func testALayoutStoredBeforePerRowHeightsKeepsOneHeightForEveryRow() throws {
        var compact = try XCTUnwrap(LayoutPreset.named("compact")).customization
        compact.preset = nil
        let letterHeight = compact.geometry.keyHeight
        XCTAssertNotEqual(
            letterHeight, Theme.Metrics.keyHeight,
            "Compact must differ from the shipped constant, or a wrong fallback still passes")

        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(compact))
                as? [String: Any])
        var geometryJSON = try XCTUnwrap(object["geometry"] as? [String: Any])
        geometryJSON.removeValue(forKey: "actionRowHeight")
        geometryJSON.removeValue(forKey: "bottomRowHeight")
        object["geometry"] = geometryJSON

        let old = try JSONSerialization.data(withJSONObject: object)
        let geometry = try JSONDecoder().decode(KeyboardCustomization.self, from: old).geometry

        XCTAssertEqual(geometry.keyHeight, letterHeight, accuracy: 0.001)
        XCTAssertEqual(
            geometry.height(.action), letterHeight, accuracy: 0.001,
            "an old layout's action row was its letter height, not the shipped 43")
        XCTAssertEqual(
            geometry.height(.bottom), letterHeight, accuracy: 0.001,
            "an old layout's space row was its letter height, not the shipped 43")
    }

    /// **The keyboard is a second process.** `load()` fills the published copy
    /// once per launch, so a keyboard already on screen when the user taps Done
    /// has to read through `UserDefaults` again. The broken version returns the
    /// launch-time copy, so this writes *after* the read that would have cached
    /// it.
    func testTheStoredAccessorSeesAWriteMadeAfterItWasFirstRead() throws {
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
        let power = LayoutPreset.named("power")!.customization
        defaults.set(try JSONEncoder().encode(power), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), power)
    }
}
