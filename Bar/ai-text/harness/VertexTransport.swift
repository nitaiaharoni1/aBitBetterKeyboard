import Foundation

/// Calls Vertex AI directly, for bar scoring only.
///
/// This is a measurement tool, not app code, and it must never ship inside an
/// app target. It authenticates with a gcloud access token from the developer's
/// machine — a shipped keyboard cannot hold a credential like that, which is why
/// the app talks to `BackendTransport` instead and lets a backend own the key.
/// It lives under `Bar/`, which no target compiles.
///
/// Model choice matches the shipping backend: `gemini-3.5-flash-lite`,
/// thinking off. See `thinkingBudget`.
struct VertexTransport: CloudTransport {
    let projectID: String
    let accessToken: String
    let model: String
    let session: URLSession

    init(
        projectID: String,
        accessToken: String,
        model: String = "gemini-3.5-flash-lite",
        session: URLSession = .shared
    ) {
        self.projectID = projectID
        self.accessToken = accessToken
        self.model = model
        self.session = session
    }

    /// Reads what `run-real.sh` exports. Nil when the harness was run without a
    /// token, so the run degrades to on-device only rather than dying.
    static func fromEnvironment() -> VertexTransport? {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["VERTEX_ACCESS_TOKEN"], !token.isEmpty,
            let project = environment["VERTEX_PROJECT"], !project.isEmpty
        else { return nil }
        return VertexTransport(
            projectID: project,
            accessToken: token,
            model: environment["VERTEX_MODEL"] ?? "gemini-3.5-flash-lite"
        )
    }

    /// How much the model may think, in tokens. `VERTEX_THINKING_BUDGET`
    /// overrides it; `-1` is Vertex's own value for dynamic thinking, which is
    /// what the model does when no budget is set at all.
    ///
    /// Off, matching `Backend/src/vertexClient.js`. Measured 2026-08-14 on
    /// `gemini-3.5-flash-lite`: thinking 0 kept Latin loanwords and cut Fix
    /// to ~1.2s. On `gemini-2.5-flash`, 0 transliterated `sync` into `סִינְק`
    /// and a 512 cap was the fix; do not put that 512 back on Lite.
    static var thinkingBudget: Int {
        ProcessInfo.processInfo.environment["VERTEX_THINKING_BUDGET"].flatMap(Int.init) ?? 0
    }

    func send(_ request: CloudRequest) async throws -> [String: String] {
        var properties: [String: Any] = [:]
        for field in request.fields {
            properties[field.name] = ["type": "STRING", "description": field.description]
        }

        var generationConfig: [String: Any] = [
            "responseMimeType": "application/json",
            "responseSchema": [
                "type": "OBJECT",
                "properties": properties,
                "required": request.fields.map(\.name),
                // Without this the model fills a JSON object's fields in
                // whatever order it likes, and the engines rely on the order:
                // Reply settles whether the message can be agreed to before it
                // writes the reply that agrees, and Rewrite names the decision
                // before it writes three versions of it. A backend serving this
                // contract has to do the same.
                "propertyOrdering": request.fields.map(\.name)
            ]
        ]
        generationConfig["thinkingConfig"] = ["thinkingBudget": Self.thinkingBudget]

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.instructions]]],
            "contents": [["role": "user", "parts": [["text": request.prompt]]]],
            "generationConfig": generationConfig
        ]

        let url = URL(
            string:
                "https://aiplatform.googleapis.com/v1/projects/\(projectID)/locations/global/publishers/google/models/\(model):generateContent"
        )!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 120
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw AIEngineError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            switch status {
            case 401, 403: throw AIEngineError.cloudNotConfigured
            case 429: throw AIEngineError.failed("Vertex rate limited.")
            default: throw AIEngineError.failed("HTTP \(status): \(detail.prefix(300))")
            }
        }

        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIEngineError.failed("Vertex returned something unreadable.")
        }
        // A blocked prompt comes back 200 with no candidates, so the block has to
        // be read before the content is.
        if let feedback = root["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil {
            throw AIEngineError.refused
        }
        guard let candidate = (root["candidates"] as? [[String: Any]])?.first else {
            throw AIEngineError.empty
        }
        if let reason = candidate["finishReason"] as? String,
            reason == "SAFETY" || reason == "PROHIBITED_CONTENT"
        {
            throw AIEngineError.refused
        }
        guard let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]],
            let text = parts.compactMap({ $0["text"] as? String }).first,
            let payload = text.data(using: .utf8),
            let fields = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            throw AIEngineError.empty
        }
        return fields.compactMapValues { $0 as? String }
    }
}
