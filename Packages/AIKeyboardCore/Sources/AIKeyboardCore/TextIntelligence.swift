import Foundation

// MARK: - Errors, the routing half

/// `AIEngineError` itself moved to `AIKeyboardShared` with the transport that
/// throws it. This is the one question about it that only a router asks, so it
/// stayed with the router.
extension AIEngineError {

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

    /// `style` is the long-press pass: proofread on a tap, spelling / punctuate /
    /// polish from the popup. An engine that cannot honour a narrower pass runs
    /// proofread rather than inventing a second prompt set.
    func fix(_ text: String, style: FixStyle) async throws -> String
    /// `instruction` is the user's own register, or nil for one of the six
    /// built-in ones. Only meaningful alongside a non-nil `tone`: Rewrite offers
    /// three different *decisions* rather than one register, and a user-authored
    /// register has nothing to say about which decision each version takes.
    ///
    /// An engine that cannot honour the instruction runs the built-in `tone`
    /// instead. It must never fold text it cannot serve into its own
    /// instructions — see `FoundationModelsEngine.variants`.
    func variants(
        for text: String, tone: ToneStyle?, instruction: String?
    ) async throws
        -> [RewriteVariant]
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

    public func fix(_ text: String, style: FixStyle = .proofread) async throws -> AIOutput<String> {
        try await route(text, .fix) { try await $0.fix(text, style: style) }
    }

    /// **The register is not part of the routing question, and that is a
    /// decision.** It is free text going into the model's *instructions*, and
    /// Apple's model rejects a whole session whose instructions are in a language
    /// it does not list — so an earlier version of this routed on the message and
    /// the register together, to keep that pair away from the on-device engine.
    /// That put the guard in the wrong place twice over: it sent an English
    /// sentence to the cloud and five seconds of latency to buy a register the
    /// cloud composer then dropped anyway, and it left the composer itself free to
    /// merge the two languages for any caller that did not route. `Prompts.tone`
    /// drops a register the chosen instruction set does not speak, so by the time
    /// an engine sees one it is already safe to run, and the message alone decides
    /// which engine that is — exactly as it does for Fix and Rewrite.
    public func variants(
        for text: String, tone: ToneStyle?, instruction: String? = nil
    ) async throws -> AIOutput<[RewriteVariant]> {
        try await route(text, tone == nil ? .rewrite : .tone) {
            try await $0.variants(for: text, tone: tone, instruction: instruction)
        }
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
