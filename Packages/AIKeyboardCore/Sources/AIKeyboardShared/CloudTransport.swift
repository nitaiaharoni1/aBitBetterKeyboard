import Foundation

// The wire format and the one transport that ships, in `AIKeyboardShared`
// because there are now two producing processes. The keyboard sends text
// through `CloudIntelligence`; the broadcast upload extension sends one
// downscaled frame through `CloudScreenReader`. Both go to the same backend
// with the same field encoding, and a second copy of that encoding in the
// capture target would drift from the one the bar scores.

// MARK: - Transport

/// One field the model must fill in. Mirrors an `@Guide` on the on-device path,
/// so both engines are driven by the same prompts and the same output shape.
public struct CloudField: Sendable {
    public let name: String
    public let description: String
    /// Sub-fields, when this field is a list of objects rather than one string.
    ///
    /// Only the screen reader uses this. **The enumeration is load-bearing; this
    /// nesting is not, and this comment used to claim otherwise.** Making the
    /// model list every message bubble before naming one is what stops it
    /// answering a message three positions above the newest — dropping the list
    /// costs 2 points of sender, 3 of keyboard language and four near-misses, and
    /// introduces a trap (`Bar/screen-context/ablation/enumerate.json`).
    ///
    /// Whether that list arrives as a nested array or as a JSON string in a plain
    /// field is a different question, and the honest answer is that it does not
    /// measurably matter. This comment said flattening cost 7 points of message
    /// accuracy and 3 of sender. Re-measured with both sides run in one sitting,
    /// the nested form scores 28 sender against the flat form's 29 — a point
    /// *worse*, inside a noise floor of ±1
    /// (`Bar/screen-context/ablation/flatten.json` against
    /// `size-encoder/scale2-jpeg.json`). Keep the nesting if you like it; do not
    /// defend it with a number.
    public let items: [CloudField]?

    public init(_ name: String, _ description: String, items: [CloudField]? = nil) {
        self.name = name
        self.description = description
        self.items = items
    }
}

/// An image travelling with a request. Screen reading is the only caller.
public struct CloudImage: Sendable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String = "image/jpeg") {
        self.data = data
        self.mimeType = mimeType
    }
}

/// A recording travelling with a request. Dictation is the only caller.
///
/// **Not folded into `CloudImage` as a general "media" type**, though the wire
/// shape is identical and the temptation is real. They are separated because
/// they go to different endpoints, and they go to different endpoints because a
/// picture of somebody's screen and a recording of their voice deserve different
/// retention rules on the backend. Collapsing them here is what would quietly
/// make that one rule.
public struct CloudAudio: Sendable {
    public let data: Data
    public let mimeType: String

    /// 16 kHz mono LEI16 WAV by default, which is what `Bar/dictation/` is
    /// recorded at and therefore what every published number was measured on.
    public init(data: Data, mimeType: String = "audio/wav") {
        self.data = data
        self.mimeType = mimeType
    }
}

public struct CloudRequest: Sendable {
    public let instructions: String
    public let prompt: String
    public let fields: [CloudField]
    public let image: CloudImage?
    public let audio: CloudAudio?

    public init(
        instructions: String,
        prompt: String,
        fields: [CloudField],
        image: CloudImage? = nil,
        audio: CloudAudio? = nil
    ) {
        self.instructions = instructions
        self.prompt = prompt
        self.fields = fields
        self.image = image
        self.audio = audio
    }
}

/// The network half of the cloud engine, split out so the routing, prompting and
/// parsing above it can be tested without a key or a connection.
public protocol CloudTransport: Sendable {
    func send(_ request: CloudRequest) async throws -> [String: String]
}

// MARK: - Recovering from a rejected session token

