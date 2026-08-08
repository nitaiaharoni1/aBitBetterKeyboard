import Foundation

// MARK: - Result

/// Which engine produced an answer, so the UI can be honest about what the user
/// is looking at instead of presenting every result with equal confidence.
public enum AIProvenance: Sendable, Equatable {
    case onDevice
    case cloud
    /// The on-device model answered in a language Apple does not list as
    /// supported, because no cloud engine was reachable. The answer is worth
    /// showing — the user can compare it against their original and reject it —
    /// but the UI has to say it is best effort.
    case onDeviceBestEffort

    public var isBestEffort: Bool { self == .onDeviceBestEffort }
}

public struct AIOutput<Value: Sendable>: Sendable {
    public let value: Value
    public let provenance: AIProvenance

    public init(_ value: Value, provenance: AIProvenance) {
        self.value = value
        self.provenance = provenance
    }
}

// MARK: - Errors

/// Everything that can come back instead of text. Each case carries what to put
/// on screen, because "something went wrong" is the one message the panel must
/// never show.
public enum AIEngineError: Error, Equatable, Sendable {
    /// Apple Intelligence is on but the model assets are not on disk yet. This
    /// is also what every iOS Simulator reports, where `availability` claims the
    /// model is available and generation then fails.
    case modelNotReady
    case appleIntelligenceOff
    case deviceNotSupported
    /// No engine can serve this language right now. Carries the script we saw.
    case unsupportedLanguage(TextScript)
    /// The safety guardrail rejected the input or the output. Fires on benign
    /// Hebrew slang, so it has to read as a limitation rather than an accusation.
    case refused
    case inputTooLong
    /// A keyboard extension has no network at all until the user grants Full
    /// Access, so the cloud engine cannot even be attempted.
    case needsFullAccess
    case cloudNotConfigured
    case network(String)
    /// The model answered, but with nothing usable.
    case empty
    /// Everything the model produced added something the message never said — a
    /// time, a number, a day, a promise. See `OutputGuard`. Distinct from
    /// `.empty` because the user needs to know the answer was withheld rather
    /// than missing: retrying is worth it, and trusting the next one is not.
    case invented
    /// The call did not come back. Not hypothetical: on a simulator the
    /// on-device path blocks instead of failing, and the app is killed.
    case timedOut
    /// Reply asked the capture session for a reading of the screen in front of
    /// the user and did not get one it may use. Carries the reason, because
    /// "screen context stopped when you took a call" and "the screen was not
    /// read in time" need different things from the user.
    ///
    /// Distinct from every case above because no model ran: the failure is that
    /// there was nothing safe to answer *about*. `ScreenContextSession` throws it
    /// rather than falling back on the last reading it had, which is the one
    /// thing that would put a reply about somebody else's message into the
    /// user's name.
    case screenNotRead(String)
    case failed(String)

    public var title: String {
        switch self {
        case .modelNotReady: return "Model not ready"
        case .appleIntelligenceOff: return "Apple Intelligence is off"
        case .deviceNotSupported: return "Not supported on this device"
        case .unsupportedLanguage: return "Language not supported"
        case .refused: return "Can't rewrite this one"
        case .inputTooLong: return "Text is too long"
        case .needsFullAccess: return "Full Access needed"
        case .cloudNotConfigured: return "No cloud model"
        case .network: return "No connection"
        case .empty: return "Nothing came back"
        case .invented: return "Nothing safe to suggest"
        case .timedOut: return "Took too long"
        case .screenNotRead: return "Couldn't read the screen"
        case .failed: return "Couldn't finish"
        }
    }

    public var message: String {
        switch self {
        case .modelNotReady:
            return "The on-device model is still downloading. Try again in a few minutes."
        case .appleIntelligenceOff:
            return "Turn on Apple Intelligence in Settings to use AI actions on device."
        case .deviceNotSupported:
            return "This device can't run the on-device model, and no cloud model is set up."
        case .unsupportedLanguage(let script):
            let name = script == .hebrew ? "Hebrew" : "This language"
            return
                "\(name) isn't one of the languages the on-device model supports, and no cloud model is set up."
        case .refused:
            return "The model declined this text. Editing it slightly usually gets past it."
        case .inputTooLong:
            return "Select a shorter passage and try again."
        case .needsFullAccess:
            return
                "This language needs the cloud model, which needs Full Access. Turn it on in Settings › Keyboards."
        case .cloudNotConfigured:
            return "This language needs a cloud model, and none is set up in this build."
        case .network(let detail):
            return detail.isEmpty ? "The cloud model couldn't be reached." : detail
        case .empty:
            return "The model returned an empty answer. Try again."
        case .invented:
            return
                "Every suggestion added a time, a date or a promise that wasn't in the message, so none were shown. Try again."
        case .timedOut:
            return "The model didn't answer in time. Try again."
        case .screenNotRead(let reason):
            let detail = reason.isEmpty ? "The screen wasn't read." : reason
            return "\(detail) Nothing was suggested, because the last reading is not what's on screen now."
        case .failed(let detail):
            return detail.isEmpty ? "Try again." : detail
        }
    }

