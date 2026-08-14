import XCTest

@testable import AIKeyboardCore

/// Retired-settings and end-reason tests extracted from `CaptureChannelTests`.
final class CaptureChannelEndTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("capture-channel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    // MARK: - Settings nobody reads any more

    func testRetiredSettingsKeysAreRemoved() throws {
        let suite = "retired-keys-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "screenContextCloudReplies")
        defaults.set(true, forKey: "onDeviceAI")
        defaults.set(false, forKey: "learnsFromTyping")
        defaults.set(true, forKey: "screenContextAllowed")

        SharedStore.removeRetiredKeys(from: defaults)

        XCTAssertNil(defaults.object(forKey: "screenContextCloudReplies"))
        XCTAssertNil(defaults.object(forKey: "onDeviceAI"))
        XCTAssertNil(defaults.object(forKey: "learnsFromTyping"))
        XCTAssertNotNil(
            defaults.object(forKey: "screenContextAllowed"),
            "a key the store still reads is not debris")
    }

    func testNoRetiredKeyIsStillInUse() {
        let live = Set(
            [
                "hasCompletedOnboarding", "enabledLanguages", "autocorrect", "autocapitalise",
                "predictions", "haptics", "keySounds", "defaultTone",
                "customToneInstruction", "prefersCustomTone",
                "personalDictionary", "isSubscribed", "screenContextAllowed",
                "cloudBackendURL", "cloudBackendToken"
            ])
        XCTAssertTrue(Set(SharedStore.retiredKeys).isDisjoint(with: live))
    }

    // MARK: - End reasons
    // Pure end-reason tests live in ScreenContextEndReasonTests.swift.

    /// **The first reason wins.**
    func testASecondEndingDoesNotOverwriteTheFirstReason() throws {
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: directory))
        writer.begin()

        writer.end(.notConfigured)
        XCTAssertEqual(writer.status()?.endReason, .notConfigured)

        writer.end(.stopped)
        XCTAssertEqual(
            writer.status()?.endReason, .notConfigured,
            "a diagnosis was replaced by a shrug")

        // And a new session starts clean, so the guard cannot wedge the channel.
        writer.begin()
        XCTAssertEqual(writer.status()?.endReason, ScreenContextEndReason.notEnded)
        writer.end(.stopped)
        XCTAssertEqual(writer.status()?.endReason, .stopped)
    }

    /// **An aborted transaction must not poison the page forever.**
    func testAPageSurvivesAWriterKilledMidTransaction() throws {
        let writer = try XCTUnwrap(CaptureChannelWriter(directory: directory))
        writer.begin()
        writer.heartbeat()
        XCTAssertNotNil(
            try XCTUnwrap(CaptureChannelReader(directory: directory)).status().status,
            "sanity: a healthy page reads")

        // Abandon a transaction the way a SIGKILL does: leave the sequence odd
        // with nothing to close it. Written straight into the page's first four
        // bytes, which is where the sequence lives.
        let statusFile = directory.appendingPathComponent("status.bin")
        var bytes = try Data(contentsOf: statusFile)
        let opened = bytes.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } | 1
        withUnsafeBytes(of: opened) { bytes.replaceSubrange(0..<4, with: $0) }
        try bytes.write(to: statusFile)

        let reader = try XCTUnwrap(CaptureChannelReader(directory: directory))
        XCTAssertEqual(
            reader.status(), .unsettled,
            "a half-written page must refuse to read, not lie")

        // The next session must recover the page rather than inherit its parity.
        let recovered = try XCTUnwrap(CaptureChannelWriter(directory: directory))
        recovered.begin()
        recovered.heartbeat()
        XCTAssertNotNil(
            reader.status().status,
            "a new session must repair an aborted transaction, not inherit it forever")
    }
}