/// A hook `BackendTransport.send` calls when a model route answers 401
/// despite a session token being sent: mint, or re-read, a fresher one for
/// exactly one retry of the request that failed.
///
/// **Only the containing app can conform to this for real.** App Attest binds
/// an attestation to one bundle ID, the keyboard and the broadcast extension
/// carry different ones from the app, and neither runs `DCAppAttestService`
/// at all — `AppAttestation` (in the app target) is the one conformer, and it
/// registers itself with `SessionReattestation.shared` the first time it
/// runs, which happens at launch before any AI action can be attempted. A
/// transport built in either extension finds nothing registered and answers
/// the 401 honestly rather than retrying into nothing — see
/// `BackendTransport.send`.
public protocol SessionReattestor: Sendable {
    /// The fresh bearer to retry with, or nil when re-attestation itself
    /// failed (offline, Apple refused, the service refused it again) or
    /// produced nothing to send.
    func reattest() async -> String?
}

/// Coordinates recovery from a 401 that arrives despite a session token
/// existing, one process at a time.
///
/// **An actor, because the failure NIT-87 measured is concurrency.** Device
/// traffic showed bursts of 14 and 17 calls landing 401 within seconds of
/// each other from one process — a burst of retries against a failing auth,
/// not independent losses. Without serialising through here, each call would
/// ask `reattest()` on its own, which spends Apple's per-device attestation
/// allowance on a burst rather than on the one retry this exists to make.
/// `reattest()` runs the registered conformer at most once no matter how many
/// callers arrive while it is in flight, and every caller sees the same
/// result.
public actor SessionReattestation {
    public static let shared = SessionReattestation()

    private var conformer: (any SessionReattestor)?
    private var inFlight: Task<String?, Never>?

    private init() {}

    /// Called by whichever process can actually attest. Left unset in both
    /// extensions.
    public func register(_ reattestor: any SessionReattestor) {
        conformer = reattestor
    }

    /// Nil immediately, with no attempt at all, when nothing is registered —
    /// the honest answer in both extensions, which cannot mint a token for
    /// this app no matter how many times they ask.
    public func reattest() async -> String? {
        guard let conformer else { return nil }
        if let inFlight { return await inFlight.value }
        let task = Task { await conformer.reattest() }
        inFlight = task
        defer { inFlight = nil }
        return await task.value
    }
}

// MARK: - Backend transport

/// The shipping cloud path: the app talks to the product's own backend, and the
/// backend talks to whichever model provider it is configured for.
///
/// The app deliberately holds no provider credential. A keyboard extension
/// cannot safely carry a Vertex service account or an API key — anything in the
/// bundle is extractable — so the only honest shape is a backend that owns the
/// credential and exposes one narrow endpoint. That also makes the provider a
/// backend decision: swapping Gemini for Claude changes nothing here.
public struct BackendTransport: CloudTransport {
    /// Internal so `BackendTransport+Send` can reach them after the send path
    /// moved into its own file.
    let baseURL: URL
    let token: String?
    let session: URLSession

    public init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    /// The backend this build ships pointing at, used whenever the user has not
    /// named one of their own.
    ///
    /// **A URL is not a credential, and that is the whole reason this can be here
    /// while `cloudBackendToken` cannot.** Everything in a bundle is extractable,
    /// so the rule this file is built around is that no *secret* ships. An address
    /// is not one: the service behind it refuses every request that arrives without
    /// the bearer token (`Backend/src/gate.js`), so a copy of this string buys an
    /// attacker a 401 and nothing else. The token stays typed in, in
    /// `CloudModelView`, exactly as before.
    ///
    /// Deployed 2026-08-10 to Cloud Run in `handi-project`, `europe-west1`, from
    /// `Backend/deploy.sh`. Before that date this constant did not exist and
    /// `configured()` returned nil on every stock install, so Hebrew Fix, Rewrite,
    /// Tone and Reply had nowhere to run and failed for the life of the install —
    /// see `KeyboardController.init`.
    public static let bundledDefaultURL = "https://aikeyboard-backend-cq6zxsdx5a-ew.a.run.app"

