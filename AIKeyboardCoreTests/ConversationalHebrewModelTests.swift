import Foundation
import XCTest

@testable import AIKeyboardCore

final class ConversationalHebrewModelTests: XCTestCase {
    func testTheBundledModelServesRankPrefixAndExactFollowers() throws {
        let url = try XCTUnwrap(ConversationalHebrewModel.bundledResourceURL())
        let model = try XCTUnwrap(ConversationalHebrewModel.load(at: url))

        XCTAssertNotNil(model.rank(of: "אני"))
        XCTAssertTrue(model.knows("תודה"))
        XCTAssertFalse(model.knows("מילהשאינהקיימת"))
        XCTAssertEqual(model.words(startingWith: "תוד", limit: 3), ["תודה", "תודעה"])
        XCTAssertEqual(
            Array(model.followers(after: ["אני"], limit: 6)),
            ["לא", "חושב", "רוצה", "מקווה", "יודע", "רואה"])
        XCTAssertEqual(
            Array(model.followers(after: ["אני", "לא"], limit: 3)),
            ["יודע", "רוצה", "יכול"])
    }

    func testTwoWordFollowersLeadAndOneWordFollowersFillTheTail() throws {
        let model = try XCTUnwrap(
            ConversationalHebrewModel.load(
                at: try XCTUnwrap(ConversationalHebrewModel.bundledResourceURL())))

        let followers = model.followers(after: ["ראש", "הממשלה"], limit: 10)
        XCTAssertEqual(Array(followers.prefix(3)), ["בנימין", "נתניהו", "אהוד"])
        XCTAssertEqual(Array(followers.suffix(2)), ["על", "כי"])
        XCTAssertEqual(Set(followers).count, followers.count)

        XCTAssertEqual(
            model.followers(after: ["מילהשאינהקיימת", "אני"], limit: 3),
            ["לא", "חושב", "רוצה"])
    }

    func testSurfaceLookupDoesNotManufactureACliticForm() throws {
        let model = try XCTUnwrap(
            ConversationalHebrewModel.load(
                at: try XCTUnwrap(ConversationalHebrewModel.bundledResourceURL())))

        let results = model.words(startingWith: "לתוד", limit: 8)
        XCTAssertEqual(results, ["לתודעה"])
        XCTAssertFalse(results.contains("לתודה"))
    }

    func testMissingTruncatedAndWrongVersionResourcesFailClosed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(
            ConversationalHebrewModel.load(at: directory.appendingPathComponent("missing.akn1")))

        let truncated = directory.appendingPathComponent("truncated.akn1")
        try Data("AKN1".utf8).write(to: truncated)
        XCTAssertNil(ConversationalHebrewModel.load(at: truncated))

        let source = try XCTUnwrap(ConversationalHebrewModel.bundledResourceURL())
        var bytes = try Data(contentsOf: source)
        bytes[4] = 2
        bytes[5] = 0
        let wrongVersion = directory.appendingPathComponent("wrong-version.akn1")
        try bytes.write(to: wrongVersion)
        XCTAssertNil(ConversationalHebrewModel.load(at: wrongVersion))
    }

    func testInteriorIndexCorruptionFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = try XCTUnwrap(ConversationalHebrewModel.bundledResourceURL())
        let original = try Data(contentsOf: source)

        var duplicateAlpha = original
        let alphaOffset = Int(readU32(original, at: 32 + 3 * 8))
        duplicateAlpha.replaceSubrange(
            (alphaOffset + 4)..<(alphaOffset + 8),
            with: duplicateAlpha[alphaOffset..<(alphaOffset + 4)])
        let duplicateAlphaURL = directory.appendingPathComponent("duplicate-alpha.akn1")
        try duplicateAlpha.write(to: duplicateAlphaURL)
        XCTAssertNil(ConversationalHebrewModel.load(at: duplicateAlphaURL))

        var badFollower = original
        let bigramFollowerOffset = Int(readU32(original, at: 32 + 7 * 8))
        badFollower.replaceSubrange(
            bigramFollowerOffset..<(bigramFollowerOffset + 4),
            with: [0xFF, 0xFF, 0xFF, 0xFF])
        let badFollowerURL = directory.appendingPathComponent("bad-follower.akn1")
        try badFollower.write(to: badFollowerURL)
        XCTAssertNil(ConversationalHebrewModel.load(at: badFollowerURL))
    }

    func testPurgeAndWarmRestoreTheBundledModel() {
        ConversationalHebrewModel.purge()
        ConversationalHebrewModel.warm()
        XCTAssertTrue(ConversationalHebrewModel.knows("אני"))
    }

    private func readU32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<(offset + 4)].enumerated().reduce(0) {
            $0 | UInt32($1.element) << UInt32(8 * $1.offset)
        }
    }
}
