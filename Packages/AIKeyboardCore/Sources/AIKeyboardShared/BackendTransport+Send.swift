import Foundation

// MARK: - Wire encoding and network call

extension BackendTransport {

    public func send(_ request: CloudRequest) async throws -> [String: String] {
        try await send(request, token: token, allowReattest: true)
    }

    /// `token` is threaded through explicitly, rather than always read from
    /// `self.token`, so the one retry NIT-87 asks for can run with a freshly
    /// minted bearer without constructing a second `BackendTransport`.
    /// `allowReattest` is what keeps the retry to exactly one: it is false on
    /// the recursive call, so a second 401 falls straight through to
    /// `mapped` instead of asking `SessionReattestation` again.
    private func send(
        _ request: CloudRequest, token: String?, allowReattest: Bool
    ) async throws -> [String: String] {
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
        guard status != 200 else { return try Self.decode(data) }

        // **NIT-87: a 401 on a model route can mean the session token this
        // process is holding is stale rather than "there is no cloud".**
        // `SessionReattestation` is the one thing that can tell the
        // difference without bothering the user — see its doc comment for why
        // this cannot stampede. Tried at most once per call, via
        // `allowReattest`: a second 401 after a fresh token is a real
        // refusal, not another round of the same guess.
        if status == 401, allowReattest {
            if let fresh = await SessionReattestation.shared.reattest() {
                return try await send(request, token: fresh, allowReattest: false)
            }
            // Re-attestation was not possible at all — nothing registered,
            // which today means this process is one of the two extensions —
            // or it ran and failed. A process with no path to the shared
            // session token says so by name, rather than repeating the vague
            // "reconnecting" line that used to cover Full Access too.
            if SharedContainer.url == nil {
                throw AIEngineError.needsFullAccess
            }
        }

        throw Self.mapped(status: status, body: data)
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
        case 429: return .failed("Busy right now. Try again in a moment.")
        case 500...599: return .network("Unavailable right now. Try again shortly.")
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