    /// The transport this process should use, or nil when there is nowhere to send.
    ///
    /// **Nil is now much rarer than it was, and reaching it takes a deliberate
    /// act.** A stored value wins; absent *or* empty falls back to
    /// `bundledDefaultURL`. So clearing the field in `CloudModelView` means "put
    /// the built-in server back", not "switch the cloud off" — there is no off
    /// switch here and deliberately no dead state either, because the alternative
    /// is a user who empties the box and can only recover by retyping a 52-character
    /// URL they were never shown. What still returns nil is a stored value that is
    /// not an http(s) URL, which is the case the screen refuses to save in the first
    /// place.
    ///
    /// Reads the **shared** store, not `.standard`. The app writes this setting
    /// and two extensions read it, and `.standard` in an extension is that
    /// process's own private container: the URL set in the app would never
    /// arrive, and the keyboard would report "no cloud model" for a backend that
    /// was configured. That failure is invisible from the app side, which is
    /// what made it worth a named default rather than a comment.
    ///
    /// `SharedContainer.userDefaults` rather than `SharedStore.shared`, which is
    /// the same store reached without `Combine`, `Feedback` or any of
    /// `AIKeyboardCore`: the third caller is now the broadcast upload extension,
    /// which reads this setting to reach the backend and must not link that
    /// target.
    public static func configured(
        defaults: UserDefaults = SharedContainer.userDefaults
    ) -> BackendTransport? {
        guard let url = URL(string: effectiveURL(defaults: defaults)),
            url.scheme?.hasPrefix("http") == true
        else { return nil }
        return BackendTransport(baseURL: url, token: storedToken(defaults))
    }

    /// The address a call would actually go to: the one the user named, or the one
    /// that ships when they have not named one.
    ///
    /// **One spelling of the fallback, because it briefly had three.** This rule
    /// also decides what `CloudModelView` puts in its field and what its status
    /// line claims, and a getter that answered "" while `configured()` quietly used
    /// the built-in address would put an empty box and the words "Nothing set" in
    /// front of somebody whose Hebrew rewrites were working. `SharedStore`
    /// therefore reads this rather than repeating the test.
    public static func effectiveURL(
        defaults: UserDefaults = SharedContainer.userDefaults
    ) -> String {
        storedURL(defaults) ?? bundledDefaultURL
    }

    /// The address the user named, or nil when the field is absent, empty or
    /// nothing but whitespace — the three states that all mean "I have not named
    /// one", and which `CloudModelView` trims to the same thing before saving.
    private static func storedURL(_ defaults: UserDefaults) -> String? {
        nonBlank(defaults.string(forKey: "cloudBackendURL"))
    }

