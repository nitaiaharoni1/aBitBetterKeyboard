import Foundation

// MARK: - Wire encoding and network call

extension BackendTransport {

    public func send(_ request: CloudRequest) async throws -> [String: String] {
        try Task.checkCancellation()
        if case .shared(let defaults) = credential,
            !Self.allowsCloudAIProcessing(defaults: defaults)
        {
            throw AIEngineError.cloudPermissionRequired
        }
        return try await send(request, token: currentBearer(), allowCredentialRefresh: true)
    }

    /// `token` is threaded through explicitly so the one retry NIT-87 asks for
    /// can run with a freshly minted bearer without constructing a second
    /// `BackendTransport`.
    /// `allowCredentialRefresh` is what keeps the retry to exactly one: it is false on
    /// the recursive call, so a second 401 falls straight through to
    /// `mapped` instead of rereading App Group state or asking App Attest again.
    private func send(
        _ request: CloudRequest, token: String?, allowCredentialRefresh: Bool
    ) async throws -> [String: String] {
        try Task.checkCancellation()
        let (route, body) = Self.requestBody(for: request)

        var urlRequest = URLRequest(url: endpoint.url(for: route))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        // Release credentials are App Attest sessions read from the shared
        // container at call time. A fixed bearer is available only to an
        // explicitly constructed development transport.
        if let token {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await receive(from: urlRequest)

        try Task.checkCancellation()

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status != 200 else { return try Self.decode(data) }

        // **NIT-87: a 401 on a model route can mean the session token this
        // process is holding is stale rather than "there is no cloud".**
        // `SessionReattestation` is the one thing that can tell the
        // difference without bothering the user — see its doc comment for why
        // this cannot stampede. Tried at most once per call, via
        // `allowCredentialRefresh`: a second 401 after a fresh token is a real
        // refusal, not another round of the same guess.
        if status == 401, allowCredentialRefresh {
            if let fresh = await replacementBearer(after: token) {
                return try await send(
                    request, token: fresh, allowCredentialRefresh: false)
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

    private static func requestBody(for request: CloudRequest) -> (BackendEndpoint.Route, [String: Any]) {
        var body: [String: Any] = [
            "instructions": request.instructions,
            "prompt": request.prompt,
            "fields": request.fields.map(Self.encoded)
        ]
        switch request.payload {
        case .text:
            return (.text, body)
        case .screenJPEG(let data):
            body["image"] = ["mimeType": "image/jpeg", "data": data.base64EncodedString()]
            return (.screen, body)
        case .audioWAV(let data):
            body["audio"] = ["mimeType": "audio/wav", "data": data.base64EncodedString()]
            return (.audio, body)
        }
    }

    private func receive(from request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            let maximumResponseBytes = 256 * 1_024
            guard response.expectedContentLength <= maximumResponseBytes else {
                throw AIEngineError.failed("The response was too large. Try a shorter selection.")
            }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumResponseBytes else {
                    throw AIEngineError.failed("The response was too large. Try a shorter selection.")
                }
                data.append(byte)
            }
            return (data, response)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let error = error as? AIEngineError { throw error }
            throw AIEngineError.network(error.localizedDescription)
        }
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
