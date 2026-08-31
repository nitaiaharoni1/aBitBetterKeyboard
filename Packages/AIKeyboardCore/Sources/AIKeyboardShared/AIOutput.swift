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
    /// The user has not explicitly allowed their requested text or audio to be
    /// processed by the cloud AI provider.
    case cloudPermissionRequired
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
        case .deviceNotSupported: return "Device not supported"
        case .unsupportedLanguage: return "Language not supported"
        case .refused: return "Can't rewrite this"
        case .inputTooLong: return "Text too long"
        case .needsFullAccess: return "Needs Full Access"
        case .cloudPermissionRequired: return "Cloud AI is off"
        // **Names a state, not a component.** "Cloud model not ready" tells the
        // owner of a keyboard that there is a cloud model, that it is a thing
        // they might be expected to have set up, and that theirs is broken. None
        // of the three is true or useful: it is filled in by attestation, there
        // is nothing to set up, and it reconnects on its own.
        case .cloudNotConfigured: return "Not connected"
        case .network: return "No connection"
        case .empty: return "Nothing came back"
        case .invented: return "Nothing safe to show"
        case .timedOut: return "Timed out"
        case .screenNotRead: return "Couldn't read the screen"
        case .failed: return "Couldn't finish"
        }
    }

    public var message: String {
        switch self {
        case .modelNotReady:
            return "Still downloading.\nTry again in a few minutes."
        case .appleIntelligenceOff:
            return "Turn on Apple Intelligence in Settings to use AI on device."
        // The three that dead-end on an unconnected app close with the same
        // sentence. Each of these used to end at "no cloud model is set up" and
        // stop, which is the whole of the Hebrew experience on a stock install:
        // every AI action fails, and none of them says what is happening.
        case .deviceNotSupported:
            return
                "This device can't run AI on device.\n\(BackendTransport.setUpRecovery)"
        case .unsupportedLanguage(let script):
            return
                "\(script.displayName) isn't supported on device.\n\(BackendTransport.setUpRecovery)"
        case .refused:
            return "The model declined this text.\nEdit it slightly and try again."
        case .inputTooLong:
            return "Select a shorter passage and try again."
        case .needsFullAccess:
            return
                "This needs network access.\nTurn on Full Access in Settings › Keyboards."
        case .cloudPermissionRequired:
            return
                "Nothing was sent. Allow cloud AI processing under aBitBetterKeyboard › Settings › Privacy first."
        case .cloudNotConfigured:
            // **The one error a fresh install actually hits.** At runtime there
            // is exactly one thing that produces this case:
            // `BackendTransport.mapped` turning a 401 or 403 into it, which means
            // the backend *answered* and turned this app away.
            //
            // **"Cloud model turned this away" described the mechanism to
            // somebody who cannot act on it.** `AppAttestation` fills this
            // build's bearer, so a 401 here means the app has not managed to
            // attest yet: no network since install, or a session token that
            // aged out. There is no field to check and no screen to visit, and
            // the app retries at launch, on foreground and on a background
            // refresh — so the whole of the useful content is the recovery line.
            return BackendTransport.setUpRecovery
        case .network(let detail):
            return detail.isEmpty ? "Couldn't connect. Check your network." : detail
        case .empty:
            return "The model returned nothing.\nTry again."
        case .invented:
            return
                "Suggestions invented a time, date or reason that wasn't in the message, so none were shown."
        case .timedOut:
            return "Timed out.\nTry again."
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
            return reason.isEmpty ? "The screen wasn't read.\nNothing to reply to." : reason
        case .failed(let detail):
            return detail.isEmpty ? "Try again." : detail
        }
    }
}
