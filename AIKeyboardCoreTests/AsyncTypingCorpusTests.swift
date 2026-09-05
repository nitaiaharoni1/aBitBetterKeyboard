import XCTest

@testable import AIKeyboardCore

/// Drives `Bar/typing/async/corpus.json` through the local engine and, when
/// `pauseMs` is set, through `PredictiveRefiner.standard` (on-device only).
///
/// Skips unless `ASYNC_TYPING_OUT` is set, so the ordinary suite is not a
/// model call. `Bar/typing/async/run.sh` is what sets it.
@MainActor
final class AsyncTypingCorpusTests: XCTestCase {

    func testWriteAsyncCorpusSlots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let outPath = env["ASYNC_TYPING_OUT"], !outPath.isEmpty else {
            throw XCTSkip("ASYNC_TYPING_OUT is unset")
        }
        guard let corpusPath = env["ASYNC_TYPING_CORPUS"], !corpusPath.isEmpty else {
            XCTFail("ASYNC_TYPING_CORPUS is required when ASYNC_TYPING_OUT is set")
            return
        }

        let corpus = try JSONDecoder().decode(
            CorpusFile.self, from: Data(contentsOf: URL(fileURLWithPath: corpusPath)))
        let personal = PersonalLanguageModel(url: nil)
        let engineAvailable = onDeviceEngineAvailable()

        var records: [SlotRecord] = []
        var metaEntries: [MetaEntry] = []

        for entry in corpus.entries {
            let languages = Self.languages(forKeyboard: entry.keyboard)
            let local = SuggestionEngine.suggestions(
                prefix: entry.prefix,
                context: entry.context,
                languages: languages,
                supplementary: Self.shippedPersonalDictionary,
                personal: personal)

            var slots = local
            var asyncRan = false
            if entry.pauseMs != nil {
                let language = languages[0]
                let request = PredictiveRefiner.Request(
                    textBefore: entry.context,
                    wordInProgress: entry.prefix,
                    language: language,
                    screenContext: entry.screen?.makeContext(),
                    permitted: true)
                let applied = refine(request)
                if let words = applied {
                    slots = SuggestionEngine.refinedSuggestions(
                        local: local, words: words, prefix: entry.prefix, language: language)
                    asyncRan = true
                }
            }

            let defaultIndex = slots.firstIndex(where: \.isDefault) ?? 0
            records.append(
                SlotRecord(
                    id: entry.id,
                    category: entry.category,
                    slots: slots.map(\.text),
                    defaultIndex: slots.isEmpty ? -1 : defaultIndex,
                    commits: slots.isEmpty ? entry.prefix : slots[defaultIndex].text))
            metaEntries.append(MetaEntry(id: entry.id, asyncRan: asyncRan))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let outURL = URL(fileURLWithPath: outPath)
        try encoder.encode(records).write(to: outURL)
        let metaURL = outURL.deletingPathExtension().appendingPathExtension("meta.json")
        try encoder.encode(MetaFile(engineAvailable: engineAvailable, entries: metaEntries))
            .write(to: metaURL)
    }

    private func refine(_ request: PredictiveRefiner.Request) -> [String]? {
        var applied: [String]?
        var arrived: XCTestExpectation?
        let refiner = PredictiveRefiner.standard { words, _ in
            applied = words
            arrived?.fulfill()
        }
        guard refiner.shouldRefine(request) else { return nil }
        let pending = expectation(description: "refiner apply \(request.wordInProgress)")
        pending.assertForOverFulfill = false
        arrived = pending
        refiner.refine(request)
        wait(for: [pending], timeout: 8)
        return applied
    }

    private func onDeviceEngineAvailable() -> Bool {
        if #available(iOS 26.0, *) {
            return FoundationModelsEngine().canPredict(in: .english)
        }
        return false
    }

    private static func languages(forKeyboard keyboard: String) -> [KeyboardLanguage] {
        let front: KeyboardLanguage = keyboard.hasPrefix("he") ? .hebrew : .english
        return front == .hebrew ? [.hebrew, .english] : [.english, .hebrew]
    }

    private static let shippedPersonalDictionary = [
        "Nitai", "Handi", "Wispr", "KeyboardKit", "סאפא", "בלי־פרופ"
    ]
}

private struct CorpusFile: Decodable {
    let entries: [CorpusEntry]
}

private struct CorpusEntry: Decodable {
    let id: String
    let category: String
    let keyboard: String
    let context: String
    let prefix: String
    let pauseMs: Int?
    let screen: ScreenPayload?
}

private struct ScreenPayload: Decodable {
    let appName: String
    let appIcon: String
    let sender: String
    let message: String
    let language: String

    func makeContext() -> ScreenContext {
        ScreenContext(
            appName: appName,
            appIcon: appIcon,
            sender: sender,
            message: message,
            language: language == "he" ? .hebrew : .english)
    }
}

private struct SlotRecord: Encodable {
    let id: String
    let category: String
    let slots: [String]
    let defaultIndex: Int
    let commits: String

    enum CodingKeys: String, CodingKey {
        case id, category, slots, defaultIndex = "default", commits
    }
}

private struct MetaFile: Encodable {
    let engineAvailable: Bool
    let entries: [MetaEntry]
}

private struct MetaEntry: Encodable {
    let id: String
    let asyncRan: Bool
}