    /// Whether the router should try the next engine rather than give up.
    ///
    /// Only a refusal stops here. It is a decision about the content rather than
    /// a limit of the engine, a second model will usually refuse the same text,
    /// and quietly sending refused text off the device is the wrong instinct.
    ///
    /// Everything else is worth another engine, including running out of context:
    /// the on-device model's window is small enough that Rewrite's six-field
    /// schema overflowed it on a one-line message, and the cloud model took the
    /// same input without complaint.
    var isWorthFallingBackFrom: Bool {
        switch self {
        case .refused: return false
        default: return true
        }
    }
}

// MARK: - Engine

/// One language model behind the four actions. Every call is async and can fail;
/// there is no synchronous path and no fake latency.
public protocol TextIntelligence: Sendable {
    /// Whether this engine is the right one for this text *and* this action.
    /// Asked before the call so the router can pick an engine rather than burn a
    /// round trip discovering it cannot. Action matters as much as language: an
    /// engine can be good at correcting a sentence and useless at rewriting one.
    func canHandle(_ text: String, action: AIAction) -> Bool

    func fix(_ text: String) async throws -> String
    func variants(for text: String, tone: ToneStyle?) async throws -> [RewriteVariant]
    func replies(to context: ScreenContext) async throws -> [ReplyOption]
}

// MARK: - Router

/// Sends each call to the engine that can actually serve it: on-device first for
/// the languages Apple lists, cloud for everything else.
///
/// The third branch is the one that matters for this product. Apple's on-device
/// model does not list Hebrew, and two thirds of what this keyboard is for is
/// Hebrew. When the cloud engine is missing — no key in this build, or Full
/// Access is off so the extension has no network at all — the router still runs
/// the on-device model and marks the answer `onDeviceBestEffort` so the panel can
/// say so, rather than either failing outright or passing off a guess as a fix.
public struct RoutedIntelligence: Sendable {
    private let onDevice: (any TextIntelligence)?
    private let cloud: (any TextIntelligence)?
    private let deadline: Duration

    public init(
        onDevice: (any TextIntelligence)?,
        cloud: (any TextIntelligence)?,
        deadline: Duration = .seconds(12)
    ) {
        self.onDevice = onDevice
        self.cloud = cloud
        self.deadline = deadline
    }

    /// The shipping configuration: Apple's model when the OS is new enough, and
    /// whatever cloud engine the build was given.
    public static func standard(
        cloud: (any TextIntelligence)? = nil,
        deadline: Duration = .seconds(12)
    ) -> RoutedIntelligence {
        var local: (any TextIntelligence)?
        if #available(iOS 26.0, macOS 26.0, *) {
            local = FoundationModelsEngine()
        }
        return RoutedIntelligence(onDevice: local, cloud: cloud, deadline: deadline)
    }

    public func fix(_ text: String) async throws -> AIOutput<String> {
        try await route(text, .fix) { try await $0.fix(text) }
    }

    public func variants(for text: String, tone: ToneStyle?) async throws -> AIOutput<[RewriteVariant]> {
        try await route(text, tone == nil ? .rewrite : .tone) { try await $0.variants(for: text, tone: tone) }
    }

    public func replies(to context: ScreenContext) async throws -> AIOutput<[ReplyOption]> {
        try await route(context.message, .reply) { try await $0.replies(to: context) }
    }

    private func route<Value: Sendable>(
        _ text: String,
        _ action: AIAction,
        _ call: @escaping @Sendable (any TextIntelligence) async throws -> Value
    ) async throws -> AIOutput<Value> {
        var firstFailure: AIEngineError?

        // 1. On-device, when it says it can take this language.
        if let onDevice, onDevice.canHandle(text, action: action) {
            do {
                return AIOutput(try await bounded { try await call(onDevice) }, provenance: .onDevice)
            } catch let error as AIEngineError {
                guard error.isWorthFallingBackFrom else { throw error }
                firstFailure = error
            }
        }

        // 2. Cloud, either because the language is outside the on-device model's
        //    list or because on-device just failed.
        if let cloud {
            do {
                return AIOutput(try await bounded { try await call(cloud) }, provenance: .cloud)
            } catch let error as AIEngineError {
                guard error.isWorthFallingBackFrom else { throw error }
                if firstFailure == nil { firstFailure = error }
            }
        }

        // 3. Nothing could serve it properly. Rather than show the user nothing,
        //    run the on-device model outside its supported languages and label
        //    the answer for what it is.
        if let onDevice, !onDevice.canHandle(text, action: action) {
            do {
                return AIOutput(
                    try await bounded { try await call(onDevice) }, provenance: .onDeviceBestEffort)
            } catch let error as AIEngineError {
                throw firstFailure ?? error
            }
        }

        if let firstFailure { throw firstFailure }
        // Only reachable with no engines at all: the OS is too old for Apple's
        // model and the build carries no key. Saying "no cloud model" here would
        // point at the half the user is least able to do anything about.
        throw AIEngineError.deviceNotSupported
    }

    /// Caps how long any one engine may take.
    ///
    /// This is not belt-and-braces. On a simulator the on-device call does not
    /// return an error when the model assets are missing — it blocks, the panel
    /// sits on its shimmer, and iOS kills the app. A keyboard that stops
    /// responding is a worse failure than one that says it could not finish, so
    /// every call gets a deadline and a message.
    private func bounded<Value: Sendable>(
        _ work: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw AIEngineError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw AIEngineError.timedOut }
            return first
        }
    }
}
