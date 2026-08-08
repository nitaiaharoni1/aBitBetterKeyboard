import Foundation

// MARK: - Transport

/// One field the model must fill in. Mirrors an `@Guide` on the on-device path,
/// so both engines are driven by the same prompts and the same output shape.
public struct CloudField: Sendable {
    public let name: String
    public let description: String
    /// Sub-fields, when this field is a list of objects rather than one string.
    ///
    /// Only the screen reader uses this, and it is not decoration: asking the
    /// model to enumerate every message bubble before naming one is what stops
    /// it answering a message three positions above the newest. Measured over
    /// `Bar/screen-context/`, flattening the same list into a JSON string in a
    /// plain field costs 7 points of message accuracy and 3 of sender accuracy.
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

// MARK: - Engine

/// The cloud path, which exists because Apple's on-device model does not list
/// Hebrew — the language most of this keyboard's traffic is in.
///
/// It shares `Prompts` and the field names with the on-device engine on purpose:
/// two engines with two prompt sets would drift, and the prompts are where the
/// language guarantees actually live.
public struct CloudIntelligence: TextIntelligence {
    private let transport: any CloudTransport
    /// A keyboard extension has no network at all until the user grants Full
    /// Access, so this is asked before the request rather than after it fails.
    private let networkAllowed: @Sendable () -> Bool

    public init(transport: any CloudTransport, networkAllowed: @escaping @Sendable () -> Bool = { true }) {
        self.transport = transport
        self.networkAllowed = networkAllowed
    }

    /// The cloud model has no script and no action it will not take. That is the
    /// entire reason this path exists.
    public func canHandle(_ text: String, action: AIAction) -> Bool { true }

    public func fix(_ text: String) async throws -> String {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return text }
        // `corrections` is answered before `text` and is there to be answered
        // rather than shown: naming each mistake is what stops the model
        // respelling words that were already right, and `EditScope` holds the
        // corrected message to the list it just wrote. Same fields, same order,
        // as the on-device `FixDraft`.
        let fields = try await run(
            instructions: Prompts.fix(for: source),
            prompt: "Message:\n\(source)",
            fields: [
                CloudField(
                    "corrections",
                    "Every mistake in the message, as `wrong -> right`, comma separated. Only real mistakes: a correctly spelled word, an alternative accepted spelling, slang, an abbreviation, a contraction, a deliberate lowercase and a missing full stop are not mistakes. 'none' when nothing is wrong."
                ),
                CloudField(
                    "text",
                    "The message with exactly those corrections applied and nothing else changed, in its original language and script."
                )
            ]
        )
        guard let corrected = fields["text"]?.trimmed, !corrected.isEmpty else { throw AIEngineError.empty }
        return EditScope.applied(
            corrected, to: source, corrections: fields["corrections"]?.trimmed ?? "")
    }

    public func variants(for text: String, tone: ToneStyle?) async throws -> [RewriteVariant] {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { throw AIEngineError.empty }

        if let tone {
            let fields = try await run(
                instructions: Prompts.tone(tone, for: source),
                prompt: "Message:\n\(source)",
                fields: [CloudField("text", "The message rewritten in the requested register.")]
            )
            guard let rewritten = fields["text"]?.trimmed, !rewritten.isEmpty else {
                throw AIEngineError.empty
            }
            // Tone replaces what the user typed with one string and no choice,
            // so an invented commitment here is the one they send.
            guard OutputGuard.addedSpecifics(in: rewritten, notIn: source).isEmpty else {
                throw AIEngineError.invented
            }
            return [RewriteVariant(tone: tone, text: rewritten)]
        }

        // The first two fields are answered before the three versions are
        // written, and are there to be answered rather than shown: naming the
        // decision once is what stops three phrasings of it, and listing the
        // specifics once is what stops the third version dropping the deadline
        // the message was about. Same fields, same order, as the on-device
        // `RewriteDraft`.
        let fields = try await run(
            instructions: Prompts.rewrite(for: source),
            prompt: "Message:\n\(source)",
            fields: [
                CloudField(
                    "decision",
                    "What the message decides or asks for, in a few words. 'nothing' when it only thanks, informs or shares news."
                ),
                CloudField(
                    "specifics",
                    "Every time, date, name and number in the message, comma separated. 'none' if it has none. Each one appears in all three versions."
                ),
                CloudField(
                    "firstLabel", "Two or three words in English naming the decision this version takes."),
                CloudField(
                    "firstText",
                    "The message rewritten to take that decision as directly as it can be taken. It is still a rewrite: when the message already says it directly, tighten it, and never return it word for word."
                ),
                CloudField("secondLabel", "Two or three words in English naming a different decision."),
                CloudField(
                    "secondText",
                    "The message rewritten to hand the decision back rather than settle it, asking the other person for what would settle it. When the message decides nothing, the same message, shorter and plainer."
                ),
                CloudField("thirdLabel", "Two or three words in English naming a third decision."),
                CloudField(
                    "thirdText",
                    "The message rewritten to keep the position but put a different option on the table. When the message decides nothing, the same message, warmer — and no longer than the original."
                )
            ]
        )
        return try RewriteVariant.vetted(
            [
                (label: fields["firstLabel"]?.trimmed ?? "", text: fields["firstText"]?.trimmed ?? ""),
                (label: fields["secondLabel"]?.trimmed ?? "", text: fields["secondText"]?.trimmed ?? ""),
                (label: fields["thirdLabel"]?.trimmed ?? "", text: fields["thirdText"]?.trimmed ?? "")
            ],
            against: source
        )
    }

