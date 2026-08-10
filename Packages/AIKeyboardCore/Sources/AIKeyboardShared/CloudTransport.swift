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
    private let baseURL: URL
    private let token: String?
    private let session: URLSession

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

    /// Nil rather than "" or "   ", so a blank never becomes `Bearer    `.
    private static func storedToken(_ defaults: UserDefaults) -> String? {
        nonBlank(defaults.string(forKey: "cloudBackendToken"))
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
    public static func isReady(defaults: UserDefaults = SharedContainer.userDefaults) -> Bool {
        guard configured(defaults: defaults) != nil else { return false }
        guard usesBundledBackend(defaults: defaults) else { return true }
        return storedToken(defaults) != nil
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
    /// said it was about screen reading. Every failure that dead-ends here now
    /// prints this string, and `CloudModelView` is the row it names.
    public static let settingsPath = "Settings › AI › Cloud model"

    /// The whole sentence, for the four failures that have to say it:
    /// `AIEngineError.unsupportedLanguage`, `.cloudNotConfigured`,
    /// `.deviceNotSupported` and `ScreenContextEndReason.notConfigured`.
    /// **"Set one up" became the wrong instruction when a URL started shipping.**
    /// Every caller of this reaches it in the state `isReady()` is false in, and
    /// that is now almost always an address that is already filled in with no
    /// access token beside it. Sending somebody off to stand up a server, when
    /// what they need is to paste a string into a field that is already on screen,
    /// is the kind of dead end this whole constant exists to close.
    public static let setUpRecovery = "Finish setting it up in AI Keyboard, under \(settingsPath)."

    public func send(_ request: CloudRequest) async throws -> [String: String] {
        var body: [String: Any] = [
            "instructions": request.instructions,
            "prompt": request.prompt,
            "fields": request.fields.map(Self.encoded)
        ]

        // A frame goes to its own endpoint rather than being smuggled into the
        // text one, so the backend can hold screen images to a different
        // retention rule than text. Base64 because the body is already JSON and
        // one frame is small next to the model call it pays for.
        if let image = request.image {
            body["image"] = [
                "mimeType": image.mimeType,
                "data": image.data.base64EncodedString()
            ]
        }

        // A recording goes to its own endpoint for the reason a frame does: the
        // backend can hold somebody's voice to a different retention rule than
        // their text, and it can only do that if the two arrive separately.
        if let audio = request.audio {
            body["audio"] = [
                "mimeType": audio.mimeType,
                "data": audio.data.base64EncodedString()
            ]
        }

        let path: String
        if request.image != nil {
            path = "v1/screen"
        } else if request.audio != nil {
            path = "v1/audio"
        } else {
            path = "v1/text"
        }
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        // The backend spends money per call, so an endpoint anyone can find is an
        // endpoint anyone can bill. This is *not* a bundled secret — nothing here
        // ships one, for the same reason no provider credential does: anything in
        // the bundle is extractable. It is a value the person running the backend
        // puts into settings alongside its URL, so it is exactly as private as
        // they keep it. A shipping consumer build wants App Attest instead, which
        // proves the caller is a genuine copy of this app rather than proving it
        // knows a string; `Backend/README.md` says so under its known gaps.
        if let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AIEngineError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Self.mapped(status: status, body: data) }
        return try Self.decode(data)
    }

    /// Field order is preserved all the way to the provider. Both engines rely
    /// on it: the model fills fields in the order it receives them, so a field
    /// that exists to be *decided first* only works if it arrives first.
    static func encoded(_ field: CloudField) -> [String: Any] {
        var encoded: [String: Any] = ["name": field.name, "description": field.description]
        if let items = field.items {
            encoded["items"] = items.map(Self.encoded)
        }
        return encoded
    }

    static func mapped(status: Int, body: Data) -> AIEngineError {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let message = (json?["error"] as? String) ?? ""
        switch status {
        case 401, 403: return .cloudNotConfigured
        case 413: return .inputTooLong
        // The backend forwards a provider safety block as 422 so it reads as a
        // decision about the text rather than as a service failure.
        case 422: return .refused
        case 429: return .failed("The cloud model is busy. Try again in a moment.")
        case 500...599: return .network("The cloud model is unavailable right now.")
        default: return .failed(message)
        }
    }

    static func decode(_ data: Data) throws -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIEngineError.failed("The backend returned something unreadable.")
        }
        if root["refused"] as? Bool == true { throw AIEngineError.refused }
        guard let fields = root["fields"] as? [String: Any] else { throw AIEngineError.empty }
        return fields.compactMapValues { $0 as? String }
    }
}
