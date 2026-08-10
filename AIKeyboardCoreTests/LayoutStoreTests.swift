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
        broken.bottomRow.removeAll { $0.action == .space }
        defaults.set(try JSONEncoder().encode(broken), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), .default)
    }

    func testAValidStoredLayoutComesBack() throws {
        let roomy = LayoutPreset.named("roomy")!.customization
        defaults.set(try JSONEncoder().encode(roomy), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), roomy)
    }

    /// **A layout missing the globe decodes fine, and that is deliberate.**
    /// Whether the key is required belongs to the device, not to the store, so the
    /// store validates with `showsGlobe: false` and
    /// `KeyboardController.apply(_:)` puts it back where the answer is known.
    func testAGlobelessLayoutSurvivesTheStore() throws {
        var without = KeyboardCustomization.default
        without.bottomRow.removeAll { $0.action == .globe }
        defaults.set(try JSONEncoder().encode(without), forKey: SharedStore.layoutKey)
        XCTAssertEqual(SharedStore.decodeLayout(from: defaults), without)
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