    /// The bearer to send, or nil when there is nothing to send.
    ///
    /// **Two sources, and the order is the design.** `cloudSessionToken` is what
    /// `AppAttestation` writes after the hardware proved this is a genuine build
    /// of this app, and it is the only one a shipping install ever has.
    /// `cloudBackendToken` is typed by hand, exists in Debug builds only, and
    /// wins — a simulator has no Secure Enclave, so without it there is no way
    /// to exercise a cloud action anywhere but on a device.
    ///
    /// Separate keys rather than one, so the two lifecycles cannot collide: a
    /// refresh writing the session slot must never overwrite what a developer
    /// typed. Nil rather than "" or "   ", so a blank never becomes `Bearer    `.
    private static func storedToken(_ defaults: UserDefaults) -> String? {
        nonBlank(defaults.string(forKey: "cloudBackendToken"))
            ?? nonBlank(defaults.string(forKey: "cloudSessionToken"))
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Whether a cloud call would be **accepted**, not merely addressed.
    ///
    /// **`configured() != nil` stopped being the right question the moment a URL
    /// started shipping, and every screen that asks it had to move here.** It
    /// answers "is there somewhere to send", which on a fresh install is now
    /// always yes — so Settings would read "Set up", the Screen Context prompt
    /// would offer to start a broadcast, and the dictation screen would drop its
    /// "set up the cloud" card, all for a keyboard that 401s on every single
    /// action because the token has not been pasted in yet. That is precisely the
    /// class of claim this project keeps having to unpick: an assertion that the
    /// cloud works, made by something that never measured it.
    ///
    /// The rule is not "a token is required", because a backend somebody runs
    /// themselves with no `BACKEND_TOKEN` accepts everyone and is a perfectly good
    /// backend — `BackendTransportSuiteTests` pins that. It is: **the backend
    /// this build ships gates on a bearer, so choosing it and not supplying one is
    /// an incomplete setup.** A backend the user typed in is their business, and
    /// this says yes to it either way.
    ///
    /// Still not a guarantee. A token can be wrong, revoked or pointed at the
    /// wrong service, and only a call finds that out — which is why the failure
    /// path maps 401 to `cloudNotConfigured` and names `settingsPath`. This closes
    /// the one case that is knowable without spending a request.
    ///
    /// **Expiry is asked about here, and only of an attested token.** A session
    /// token has a ninety-day life and only the containing app can renew it, so
    /// an install whose owner has not opened the app in three months has a token
    /// the service will refuse. Saying "set up" about it would put a green tick
    /// in front of a keyboard that 401s on every action, which is exactly the
    /// class of claim `isReady` exists to prevent. A typed token carries no
    /// expiry to read and is taken at face value.
    public static func isReady(defaults: UserDefaults = SharedContainer.userDefaults) -> Bool {
        guard configured(defaults: defaults) != nil else { return false }
        guard usesBundledBackend(defaults: defaults) else { return true }
        if nonBlank(defaults.string(forKey: "cloudBackendToken")) != nil { return true }
        guard let session = nonBlank(defaults.string(forKey: "cloudSessionToken")),
            let expiry = SessionToken.expiry(of: session)
        else { return false }
        return expiry > Date()
    }

    /// Whether the address in force is the one that ships rather than one the user
    /// named. The same absent-or-empty test `configured` falls back on, so the two
    /// cannot disagree about which backend is being talked about.
    public static func usesBundledBackend(
        defaults: UserDefaults = SharedContainer.userDefaults
    ) -> Bool {
        effectiveURL(defaults: defaults) == bundledDefaultURL
    }

    /// Where the containing app lets somebody set this up, spelled once.
    ///
    /// **One key, one screen, one name.** `cloudBackendURL` is read by three
    /// processes — the keyboard's text actions, the capture extension's screen
    /// reader, and the app itself — and for most of this project it had a single
    /// writer, a field titled "Where the screen is read" on the Screen Context
    /// screen. So a Hebrew Fix, Rewrite, Tone or Reply failed with "no cloud model
    /// is set up" and named nowhere to go, while the one place that could fix it
    /// said it was about screen reading. The screen that name pointed at is
    /// gone. Keep the string so old comments and the name test still resolve;
    /// do not print it. Recovery is `setUpRecovery`.
    public static let settingsPath = "Settings › AI › Cloud model"

    /// The whole sentence, for the failures that have to say it:
    /// `AIEngineError.unsupportedLanguage`, `.deviceNotSupported`,
    /// `ScreenContextEndReason.notConfigured` and the cloud dictation card.
    ///
    /// **Not an instruction, and every version of it until now was one.** First
    /// "Finish setting it up under \(settingsPath)", which pointed at a token
    /// field that has since left the shipping app. Then "Open aBitBetterKeyboard once to
    /// reconnect", which is a chore handed to somebody who does not know this
    /// product has a cloud model, cannot see one, and did not ask for one. There
    /// is no setting behind either sentence: `AppAttestation` fills the bearer, at
    /// launch, on every return to the foreground, and on a background refresh
    /// while the app is closed. The honest sentence is therefore a status, not a
    /// task — and it is the same shape `SetupState.fullAccessDetail` already
    /// settled on for the same state.
    ///
    /// It has to read correctly appended to four different first lines
    /// (`unsupportedLanguage`, `cloudNotConfigured`, `deviceNotSupported`) and
    /// standing alone as `ScreenContextEndReason.notConfigured.recovery`, which is
    /// why it names the app rather than saying "it".
    public static let setUpRecovery = "aBitBetterKeyboard is reconnecting. Try again in a moment."

    // send, encoded, mapped, and decode are in BackendTransport+Send.swift.
}
