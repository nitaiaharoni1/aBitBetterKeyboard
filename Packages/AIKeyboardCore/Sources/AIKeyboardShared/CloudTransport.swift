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

public struct CloudRequest: Sendable {
    public let instructions: String
    public let prompt: String
    public let fields: [CloudField]
    public let image: CloudImage?

    public init(
        instructions: String,
        prompt: String,
        fields: [CloudField],
        image: CloudImage? = nil
    ) {
        self.instructions = instructions
        self.prompt = prompt
        self.fields = fields
        self.image = image
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

    /// Nil when the build has no backend configured, which is the state the app
    /// ships in today. The router then reports that rather than guessing.
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
        guard let raw = defaults.string(forKey: "cloudBackendURL"),
            let url = URL(string: raw), url.scheme?.hasPrefix("http") == true
        else { return nil }
        let token = defaults.string(forKey: "cloudBackendToken")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return BackendTransport(baseURL: url, token: (token?.isEmpty == false) ? token : nil)
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
    public static let setUpRecovery = "Set one up in AI Keyboard, under \(settingsPath)."

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

        let path = request.image == nil ? "v1/text" : "v1/screen"
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
