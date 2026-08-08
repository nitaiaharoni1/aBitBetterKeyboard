import Foundation

// The result and error types every engine answers with, in `AIKeyboardShared`
// because two of the three cross the process boundary: `BackendTransport` maps
// an HTTP status to an `AIEngineError`, and `CloudScreenReader` answers with an
// `AIOutput`, and both of those now run inside the broadcast upload extension.
// The engines themselves, the router and `TextIntelligence` stayed in
// `AIKeyboardCore`.

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
            // **The reason is the whole message, and it used to have a cause
            // stapled to it.** The sentence that lived here — "the last reading
            // is not what's on screen now" — names one of the five things
            // `CaptureFreshness` can refuse, and it was printed under all of
            // them: a session that never started, a keyboard without Full
            // Access, a broadcast iOS ended for a phone call, and, on a device
            // today, a read request nothing answered because reading inside the
            // capture process is not built. Each of those is a different thing
            // for the user to do, and four of them were told the wrong one.
            return reason.isEmpty ? "The screen wasn't read, so there was nothing to reply to." : reason
        case .failed(let detail):
            return detail.isEmpty ? "Try again." : detail
        }
    }
}