    public func replies(to context: ScreenContext) async throws -> [ReplyOption] {
        // `unnamed` leads for the same reason `decision` leads Rewrite: whether
        // the message can be agreed to at all has to be settled before the reply
        // that agrees to it is written.
        let fields = try await run(
            instructions: Prompts.reply(for: context),
            prompt: "From \(context.sender):\n\(context.message)",
            fields: [
                CloudField(
                    "unnamed",
                    "The task, file or item the sender refers to but never identifies — 'this', 'it' — when agreeing would mean taking on something the user cannot see. Empty when the message says what it is about, and empty when it only asks for time or attention: agreeing to talk hides nothing."
                ),
                CloudField(
                    "addressee",
                    "The grammatical gender to address the sender in, worked out from their name: 'feminine' or 'masculine'. 'none' when the reply is in a language that does not inflect for it."
                ),
                CloudField(
                    "accept",
                    "A reply that agrees or accepts. If something is unnamed above, it still asks what it is. Address the sender in the gender named above, never with a slash form."
                ),
                CloudField(
                    "pushBack",
                    "A reply that declines, disagrees or negotiates. If something is unnamed above, it refuses to commit until it knows what it is, and asks. Same gender as above."
                ),
                CloudField(
                    "ask",
                    "A reply that asks the one question needed before answering, addressing the sender in the gender named above."
                )
            ]
        )
        return try ReplyOption.vetted(
            accept: fields["accept"]?.trimmed ?? "",
            pushBack: fields["pushBack"]?.trimmed ?? "",
            ask: fields["ask"]?.trimmed ?? "",
            against: context.message,
            unnamed: fields["unnamed"]?.trimmed ?? ""
        )
    }

    private func run(
        instructions: String,
        prompt: String,
        fields: [CloudField]
    ) async throws -> [String: String] {
        guard networkAllowed() else { throw AIEngineError.needsFullAccess }
        return try await transport.send(
            CloudRequest(instructions: instructions, prompt: prompt, fields: fields)
        )
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
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
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Nil when the build has no backend configured, which is the state the app
    /// ships in today. The router then reports that rather than guessing.
    ///
    /// Reads the **shared** store, not `.standard`. The app writes this setting
    /// and the keyboard extension reads it, and `.standard` in an extension is
    /// that process's own private container: the URL set in the app would never
    /// arrive, and the keyboard would report "no cloud model" for a backend that
    /// was configured. That failure is invisible from the app side, which is
    /// what made it worth a named default rather than a comment.
    public static func configured(
        defaults: UserDefaults = SharedStore.shared.userDefaults
    ) -> BackendTransport? {
        guard let raw = defaults.string(forKey: "cloudBackendURL"),
            let url = URL(string: raw), url.scheme?.hasPrefix("http") == true
        else { return nil }
        return BackendTransport(baseURL: url)
    }

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
