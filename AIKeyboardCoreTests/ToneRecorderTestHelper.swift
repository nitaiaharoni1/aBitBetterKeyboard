import XCTest

@testable import AIKeyboardCore

/// Shared test double used by `DefaultToneTests` and `DefaultToneSettingsTests`.
final class ToneRecorder: TextIntelligence, @unchecked Sendable {

    private let lock = NSLock()
    private var recordedSources: [String] = []
    private var recordedTones: [ToneStyle?] = []
    private var recordedInstructions: [String?] = []
    private var fixes = 0
    private var released = true

    var failure: AIEngineError?
    var answer = "rewritten"

    var sources: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedSources
    }
    var tones: [ToneStyle?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTones
    }
    var instructions: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return recordedInstructions
    }
    var fixCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fixes
    }
    var variantCount: Int { tones.count }

    /// Hold the next call open until `release()`, so a second tap lands while the
    /// first is genuinely still in flight.
    func hold() {
        lock.lock()
        released = false
        lock.unlock()
    }
    func release() {
        lock.lock()
        released = true
        lock.unlock()
    }
    private var isReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        return released
    }

    func canHandle(_ text: String, action: AIAction) -> Bool { true }

    func fix(_ text: String) async throws -> String {
        lock.lock()
        fixes += 1
        lock.unlock()
        if let failure { throw failure }
        return text
    }

    func variants(
        for text: String, tone: ToneStyle?, instruction: String?
    ) async throws
        -> [RewriteVariant]
    {
        lock.lock()
        recordedSources.append(text)
        recordedTones.append(tone)
        recordedInstructions.append(instruction)
        lock.unlock()

        // Bounded, so a mistake in a test times out rather than wedging the suite.
        let deadline = Date().addingTimeInterval(5)
        while !isReleased, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        if let failure { throw failure }
        return [RewriteVariant(tone: tone ?? .clearer, text: answer)]
    }

    func replies(to context: ScreenContext) async throws -> [ReplyOption] { [] }
}

/// `SharedStore.init` is private and the singleton is the App Group plist, so
/// there is no scratch instance to build. Every test that writes a setting puts it
/// back.
/// Shared by `DefaultToneTests` and `DefaultToneSettingsTests`.
struct ToneSettings {
    let tone: ToneStyle
    let prefersCustom: Bool
    let custom: String

    static func snapshot() -> ToneSettings {
        let store = SharedStore.shared
        return ToneSettings(
            tone: store.defaultTone,
            prefersCustom: store.prefersCustomTone,
            custom: store.customTone
        )
    }

    func restore() {
        let store = SharedStore.shared
        store.defaultTone = tone
        store.prefersCustomTone = prefersCustom
        store.customTone = custom
    }
}
